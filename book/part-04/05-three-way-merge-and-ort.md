# `ort` 三方合并：策略生成候选 tree，不替团队判断业务

`ort` 是当前 Git 对两个头执行普通三方合并时的默认策略。它读取最佳共同祖先、当前 `HEAD` 和被合入提交的 tree，计算路径变化、推断重命名并尝试组合。没有机械冲突时，策略可以直接生成候选 tree；有冲突时，它保留 index stages、工作区结果和操作状态，等待人作决定。

策略成功只说明 Git 找到了结构上可提交的 tree。两个分支分别修改不同行，却可能共同破坏锁顺序、协议兼容、配置约束或数据库迁移。测试、评审和运行验证不属于合并算法。

## 进入条件与完成标准

本章实验以 Git 2.49.0 为核对版本。旧 Git 可能使用不同默认策略，也可能没有 `AUTO_MERGE`。真实仓库先记录：

~~~bash
git version
git status --short --branch
git config --show-origin --get-regexp '^merge\.'
git rev-parse 'HEAD^{commit}'
git rev-parse 'refs/heads/topic^{commit}'
git merge-base --all HEAD topic
~~~

配置没有匹配时 `config --get-regexp` 返回 1，不代表 merge 不可用。所有写入示例只在可销毁仓库执行。

读完本章后，应能解释 `ort` 的三方输入、多 base 和重命名推断，区分 strategy 与 strategy option，读取冲突现场的 `HEAD`、`MERGE_HEAD`、index 和 `AUTO_MERGE`，并说明自动合并结果需要哪些额外验证。

## 策略从提交图走到结果 tree

`git merge topic` 在分叉历史中的主要输入为：

~~~text
base tree       最佳共同祖先或递归合成的参考 tree
ours tree       merge 开始时的 HEAD tree
theirs tree     topic 尖端的 tree
~~~

`ort` 比较 base 到两侧的路径、mode 和对象变化，再生成结果。存在多个最佳共同祖先时，它可以先合并这些 base，构造虚拟参考 tree。最终 merge commit 只保存父 OID 和结果 tree，不保存“使用了哪个虚拟 base”或一份冲突路径清单。

因此，事故与审计要在合并现场保存：

~~~bash
git merge-base --all HEAD topic
git diff --name-status -z "$(git merge-base HEAD topic)" HEAD
git diff --name-status -z "$(git merge-base HEAD topic)" topic
~~~

简单图中单个 base 可以这样观察。多个 base 时不要任取第一行冒充完整输入；保存全集、Git 版本、策略和最终 tree。

## Strategy 与 strategy option 作用范围不同

下面两种写法名字相近，结果完全不同：

~~~bash
git merge -X ours topic
git merge -s ours topic
~~~

`-X ours` 是 `ort` 的策略选项。发生内容冲突时，它偏向 ours，但 theirs 中没有冲突的新增或修改仍会进入结果。它不等于“最终 tree 使用当前分支全部内容”。

`-s ours` 选择 `ours` 合并策略。结果 tree 完全等于当前 `HEAD` tree，忽略其他头的 tree 变化；成功的 merge commit 仍把其他头记录为父提交，因此图上显示历史已合并。

Git 没有一个与 `ours` strategy 对称的内置 `theirs` strategy。`-X theirs` 只是 `ort` 的相反冲突偏好。

这两类选项都不能作为日常“自动解决冲突”按钮。使用前要列出被舍弃的 path/OID、配置与 schema 变化，验证最终 tree 和运行行为，并在评审中说明为什么整个 tree 或冲突 hunk 可以偏向一侧。

## 自动合并没有 unmerged stage

两侧修改不同路径时，`ort` 可以直接形成 stage 0：

~~~bash
git merge --no-ff --no-commit topic
git ls-files --unmerged
result_tree="$(git write-tree)"
git diff --staged --check
~~~

`ls-files --unmerged` 无输出表示 index 已有唯一候选，不表示业务正确。至少核对：

- result tree 同时包含预期两侧变化；
- 没有生成物、属性/filter 或 mode 意外变化；
- 两父视角的 diff 可解释；
- 目标测试、构建、配置和数据库兼容检查通过；
- 候选 OID 与评审/CI 结果绑定。

需要放弃时，在仍有 `MERGE_HEAD` 的状态执行 `git merge --abort`。合并前存在本地修改时，abort 的恢复边界更复杂，不能把它当备份。

## 冲突现场有四类状态

普通 merge 停止后：

~~~text
HEAD        合并前当前分支的 commit
MERGE_HEAD  被合入的 commit
index       自动合并的 stage 0 与冲突 stage 1/2/3
工作区      自动结果、冲突标记和后续人工编辑
~~~

先采集，不先编辑：

~~~bash
git status --short --branch
git rev-parse 'HEAD^{commit}'
git rev-parse 'MERGE_HEAD^{commit}'
git ls-files --unmerged
git diff --name-status --diff-filter=U
~~~

`HEAD` 通常没有移动。`MERGE_HEAD` 不存在时，现场可能是 rebase、cherry-pick、revert 或普通脏工作区，不能运行错误的 `merge --continue`。

Index stage 的完整数据模型见[Index 内部结构](../part-03/05-index-internals.md)。工作区标记只是可编辑视图；路径、二进制和 submodule 冲突可能没有 `<<<<<<<`。

