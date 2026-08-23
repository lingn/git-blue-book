# 阅读本地历史：`git log`、`git show` 与范围

提交创建后，问题从“现在改了什么”变成“这份内容从哪里来”。`git log` 和 `git show` 都是本地历史查询命令，但它们只看得到当前解析范围内、且能从指定引用或对象找到的内容。网页平台、远程服务器和已经过期的远程跟踪分支都不能被它们自动替代。

本章把历史阅读变成可复核的证据工作。所有命令在仓库根目录执行，示例中的行号、对象 ID 和提交时间都以本地实际值为准。

## 进入条件与完成标准

准备一个至少有两条提交的练习仓库。若仓库还没有提交，先按前几章完成最小提交。查询不需要网络。

读完本章后，你应能：

- 区分“当前分支历史”“所有本地引用可达历史”和“远程平台历史”；
- 用图形、摘要、父提交和路径过滤阅读提交；
- 理解 `A..B` 和 `A...B` 的范围差异；
- 用 `show` 同时查看提交元数据、快照和相对父提交的差异；
- 在短 ID 歧义、浅克隆、删除分支和对象不可达时停止误判；
- 保存足以复核的完整对象 ID、引用名称和查询条件。

## 先看当前引用指向哪里

在仓库根目录执行：

~~~bash
git status --short --branch
git symbolic-ref --quiet --short HEAD || git rev-parse --verify HEAD
git rev-parse --verify HEAD^{commit}
~~~

第一条显示当前工作区状态和分支摘要。第二条在有分支时输出分支名，分离 `HEAD` 时输出提交 ID。第三条确认 `HEAD` 最终解析为 commit 对象；首次提交前它会失败，这是“还没有历史”的证据。

记录历史时，至少保存：

- 完整提交 ID，而不是只保存四位短前缀；
- 查询使用的引用，例如 `main`、`HEAD` 或 `--all`；
- 是否使用了路径、时间、父提交或浅克隆过滤；
- 查询发生的时间和本地 Git 版本。

提交 ID 是对象内容的结果，身份、父提交、时间和说明任何一项变化都会生成新 ID。示例中的 ID 只能当作占位符。

## `git log` 的默认范围

最简单的列表：

~~~bash
git log
~~~

默认从当前 `HEAD` 沿父提交向后遍历，通常按新到旧显示提交说明、作者和时间。它不会自动列出其他本地分支，也不会查询远端。

更适合理解提交图的形式：

~~~bash
git log --graph --decorate --oneline --all
~~~

各选项的作用是：

| 选项 | 作用 | 可能的误解 |
| --- | --- | --- |
| `--graph` | 用字符表示父子分叉 | 不是完整的拓扑图可视化 |
| `--decorate` | 显示分支、标签等引用名 | 引用名不是提交对象的一部分 |
| `--oneline` | 缩短提交说明和 ID | 短 ID 可能随仓库增长变得不唯一 |
| `--all` | 从本地 refs 的多个入口遍历 | 不会刷新远端，也不代表平台所有 refs |

输出顺序受拓扑、日期和选项影响。自动化不要解析彩色图形字符；可以使用机器格式：

~~~bash
git log --format='%H%x09%P%x09%an%x09%ae%x09%s' --no-color
~~~

如果提交说明、姓名或路径可能包含制表符和换行，需使用更严格的格式或 NUL 分隔方案，并按项目的证据采集规范解析。不要把示例格式直接当作通用 CSV。

## `git show` 查看一份对象和差异

对某个完整 ID 或足够唯一的前缀执行：

~~~bash
git show --format=fuller --stat <commit-id>
git show --format=fuller --name-status <commit-id>
git show <commit-id>
~~~

当参数是 commit 时，`show` 显示提交字段和相对于父提交的差异。合并提交默认可能使用 combined diff，某个文件如果没有相对多个父提交的独特变化，输出中可能被省略；要分别审查每个父提交，应显式使用 `-m` 或父提交选择语法。根提交没有父提交，差异会按空树与该提交的 tree 计算。使用 `--stat` 只看统计，`--name-status` 看路径状态，适合先缩小范围。

要查看提交中的某个文件在该快照的内容：

~~~bash
git show <commit-id>:README.md
~~~

冒号后的路径属于该提交的 tree，不是当前工作区路径。路径包含特殊字符时应引用整个参数，且先用 `git cat-file -e <commit-id>:path` 检查对象是否存在。

提交说明和差异不是同一层证据。提交说明是作者提供的意图，tree 和 blob 才是实际快照。审查时把“说了什么”和“写入了什么”分开核对。

## 两种范围写法

设 `A` 和 `B` 都能解析为提交：

~~~bash
git log A..B
git log A...B
~~~

含义如下：

| 范围 | 实际集合 | 常见问题 |
| --- | --- | --- |
| `A..B` | 从 B 可达、从 A 不可达的提交 | “B 比 A 多了什么” |
| `A...B` | 两侧各自可达、但不在共同祖先之后的对称差集 | “两侧各自有哪些分叉提交” |

`A..B` 不显示 A 本身，`A...B` 也不是“从共同祖先到 B 的所有提交”。要先确认共同祖先：

~~~bash
git merge-base A B
git log --left-right --graph --oneline A...B
~~~

`--left-right` 用符号标出提交属于哪一侧。若任一名称解析失败，先用 `git rev-parse --verify` 检查引用，不要修改分支来“让范围命令通过”。

## 从路径阅读一条变化线

只看某个路径的提交：

~~~bash
git log --oneline --follow -- README.md
~~~

`--follow` 只对单一路径工作，并通过相似度启发式尝试跨重命名追踪。它可能漏掉复制、复杂拆分、合并中的一侧变化，不能作为绝对归因证明。目录范围使用：

