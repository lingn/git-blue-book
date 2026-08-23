# 仓库变慢、对象膨胀与磁盘告急：性能和容量故障

“Git 变慢了”和“仓库太大了”经常同时出现在报障里，却不是同一个问题。status 慢可能是工作区路径太多、文件系统 stat 成本高、fsmonitor 失效或网络文件系统延迟；log 慢可能是历史遍历、路径过滤、重命名检测或缺少辅助索引；clone/fetch 慢还可能发生在网络、服务端打包、认证代理或 LFS。对象库字节数很小，也不能证明没有 inode、临时空间或外部制品容量风险。

本章按症状建立第一轮诊断路径，再把性能、容量、完整性和维护副作用分开。目标不是找到一个“优化开关”，而是证明哪一层变成了瓶颈，选择受控动作，并在动作前后核对逻辑状态。没有固定 workload、版本、缓存条件和样本口径时，一次命令的耗时只能作为现场线索，不能写成通用结论。

本章以 Git 2.49.0 和本地隔离实验为基线。commit-graph、MIDX、bitmap 与 maintenance 是 Git 的本地机制；LFS、制品库、网络文件系统、托管平台服务端负载、磁盘坏块和计费配额必须在目标环境按版本、权限、套餐和核对日期验证。

读完本章后，你应能：

- 把 status、log、switch/checkout、clone/fetch 的慢分别映射到工作区、index、历史、对象、传输或外部数据面；
- 定义可比较的 workload、冷/热缓存、样本数、p50/p95 和失败率，而不是只记录一次毫秒值；
- 分层盘点 Git 对象、refs、index、工作区、LFS、制品、备份、日志、inode 与维护 scratch 空间；
- 使用 count-objects、rev-list、for-each-ref、index 统计和 Trace2 判断证据边界；
- 在写入辅助索引或运行维护前固定 refs、HEAD、tree、可达提交和工作区，并在之后验证不变量；
- 识别 gc --prune=now、删除 pack/idx、清理 LFS 或改变服务端配置的停止条件。

## 先把症状说完整

报障至少要包含以下信息：

| 维度 | 必须固定的事实 | 缺少它会造成的误判 |
| --- | --- | --- |
| 命令和目标 | 完整命令、pathspec、分支、是否使用 LFS/filter、最终要改善什么 | 把不同 workload 的耗时放在一起比较 |
| 执行位置 | Git 版本、仓库/工作树、文件系统、是否 linked worktree 或网络挂载 | 在另一个 clone 上复现，得到错误结论 |
| 时间口径 | 开始/结束时间、样本数、暖机次数、冷/热缓存、并发与后台任务 | 把缓存命中或服务端排队当作稳定性能 |
| 输入规模 | tracked paths、提交数、refs、pack 数、历史跨度、LFS/制品字节 | 用仓库总 GB 代替真正的成本因子 |
| 结果质量 | 退出码、stderr、错误率、p50/p95、是否有取消或超时 | 只看成功样本，遗漏失败和长尾 |
| 共享边界 | 是否在共享分支、是否有人同时 fetch/repack、服务端是否在维护 | 把竞态或后台任务归因到命令本身 |

建议把一次报障写成如下形式，而不是“仓库很慢”：

~~~text
目标：在本地工作树中把 status --short 的 p95 从 4.2 s 降到团队约定阈值以下，工作区内容和 refs 不变
位置：Git 2.49.0，macOS 本地 APFS，非 linked worktree；未使用 LFS smudge
workload：连续执行 2 次预热后采集 20 次，工作区有 180,000 个 tracked paths，后台无 fetch
现象：第 95 百分位 4.2 s，Trace2 显示 index refresh 占主要时间；没有失败样本
容量：objects 18 GiB，refs 12,400，index 230 MiB，LFS/制品/备份未在本次数据面内
安全边界：只读采集；任何 maintenance 需要先有备份、scratch 和互斥窗口
~~~

## 四类常见慢症状的首轮路径

下面的命令都应在出现症状的同一个仓库根目录执行。先保存第十三篇第一章的证据包；status 和 log 的采集可设置 GIT_OPTIONAL_LOCKS=0，但这不会把所有 Git 或外部 helper 变成安全沙盒。

