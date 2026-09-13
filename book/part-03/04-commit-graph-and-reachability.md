# 提交图与可达性：父关系比时间和分支名更可靠

一个 commit 保存根 tree、零个或多个父 commit、身份、时间和说明。把每个 commit 看作节点，把 `parent` 字段看作从子节点指向父节点的边，就得到 Git 的提交图。分支名、标签名和平台评审号都位于图外；它们只是进入某些节点的入口。

分支是否包含某个修复、两条历史能否快进、三方合并从哪里开始、CI 应检查哪些提交，最终都依赖父关系和查询根。提交时间适合展示，不能替代拓扑证据。

## 进入条件与完成标准

只读命令可以在普通仓库运行。创建分叉、合并、浅克隆或 commit-graph 的命令只在一次性实验仓库执行。观察前固定：

~~~bash
git status --short --branch
git rev-parse --verify 'HEAD^{commit}'
git rev-parse --is-shallow-repository
git rev-parse --show-object-format
~~~

`HEAD^{commit}` 在 unborn 仓库会失败。浅仓库输出 `true` 时，本地父遍历可能在边界提前停止；此时不能把缺少共同祖先直接解释成两条历史无关。

读完本章后，应能从 commit 对象读取父边，区分拓扑与日期，明确 revision 集合的左右方向，解释一个或多个 merge base，识别 refs/reflog/shallow/replace refs 对可见图的影响，并说明 commit-graph 与 generation data 为什么只加速查询、不创造历史事实。

## Commit 对象只保存向父节点的边

观察一个候选：

~~~bash
candidate="$(git rev-parse --verify 'HEAD^{commit}')"
git cat-file -p "$candidate"
git rev-list --parents --max-count=1 "$candidate"
git rev-parse "$candidate^{tree}"
~~~

`cat-file -p` 展示 commit payload，其中每个 `parent` 行都是对象身份的一部分。`rev-list --parents` 的第一列是候选，后续列按对象记录的顺序给出父 OID。`rev-parse ...^{tree}` 取得根 tree。

父数量决定基本形状：

| 父数量 | 常见形状 | 不能据此证明 |
| --- | --- | --- |
| 0 | 根提交 | 它是组织最早的代码来源 |
| 1 | 普通提交 | 它来自某个特定分支或评审 |
| 2 | 常见二路合并提交 | 平台审批、测试和发布均通过 |
| 3 个以上 | 八爪鱼合并等多父提交 | 每对父都经过独立三方合并 |

Commit 不保存分支名、评审号、流水线状态或“第几个版本”。同一个 commit 在一个 clone 中叫 `main`，在另一个 clone 中可以只有标签，图的父边不变。

Git 的普通 commit 图按对象 ID 引用已经存在的父对象，不允许通过常规写入形成环。历史遍历从子节点沿父边向过去移动；“后代”是反向关系，需要从其他入口或索引中发现。

## 日期不是拓扑顺序

Commit 同时保存 author 和 committer 身份/时间。时钟漂移、时区、历史重建、补丁移植和人为设置日期都可能让后代 commit 的时间早于祖先。

读取结构和时间：

~~~bash
git show --no-patch --format='%H%n%P%n%aI%n%cI%n%s' "$candidate"
git merge-base --is-ancestor "$older_candidate" "$newer_candidate"
~~~

第二条只按父边判断祖先关系。退出 0 表示第一个 commit 是第二个的祖先，退出 1 表示不是，其他非零表示输入或仓库错误。脚本要保留三类结果。

`git log --date-order`、`--author-date-order` 和 `--topo-order` 是不同展示策略。它们改变输出顺序，不修改 commit，也不把时间顺序升级为因果关系。发布系统若需要“B 基于 A”，应保存 OID 并检查祖先关系，不能比较提交时间戳。

## 可达性必须带查询根

从 commit B 沿父边能走到 A，就说 A 从 B 可达，也说 A 是 B 的祖先。常用判断：