~~~bash
git log --oneline --all -- docs/
git log --diff-filter=D --summary --all -- path/to/file
~~~

如果要搜索内容变化，后续历史取证篇会介绍 `-S`、`-G`、`blame`、`-M` 和 `-C`。本章只建立可靠入口，不把启发式结果当成唯一事实。

## 合并提交和主线视角

合并提交有多个父提交。普通 `git show <merge>` 默认主要展示相对第一个父提交的差异，可能无法解释另一条分支带来的完整变化。需要明确每个父提交：

~~~bash
git rev-list --parents -n 1 <merge-commit>
git diff <merge-commit>^1 <merge-commit>
git diff <merge-commit>^2 <merge-commit>
~~~

`^1`、`^2` 是父提交选择语法，前提是该提交确实有对应父节点。团队审查主线发布时可以使用：

~~~bash
git log --first-parent --oneline <main-ref>
~~~

`--first-parent` 适合观察主线合入事件，不等于完整代码演变历史。它和完整图、逐父 diff 应分别保存，不要用一个视角替代另一个。

## 标签、远程跟踪和网页历史

查看本地引用：

~~~bash
git show-ref
git for-each-ref --format='%(refname) %(objectname) %(objecttype)'
~~~

轻量标签通常直接指向 commit，附注标签指向 tag 对象。查看标签时用：

~~~bash
git show <tag-name>
git rev-parse <tag-name>^{commit}
~~~

`origin/main` 是本地的远程跟踪引用，不是服务器实时查询。它只有在上次 fetch 后才更新。网页上的评审状态、合并队列、CI 结果、部署版本和权限事件不属于 Git 对象，`git log` 无法单独证明它们。

若需要查询远端可见的引用而不更新本地 refs，可以在有权限和网络的环境中使用：

~~~bash
git ls-remote --heads <remote-url>
~~~

这会访问远端并可能暴露 URL、认证来源和网络信息，不属于本地只读实验。命令输出只能证明该次会话能看到的引用，不能替代平台控制面审计。

## 删除分支、reflog 与可见性边界

删除本地分支会移除一个引用名，但未必立即删除对象。其他分支、标签、reflog 或已知 ID 可能仍能找到提交。反过来，`git log --all` 只遍历当前 refs，找不到某个对象不等于它从磁盘和所有副本中消失。

事故时先保存：

~~~bash
git for-each-ref
git reflog --all
git fsck --no-reflogs --unreachable
~~~

`reflog` 是本地引用移动记录，不是远程审计日志；`fsck` 的不可达对象也可能在维护后过期。恢复章节会说明如何建立恢复引用。当前不要运行 `gc`、`prune` 或删除对象来“整理历史”。

## 浅克隆的历史边界

如果仓库来自浅克隆，`git log` 只能看到本地已有的祖先范围。检查边界：

~~~bash
git rev-parse --is-shallow-repository
git log --boundary --oneline HEAD
~~~

输出中的边界提交不是完整历史的证明。需要更多祖先时，使用目标环境允许的 `fetch --deepen` 或 `--unshallow`，并记录网络、权限和对象量影响。不要在排障报告中把浅边界外的提交写成“不存在”。

## 历史查询失败时的恢复路径

| 现象 | 首先收集 | 正确分流 | 不要做的事 |
| --- | --- | --- | --- |
| `ambiguous argument` | 完整前缀、候选引用和 `git show-ref` | 改用完整 OID 或限定引用 | 随意删除同名分支 |
| `bad object` | 引用、浅状态、对象库统计 | 判断对象缺失、权限或拼写错误 | 立刻运行清理 |
| `A..B` 没输出 | 两端 OID、merge-base、当前 refs | 可能是 B 没有新增提交 | 以“Git 丢了提交”结束调查 |
| 路径历史断开 | 重命名、合并、pathspec 和 `--follow` 限制 | 保存多个查询视角 | 把启发式路径追踪当作绝对归因 |
| 本地和网页不一致 | fetch 时间、远程跟踪 OID、平台页面 | 分开记录 Git 数据面和平台控制面 | 直接 reset 或强推“同步” |
| 找不到误删提交 | reflog、其他 refs、bundle/副本 | 先建立恢复引用，再评估可达性 | 先 gc 或 prune |

所有查询失败都应保留原始错误、命令和执行位置。历史阅读不会修复引用，误用改写命令反而可能扩大事故。

## 一个可复核的历史阅读顺序

在提交审查、回滚评估或故障调查中，可以保存：

~~~bash
git status --short --branch
git log --graph --decorate --oneline --all
git show --format=fuller --stat <candidate>
git show <candidate> -- path/to/file
git rev-list --parents -n 1 <candidate>
~~~

最后一条把父提交列表固定下来。若候选来自远程或平台，另存远端查询结果、平台事件 ID 和核对时间，不能只给本地 `log` 截图。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-2.sh
~~~

共享实验会创建多条本地提交，验证 `log --oneline` 顺序、`show --stat` 的路径统计、完整 ID 可解析、范围查询和最终历史计数。提交时间和 OID 由临时身份、时钟和 Git 版本决定，脚本只检查关系与标题，不伪造平台页面输出。

实验不能证明远端历史、评审事件、签名信任、部署记录、浅克隆之外的对象或其他 clone 的 reflog。那些证据必须从相应系统和副本中获取。

## 小结

`git log` 从引用出发读取可达提交，`git show` 把一个对象的元数据、快照和相对父提交的差异展开。先固定引用和完整 OID，再选择图形、范围、路径或父提交视角；明确本地远程跟踪缓存、浅边界和平台控制面，才能避免把“当前看不到”误判成“历史不存在”。
