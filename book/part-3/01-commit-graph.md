# 提交如何组成历史：从父提交读懂提交图

第二篇把文件内容写进提交。现在把提交从列表里还原出来：一个提交不是“第 3 版”的编号，而是一个带有完整快照和父提交指针的对象。分支、合并、rebase、回滚和远端拒绝，最终都在回答同一个问题：某个提交能否沿父关系到达另一个提交。

## 进入条件与完成标准

准备一个至少有两条提交的练习仓库，在仓库根目录执行命令。先保存：

~~~bash
git status --short --branch
git --version
~~~

如果工作区不干净，先完成或保存当前工作。不要在真实项目里为了制造图形而删除分支或重置引用。

读完本章后，你应能：

- 读取一个提交的完整 OID、父提交、根 tree 和说明；
- 区分根提交、普通提交和合并提交；
- 用可达性而不是时间判断两个提交的关系；
- 用 \`merge-base\`、\`--first-parent\` 和 \`--ancestry-path\` 选择历史视角；
- 解释分支名只是引用，提交图本身不保存分支名；
- 在历史查询失败时保留证据，不把空输出解释成数据丢失。

## Commit 里保存了什么

对当前提交执行：

~~~bash
git show --no-patch --format=fuller HEAD
git rev-list --parents -n 1 HEAD
git rev-parse HEAD^{tree}
~~~

第一条展示作者、提交者、时间、说明和其他元数据。第二条把当前提交和它的父提交列在同一行。第三条解析当前 commit 指向的根 tree。

可以把关系写成：

~~~text
commit C
├── tree T
├── parent P1
├── parent P2 ...（只有合并提交才可能有多个）
├── author ...
├── committer ...
└── message
~~~

commit 对象不保存“它来自哪个分支”，也不保存一份逐行补丁。文件快照在 tree 和 blob 中，差异由 Git 根据两个快照计算。分支名和标签名位于对象之外的 refs 中。

## 三种提交图形

### 根提交

仓库第一次提交没有父提交：

~~~text
C0
~~~

验证某个提交是不是根提交：

~~~bash
test "$(git rev-list --parents -n 1 <commit> | wc -w | tr -d ' ')" = 1
~~~

这里的 \`<commit>\` 必须替换成已确认存在的 OID 或引用。不要在没有先验证输入时把它放进脚本。

### 线性提交

普通提交只有一个父提交：

~~~text
C0 <- C1 <- C2
~~~

C2 的父提交是 C1。日期可以帮助阅读，但不能决定父子关系。两台机器时钟不同、提交被复制到其他仓库，父字段仍然保持原值。

### 合并提交

两条历史汇合时，合并提交有两个或更多父提交：

~~~text
      N
     / \
C0 <- C   M
     \ /
      V
~~~

M 的第一父提交通常是执行合并时所在分支的旧尖端，第二父提交是被合入分支的尖端。父顺序会影响 \`^1\`、\`^2\`、\`--first-parent\` 和默认 diff 视角，不是可忽略的显示细节。

读取父列表：

~~~bash
git rev-list --parents -n 1 <merge-commit>
~~~

如果输出只有提交本身和一个父 ID，它不是合并提交。不要把“图上看起来有分叉”当成父数量证据。

## 可达性决定“包含”

给定提交 B，如果从 B 沿父提交反向遍历能够到达 A，就说 A 是 B 的祖先，B 包含 A 的历史。用命令判断：

~~~bash
git merge-base --is-ancestor A B
printf 'exit=%s\n' "$?"
~~~

退出码为 0 表示 A 是 B 的祖先，1 表示不是，其他非零值表示参数或仓库错误。脚本必须区分这三类结果，不能用“命令非零”统一表示失败。

也可以读取共同祖先：

~~~bash
git merge-base A B
~~~

它通常返回一个最佳共同祖先，但复杂历史可能有多个候选。需要保留全部候选时使用：

~~~bash
git merge-base --all A B
~~~

共同祖先是三方合并的 base 候选，不是“两个分支上次改文件的时间点”。合并策略会继续处理多个 base 和路径变化，不能只把 \`merge-base\` 的一个 OID 当作完整合并解释。

## 从引用走到对象

分支引用、标签引用和 \`HEAD\` 都是找到提交的入口：

~~~bash
git show-ref
git for-each-ref --format='%(refname) %(objectname) %(objecttype)'
git rev-parse --verify HEAD^{commit}
~~~

从 \`refs/heads/main\` 找到 commit 后，Git 再沿 commit 的 tree 找到路径。引用移动不会修改旧 commit。删除一个分支也不会立刻逐层删除它曾经指向的对象，是否仍可恢复取决于其他 refs、reflog、对象保留和维护窗口。

因此下面两件事不能互换：

- \`git log --all\` 找不到对象，只能说明当前本地 refs 的遍历范围没有它；
- \`git fsck --unreachable\` 找到对象，只能说明对象存在但暂时没有从指定根可达。

历史调查时先固定 refs 和查询根，再讨论对象是否真的缺失。对象生命周期在第五篇和取证篇展开。

## 选择历史视角

### 完整提交图

~~~bash
git log --graph --decorate --oneline --all
~~~

这是人读的图形。它受排序、终端颜色和引用数量影响，不适合机器解析。审查记录至少还要保存完整 OID 和查询时间。

### 主线视角

~~~bash
git log --first-parent --oneline main
~~~

\`--first-parent\` 沿每个合并提交的第一父提交继续前进，适合阅读主线何时合入了哪些分支。它会隐藏功能分支内部的提交，不能替代完整历史调查。

### 共同祖先到候选之间的路径

~~~bash
git log --ancestry-path --oneline A..B
~~~

这个范围只保留位于 A 到 B 的祖先路径上的提交。它适合回答“哪些提交处在这条演变链上”，但路径和范围组合复杂时必须先验证 A、B 都是预期对象。不要把普通 \`A..B\` 的输出当成唯一的因果链。

## 为什么提交 ID 改一点就全变

Git 对象 ID 包含对象类型、内容长度和内容。commit 的父提交、tree、身份、时间、说明或签名字段改变，都会得到新的 OID。只改提交说明也不是“编辑原提交”，而是创建一个内容不同的新 commit。

这解释了：

- 分支移动可以不改对象；
- amend、rebase 和 cherry-pick 会生成新 commit；
- 标签可以稳定指向一个旧 OID；
- 远端拒绝非快进时，比较的是引用的祖先关系，不是文件夹日期。

不要在书稿中写死一个固定的 40 位 ID。仓库可能使用 SHA-1 或 SHA-256，示例 ID 也会因身份和时钟变化。

## 观察提交快照和父差异

对一个候选提交：

~~~bash
candidate=<full-commit-id>
git cat-file -t "$candidate"
git rev-parse "$candidate^{tree}"
git show --format=fuller --stat "$candidate"
git show "$candidate" -- path/to/file
~~~

\`cat-file -t\` 证明对象类型，\`rev-parse\` 证明 tree 入口，\`show\` 展开元数据、统计和差异。最后一条的路径属于提交 tree；它不读取当前工作区版本。

合并提交要指定父视角：

~~~bash
git diff "$candidate^1" "$candidate"
git diff "$candidate^2" "$candidate"
git show -m --format=fuller "$candidate"
~~~

没有第二父提交的对象执行 \`^2\` 会失败。失败后应回到 \`rev-list --parents\` 检查对象形状，不要修改历史来满足命令。

## 查询失败与恢复边界

| 现象 | 先收集 | 解释边界 | 低风险动作 |
| --- | --- | --- | --- |
| \`bad revision\` | 原始参数、\`show-ref\`、\`rev-parse --verify\` | 名称拼错、ref 不可见或对象缺失都可能 | 先固定完整 OID 和 refs |
| \`merge-base\` 无输出 | 两端是否都是 commit、是否有共同历史 | 两个独立根或浅边界都可能 | 检查 \`--is-shallow-repository\` 和对象范围 |
| 图形看不到一条分支 | \`git for-each-ref\`、是否使用 \`--all\` | 分支已删除、隐藏 ref 或查询范围不足 | 查询 reflog/备份，不先 reset |
| 时间顺序与图形不一致 | parent 列表、提交者时间、时区 | 时间不是拓扑关系 | 以 parent 和 reachability 为准 |
| 合并 diff 看起来为空 | 父提交选择、combined diff 规则 | 可能是相对多个父没有独特变化 | 用 \`-m\` 分别比较每个父 |

所有失败命令都应保存 stderr、执行目录、Git 版本和输入 OID。不要用 \`gc\`、\`prune\` 或强制重写来“让图变简单”。

## 隔离实验验证了什么

在书稿仓库根目录执行：

~~~bash
./scripts/verify-part-3-basics.sh
~~~

实验创建根提交、功能分支和快进合并，验证分支引用移动、提交父关系、祖先判断和合并后两引用指向同一 OID。它使用临时仓库与合成身份，不连接远端，也不模拟平台评审或部署事件。

实验成功证明本地 commit graph 和引用关系符合断言，不证明提交作者经过认证、合并结果满足业务测试，也不证明网页平台显示与本地 refs 一致。

## 小结

提交是带父关系的快照对象，分支只是指向对象的引用。读历史时先固定引用、完整 OID 和父列表，再用可达性、共同祖先和指定父视角解释图形。日期、文件列表和网页显示都不能替代提交图本身。
