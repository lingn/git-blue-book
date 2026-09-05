# rebase 模型与安全工作流：把历史重建变成可回退流程

本章合并原第四篇的 rebase 模型与安全执行章节。先解释 rebase 如何用新父提交重建对象，再按恢复引用、冲突、中止、验证和共享推送的顺序操作。交互式 todo 的具体动作见[交互式 rebase](05-interactive-rebase.md)。

## rebase 与其他整合方式

| 动作 | 主线历史形状 | 是否生成新提交 | 适合场景 |
| --- | --- | --- | --- |
| merge | 保留两侧父关系，分叉时有 merge commit | 可能 | 已共享分支、需要保留集成事件 |
| rebase | 把功能提交接到新基线后 | 是 | 未共享分支、需要线性审查 |
| squash merge | 主线写入一个压缩提交 | 是 | 评审后压平主线，但需保留来源证据 |
| cherry-pick | 在另一分支重放指定变化 | 是 | 维护分支迁移独立修复 |

文件内容或补丁可以等价，提交 OID 仍会因为 parent、author/committer、时间、说明或签名变化而不同。共享边界决定能否接受这些新坐标。

rebase 不是“把分支指针挪到另一个位置”。它会读取一段提交的变化，在新的父提交之后逐个重放，并让当前分支指向新生成的提交。只要父提交、提交者时间、提交说明、签名或 tree 有一项不同，新的 OID 就可能不同。

本章讲普通 rebase 的可执行流程。需要修改提交顺序、拆分提交或批量执行命令时，进入第五篇的交互式 rebase 章节。

## 进入条件与完成标准

准备一个只由自己使用的功能分支，或已经得到团队明确授权的改写分支。开始前在仓库根目录执行：

~~~bash
git status --short --branch
git branch --show-current
git rev-parse --verify HEAD^{commit}
git log --graph --decorate --oneline --all
~~~

工作区和 index 应干净，不能有另一个 merge、rebase、cherry-pick 或 revert 正在进行。保存当前尖端和当前分支名：

~~~bash
old_branch="$(git branch --show-current)"
old_tip="$(git rev-parse HEAD)"
git reflog -1
~~~

如果 old_branch 为空，说明当前处于分离 HEAD。先切换到明确的功能分支，或建立恢复引用后再决定是否继续。不要站在 main 上，仅为了让历史看起来线性就重建主线。

读完本章后，你应能：

- 在重写前保存分支、尖端 OID 和恢复引用；
- 选择普通 rebase、--onto 或保留合并拓扑的模式；
- 逐提交处理冲突，并正确区分 continue、skip、abort 和 quit；
- 用最终 tree、父关系、range-diff 和测试证明变化没有丢失；
- 判断变基后的推送是否会改写已共享引用；
- 说明签名、评审、CI、制品和部署记录为何需要重新绑定新 OID。

## 先固定基线和恢复入口

假设功能分支当前包含两个提交，远程主线可能已经前进。先获取远程观察点：

~~~bash
git fetch origin
old_base="$(git merge-base HEAD origin/main)"
old_tip="$(git rev-parse HEAD)"
git branch recovery/before-rebase "$old_tip"
git rev-parse recovery/before-rebase
~~~

fetch 会更新本地对象和 origin/main，不会移动当前功能分支。old_base 是这次 rebase 默认要替换的共同祖先，old_tip 是重建前的完整 OID。恢复分支只是增加一个 ref，不会复制对象，也不会改变工作区。

确认待重放范围：

~~~bash
git log --oneline "$old_base".."$old_tip"
git diff --stat "$old_base".."$old_tip"
git show --no-patch --format='%H%n%P%n%T%n%s' "$old_tip"
~~~

如果范围包含合并提交、发布标签、其他人的提交或不应迁移的依赖，先停止。普通 rebase 默认按一条线性提交序列重放，不能假设它会无损保留原有合并拓扑。

## 普通 rebase 的状态变化

在功能分支执行：

~~~bash
git rebase origin/main
~~~

成功时通常发生：

1. Git 计算当前分支与 origin/main 的共同祖先；
2. 暂时保存当前分支独有的提交；
3. 把当前分支移动到 origin/main；
4. 按原顺序创建新的提交对象；
5. 让功能分支指向最后一个新提交；
6. 更新 index 和工作区以匹配新历史。

成功后检查：

~~~bash
new_tip="$(git rev-parse HEAD)"
new_base="$(git merge-base HEAD origin/main)"
git merge-base --is-ancestor origin/main HEAD
git log --graph --decorate --oneline --all
git diff --stat origin/main...HEAD
git diff --check
printf 'old_tip=%s\nnew_tip=%s\nbase=%s\n' "$old_tip" "$new_tip" "$new_base"
~~~

merge-base --is-ancestor 退出码为 0，说明新功能尖端包含远程主线。new_tip 与 old_tip 通常不同，这是提交被重建的直接证据。最终差异仍需与目标功能清单和测试结果比较，不能只看 OID 变化。

