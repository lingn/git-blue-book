# 先测量，再优化：大仓库性能与维护基线

“仓库超过多少 GB 就算大”没有通用答案。一个只有几百 MB、却有数百万 tracked paths 的仓库，`status` 可能很慢；一个包含多年历史和大量 blob、但工作区很小的仓库，日常编辑可能正常，clone 与服务端 fetch 却很重；数十万 refs 又会形成另一类瓶颈。

性能治理的第一步不是选择 `gc`、部分克隆或 monorepo 拆分，而是固定一个真实工作负载，记录它读取了哪一层数据，在可比较环境中测量。优化只在目标指标改善、正确性保持、维护成本可接受时成立。

进入本章前，读者应理解 commit/tree/blob、refs、index、工作区、packfile、远程协商、浅克隆、部分克隆与 sparse-checkout。读完后，应能建立仓库规模清单和命令时延基线，使用 Trace2 分解 Git 内部阶段，解释 commit-graph、MIDX 与 bitmap 分别优化什么，并安全验证显式维护没有改变 refs、对象身份和候选 tree。

本章命令在 Git 2.49.0 和 macOS 上验证。任何性能数据都必须同时记录硬件、操作系统、文件系统、Git 版本、仓库对象、配置、缓存状态、并发负载和测量次数。本章实验只验证机制，不提供可外推的毫秒或吞吐结论。

## “大”至少有六个维度

先把仓库规模拆成可观察量：

| 维度 | 典型指标 | 更容易影响的路径 |
| --- | --- | --- |
| 历史图 | reachable commits、拓扑宽度、merge 密度 | `log`、`merge-base`、包含性判断、push 协商 |
| 对象库 | loose/in-pack objects、pack 数、pack bytes、delta 链 | clone/fetch、对象查找、repack、磁盘占用 |
| refs | 本地/远程分支、tags、隐藏 refs 数量 | ref 枚举、协商、服务端广告与策略检查 |
| index | tracked paths、index bytes、稀疏状态 | `status`、`add`、checkout、merge |
| 工作区 | 文件/目录数、未跟踪项、文件系统时延 | `status`、切换、IDE 与文件监控 |
| 外部边界 | 网络 RTT/带宽、LFS/submodule、代理和服务端负载 | clone/fetch/push、按需对象与构建依赖 |

这些维度不能互相替代。仓库磁盘大小相同，不表示命令成本相同；commit 数相同，路径历史和文件系统扫描也可能差几个数量级。组织应按开发者交互、CI、远端服务和备份分别测量，而不是发布一个“仓库总大小”指标后停止诊断。

### 从慢命令反推候选瓶颈

| 症状 | 首先采集 | 不应立即推断 |
| --- | --- | --- |
| `status` 慢 | tracked/untracked paths、index、fsmonitor、文件系统、Trace2 | 对象库一定需要 gc |
| `log -- path` 慢 | commit 数、merge 图、commit-graph、changed-path Bloom filters | 文件太大 |
| 分支切换慢 | checkout 路径数、filters/LFS、磁盘、未跟踪冲突 | 历史太长 |
| clone/fetch 慢 | 网络、协商 tips、server CPU、pack bytes、bitmap、filter 能力 | 客户端工作区太大 |
| 任意对象读取抖动 | pack 数、MIDX、alternates、磁盘与并发维护 | commit-graph 缺失 |
| ref 列表/协商慢 | refs 数与后端、隐藏 refs、服务端策略 | blob 太多 |

一项优化只有作用于瓶颈所在的数据结构，才有可能改善目标工作负载。例如 commit-graph 不会减少工作区目录扫描，sparse-checkout 不会减少服务端已有对象库，MIDX 也不会让网络 RTT 消失。

## 建立可复现测量单

每次基线至少记录：

```text
测量 ID与日期
机器型号、CPU、内存、电源模式
操作系统、文件系统、挂载/网络盘、杀毒与索引器
Git 版本、object/ref format、关键 config 来源
仓库绝对位置、HEAD/候选 commit、partial/shallow/sparse 状态
工作负载命令、输入 refs/pathspec、输出是否丢弃
冷/热缓存定义、预热步骤、重复次数
并发 Git/IDE/构建/备份负载
real/user/sys、Trace2 证据与错误
```

“冷缓存”必须写明怎样实现。在普通开发机上第一次运行不等于稳定冷缓存；后台索引、前一次测试和操作系统页缓存都可能介入。不要用未经评审的 `sudo purge`、drop_caches 或重启生产主机制造数据点。需要冷缓存对比时，使用可销毁虚拟机、同一镜像、同一磁盘快照与明确启动流程。

