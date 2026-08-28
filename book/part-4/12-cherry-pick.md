# 只迁移需要的提交：cherry-pick 的来源、目标和新 OID

cherry-pick 适合把一个已经存在的提交所表达的变化应用到另一条历史。它复制的是变化，不是把原提交从一个分支搬到另一个分支。目标分支会得到一个新的 commit，新的父提交和上下文可能让结果不同。

## 进入条件与完成标准

假设修复提交在 develop，维护分支 release/1.x 只需要这一个修复。开始前在目标仓库执行：

~~~bash
git status --short --branch
git rev-parse --verify develop^{commit}
git rev-parse --verify release/1.x^{commit}
git show --no-patch --format='%H%n%P%n%T%n%s' <fix-commit>
~~~

目标工作区和 index 应干净。来源提交必须是已经取得且对象完整的本地 commit，不能只凭网页标题或短 ID 猜测。

读完本章后，你应能：

- 解释来源提交、目标分支和新提交的关系；
- 用 full OID 和路径差异审查 cherry-pick 输入；
- 识别多提交顺序、依赖、merge commit 和空提交风险；
- 处理冲突、continue、abort 和 skip；
- 判断重复挑选、补丁相同但 OID 不同和后续合并的影响；
- 将修复来源、目标、测试和发布证据写入变更记录。

## 提交图和结果形状

来源历史：

~~~text
develop: A <- B <- F
release: A <- R
~~~

在 release 上挑选 F：

~~~text
release: A <- R <- F'
~~~

F' 的父提交是 R，不是 F 的父提交 B，因此 F' 的 OID 与 F 不同。原提交 F 仍在 develop 或其他 refs 中，cherry-pick 不会移动来源分支。

如果目标已经包含 F 的等价变化，Git 可能报告空提交或提示变化已经存在。空结果需要人工判断，不能为了得到一个新节点强制提交。

## 先核对来源和目标

获取来源分支的最新本地观察点：

~~~bash
git fetch origin
git show --format=fuller --stat <fix-commit>
git show <fix-commit> -- path/to/fix
git rev-list --parents -n 1 <fix-commit>
~~~

记录：

- 来源完整 OID 和父提交；
- 来源提交改变的路径；
- 目标分支当前 OID；
- 该修复是否依赖前序提交、配置、迁移或其他组件；
- 目标分支是否已经包含等价变化。

切到目标分支并再次确认：

~~~bash
git switch release/1.x
git status --short --branch
git rev-parse HEAD
~~~

不要在有未提交工作时直接挑选。cherry-pick 会写对象、index 和工作区，冲突时还会写 CHERRY_PICK_HEAD 和临时状态。

## 挑选一个提交

~~~bash
git cherry-pick <fix-commit>
~~~

成功后：

~~~bash
git show --no-patch --format='%H%n%P%n%T%n%s' HEAD
git show --stat HEAD
git status --short --branch
~~~

验证新提交的父提交是挑选前的 release 尖端，提交说明和最终 tree 符合修复意图。来源 OID 与目标新 OID 必须分开记录。

如果只想先把结果放入 index 再审查：

~~~bash
git cherry-pick --no-commit <fix-commit>
git diff --staged --check
git diff --staged
~~~

no-commit 不创建目标 commit，但会把变化放入 index 和工作区。确认后用明确说明的 git commit；发现结果不对则按路径恢复，不要继续挑选下一个提交。

## 多提交的顺序

挑选一组提交：

~~~bash
git cherry-pick <fix-1> <fix-2> <fix-3>
~~~

Git 按给定顺序应用。顺序通常应遵循来源历史，先挑基础改动再挑依赖它的修复。一次批量操作中任何提交冲突或失败，都可能留下进行中的 cherry-pick 状态；先看 status 和当前 CHERRY_PICK_HEAD，再决定继续或 abort。

如果提交是 merge commit，需要指定 mainline：

~~~bash
git cherry-pick -m 1 <merge-commit>
~~~

-m 选择把哪个父提交当作主线，补丁是 merge 相对该父提交的变化。选择错误会应用错误的差异，必须先读取 parent 列表和合并意图。不要对 merge commit 盲目使用 -m 1。

## 冲突、continue、skip 和 abort

冲突后先保存：

~~~bash
git status --short --branch
git rev-parse --verify CHERRY_PICK_HEAD
git cherry-pick --show-current-patch
git ls-files --unmerged
~~~

形成最终文件后逐路径标记：

~~~bash
git add -- path/to/resolved-file
git diff --staged --check
git cherry-pick --continue
~~~

continue 可能打开编辑器，也可能因 hook 或空提交再次失败。修复具体原因后重试。

skip 会跳过当前来源提交：

~~~bash
git cherry-pick --skip
~~~

只有确认该提交的变化已由目标现状提供、或责任人明确决定不需要时才使用。skip 会放弃整个当前提交的应用，不能把它当作“跳过冲突文件”。

放弃整个挑选序列：

~~~bash
git cherry-pick --abort
git status --short --branch
git rev-parse HEAD
~~~

abort 尝试恢复开始前的 HEAD、index 和工作区。开始前若已有未提交修改，恢复边界会变复杂，先用保存副本或独立 worktree。

## 重复挑选和等价补丁

F 与 F' 的内容可能相同，但对象 ID、父提交和作者/提交者字段可能不同。未来把 develop 合入 release 时，Git 可能识别等价补丁，也可能因为上下文、冲突或配置变化再次要求人工处理。

记录来源和目标：

~~~text
source_commit: <develop 中的完整 OID>
target_branch: release/1.x
picked_commit: <新提交完整 OID>
reason: 将安全修复迁移到维护分支
verification: <测试、构建和部署证据>
~~~

这份记录比在提交说明中写一个短 ID 更耐用。平台评审、制品和部署系统也要绑定目标新 OID，不能继续引用来源分支上的旧提交。

## 失败路径和恢复

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| bad object/unknown revision | 来源 ref、完整 OID、fetch 时间 | 先取得对象，不改目标分支 |
| cherry-pick 产生冲突 | CHERRY_PICK_HEAD、stages、当前目标 OID | 按路径解决、continue 或 abort |
| empty cherry-pick | 目标是否已有等价变化、来源说明 | 选择 skip、no-commit 后记录，或经批准的空提交 |
| 多提交顺序错误 | 每个来源 parent、依赖和结果 tree | abort 后按历史顺序重做 |
| merge commit 结果不对 | parent 列表、mainline 选择 | abort，重新选择父视角 |
| 目标分支已共享 | 目标 OID、评审/部署引用 | 追加修正或走发布流程，不重写 |
| push 后发现挑错 | source/target OID、制品和部署状态 | 用 revert 追加撤销，保留审计链 |

不要用 reset --hard 或删除 CHERRY_PICK_HEAD 作为完成手段。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-history.sh
~~~

实验验证 Bob 在非快进之后 rebase 生成新提交，维护分支从 develop 的修复提交创建不同 OID 的 cherry-pick 提交，并保持工作区干净。它不验证真实评审、平台权限、制品或部署。

## 小结

cherry-pick 把来源提交表达的变化应用到目标上下文，产生一个新的 commit。先核对来源、依赖和目标，再逐个按顺序应用；冲突时保留 CHERRY_PICK_HEAD 和 index 证据，continue、skip、abort 各有不同后果。发布记录同时保存 source、target、picked OID 和验证结果，才能保持可追溯。