| 症状 | 先看什么 | 证据能说明什么 | 不要直接做什么 |
| --- | --- | --- | --- |
| status 慢 | tracked path 数、index 字节、工作区所在文件系统、Trace2 region、fsmonitor/filter 配置 | 是否在工作区/index/stat 边界消耗时间 | 不要先 reset --hard、删除 index 或修改 skip-worktree |
| log/rev-list 慢 | 提交数、refs 根、是否带 pathspec/--follow/重命名检测、commit-graph 是否存在 | 是历史遍历、路径过滤、根集合还是辅助索引缺失 | 不要用截断历史或删除 refs 来“变快” |
| switch/checkout 慢 | 变更路径数、稀疏规则、filter/LFS、hooks、目标文件系统、未完成操作 | 是 tree/index 写入、外部水合、脚本还是锁等待 | 不要在未保存工作区的情况下反复切换或清理 |
| clone/fetch 慢 | endpoint/协议、包体字节、协商、服务端等待、代理、过滤/浅边界、LFS 后续请求 | 网络/服务端/客户端对象写入的哪一段变慢 | 不要凭一次慢 fetch 推断 Git 对象库损坏或直接删远端历史 |

首轮采集可以使用：

~~~bash
git --version
git rev-parse --show-toplevel
git rev-parse --show-object-format
git rev-parse --show-ref-format
git status --short --branch
git count-objects -vH
git rev-list --count --all
git for-each-ref --format='%(refname)' | wc -l
git ls-files -z | tr -cd '\0' | wc -c
git rev-parse --git-path index
~~~

这些命令读取本地布局、对象统计、refs 和 index；它们不连接远端。status 可能刷新可选 index 信息，若要做更严格的第一轮快照，可使用 GIT_OPTIONAL_LOCKS=0 并保存退出码。对象统计中的 size-pack 是 pack 目录的 Git 计量，不是磁盘所有占用；wc 对 NUL 计数只适用于统计条目数量，不应把路径字节当作文件数。

任一命令失败都要保留 stderr 和退出码，标为 inconclusive，先检查仓库发现、权限、格式和锁文件。空输出不等于零：没有 refs、没有 tracked paths 和采集器失败必须分开记录。

## status 慢：工作区、index 和文件系统边界

status 需要比较 HEAD、index 和工作区。tracked path 数、目录层级、文件系统 stat 延迟、大小写/时间戳精度、fsmonitor、稀疏规则和 clean/smudge filter 都可能改变成本。一个只含少量历史的仓库也可能因为工作区有大量路径而慢。

先固定三个规模量：

~~~bash
index_path="$(git rev-parse --git-path index)"
printf 'index=%s\n' "$index_path"
wc -c < "$index_path"
git ls-files -z | tr -cd '\0' | wc -c
git config --show-origin --get core.fsmonitor || true
git config --show-origin --get core.untrackedCache || true
git sparse-checkout list 2>/dev/null || true
~~~

然后在受信任仓库中采集一次结构化 Trace2 事件：

~~~bash
trace_file="$(mktemp /tmp/git-status-trace.XXXXXX)"
GIT_OPTIONAL_LOCKS=0 GIT_TRACE2_EVENT="$trace_file" \
  git status --short >/dev/null
sed -n '1,12p' "$trace_file"
~~~

Trace2 可以告诉你命令的 region、子进程和退出事件，但它不自动说明“正确的优化是什么”，也可能暴露路径、参数和环境信息。只在受控目录保存原件，分享时生成脱敏副本。比较前必须固定暖机次数、工作区内容、后台任务和缓存条件。

如果只是在网络文件系统或容器 bind mount 上慢，先做同一提交、同一 tracked path 集合的本地文件系统对照；如果本地也慢，再继续看 index、filter 和 path 数。不要为了让 status 变快而直接删除 index、关闭所有 hooks 或把 sparse 规则写成业务忽略规则，这些动作会改变语义和恢复成本。

## log 慢：历史根集合和路径过滤

log --all 的成本与 refs 根集合和提交数有关；带 pathspec、--follow、-S、-G 或重命名/复制检测时，还会读取 tree 和 diff。commit-graph、generation data 与 changed-path Bloom filters 可以减少部分遍历，但只有在 workload 命中时才可能改善。

先用同一输入比较，而不是拿 log --all 与 log -- path/to/file 比较：

~~~bash
git rev-list --count --all
git for-each-ref --format='%(refname) %(objectname)' | sort | sed -n '1,40p'
git commit-graph verify
git rev-list --count --all --objects >/dev/null
~~~

最后一条只验证一次对象枚举能够完成；它不是性能基准，也不能说明服务端 fetch 的速度。若路径历史很慢，记录 pathspec、是否启用重命名检测、历史深度和候选 refs。限制 -n 只能减少输出或遍历范围，不能证明完整历史查询已经优化。

## switch/checkout 慢：写入工作区前先看外部边界