“热缓存”也不只是把命令再跑一次。规定预热次数、等待时间和是否允许后台维护，至少采集多个样本并报告中位数与尾部值。一次最快结果只说明那一次运行快。

## 固定逻辑状态与配置

在目标仓库根目录先只读记录：

```bash
git version
git rev-parse --show-toplevel
git rev-parse --show-object-format
git rev-parse --show-ref-format
git rev-parse --verify 'HEAD^{commit}'
git status --short --branch
git config --show-origin --show-scope --list
```

Git 2.49 支持这里的 object/ref format 查询；旧版本缺少选项时应记录“命令不支持”，不能猜默认值。最后一条可能暴露内部 URL、helper、代理和本机路径，证据文件要限制访问并脱敏。

`status` 通常是观察命令，但可能刷新 index 的 stat 信息，并受 fsmonitor、untracked cache、filters 和文件系统影响。在需要最大限度减少可选写锁的测量副本中，可使用：

```bash
git --no-optional-locks status --porcelain=v1
```

它不承诺进程完全不读配置或不访问工作区。高风险仓库仍需按[不受信任仓库](../part-10/05-untrusted-repositories.md)的隔离边界处理。

### 记录 shallow、partial 与 sparse 状态

受限仓库的“本地对象数少”可能只是对象在远端：

```bash
git rev-parse --is-shallow-repository
git config --show-origin --get-regexp '^remote\..*\.promisor$|^remote\..*\.partialclonefilter$'
git sparse-checkout list
```

第一条输出 `true` 或 `false`。第二条没有匹配时退出 1；第三条在未启用 sparse-checkout 时也可能失败。把这些失败作为状态记录，不要用 `|| true` 隐藏在测量报告中。

部分克隆中的对象访问可能触发网络按需 fetch；第一次与后续运行因此测到不同输入。离线测试、服务端测试和开发者在线测试必须分组，不能混在同一分位数里。

## 采集规模指标，不先做维护

### 对象物理布局

```bash
git count-objects -vH
```

命令读取对象目录，报告 loose object 数与空间、in-pack 数、pack 数与空间、可裁剪的重复 loose objects、garbage 和 alternates。`-H` 适合人工阅读；自动化采集使用不带 `-H` 的 KiB 数值，避免解析 `MiB` 等本地化单位。

这不是“所有历史逻辑对象”的完整统计。Alternates 可能把对象放在其他目录，partial clone 可能尚未取得 promisor 对象，不可达对象与 cruft pack 也需要单独解释。看到 `garbage` 不要立即删除：它可能是并发中间文件、损坏证据或管理员放入对象目录的错误文件，应先记录路径与进程状态。

### Reachable commits 与 refs

```bash
git rev-list --count --all
git for-each-ref --format='%(refname)' | wc -l
```

第一条遍历所有普通 refs 可达 commit 的并集，结果不会按分支重复计同一 commit；它本身可能是昂贵查询，应在测试副本或低峰执行。`--all` 不等于平台所有隐藏引用、reflog 或不可达对象。第二条统计当前客户端可见 refs，`HEAD` 等 root refs 默认不在其中。

服务端性能调查必须在服务端权限范围内重复采集；客户端 clone 看不到服务端隐藏 refs，不能代表协商输入全集。

### Tracked paths 与 index 大小

```bash
tracked_paths="$(git ls-files -z | tr -cd '\000' | wc -c | tr -d ' ')"
index_path="$(git rev-parse --path-format=absolute --git-path index)"
index_bytes="$(wc -c < "$index_path" | tr -d ' ')"
printf 'tracked_paths=%s\nindex_bytes=%s\n' "$tracked_paths" "$index_bytes"
```

NUL 计数避免文件名中的换行破坏路径数量。命令只读取当前 index；sparse index 可以用一个 sparse-directory entry 表示大量路径，因此 index bytes 和 `ls-files` 展开语义要与 `index.sparse`、sparse-checkout 范围一起记录。Linked worktree 的 index 路径不一定是仓库根 `.git/index`，所以使用 `--git-path` 解析。

Index 小不表示工作区扫描便宜。还要记录受跟踪与未跟踪目录数量、文件系统类型、网络挂载、symlink/大小写行为、IDE watcher 和安全软件。不同操作系统的可靠文件枚举命令不同，本书不提供一个会误处理特殊文件名的通用 `find | wc` 快捷统计。

## 测量用户真正等待的命令