## Conflict style 只改变工作区展示

~~~bash
git config --local merge.conflictStyle zdiff3
git config --show-origin --get merge.conflictStyle
~~~

`diff3` 会把 base 段加入文本标记，`zdiff3` 还会压缩三方共同上下文。配置影响随后生成的文本冲突，不修改 stage 对象，不解决二进制或路径冲突。旧 Git 不支持 `zdiff3` 时应使用已验证选项，不把新版本输出写成全局事实。

团队统一配置要记录作用域与版本。仅为一次冲突修改全局配置，会影响其他仓库；回退前用 `--show-origin` 确认值来自哪里。

## `AUTO_MERGE` 记录初始自动结果

Git 2.49.0 的 `ort` 在冲突时写 `AUTO_MERGE`，指向包含初始工作区冲突内容的 tree：

~~~bash
git cat-file -t AUTO_MERGE
auto_merge_tree="$(git rev-parse 'AUTO_MERGE^{tree}')"
git diff AUTO_MERGE
~~~

刚停止且未编辑时，`git diff AUTO_MERGE` 通常为空。人工修改受跟踪文件后，它显示相对初始自动结果的进展。这有助于分开 Git 生成内容与人工决策。

`AUTO_MERGE` 不是永久 ref、发布候选或平台审计。后续操作可以覆盖或删除它，旧版本和其他策略可能没有它，未跟踪文件也不在 tree 中。需要留证时保存 tree OID、stage 清单、工作区副本和人工说明。

## Rename detection 是 tree 差异推断

Commit 不保存 rename 事件。`ort` 根据删除/新增内容的相似度和候选集合推断文件重命名，再由多条 rename 推断目录迁移。复制检测不是普通 merge rename 处理的同义词。

观察配置：

~~~bash
git config --show-origin --get merge.renames
git config --show-origin --get merge.renameLimit
git config --show-origin --get merge.directoryRenames
~~~

未设置时使用当前版本默认值。大规模删除/新增、生成文件和低相似度改写可能让预期 rename 未被识别。不要为了让一次 merge 通过就全局提高 limit 或改成自动目录迁移；在隔离分支记录候选规模、耗时、配置和最终 path/OID。

具体 rename/delete、rename/rename 和目录迁移决策由下一章负责。

## 自动结果必须按业务闭包验证

文本不重叠仍可能语义冲突，比如：

- 一侧新增必填字段，另一侧新增旧格式客户端；
- 一侧改变锁顺序，另一侧引入第二把锁；
- 一侧迁移配置路径，另一侧在旧路径新增键；
- 一侧改变数据库约束，另一侧部署仍写旧值；
- 一侧升级生成器，另一侧提交由旧生成器产生的文件。

验证从变更闭包出发，而不是只测冲突路径。保存依赖图、测试选择、构建输入、schema 兼容和最终制品证据。Git 的退出码 0 只证明策略完成。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| 自动 merge 成功但行为失败 | 三方 tree、依赖闭包、测试和配置 | 未提交时 abort；已提交按共享边界修复 |
| `AUTO_MERGE` 不存在 | Git 版本、策略、是否确有冲突 | 使用 stages/工作区证据，不伪造引用 |
| `-X ours` 仍带入 theirs 文件 | 策略选项语义、非冲突 paths | 审查完整 result tree；需要全 ours 要另行审批策略 |
| `-s ours` 丢失预期变化 | 最终 tree、父列表和使用理由 | 阻止发布，重新构造正确候选 |
| 预期 rename 被当作删除/新增 | 相似度、候选数、配置和两侧 tree | 在副本调整参数并评审，不全局覆盖 |
| 文本标记消失但仍不能提交 | `ls-files -u`、路径类型、其他冲突 | 逐条解决 index，不能只 grep 标记 |
| 策略/配置不一致 | `--show-origin`、命令参数和 Git 版本 | 固定候选环境，显式选择并重新验证 |

共享错误 merge 不应通过重写隐藏。保留父 OID、结果 tree、评审与发布状态，按第七篇使用 revert 或追加修复；数据库与部署状态单独恢复。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-ort-path-conflicts.sh
~~~

实验对同一分叉分别执行 `-X ours` 和 `-s ours`，断言前者保留 theirs 非冲突新增，后者结果 tree 等于 main，但两者都创建二父 commit。它还制造内容冲突，验证 `AUTO_MERGE` 是 tree、初始 diff 为空、人工编辑后 diff 出现。

已有 `scripts/verify-complex-conflicts-rerere.sh` 继续验证 zdiff3、rename/delete、目录重命名和 rerere。实验只证明 Git 2.49.0 的本地行为，不外推平台合并实现或业务正确性。

## 小结

`ort` 根据 base、ours 和 theirs 的 tree 生成候选，rename 与目录迁移来自推断。`-X ours`、`-s ours` 的作用范围不同，`AUTO_MERGE` 也只是临时解决基线。无机械冲突不能证明业务兼容，最终 tree、测试、评审和发布证据必须分别验收。

## 资料

- [git-merge](https://git-scm.com/docs/git-merge)
- [merge strategies](https://git-scm.com/docs/merge-strategies)
- [git-merge-tree](https://git-scm.com/docs/git-merge-tree)
- [git-diff](https://git-scm.com/docs/git-diff)
- [git-config](https://git-scm.com/docs/git-config)