~~~bash
git merge-base --is-ancestor "$a" "$b"
git rev-list --count "$a..$b"
git rev-list --objects "$b"
~~~

第一条回答祖先布尔关系。第二条计算从 B 可达、但从 A 不可达的 commit 数；只有 A 确实是 B 的祖先时，它才等于“B 比 A 前进了多少步”的直觉。第三条还遍历 B 所需的 tree/blob/tag 入口，输出范围可能很大。

“仓库中全部可达提交”也必须定义根：

~~~bash
git rev-list --count --all
git rev-list --objects --all
git rev-list --reflog --all
~~~

`--all` 以当前本地可见 refs 等作为根，不等于远端服务器的隐藏 refs、其他 clone、平台数据库或不可达对象。`--reflog` 会把本地 reflog 提到的提交加入遍历根；日志过期、未启用或位于另一个 worktree 时，集合会不同。

一个 commit 可以真实存在于对象库，却不在 `rev-list --all` 的结果中。先用 `cat-file -e "$oid^{commit}"` 判断对象可读，再讨论它是否从指定 refs 可达。经过核验后创建 `refs/recovery/*`，该 commit 才重新进入以 `--all` 为根的普通引用视图。

## 两点范围有明确方向

设两条分支从 A 分开，各自前进到 L 和 R：

~~~text
      L1 <- L
     /
A <-
     \
      R1 <- R
~~~

常见集合表达式：

| 表达式 | Commit 集合 | 常见问题 |
| --- | --- | --- |
| `A..B` | B 可达减去 A 可达 | “B 有而 A 没有” |
| `A...B` | A、B 对称差 | “只在某一侧的提交有哪些” |
| `^A B` | 与 `A..B` 同类的排除/包含写法 | 组合多个根和排除根 |
| `--not A --all` | 全部选中根减去 A 可达 | 盘点 A 之外的本地 refs 历史 |

机器读取左右数量：

~~~bash
git rev-list --left-right --count "$left...$right"
~~~

输出是左侧独有数和右侧独有数，中间通常为制表符。它不说明补丁是否等价，也不说明哪一侧经过审批。

`git diff A...B` 的三点语义与 `git log A...B` 不同：diff 通常比较 merge base 与 B 的 tree，log 则选择对称差 commit 集合。命令、参数和输出类型必须一起记录，不能只写“三点范围”。

## Merge base 是最佳共同祖先集合

两端都能到达的 commit 是共同祖先。若某个共同祖先不是另一个共同祖先的祖先，它属于“最佳”候选。查询：

~~~bash
git merge-base --all "$left" "$right"
~~~

普通分叉常只有一个结果。Criss-cross 等复杂图可能有多个互不为祖先的最佳共同祖先；不带 `--all` 时只返回其中一个，不能把它当作唯一历史事实。

三方合并会基于共同祖先和两端 tree 计算结果，但具体策略可能先合并多个 base、处理重命名并构造虚拟祖先。`merge-base` 输出只能证明图关系，不等于完整的 `ort` 冲突解释。

`git merge-base --octopus A B C` 面向一次多头合并寻找共同基础，和依次对每一对运行二参数命令不是同一问题。`--independent` 返回输入中不能从其他输入到达的头。自动化应根据业务问题选择模式，不把所有结果都叫“分叉点”。

## Fork point 引入本地 reflog 假设

`git merge-base --fork-point <upstream> <topic>` 会参考上游 ref 的 reflog，尝试识别 topic 从上游旧位置分出的点。它适合上游发生过重写且本地日志仍保留证据的场景，不是 merge base 的通用替代。

同一个 topic 在不同 clone 中可能得到不同 fork point，因为 reflog 不传输且会过期。CI、评审和审计需要可重复基线时，优先保存明确 base OID、目标 OID 和选择规则；fork-point 无结果时回到 refs、reflog、浅边界和平台候选事实核对，不静默改用另一个范围。

## 第一父视角是投影，不是另一张图