在无未提交工作、已固定候选 commit 的测量副本中，POSIX 环境可记录：

```bash
/usr/bin/time -p git --no-optional-locks status --porcelain=v1 >/dev/null
/usr/bin/time -p git log --topo-order --all --format='%H' >/dev/null
```

`time -p` 把 `real`、`user`、`sys` 写到标准错误；Git 输出被丢弃，避免终端渲染成为主要成本。Windows 应使用同等可审计的计时工具，并记录工具版本。命令不修改 refs，但 status 仍读取完整工作区，log 会遍历实际历史。

每个样本必须使用相同参数和输出处理。Path history、merge-base、fetch negotiation、checkout、IDE status 等要分别建 workload，不能用一次 `git log` 推断全部体验。报告至少给样本数、中位数、p95/最大值和失败次数；样本很少时不要伪装成统计显著性。

### 客户端与服务端时延要拆开

Fetch 的端到端时间可能包含 DNS、代理、TLS/SSH、身份验证、ref advertisement、协商、服务端对象遍历、压缩、传输、客户端解包、ref 更新和自动维护。只看总秒数无法决定是加 bitmap、扩容服务器还是修代理。

使用固定服务器、网络位置和 ref 更新量分别测量；记录收发 bytes、server trace 与 client trace。托管平台是否暴露服务端指标、限流或 pack cache 是易变事实，应按产品与核对日期登记。

## Trace2 用于解释阶段，不替代基准设计

Git Trace2 可以输出结构化 event 或面向性能的 region 记录。以下命令把一次 status 的 JSON Lines 写到仓库外临时目录：

```bash
trace_root="$(mktemp -d "${TMPDIR:-/tmp}/git-trace.XXXXXX")"
trace_file="$trace_root/status.json"

GIT_TRACE2_EVENT="$trace_file" \
  git --no-optional-locks status --porcelain=v1 >/dev/null
```

前提是在测量副本根目录运行，临时目录可写。命令会创建 trace 文件；成功事件通常包含 version、start、cmd_name、region、data、exit 等记录，具体字段随 Git 版本和命令路径变化，不应逐字匹配固定行。

Trace 可能包含命令参数、绝对路径、远端信息、线程与进程标识。它不是默认可公开日志；采集前定义保留、脱敏与访问权限。Trace 本身也有开销，应在“诊断运行”和“低开销时延基准”之间分开采样。

先查看最耗时 region 和 child process，再形成假设。例如大量 index refresh/worktree 扫描指向文件系统路径；revision walk 指向历史辅助数据；pack-objects 或 negotiation 指向对象遍历与传输。只有 region 与规模指标共同支持，才进入优化实验。

## Commit-graph 是历史图的辅助索引

commit-graph file 序列化 commit 的拓扑相关信息和 generation number，使许多可达性/拓扑查询不必反复解压每个 commit object。它不替代 commit 对象，不改变父关系，也不缩短历史。

在测试 clone 或维护窗口中写入全部 refs 可达 commit，并为 path history 计算 changed-path Bloom filters：

```bash
git commit-graph write --reachable --changed-paths
git commit-graph verify
```

第一条读取所有 refs 与 commit/tree，并在对象目录的 `info` 区写辅助文件；`--changed-paths` 需要比较路径，在大型仓库可能明显耗时，且后续写入会延续该意图。第二条把 commit-graph 与对象库交叉验证，成功通常无输出。

适用工作负载包括部分 `log --graph`、merge-base、包含性判断和 path history；收益取决于图形状、现有 cache、Git 版本和 Bloom filter 覆盖。不能因为文件存在就宣称改善。

Mixed-version 团队还要核对 changed-path Bloom filter 版本。Git 2.49 可配置的格式版本并不保证旧客户端理解；先建立客户端矩阵，再在共享对象存储写入新格式。

若 verify 失败，停止自动维护并保存文件、Git 版本和对象库证据。可临时在隔离诊断中用：

```bash
git -c core.commitGraph=false log --oneline -n 5
```

这只让本次命令回退到直接读取 commit objects，不修复损坏，也不删除证据。确认对象库健康后再重建辅助图；事故现场不要把失败归因于“缓存”后同时运行 gc/repack。

## MIDX 优化多 pack 查找，bitmap 优化可达对象枚举

每个 pack 通常有自己的 `.idx`。Pack 很多时，对象查找需要在多个 index 之间工作；multi-pack-index（MIDX）为一个 object directory 中的多个 pack 建统一索引。它不会仅因 `write` 就合并或删除 pack，也不改变对象 ID。

