# 工作做到一半需要切任务：stash 的临时状态与恢复边界

stash 适合保存一段还不能形成正式提交的本地修改，让当前工作区回到可切换状态。它是仓库中的临时引用和提交对象，不是云端同步，也不是长期备份。使用前要先判断修改是否真的不能提交，以及它是否包含不能进入共享对象库的敏感内容。

## 进入条件与完成标准

在需要临时收纳的本地仓库根目录执行。先记录：

~~~bash
git status --short --branch --untracked-files=all
git diff --no-ext-diff --no-textconv
git diff --no-ext-diff --no-textconv --staged
git branch --show-current
git rev-parse --verify HEAD^{commit}
~~~

工作区可以有已跟踪和未跟踪修改，但必须是你明确拥有的内容。不要在真实项目中用 stash 替代提交、评审或备份流程，也不要把生产令牌、私钥和客户数据放进 stash。

读完本章后，你应能：

- 解释 stash 保存的对象和 refs/stash 入口；
- 区分普通收纳、包含未跟踪、包含忽略文件和只收纳 index；
- 选择 apply、pop、branch、drop 和 abort 风格的恢复动作；
- 处理应用冲突、stash 记录保留和恢复失败；
- 从 stash reflog 或对象库寻找意外删除的记录；
- 说明 stash 中的秘密仍然可能被对象和副本保留。

## stash 保存什么

执行：

~~~bash
git stash push -m "wip: search filter draft"
~~~

Git 会把当前工作区相对 HEAD 的变化保存到一个由 refs/stash 指向的对象集合，并把工作区和 index 恢复到适合继续操作的状态。现代命令使用 push，旧资料中的 save 只应作为历史写法识别。

常见工作模型：

~~~text
HEAD = H
工作区 = W
index = I

stash@{0} -> 保存 W/I 相对 H 的临时对象
工作区和 index -> 回到 H
~~~

stash 本身不是一个“文件压缩包”。内部通常包含一个表示工作区状态的提交和一个表示 index 状态的父提交；包含未跟踪文件时还可能有额外父提交。具体对象形状可能随 Git 版本和选项变化，恢复时以 refs/stash、父列表和 tree 为准。

stash push 通常写入对象、index 和 refs/stash reflog，属于有副作用动作。成功后立即检查：

~~~bash
git status --short --branch --untracked-files=all
git stash list
git stash show --stat stash@{0}
git show --no-patch --format='%H%n%P%n%T%n%s' stash@{0}
~~~

工作区“干净”只表示已跟踪和被扫描的变化已处理，不表示 stash 内容已备份、已加密或已上传。

## 未跟踪和忽略文件的范围

普通 stash 默认只收纳已跟踪文件的工作区和 index 修改。需要包含未跟踪文件：

~~~bash
git stash push --include-untracked -m "wip: search filter with new files"
~~~

短选项 -u 等价。被忽略文件默认仍不包含；连忽略文件一起收纳：

~~~bash
git stash push --all -m "wip: complete local fixture"
~~~

-a 会把忽略的构建产物、日志和本地缓存也放进 stash，可能产生很大对象和敏感数据。除非已逐项审查，否则不要在大型仓库或生产工作区使用 --all。

收纳前先查看范围：

~~~bash
git status --short --ignored --untracked-files=all
git check-ignore -v -- path/to/suspect
~~~

如果未跟踪路径来自另一个人的工作或含秘密，停止操作。stash 会把收纳内容写进本地对象库，忽略规则不会提供访问控制。

## 只收纳部分变化

可以只对指定路径收纳：

~~~bash
git stash push -m "wip: selected files" -- path/to/file-a path/to/file-b
~~~

也可以交互选择 hunk：

~~~bash
git stash push --patch -m "wip: selected hunks"
~~~

pathspec 和 patch 的选择结果取决于当前 index、属性和工作区内容。执行后保存 status、stash show 和未收纳的 diff，确认没有把工作区误认为已经全部清空。对于需要长期协作的改动，优先拆成正式提交而不是长期依赖部分 stash。

## index 的两个特殊选项

若已暂存的内容应保持在 index，只收纳未暂存修改：

~~~bash
git stash push --keep-index -m "wip: leave staged candidate"
~~~

若只想保存已经暂存的修改：

~~~bash
git stash push --staged -m "wip: staged candidate"
~~~

这两个选项会让工作区和 index 的结果不同于普通 stash。执行后用：

~~~bash
git status --short
git diff
git diff --staged
~~~

验证剩余内容。不要只看 stash list 判断操作成功。

## apply、pop 和 branch

恢复前先查看目标上下文：

~~~bash
git status --short --branch
git log --oneline --decorate -3
git stash show --stat stash@{0}
~~~