合并提交的第一父通常是执行合并时当前分支的旧尖端。以下命令只沿第一父：

~~~bash
git log --first-parent --oneline refs/heads/main
~~~

它适合阅读主线何时接纳一项变化，会隐藏被合入分支内部的提交。`--ancestry-path A..B` 则只保留位于 A 到 B 某条祖先路径上的提交。两者都是对同一 DAG 的查询投影，不能用输出较短证明其他提交不存在。

合并结果需要分别比较父视角：

~~~bash
git rev-list --parents --max-count=1 "$merge_oid"
git diff "$merge_oid^1" "$merge_oid"
git diff "$merge_oid^2" "$merge_oid"
~~~

父顺序是 commit payload 的一部分。Squash merge 不创建指向功能分支尖端的父边，因此 tree 可以包含相同改动，`merge-base --is-ancestor <feature> <squash>` 仍返回 1。拓扑包含与内容/补丁等价必须分开验证。

## 浅边界和替换引用会改变可见图

浅克隆通过本地 shallow 边界把某些 commit 暂时当作根。边界之外的父对象可能未取得，因此 `log` 提前停止、`merge-base` 无结果、`blame` 或 `bisect` 证据不足，都可能是当前 clone 的正常限制。

先检查：

~~~bash
git rev-parse --is-shallow-repository
git rev-parse --git-path shallow
git config --show-origin --get-regexp '^remote\..*\.promisor$|^remote\..*\.partialclonefilter$'
~~~

需要扩大历史时按工作负载选择 `fetch --deepen=<n>` 或在容量允许时 `fetch --unshallow`，并在操作后重新固定候选 OID 和 merge base。Fetch 会写对象、远程跟踪 refs 和 `FETCH_HEAD`，不是只读诊断。

`refs/replace/*` 可以让 revision 遍历把一个对象替换为另一个对象。调查原始对象关系时同时记录 replace refs，并用受控命令对照：

~~~bash
git replace -l
git --no-replace-objects rev-list --parents --max-count=20 "$candidate"
~~~

旧式 graft、replace refs、commit-graph、alternates 和 promisor 都会影响某些观察路径。证据清单必须记录配置、refs、命令和 Git 版本，不能只截一张 `log --graph`。

## Commit-graph 是可重建的加速结构

对象数据库已经包含完整 commit 和父边。Commit-graph 文件缓存 commit OID、父关系、根 tree、generation data，并可包含 changed-path Bloom filters，帮助 Git 少解析对象或更快裁剪不可能的路径。

在维护副本中写入：

~~~bash
git commit-graph write --reachable --changed-paths
git commit-graph verify
~~~

`write` 会读取当前可达 commits 并写对象库下的辅助文件，可能消耗 CPU、内存、I/O 和临时空间；`verify` 校验 commit-graph 结构，不证明 refs、工作区和业务结果正确。维护前后至少保存并比较 refs、`rev-list --all`、关键 tree 和 `fsck` 结果。

Generation number 表示拓扑层级约束，帮助遍历优先排除不可能的祖先。较新的 commit-graph 格式还能保存 corrected commit date 等代际数据。它们是由父图和时间派生的查询索引，不写回 commit 对象，也不改变 OID。

Commit-graph 可以暂时落后于 refs。写完图后新建 commit，Git 仍应从对象库读取新节点；下一次维护再把它纳入图。删除 commit-graph 或设置 `core.commitGraph=false` 会放弃该加速路径，不应改变逻辑查询结果。若关闭索引后结果不同，应按损坏或实现问题处理，不能继续把索引结果当权威。

Split commit-graph、generation data 版本和 Bloom filter 可用性随 Git 版本、仓库格式和维护策略变化。第九篇的[性能与维护基线](../part-09/01-measure-before-optimizing.md)负责测量收益和成本，本章不提供可外推的毫秒结论。

## 证据顺序决定诊断质量

提交图异常时按以下顺序收集：