切换分支可能移动 HEAD、更新 index、删除/写入大量文件，并触发 filter、LFS、submodule 或 hooks。先不要在原工作树反复重放；在已保存状态且允许重放时，记录：

~~~bash
git status --porcelain=v2 --branch
git diff --stat
git sparse-checkout reapply --no-cone 2>/dev/null || true
git config --show-origin --get-regexp '^(filter\.|submodule\.|core\.hooksPath)' || true
git worktree list --porcelain
~~~

reapply 不是通用诊断命令，配置不支持时的非零要保留；它也可能改变工作区，不能作为无副作用采集。对于 LFS，Git tree 中的 pointer blob、LFS cache/service 和工作区字节是三个不同数据面；Git fsck 通过不代表水合一定成功。对于 submodule，外层 tree 只记录 gitlink，递归 checkout 还需要另一个仓库和 URL。相关故障应分流到第九篇的 LFS/submodule 章节，而不是反复删除 .git/modules。

## clone/fetch 慢：把客户端和服务端分开

clone/fetch 同时涉及协商、对象打包、网络传输、本地写入和可选的 LFS/子模块后续请求。客户端可以测量请求的总时延和收到的字节，但不能仅靠本地 Trace2 推断服务端 CPU、共享存储、平台限流或其他租户负载。

在获批的 endpoint 上做有限采集：

~~~bash
git ls-remote --symref origin HEAD
GIT_TRACE2_EVENT="$trace_file" git fetch --no-write-fetch-head origin \
  '+refs/heads/main:refs/remotes/origin/main'
~~~

ls-remote 只读远端 ref 探针；fetch 会连接远端、写对象和远程跟踪 ref，即使 --no-write-fetch-head 不写 FETCH_HEAD。执行前保存本地 refs、对象统计和认证上下文，避免 IDE 或定时任务同时 fetch。失败时保留原始 stderr，不把网络超时改写成“远端没有分支”。若需要 packet 或 curl trace，必须确认日志不会包含令牌、Authorization header、内部 URL 或路径，并只在受控环境短时启用。

## 容量不是一个数字：按数据面拆预算

容量盘点应至少分为以下层，每层都有自己的 owner、指标来源、保留策略和恢复目标：

| 数据面 | Git/系统证据 | 典型误判 |
| --- | --- | --- |
| loose/pack 对象 | git count-objects -vH、pack/idx/MIDX 大小 | 只看工作区大小，忽略历史 blob |
| refs 与 reflog | git for-each-ref、git reflog --all | 删除分支后以为对象立刻消失 |
| commit/tree/index | rev-list --count、index 字节、tracked path 数 | 把提交数当作所有对象或时延的代理 |
| 工作区与临时空间 | Git directory、worktree、repack scratch、系统 df/inode | 只看 .git，忽略 checkout 和维护峰值 |
| LFS payload/cache | LFS pointer OID、cache/service/backup 指标 | Git fsck 通过就认为二进制可恢复 |
| 制品、日志、镜像和备份 | 制品仓库、CI retention、快照与 WORM 指标 | 用 Git prune 绕过外部保留政策 |

Git 本地命令可以证明前四层的部分逻辑事实，不能伪造 LFS、制品、平台配额、inode 或磁盘健康。来源不可用时写 inconclusive，不能把采集失败转成 0 字节。硬限制、headroom 和行动窗口见[健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md)；本章只负责把性能报障分流到正确的数据面。

## 选择辅助索引和维护动作

确认 workload 与基线后，才考虑下面的受控动作：

~~~bash
git commit-graph write --reachable --changed-paths
git commit-graph verify
git multi-pack-index write --bitmap
git multi-pack-index verify
git maintenance run --task=commit-graph
git maintenance run --task=incremental-repack
~~~

这些命令会在 .git/objects/info 或 pack 目录写辅助文件，incremental-repack 还可能重排 pack。执行前必须有：

1. 固定 refs、HEAD、HEAD^{tree}、可达提交集合和工作区摘要；
2. 确认有可验证的备份/恢复点、足够 scratch 空间和维护互斥锁；
3. 冻结或协调会同时 fetch、push、clone、备份和索引维护的任务；
4. 记录 Git 版本、命令、开始/结束时间、stdout/stderr 和退出码。

维护成功后重新核对：

~~~bash
git show-ref
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
git rev-list --all | sort
git fsck --full --no-progress
git status --porcelain=v1
~~~

refs、HEAD、tree、可达提交集合和工作区必须满足预先声明的不变量；fsck 失败、对象读取错误、锁未释放、scratch 耗尽或结果无法解释时立即停止并进入第十一篇取证/恢复流程。维护退出码为 0 只证明进程完成，不证明容量下降、性能改善或外部副本完整。

