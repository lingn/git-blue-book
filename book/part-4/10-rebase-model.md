# 变基的本质：用新父提交重建一段历史

rebase 常被口语化成“把分支挪到最新主线”。这个说法隐藏了关键事实：提交对象不可原地修改，变基会把原提交表达的变化重新应用到新起点，生成一组新的 commit。分支引用移动了，原来的 commit OID 不会改变。

## 进入条件与完成标准

准备一个已经分叉的本地功能分支，并确认它是否已推送、是否被评审或其他协作者使用。开始前保存：

~~~bash
git status --short --branch
git branch --show-current
git log --graph --decorate --oneline --all
git rev-parse HEAD
~~~

工作区和 index 应干净。不要在不知道分支所有权时直接 rebase。

读完本章后，你应能：

- 画出 rebase 前后的父提交关系；
- 解释旧提交和新提交为什么有不同 OID；
- 区分 rebase、merge、squash 和 cherry-pick 的历史结果；
- 选择 --onto、--keep-base、--rebase-merges 等范围选项；
- 判断提交是否已共享以及推送是否需要租约；
- 在 rebase 失败时根据状态文件选择 continue、skip、abort 或 quit。

## 一个分叉历史

假设主线在 M，功能分支从 B 分出 F1、F2：

~~~text
      F1 <- F2  feature
     /
A <- B <- M     main
~~~

在 feature 上执行：

~~~bash
git rebase main
~~~

Git 找到 feature 与 main 的共同祖先 B，暂时取出 feature 独有的提交，切换基线到 M，再依次应用它们的变化：

~~~text
A <- B <- M <- F1' <- F2'  feature
~~~

F1' 和 F2' 不是 F1、F2 的别名。它们的父提交、tree、提交者时间或签名字段可能不同，所以 OID 通常也不同。原 F1、F2 仍存在于 reflog、备份或其他 refs 中，直到对象保留窗口结束。

## “变化相同”不等于“提交相同”

rebase 尽量重现原提交带来的补丁，但新基线周围的内容可能已经改变，结果可能：

- 发生冲突；
- 生成不同的最终文件；
- 产生空提交；
- 触发 hooks、签名或测试差异；
- 因依赖缺失而无法继续。

因此 rebase 后需要同时比较最终 tree 和提交图：

~~~bash
old_tip="$(git rev-parse HEAD)"
git rebase main
new_tip="$(git rev-parse HEAD)"
git diff main...HEAD
git log --graph --decorate --oneline --all
printf 'old=%s new=%s\n' "$old_tip" "$new_tip"
~~~

old_tip 与 new_tip 不同是正常现象。不能只比较文件内容就说“历史没变”。

## rebase 与其他整合方式

| 动作 | 主线历史形状 | 是否生成新提交 | 适合场景 |
| --- | --- | --- | --- |
| merge | 保留两侧父关系，分叉时有 merge commit | 可能 | 已共享分支、保留集成事件 |
| rebase | 让功能提交接到新基线后 | 是 | 未共享分支、需要线性审查 |
| squash merge | 主线只写一个压缩提交 | 是 | 平台评审后压缩主线，但需保留来源证据 |
| cherry-pick | 在另一个分支应用指定变化 | 是 | 维护分支迁移独立修复 |

“线性”只描述提交图，不代表内容、评审或部署一定更可靠。选择首先由共享边界、回退需求和证据链决定。

## 选择 rebase 范围

默认 rebase 当前分支到目标：

~~~bash
git rebase main
~~~

明确把一段提交移到另一个新起点：

~~~bash
git rebase --onto release/1.x main feature/search
~~~

这会把 feature/search 中不属于 main 的提交，重放到 release/1.x。范围错误可能漏掉依赖或重放不该迁移的提交，执行前先用：

~~~bash
git log --oneline release/1.x..feature/search
git merge-base main feature/search
~~~

--keep-base 保留共同祖先作为基线，用于希望只重放未重复提交的场景，具体结果与 Git 版本和提交图有关。--rebase-merges 尝试重建原历史中的合并结构，而不是只沿第一父路径线性重放；它增加了 todo 计划和冲突复杂度，不能当作普通 rebase 的无损模式。

生产脚本应显式写目标、范围和 Git 版本，不依赖当前目录或默认上游。

## 共享边界是黄金判断

判断能否直接 rebase，先问谁已经拿到这些 OID：

- 只在本地、只有当前操作者使用：通常可以按团队约定 rebase；
- 已推送但没有协作者依赖：需要明确通知并保存旧 OID；
- 已被评审、其他 worktree、CI、制品或部署引用：默认追加修正或 merge；
- 已进入共享主线：不要未经协调改写。

rebase 后普通 push 通常会因远端仍指向旧 commit 而拒绝。允许改写时也应使用显式 lease，保存 expected-old、new OID 和恢复 bundle。force-with-lease 不是备份和授权替代品。

## 签名、审计和外部证据

rebase 产生新 commit，原 commit 的签名不会自动迁移到新对象。若团队要求签名，必须在重建后重新签名并核对新 OID。评审链接、CI 结果、制品摘要和部署记录若绑定旧 OID，也需要重新生成或明确映射。

作者字段通常可以保留，提交者和时间可能变化。不要把“作者没变”解释成对象和责任链没变。

## 失败状态

rebase 进行中可能写入 rebase-merge 或 rebase-apply 状态目录，HEAD 可能暂时停在某个中间提交。先执行：

~~~bash
git status
git rebase --show-current-patch
git rev-parse --verify REBASE_HEAD
git ls-files --unmerged
~~~

不同后端和版本的状态文件略有差异，status 是面向人的入口，show-current-patch 用于确定正在重放的原提交。不要删除状态目录来“结束”。

## continue、skip、abort 与 quit

- git rebase --continue：解决当前提交后继续重放；
- git rebase --skip：放弃整个当前来源提交，只有确认变化已存在或明确不需要时使用；
- git rebase --abort：尝试恢复到 rebase 开始前的分支、index 和工作区；
- git rebase --quit：清除状态目录但保留当前 HEAD、index 和工作区，交给操作者接管。

abort 在开始前工作区干净时最可靠。已有未提交修改、autostash、外部编辑或多个 worktree 会让恢复更复杂。quit 不是 abort 的快捷写法。

## 失败路径和恢复

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| rebase 找不到共同祖先 | 两端 OID、merge-base、浅状态 | 检查历史范围和浅克隆，不强行 onto |
| 冲突反复出现 | 当前 patch、stages、目标 tree | 按提交意图逐次解决，或 abort |
| 产生空提交 | 目标是否已有等价变化 | 选择 skip 或明确保留空提交 |
| 新 OID 已被别人引用 | 旧/新 OID、评审和 CI 记录 | 停止推送，协调使用者 |
| rebase 后 push 被拒绝 | 远端 old OID、lease、并发更新 | 先核对远端，再按授权使用租约 |
| abort 后恢复不完整 | 开始前状态和保存副本 | 从副本或恢复引用重建，不删除现状 |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-history.sh
~~~

实验验证非快进后 rebase 能保留功能变化但生成新 OID，再推送到本地 bare server；它不验证真实评审、CI、签名、制品或平台的强制更新权限。

## 小结

rebase 是重建提交，不是移动旧对象。先确认范围和共享边界，再选择普通或带范围的 rebase；完成后核对新 OID、最终 tree、测试和外部引用。冲突时 continue、skip、abort、quit 的后果不同，强制更新必须由显式租约和协作授权保护。