## 用 range-diff 检查重建是否丢变化

range-diff 比较两组提交序列，而不是只比较最终文件：

~~~bash
git range-diff "$old_base".."$old_tip" "$new_base".."$new_tip"
~~~

它会尝试把旧序列和新序列按补丁相似度配对，显示新增、删除或修改的提交。提交说明、上下文和补丁改变时，输出可能出现重排或差异；这不是自动证明等价。

审查 range-diff 时重点看：

- 每个原提交是否都有明确的新对应项；
- 某个提交是否被意外跳过或合并；
- 补丁是否因新基线而改变了实际语义；
- 提交说明、作者、提交者、签名和验证结果是否仍符合规则。

对于包含合并提交的历史，先评估 --rebase-merges 或改用 merge。不要用一段看起来“相似”的 range-diff 取代构建和业务测试。

## --onto 改变的是起点和范围

需要把一段功能提交迁移到另一个分支时：

~~~bash
git rebase --onto release/1.x main feature/search
~~~

该命令把 feature/search 中不属于 main 的提交，重放到 release/1.x。它同时指定新起点、旧范围边界和目标分支，范围写错就可能漏掉基础提交或把无关提交带入维护分支。

执行前先计算候选集合：

~~~bash
git log --oneline main..feature/search
git merge-base main feature/search
git log --oneline release/1.x..feature/search
~~~

如果目标分支和旧边界没有共同历史，或候选包含数据库、配置和共享库依赖，先停止并建立迁移清单。--onto 不是跨项目复制，也不自动迁移制品、LFS 对象、子模块提交和评审数据。

--keep-base 用于希望保留共同祖先作为基线的场景，具体效果取决于提交图和 Git 版本。--rebase-merges 尝试重建原来的合并结构，会增加 todo 计划和冲突数量。生产脚本应显式记录 Git 版本、完整 refs 和选项，不依赖默认配置。

## 变基冲突的第一轮取证

如果重放某个提交发生冲突，Git 会暂停并保留进行中的状态。先不要编辑文件，执行：

~~~bash
git status --short --branch
git rev-parse --verify REBASE_HEAD
git rebase --show-current-patch
git ls-files --unmerged
git rev-parse HEAD
git reflog -3
~~~

REBASE_HEAD 通常指向正在重放的原提交。show-current-patch 展示该提交的补丁。ls-files --unmerged 能说明哪些路径仍处于未合并阶段；它比搜索工作区标记更可靠。

不同 Git 版本和后端可能使用 rebase-merge 或 rebase-apply 状态目录。状态目录是操作数据，不是让脚本直接删除的临时文件。原始错误、当前 patch、HEAD 和 index stages 都应写入排障记录。

## rebase 中的 ours 和 theirs

普通 merge 中，ours 通常是当前分支，theirs 是被合入分支。rebase 把原提交逐个应用到新基线，冲突提示中的视角可能与直觉不同：

- 当前检出的新基线代表正在构建的结果；
- 正在重放的原提交提供要应用的变化。

不要仅凭 ours 或 theirs 选择整边。先阅读 REBASE_HEAD 的提交说明、旧提交 tree、新基线 tree 和业务约束，再形成最终文件。配置、接口、schema 和权限变化尤其不能用标签替代判断。

## 解决一个冲突并继续

编辑明确的冲突路径后：

~~~bash
git diff -- path/to/resolved-file
git add -- path/to/resolved-file
git diff --staged --check
git diff --staged -- path/to/resolved-file
git ls-files --unmerged
git rebase --continue
~~~

git add 把最终文件写入 index，并移除该路径的 unmerged stages。它只表示这一条路径已经选定，不表示整个重放提交或业务行为正确。rebase --continue 可能运行 hooks、打开编辑器，或在下一个提交再次冲突。

如果解决结果没有实际变化，Git 可能提示当前提交变成空提交。此时应判断变化是否已经由新基线提供，再选择继续保留空提交或 skip；不要为了让命令前进而随意跳过。

## skip、abort 和 quit 的边界

| 动作 | 作用 | 主要风险 |
| --- | --- | --- |
| rebase --continue | 使用当前 index 完成正在重放的提交，继续后续序列 | 未审查就继续会把错误结果写入新历史 |
| rebase --skip | 放弃整个当前原提交，继续下一个 | 可能丢掉该提交独有的修复 |
| rebase --abort | 尝试恢复到开始前的分支、HEAD、index 和工作区 | 开始前已有未提交修改时恢复可能不完整 |
| rebase --quit | 清除 rebase 状态，保留当前 HEAD、index 和工作区 | 不会回到旧历史，需由操作者接管 |

继续前保存：

~~~bash
git status --short --branch
git rebase --show-current-patch
git diff --staged
~~~

确认当前提交的变化已在新基线中，且团队明确允许放弃，才使用 rebase --skip。发现目标起点、范围或结果错误时使用：