当对象目录确有多个 pack 时：

```bash
git multi-pack-index write --bitmap
git multi-pack-index verify
```

第一条写 MIDX 和对应 multi-pack bitmap；第二条验证 MIDX 内容。Bitmap 预计算部分可达集合，主要帮助 pack 生成、clone/fetch 服务端遍历等对象枚举；它不会加速工作区扫描。仓库只有一个 pack 或瓶颈不在对象查找时，MIDX 收益可能很小。

`--bitmap` 与 incremental MIDX 的当前组合存在限制，不能把不同教程的选项机械拼接。MIDX 的 `expire` 会删除不再被 MIDX 引用的 pack，`repack` 会写新 pack 并改变物理布局；它们比 `write/verify` 更需要磁盘余量、锁竞争和恢复评估。

诊断 MIDX 可用性时，可让单次读取回退到逐 pack index：

```bash
git -c core.multiPackIndex=false cat-file -e 'HEAD^{commit}'
```

成功只证明对象仍可由基础 pack index 找到。若 MIDX verify 失败，先停止相关维护，记录 pack/MIDX 清单与正在运行的进程；不要删除 pack 来“对齐索引”。

## Maintenance 是任务编排，不是一颗加速按钮

`git maintenance run` 可显式运行 commit-graph、incremental-repack、loose-objects、pack-refs、prefetch、gc 等任务。不同任务的写入范围、锁、网络和恢复影响不同。

在已备份、无事故取证、磁盘余量充足的测试 clone 中，可先只运行目标任务：

```bash
git maintenance run --task=commit-graph
git commit-graph verify
```

命令以前台方式更新辅助图，不注册调度器。若要试验 incremental-repack，应先记录 pack/MIDX、refs、HEAD tree、工作区、磁盘余量和当前进程；任务会调整 pack 物理布局，但逻辑对象与 refs 应保持：

```bash
git maintenance run --task=incremental-repack
git multi-pack-index verify
git fsck --full
```

`fsck --full` 可能在大仓库耗时很长，并遍历 alternates；把它放进维护验证窗口，不要塞进每个交互命令。验证还要比较维护前后的 `show-ref`、HEAD/tree、可达 commit 集和工作区状态。

`git maintenance start` 完全不同：它会 register 仓库、修改用户级 config，并按平台创建或更新后台调度任务。`stop` 与 `unregister` 的职责也不同，unregister 后某些 local config 可能保留。没有审计 OS scheduler、Git 二进制路径、多仓库负载和组织运维责任前，不要让开发者照抄 start。

并发维护会争夺对象数据库锁；官方文档也特别警告不要把独立 `git gc` 与 maintenance run 随意混排。维护窗口超过调度周期时，先降低任务复杂度或频率，不要无限增加并发。

## 优化决策必须绑定证据

| 证据支持的瓶颈 | 候选措施 | 主要代价/边界 | 验证工作负载 |
| --- | --- | --- | --- |
| 历史拓扑遍历 | commit-graph、generation data | 辅助文件更新与版本兼容 | log/merge-base/contains |
| path history | changed-path Bloom filters | 写入成本、覆盖和误报；不改变正确结果 | `log -- path` |
| 多 pack 对象查找 | MIDX、incremental repack | 索引/pack 锁、磁盘和维护复杂度 | cat-file、fetch server、repack |
| 可达对象枚举/pack 生成 | pack 或 MIDX bitmap | bitmap 生成成本与 tip 覆盖 | clone/fetch/rev-list workload |
| index/工作区规模 | sparse-checkout/sparse index、fsmonitor、untracked cache | 工具兼容、漏报/daemon 运维、路径外操作 | status/add/switch |
| 初次对象传输 | partial clone、bundle URI、服务端 cache | 服务器支持、按需网络、恢复依赖 | fresh clone + 后续对象访问 |
| 仅需有限历史的短命 CI | shallow clone | ancestry 不完整、merge/tag/版本计算边界 | 精确 CI job，不外推开发环境 |

Fsmonitor 与 untracked cache 依赖文件系统和 daemon/mtime 假设；sparse index 要求 cone-mode sparse-checkout，并非所有命令与第三方工具都同样受益。每个能力应单独试验、保留关闭路径和兼容矩阵。

仓库拓扑调整是最后一层。Monorepo 拆分可能减少单仓库 paths，却增加跨仓库版本、权限、原子变更和发布协调；合并多个仓库则反向交换成本。没有构建图、所有权与变更耦合数据时，不能从 Git status 的一次慢样本推导组织拆分。