1. 固定仓库路径、Git 版本、object/ref format、shallow/partial/replace 状态；
2. 保存输入完整 OID，并用 `cat-file -e '<oid>^{commit}'` 验证对象类型；
3. 用 `rev-list --parents` 读取实际父边；
4. 明确 refs、reflog 或显式 OID 组成的查询根；
5. 再运行范围、merge-base、first-parent 或路径历史查询；
6. 怀疑辅助索引时，在副本中比较启用/禁用 commit-graph 的结果。

平台图形、提交日期、分支颜色和说明文本适合导航，不能替代这组结构证据。对象 missing/corrupt 时转入[对象取证与恢复](../part-11/02-object-forensics-and-recovery.md)，不要用重写历史或立即维护掩盖错误。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| `merge-base` 无输出 | 两端类型、独立根、shallow/partial、replace refs | 补齐证据或确认无共同历史，不伪造 base |
| `--is-ancestor` 返回非零 | 区分退出 1 与命令错误 | 退出 1 是关系不成立，其他错误先修输入/对象来源 |
| 时间更晚的 commit 不是后代 | 父列表、author/committer 时间和时区 | 以父边判断，单独调查时钟或重建来源 |
| `A..B` 数量与预期相反 | 参数左右、refs 新鲜度和共同祖先 | 保存完整 OID 后重新计算，不交换参数凑结果 |
| `--all` 找不到已知 OID | `cat-file`、refs、reflog、查询权限 | 对象存在时先建核验后的 recovery ref |
| commit-graph verify 失败 | 文件路径、磁盘、并发维护、对象完整性 | 停止维护，在副本禁用/重建索引并验证逻辑集合 |
| 浅 clone 的历史工具提前停止 | shallow 文件、depth、远端对象来源 | 按需 deepen/unshallow，重新绑定候选与结果 |
| 平台图与本地不同 | 两端 OID、隐藏 refs、拉取时间、候选构造 | 分开采集平台与 Git 数据面，不按截图改历史 |

`commit-graph write`、fetch 和创建 recovery ref 都是写操作。事故现场先制作证据副本并停止并发 writer；真实仓库不能为了复现本章实验创建分叉、合并或改写辅助索引。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-commit-graph-reachability.sh
~~~

实验创建根提交、两侧分叉和二父合并，断言父顺序、祖先关系、左右独有计数和唯一 merge base。它再创建一个时间早于祖先的后代，证明 committer 时间不决定拓扑；构造存在但未被 refs/reflog 引用的 commit，验证 recovery ref 如何改变 `--all` 可达集合；写入并校验 commit-graph，证明索引前后 refs、提交集合和 tree 不变。

最后通过 `file://` 创建 depth 1 浅克隆，验证边界外 commit 当前不可用，unshallow 后同一 OID 与 merge-base 恢复。实验不连接托管平台，不测性能收益，不模拟隐藏 refs、部分克隆服务端、criss-cross 多 base 或损坏 commit-graph 的生产恢复。

## 小结

提交图由 commit 的父字段定义，引用和日志只提供遍历入口。可达性、范围和 merge base 都依赖明确的 OID、根集合与本地对象边界；时间、分支名和平台图形只能辅助阅读。Commit-graph 与 generation data 可以加速同一组逻辑查询，但不改变对象、父边或 refs，维护后必须用逻辑不变量验收。

## 资料

- [git-commit](https://git-scm.com/docs/git-commit)
- [git-rev-list](https://git-scm.com/docs/git-rev-list)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
- [git-merge-base](https://git-scm.com/docs/git-merge-base)
- [git-log](https://git-scm.com/docs/git-log)
- [git-commit-graph](https://git-scm.com/docs/git-commit-graph)
- [gitformat-commit-graph](https://git-scm.com/docs/gitformat-commit-graph)
- [shallow](https://git-scm.com/docs/shallow)
- [git-replace](https://git-scm.com/docs/git-replace)