~~~bash
git rebase --abort
git branch --show-current
git rev-parse HEAD
git rev-parse recovery/before-rebase
git status --short --branch
~~~

abort 成功后，当前分支尖端应回到 old_tip，工作区和 index 应与开始前一致。若开始前有 autostash 或外部工具改动，逐项比较保存的 status、diff 和 stash，不要假设自动恢复无误。quit 适合明确要保留中间现场的高级操作，不是取消变基的快捷写法。

## 自动暂存和命令执行

工作区不干净时，某些场景可以使用：

~~~bash
git rebase --autostash origin/main
~~~

Git 会创建临时 stash，变基结束后尝试应用。应用阶段仍可能冲突，且 stash 可能把本地未提交内容带回一个不同的基线。高风险重写应先显式提交临时节点或使用独立 worktree，再决定是否允许 autostash。

交互式 rebase 中的 --exec 会在每个重放提交后执行命令。命令的输出、退出码和副作用会影响变基能否继续。它适合在隔离环境运行快速检查，不应调用部署、删除远端 ref 或修改共享系统。需要重排、拆分、reword 和 exec 的完整流程见第五篇。

## 变基后的签名、评审与发布记录

新提交不会自动继承旧 commit 的签名字段。若团队要求签名，重建后必须重新签名并验证新对象。平台评审、CI 结果、制品摘要和部署记录如果绑定旧 OID，也要重新关联或重新生成。

至少保存：

~~~text
old_base: <变基前共同祖先>
old_tip: <变基前功能尖端>
new_base: <变基后共同祖先>
new_tip: <变基后功能尖端>
range_diff: <旧序列与新序列比较结果>
tests: <干净检出中的命令与结果>
artifacts: <制品摘要和构建输入>
shared_refs: <评审、CI、发布和部署引用>
~~~

作者字段可能保持不变，提交者和时间可能变化。不要把“作者名字没变”当作签名、评审或发布证据。

## 变基后的推送

未推送过的新分支可以普通首次推送。已经推送过的分支，由于远端仍指向旧提交，普通 push 通常会拒绝。若团队明确允许改写，先查询并保存远端旧值：

~~~bash
expected_remote="$(git ls-remote origin refs/heads/feature/search | awk '{print $1}')"
new_tip="$(git rev-parse HEAD)"
printf 'expected_remote=%s\nnew_tip=%s\n' "$expected_remote" "$new_tip"
~~~

在确认分支所有权、评审影响、恢复来源和平台规则后，才考虑显式租约：

~~~bash
git push --force-with-lease=refs/heads/feature/search:"$expected_remote" \
  origin HEAD:refs/heads/feature/search
~~~

租约只检查远端 ref 是否仍为 expected value，不提供权限、备份或绝对锁。查询和推送之间仍有竞态，拒绝后要重新 fetch、比较 OID 和通知协作者。不得用无条件 git push --force 代替协调。

## 失败路径和恢复

| 现象 | 首先收集 | 处理 |
| --- | --- | --- |
| 工作区不干净，rebase 不启动 | status、diff、stash | 提交临时节点、stash 或独立 worktree |
| bad revision/没有共同祖先 | refs、OID、merge-base、浅状态 | 修正范围或补全历史，不强行 onto |
| rebase 冲突 | REBASE_HEAD、current patch、stages | 按提交意图逐路径解决，或 abort |
| continue 报 hook/编辑器错误 | hook 输出、提交说明、当前 patch | 修复具体原因后重试 |
| 产生空提交 | 新基线是否已有等价变化 | 明确 skip 或保留，不静默丢弃 |
| abort 后状态不同 | 开始前保存、autostash、外部修改 | 从恢复引用和副本逐项重建 |
| 普通 push 被拒绝 | 远端 old OID、new OID、共享边界 | 重新核对，获批后使用显式租约 |
| 评审/CI 仍指向旧 OID | 平台事件、制品和部署清单 | 重新绑定或追加修正，不假设自动迁移 |

不要删除 .git/rebase-*、REBASE_HEAD 或恢复分支来结束失败。它们可能是唯一的恢复和审计入口。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-history.sh
~~~

实验在两个本地 clone 中制造非快进，再执行 rebase，验证功能变化保留但提交 OID 改变，随后普通 push 可以更新本地 bare server。交互式重排、拆分、冲突和 abort 由：

~~~bash
./scripts/verify-interactive-rebase.sh
~~~

单独验证。实验不证明真实平台的强制更新授权、评审候选、签名、CI、制品和部署记录。

## 小结

安全 rebase 的核心顺序是：确认分支所有权，保存旧 OID 和恢复引用，固定新基线，逐提交重放，按 range-diff、最终 tree 和测试验收，再决定是否用显式租约更新远端。它重建的是提交对象，不是修改旧对象；线性历史的收益不能抵消共享边界和证据链风险。