优先采用 apply：

~~~bash
git stash apply stash@{0}
git status --short --untracked-files=all
git diff
git diff --staged
~~~

apply 尝试恢复但保留 stash 记录，适合先验证。确认内容、测试和提交都正确后再删除：

~~~bash
git stash drop stash@{0}
~~~

pop 等价于尝试 apply，成功后再删除记录：

~~~bash
git stash pop stash@{0}
~~~

如果应用发生冲突，stash 记录通常仍保留，不能假设 pop 已经删除。此时先保存冲突现场，解决或恢复后再明确 drop。

复杂 stash 更适合创建独立分支：

~~~bash
git stash branch recover/search-filter stash@{0}
~~~

它通常从 stash 创建时的基线提交创建新分支，再应用 stash。该命令可能切换工作区并因冲突失败。成功后验证新分支、父提交、工作区和测试，不要把 branch 当成无冲突保证。

## 应用冲突的处理顺序

stash 应用本质上是把旧工作区变化套到当前上下文，当前分支如果已改变就可能冲突。先记录：

~~~bash
git status --short --branch
git stash show --patch stash@{0}
git ls-files --unmerged
git reflog --all -5
~~~

对冲突路径按照合并流程决定最终内容，逐路径 add 或 rm，再运行测试。不要在不了解差异时使用 restore --source=HEAD 或 reset --hard 清场。若不想继续应用，保留 stash 记录，另建恢复分支或从备份复制内容。

stash 应用不一定保留原始提交作者、文件模式和外部工具状态。过滤器、换行、子模块和 LFS 路径都需要重新核对。

## stash list、索引和删除

查看记录：

~~~bash
git stash list --date=iso-strict
git reflog show refs/stash
git show --stat stash@{0}
~~~

stash@{0} 是当前最新记录，新增或删除记录后编号会变化。长期任务不要只在工单中写编号，记录完整 stash commit OID、创建时间、分支和基线。

删除单条记录：

~~~bash
git stash drop stash@{0}
~~~

清空所有 stash：

~~~bash
git stash clear
~~~

clear 会删除 refs/stash 入口，可能让多个未提交工作失去直接恢复路径。真实仓库执行前先导出重要记录或建立分支。事故现场不要运行 clear、gc 或 prune。

## 误删 stash 怎样恢复

stash drop 或 clear 之后，对象可能暂时仍在本地：

~~~bash
git fsck --no-reflogs --unreachable
git reflog --all
~~~

找到疑似 stash commit 后，先建立恢复引用：

~~~bash
git branch recovery/stash <full-commit-id>
git show --stat recovery/stash
~~~

对象不可达并不代表永久保留。自动维护、对象过期、重新打包和其他 clone 都会改变恢复机会。stash 不能替代正式提交或备份。

## 敏感内容和安全边界

stash 不是加密容器。加入 stash 的秘密可能出现在：

- 本地对象库、packfile 和 refs/stash reflog；
- 文件系统快照、备份和磁盘恢复空间；
- IDE、终端、错误日志和安全扫描缓存；
- 同步工具或团队共享的本地仓库副本。

如果误把凭据放入 stash，先按凭据撤销和轮换流程处理，再评估对象和副本清理。删除 stash 记录本身不能证明秘密已从所有对象和副本消失。

## 失败路径和恢复

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| stash 后仍有文件 | status、未跟踪/忽略扫描、pathspec | 判断是否故意保留或使用 -u，逐项处理 |
| apply/pop 冲突 | stash OID、当前 HEAD、stages、diff | 保留 stash，逐路径解决或恢复 |
| pop 失败但记录消失 | stash reflog、对象 fsck、操作输出 | 先建 recovery ref，不运行清理 |
| stash 过大或失败 | 对象统计、磁盘空间、路径范围 | 停止扩大范围，拆分或正式提交 |
| 需要跨天协作 | 分支、提交、评审状态 | 把工作转换为正式提交，不长期依赖 stash |
| stash 含真实秘密 | refs、对象、日志、副本 | 先撤销轮换，再按历史清理流程处置 |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-6-engineering.sh
~~~

实验验证已跟踪和未跟踪修改经 -u 收纳后可以恢复，apply 保留记录，工作区可以回到已知状态。它不证明 stash 的加密、跨设备恢复、文件系统快照清理、真实凭据处置或平台同步。

## 小结

stash 是本地临时状态入口，不是备份。先记录工作区、index 和分支，再选择收纳范围；恢复优先 apply，验证后再 drop，重要 stash 可以转成恢复分支。冲突、删除和秘密泄漏都要保留对象证据，不能用“状态干净”证明内容已经安全。