不要在第一轮排障中运行 git gc --prune=now，不要手工删除 .pack/.idx/MIDX，也不要把 git repack 当作容量修复按钮。它们可能改变物理布局、删除仍被其他 worktree/备份需要的对象，甚至制造新的缺失对象。若必须处置过期对象，应先做保留评估、完整备份、隔离副本演练和批准的维护窗口。

## 容量不足和性能变慢不能互相替代

两种状态需要分别判定：

- **性能风险**：目标命令的 p95/p99、错误率或队列等待超过约定 SLO；对象总字节可以正常，但某个文件系统、路径规模或服务端仍是瓶颈。
- **容量风险**：Git 对象、refs、LFS、制品、备份或 scratch 的硬限制/行动 headroom 不满足；命令当前可能很快，但下一次 repack 或恢复已经没有峰值空间。
- **完整性风险**：fsck、对象读取、pack/idx 或外部 payload 校验失败；容量充足也必须按事故流程停写。
- **证据缺口**：采集源不可见、权限不足、单位/时间窗不一致或只剩一次样本；结论必须是 inconclusive。

组织级看板不要把这些状态平均成一个“健康分”。一个仓库 objects 有余量但 LFS 服务不可用，应显示外部数据面故障；一个 repo 性能正常但 scratch 低于下一次维护峰值，应阻止维护而不是标记 pass。

## 隔离实验：只验证机制，不声称收益

本书提供 scripts/verify-performance-troubleshooting.sh。在仓库根目录执行：

~~~bash
bash scripts/verify-performance-troubleshooting.sh
~~~

实验会在 mktemp 中创建虚构身份的本地仓库，生成多批提交和多个 pack/ref，采集对象、refs、tracked paths、index 和一次 Trace2 status 事件；随后写入并验证 commit-graph、MIDX bitmap，运行受控 maintenance task，最后核对 refs、HEAD、tree、可达提交和工作区不变。脚本还用明确标注的容量 fixture 检验 pass、warn、fail、inconclusive 的分流，避免把来源不可用当成零。

实验能够证明：这些 Git 命令在当前版本的输入/输出边界、辅助索引可被验证、维护不会改变 fixture 的逻辑历史，以及容量分类器按硬限制和证据缺口停止。实验不能证明：冷/热缓存差异、真实 p95/p99、网络或服务端性能、LFS/制品/备份容量、inode/磁盘故障、后台 scheduler、平台套餐/计费或真实维护收益。任何生产优化都必须在代表性副本和目标环境重新测量。

## 故障处置清单

1. 先保存第十三篇的最小证据集、原始错误和当前 refs；不要先清理或重写。
2. 用固定 workload 重现一次，记录 Git 版本、文件系统、规模、缓存、并发和 p50/p95/失败率。
3. 按工作区/index、历史/对象、传输/服务端、LFS/外部数据面分流；容量按 Git、refs、LFS、制品、备份和 scratch 分层。
4. 先选择只读证据；任何 fetch、repack、maintenance 或配置变更都写动作卡、停止条件和恢复路径。
5. 维护前后核对 refs、HEAD、tree、可达对象、工作区、错误率和外部副本；不满足即停止并升级。
6. 把“未测量”“来源不可用”“本地实验未覆盖”显式写成缺口，不用一次成功命令宣称性能或出版级结论。

## 小结

性能排障从 workload 和证据开始：status 关注工作区/index，log 关注历史根和路径过滤，switch/checkout 关注工作区写入与 filter/LFS，clone/fetch 关注协商、网络、服务端和本地对象写入。容量排障必须按数据面分层，Git 对象大小不能代替 LFS、制品、备份、inode 和 scratch 预算。

commit-graph、MIDX、bitmap 和 maintenance 只能作为经过测量的候选动作。它们有写入副作用，不保证每个 workload 都变快；运行前后必须核对逻辑历史和工作区。对于外部服务、真实磁盘、平台配额和区域故障，本地实验只能标出边界，不能替代目标环境的受控验证。

## 资料

- [git-count-objects](https://git-scm.com/docs/git-count-objects)
- [git-rev-list](https://git-scm.com/docs/git-rev-list)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-commit-graph](https://git-scm.com/docs/git-commit-graph)
- [git-multi-pack-index](https://git-scm.com/docs/git-multi-pack-index)
- [git-maintenance](https://git-scm.com/docs/git-maintenance)
- [Trace2 API](https://git-scm.com/docs/api-trace2)
- [git-status](https://git-scm.com/docs/git-status)