## 一轮性能变更怎样验收

1. 固定仓库 commit/refs、工作负载、机器镜像和配置来源；
2. 采集规模、错误率、Trace2 和足够多的冷热样本；
3. 写出瓶颈假设和候选机制实际作用的数据结构；
4. 在可销毁 clone 或测试服务端只改一个变量；
5. 验证 refs、对象可达性、HEAD tree、工作区和命令结果一致；
6. 重跑相同 workload，报告分布而不是单次最快值；
7. 测量维护写入、磁盘峰值、锁等待与后台资源成本；
8. 定义回退配置、辅助索引重建、告警阈值与负责人；
9. 小比例发布后观察真实开发者/CI/服务端指标；
10. 记录无收益结果，避免团队几年后重复试错。

性能提升若以漏掉文件、缺失历史、错误构建或更短恢复窗口换取，就不是通过验收。正确性检查与时延测量同等重要。

## 常见失败与恢复

| 症状 | 首要证据 | 安全处理 |
| --- | --- | --- |
| `count-objects` 报 garbage | 文件路径、mtime、并发进程、磁盘错误 | 先保存证据并确认写入者，不直接 prune |
| commit-graph verify 失败 | graph chain、Git 版本、objects/fsck | 暂停维护，单次禁用读取诊断；对象健康后重建 |
| MIDX verify 失败 | MIDX、pack/idx 清单、并发 repack | 回退基础 pack index 只读验证，不删 pack |
| maintenance 磁盘耗尽 | task、临时/新 pack、磁盘与锁 | 停止新增任务，保全对象库；按官方恢复评估临时文件 |
| 优化后均值快但 p95 变差 | 全部样本、后台任务、锁与冷热分组 | 不扩大发布；分离维护和交互资源，重测 |
| partial clone 离线失败 | promisor config、缺失对象、网络日志 | 恢复远端可用性或取得完整对象，不伪装成本地损坏 |
| sparse/fsmonitor 工具行为异常 | Git/IDE 版本、index 模式、daemon 状态 | 在测试 clone 关闭单项能力并核对完整 tree |

对象库事故中不要把 `git gc --prune=now`、手工删除 `.pack/.idx` 或重建所有索引作为第一反应。辅助索引可重建，丢失的唯一对象未必可恢复；先区分“索引坏了”和“对象真的缺失”。

## 隔离实验验证了什么

在本书仓库根目录运行：

```bash
./scripts/verify-repository-performance-baseline.sh
```

前置条件是 Bash、Git 2.49 或兼容实现、`awk`、`grep`、`find`、`sort`、`tr`、`wc`、`mktemp` 和可写临时目录。脚本创建 36 个 commit、36 个 tracked paths、4 个 refs 和至少两个 pack 的小型 fixture；隔离 system/global config，禁用自动维护，不连接网络，退出时删除自己的临时目录。

实验断言 `rev-list`、`for-each-ref`、NUL-safe path count、index bytes 和 `count-objects -v` 指标可采集；一次 status 生成 Trace2 event 文件并包含 version/exit 事件。它不比较运行时长，因为这种小型临时仓库不能代表真实磁盘、网络、CPU 或 monorepo。

随后脚本写入并 verify reachable commit-graph 与 changed-path data、MIDX bitmap，再分别运行显式 commit-graph 和 incremental-repack maintenance task。完成后执行 commit-graph/MIDX verify 与 `fsck --full`，并断言 refs、HEAD、HEAD tree、可达 commit 集和干净工作区与维护前一致；同时验证禁用 commit-graph/MIDX 后基础对象路径仍可读取。

成功时只输出：

```text
Scale metrics, Trace2, commit-graph, MIDX bitmap, and explicit maintenance passed.
```

实验没有验证任何性能收益、后台 scheduler、服务端负载、partial clone、LFS、网络文件系统、真实冷缓存或磁盘故障。那些结论必须按本章测量单在目标环境采集。

## 小结

大仓库不是一个容量阈值，而是历史、对象、refs、index、工作区、网络和外部依赖共同形成的工作负载。先固定逻辑状态和环境，采集规模、时延分布与 Trace2，再把瓶颈映射到具体数据结构。

Commit-graph 加速历史图查询，MIDX 统一多个 pack 的对象查找，bitmap 帮助可达对象枚举；maintenance 负责调度这些写入与整理任务。它们都不能替代正确性验证，也不能靠文件存在证明收益。优化完成的证据，是相同 workload 在可比较环境中改善，同时 refs、对象、tree 与团队运维边界保持正确。
