# 仓库“还能用”不等于健康：容量预算、SLO 与维护窗口

一个仓库 clone 还能成功，却已经只剩几个小时磁盘余量；LFS 用量超过预算，CI artifact 仍在加速增长；备份任务每天显示成功，但最近一次空环境恢复是两年前。平台页面没有红色告警，不代表这个工程资产健康。

仓库健康是多维状态：对象和引用是否完整、服务是否可用、关键操作是否在 SLO 内、数据副本是否足够新、容量是否有可行动余量、治理事实是否可见、恢复是否经过演练。单一 `repository_size`、一次 `git fsck` 或平均 clone 时间都不能代表全部维度。

第九篇的[性能与维护基线](../part-09/01-measure-before-optimizing.md)从单仓库工作负载出发，解释历史、对象、refs、index、工作区和网络瓶颈，以及 commit-graph、MIDX、bitmap 和 maintenance 的机制。本章不重复调优手册，而是把仓库、LFS、制品、备份、服务负载和维护任务纳入组织控制面：谁负责、何时预警、怎样预测耗尽、维护前满足哪些门禁、失败后如何停止和恢复。

本章以 Git 2.49.0、Bash 和本地仓库验证 Git 指标与维护不变量。平台容量、LFS/制品配额、API 指标、限流、计费和服务端维护能力会随厂商、版本、套餐和权限变化，具体数值必须进入事实登记。本章不给出可外推的 GB、毫秒或增长率阈值。

进入本章前，读者应理解对象库、refs、pack、LFS、制品证据链、备份/RPO/RTO、仓库生命周期和审计事件。读完后，应能：

- 用完整性、可用性、时延、新鲜度、容量、可治理性和可恢复性描述仓库健康；
- 建立来源、单位、时间、覆盖和状态明确的健康快照；
- 分别预算 Git 对象、refs、LFS、制品、备份、日志、网络和临时维护空间；
- 用 headroom 与趋势做分级预警，而不是等硬配额拒写；
- 区分 `pass`、`warn`、`fail` 与 `inconclusive`；
- 为维护任务定义互斥、磁盘放大、事故冻结、备份和回退门禁；
- 在维护后证明 refs、可达对象、HEAD tree 和服务行为保持正确；
- 从组织视角发现热点、共同故障域和无人负责的异常资产。

## 健康至少包含七个维度

| 维度 | 要回答的问题 | 代表性证据 |
| --- | --- | --- |
| 完整性 | refs 指向的对象是否可读，外部 payload 是否一致 | `fsck`、refs manifest、LFS/制品摘要、存储校验 |
| 可用性 | clone/fetch/push/API/LFS/评审入口是否可用 | 分地域探针、成功率、错误分类、依赖状态 |
| 时延 | 开发者、CI 和服务端关键路径是否在目标内 | 分位数、输入规模、冷/热状态、Trace2/服务端阶段 |
| 新鲜度 | mirror、备份、审计和索引落后权威端多久 | checkpoint、复制滞后、最后成功/完整采集时间 |
| 容量 | 各数据面和临时任务还有多少可行动余量 | 当前用量、硬限制、增长、峰值、headroom days |
| 可治理性 | Owner、分类、权限、规则、例外和指标来源是否可见 | 资产登记、认证、策略对账、采集状态 |
| 可恢复性 | 能否在 RPO/RTO 内从空环境恢复约定范围 | 最近演练、恢复点、验收结果、失败项 |

健康总览不能用简单平均。一个仓库的 clone p95 很好，但对象完整性失败，整体仍是 fail；某项 API 无权限导致数据未知，应是 inconclusive，而不是用其他绿色维度“平均掉”。

不同资产等级需要不同 SLO。公开文档、生产基础设施、受监管源码、二进制素材和冷归档的可用性、恢复和审查要求不同。统一采集字段便于比较，目标值由分类和业务依赖决定。

## 先定义资产与工作负载，再采指标

每份健康快照至少绑定：

```text
snapshot_id / collected_at / coverage_window
repository_id / locator / lifecycle / data_class / owner
authority_endpoint / replica_or_backup_id
git_version / object_format / ref_format
metric_name / value / unit / aggregation
workload_or_query / candidate_oid / config_digest
source / collector / permission_scope / status
```

没有 `repository_id`，仓库改名/转移后趋势会断成两条；没有 authority/replica 身份，主站和落后镜像的 refs 会混在一起；没有单位和聚合，`size=100` 可能是 KiB、bytes、对象数或某个平台四舍五入后的显示值。

采集状态至少区分 `available`、`partial`、`unavailable` 与 `unsupported`。API 返回空、命令退出非零、分页中断和权限不足不得写成数值 0。零是测量结果，unknown 是证据缺口。

### 指标基数要固定

同一个 “仓库大小” 可能表示：

- 当前 clone 工作区；
- 当前 Git directory；
- 可达 Git 逻辑对象；
- loose/pack 物理字节与临时 pack；
- refs/reflog/不可达/cruft；
- LFS cache 或服务端 payload；
- package、release、CI artifact/cache；
- mirror、备份和审计副本。

趋势图必须固定基数。平台升级后指标从“不含 LFS”变成“包含 LFS”，这是口径变更，不是一天内真实增长。Schema/version 和迁移标记要跟快照一起保存，必要时重算历史或断开趋势线。

## 容量预算分层，不用一个总 GB 掩盖热点

| 容量面 | 当前量与增长 | 接近上限时的典型影响 |
| --- | --- | --- |
| Git objects/pack | 对象数、bytes、pack/loose/cruft、delta 与临时输出 | push/repack 失败、磁盘耗尽、备份窗口扩大 |
| Refs/reflog | 分支/tag/隐藏 refs、更新率、日志保留 | 广告/策略/协商变慢，锁与存储增长 |
| 工作区/index | tracked paths、index bytes、checkout 临时空间 | status/checkout/IDE 变慢，本地磁盘不足 |
| LFS | pointer 数、unique payload bytes、传输、锁和缓存 | checkout/smudge 失败、上传拒绝、费用增长 |
| 制品与 package | artifact/cache/image/release bytes、版本数、下载 | 发布失败、旧制品无法恢复、成本失控 |
| 备份与 mirror | full/incremental bytes、保留链、复制流量、恢复临时空间 | RPO 失守、恢复链断裂、灾备容量不足 |
| 审计与日志 | raw/normalized/index/export bytes 与 ingest/query | 调查窗口缩短、采集停顿、查询失败 |
| 网络/请求 | clone/fetch/push/LFS/API bytes、QPS、并发和队列 | 限流、尾时延、其他仓库受 noisy neighbor 影响 |

这些预算相互关联却不能相互抵消。Git 对象只用了 20%，LFS 已超过硬限制，整体容量就是 fail；备份存储还有空间，也不能拿来当生产 pack 的即时 scratch。

预算至少有：当前用量、软阈值、硬限制、安全余量、预计增长、采购/扩容 lead time、负责人和动作。硬限制来自文件系统、平台配额或架构边界；软阈值应该给人完成归因、清理、迁移或扩容的时间。

### 临时空间是独立预算

Repack、迁移、恢复、导出和备份可能在旧数据仍存在时写新数据。维护前不能只看“最终 pack 预计更小”，要估算峰值：当前对象、候选新 pack、索引/bitmap、临时文件、失败重试和文件系统保留空间。

放大系数不是通用常数。它取决于任务、Git 版本、对象图、pack 策略、并发和存储实现，应从同类仓库演练测得并保守预算。本地 `df` 也不能代表存储后端配额、inode、thin provisioning 或快照保留。

## Headroom 比百分比更接近行动时间

容量百分比回答“用了多少”，headroom days 尝试回答“按已观测趋势还剩多久”：

```text
daily_growth = robust_trend(recent_snapshots)
headroom_days = (hard_limit - current_usage - safety_margin) / daily_growth
```

只有 growth 为正且口径稳定时才计算。两点直线只能作为合成演示；生产预测需要更长窗口、异常值/批量迁移标记、周/月季节性、版本发布峰值和置信区间。负增长可能是清理成功，也可能是指标丢失或口径变化，不能自动延长预测。

预警窗口要大于响应 lead time：扩存储、采购席位、迁移 LFS、重写历史、改变保留或拆分仓库都可能需要数周。若扩容需要 30 天，预计 7 天耗尽时才告警，阈值即使数学正确也没有运维价值。

推荐分级：

- `pass`：所有必需来源完整，当前未越硬限制，headroom 超过行动窗口；
- `warn`：尚未越限，但预计在行动窗口内触及安全/硬阈值，或恢复/维护余量偏低；
- `fail`：已越硬限制、完整性失败、备份/恢复契约失守或服务关键路径不可用；
- `inconclusive`：必需指标、单位、权限、时间窗或口径无法验证。

`warn` 不是失败的弱化名字，它应有 owner、截止和具体动作。连续数月 warn 且无人处置说明治理系统失效。

## SLI、SLO 与错误预算要按路径分开

典型 SLI：

- clone/fetch/push 的成功率和 p50/p95/p99，按地区、协议、仓库规模分层；
- ref update 服务端处理与队列时间；
- 评审/required check/merge queue 的等待与失败类型；
- LFS/制品上传下载可用性和 bytes；
- mirror/备份/审计 checkpoint 的 lag；
- 维护任务完成率、锁等待、临时空间峰值和超时；
- 恢复演练实际 RPO/RTO。

把认证失败、策略拒绝、客户端取消、服务器 5xx 和超时全算成“push 失败”会混淆安全控制与可靠性。每类结果单独统计，再按用户旅程定义 SLI 分母。

平均值会隐藏尾部和热点。组织总 p95 可能被大量小仓库稀释，少数关键 monorepo 的开发者每天等待数分钟。报告同时给资产分层分位数、最差 N 个资产和相对自身基线的突变。

错误预算适用于允许少量服务失败的 SLO，不是数据完整性、未授权写入或不可恢复对象的豁免额度。不能因为 clone SLO 有余量，就接受一次对象丢失或规则绕过。

## 组织汇总关注分布、热点和共同故障域

简单把所有仓库 bytes 相加只能做采购粗估，不能告诉运维哪个资产先出问题。组织视图至少支持：

- 按 owner、业务域、数据分类、平台实例、区域和生命周期分组；
- 当前用量、增长、headroom、错误率和恢复演练年龄；
- 最差资产、最大增长贡献、异常突变与长期无数据；
- 孤儿仓库、无预算仓库、未知 LFS/制品/备份范围；
- 共享对象池、runner、LFS 服务、备份桶和身份控制面的故障域；
- 维护队列、冲突窗口和资源配额。

同一个大客户批量 clone 可能让整个实例尾延迟上升；一个共享 object pool 损坏会影响许多看似独立仓库。资产表要记录物理依赖，告警按故障域聚合，避免几千条相同症状工单掩盖一个根因。

生命周期也是容量工具，但不能为了降指标盲目删除。归档先阻断写入并保存恢复点，删除经过依赖、保留和审批；清理 cache、artifact、LFS 或不可达对象分别遵守自己的保留契约。

## 维护窗口是一项有门禁的变更

维护状态可以写成：

```text
REQUESTED
  -> IMPACT_ASSESSED
  -> CAPACITY_RESERVED
  -> BACKUP_VERIFIED
  -> QUIESCED_OR_CONCURRENCY_APPROVED
  -> RUNNING
  -> VALIDATING
  -> COMPLETE
                -> FAILED_CONTAINED
                -> ROLLED_BACK_OR_RESTORED
```

每个任务记录：资产/故障域、任务与参数、Git/平台版本、预计读写/锁/网络/临时空间、允许并发、开始/停止条件、owner、观察者、备份恢复点、验证、回退/恢复和审计 ID。

### 维护前的硬门禁

1. 不是事故取证现场，没有 active legal hold 禁止的改写；
2. Source/replica 身份明确，单一权威和写入策略已决定；
3. 最近恢复点完整，且恢复路径与本次任务影响范围匹配；
4. 当前对象/refs/LFS/制品完整性达到任务前提；
5. 临时 bytes、inode、IOPS、网络和执行时间余量充足；
6. 与备份、mirror、GC/repack、迁移和其他维护不冲突；
7. 客户端/服务版本兼容，辅助格式变化有回退读取路径；
8. 停止条件、通知、值守和失败现场保全已准备。

“备份任务昨晚绿色”不能单独通过门禁。若 repack 影响物理对象布局，恢复点必须能在对象损坏时恢复；若要删除旧 LFS payload，Git bundle 不是对应备份。

### 互斥按共享资源，而不是按脚本名

两个任务名字不同也可能写同一对象库：独立 `git gc`、incremental repack、MIDX expire、备份扫描和 mirror 更新会争锁、磁盘或 IO。调度器的互斥 key 应包括 repository/object pool/storage volume/平台节点，必要时跨仓库。

锁要有 owner、lease/心跳、任务 ID 和故障恢复，不能只留下永远存在的空文件。发现陈旧锁时先确认进程与存储状态；直接删除可能让两个写任务并发。Git 自身 lockfile 也不等于组织级维护调度已互斥。

### 事故期间默认停止破坏性维护

对象损坏、凭据事件或未知写入正在调查时，repack、prune、GC、日志销毁和自动修复可能改变证据。事件指挥明确批准前冻结；只读健康采集也要评估负载和外部程序边界。

服务降级时可能需要只运行恢复必需任务，例如扩大存储或停止写入，而不是坚持完成原维护计划。窗口超时先进入失败包含，不能让任务无人值守跨越备份/流量高峰。

## 维护后验证逻辑状态和服务结果

Git 辅助索引或 pack 布局可以变化，以下逻辑状态默认应保持：

- 全 refs 及 symbolic HEAD；
- refs 可达 commit/object 集合；
- 关键 refs 的 commit graph 与 tree；
- annotated tag、notes、自定义 refs 和对象格式；
- LFS pointer/payload、submodule 固定 commit 和制品关联；
- 普通 clone/fetch/push、CI 和备份路径；
- 审计事件、复制 checkpoint 和恢复能力。

验证命令和成本按任务选择。`git fsck --full --strict` 能检查 Git 对象格式/连接，不证明 LFS、平台数据库、权限或性能；大型服务上全量检查可能本身超出窗口，应在副本分层执行并明确覆盖。

维护失败后不要立即运行另一个“修复”任务覆盖现场。保存 stderr、退出码、锁、临时/新旧 pack、磁盘与 refs；停止写入扩散，在可信副本判断是辅助索引问题、空间耗尽还是对象丢失。辅助文件常可重建，唯一对象被 prune 后未必能回来。

### 回退不等于物理布局复原

关闭 commit-graph/MIDX 读取可让查询回到基础对象路径，但不会恢复已经删除的 pack；回退配置也不会撤销历史重写或 LFS 迁移。任务计划要区分：

- 可关闭/重建的辅助索引；
- 可从旧 pack/快照恢复的物理布局；
- 需要 refs 条件更新的逻辑迁移；
- 已删除且只能从备份恢复的数据。

越接近不可逆删除，越需要更长观察期、独立恢复验证和双人批准。

## 平台配额与服务指标必须带版本边界

真实平台专项验证要记录：

- Git/LFS/package/artifact/cache/log/backup 分别怎样计量；
- 单仓库、namespace、账号、实例和区域限制；
- 硬拒绝、软告警、自动清理和超额计费行为；
- 指标刷新延迟、单位、是否含历史/隐藏 refs/forks/dedup；
- API 的权限、分页、采样、保留和 unavailable 语义；
- 服务端 GC/repack/maintenance 是否自动、能否观测/暂停；
- 扩容、降配、迁移和删除后的计费/恢复边界。

同一产品云服务、自托管版和不同许可层可能不同；厂商修改计量口径后，趋势需要版本标记。没有核对的具体数字不写进正文，不把 UI 进度条当精确容量证据。

## 常见失败与恢复

| 症状 | 常见原因 | 安全动作 |
| --- | --- | --- |
| 仓库大小突然下降 | 指标口径变化、采集缺失、历史清理或真实 GC | 标记趋势断点，核对 schema/refs/审计；不要自动延长 headroom |
| 总容量健康，单仓 push 失败 | 单资产/LFS/namespace/inode 达限或临时空间不足 | 分层核对限制和峰值，停止重试放大；扩容或受控迁移 |
| 用量未超限，维护仍磁盘耗尽 | 未预算新旧 pack 并存、失败重试和快照 | 停止新增任务、保全新旧对象；扩展 scratch 后从恢复点重做 |
| p50 改善但 p99 恶化 | 后台维护锁、noisy neighbor 或冷热样本混合 | 暂停推广，按故障域/工作负载分层并重测 |
| 自动 GC 与备份同时运行 | 调度器只按任务名互斥 | 围栏相关写任务，验证备份一致性；按 object pool/volume 建锁 |
| `fsck` 通过但 LFS checkout 失败 | Git pointer 完整，payload/认证/配额失败 | 保持 Git 数据，恢复 LFS 服务/备份并从空 cache 验收 |
| 指标显示 0 个 refs | API/命令失败被转换成零 | 标记 inconclusive，保存 stderr/权限/分页并修复 collector |
| 维护后对象读取失败 | Pack/index/MIDX 损坏或唯一对象被删除 | 停写保全现场；先禁用辅助索引诊断，从可信 donor/备份恢复 |
| Warn 长期无人处理 | 无 owner、阈值无动作或容量采购 lead time 未登记 | 升级资产风险，绑定工单/截止；重设可行动阈值 |
| 归档删除后容量未下降 | LFS/制品/备份/快照另有保留或延迟计量 | 按数据面核对处置，不为降指标绕过保留政策 |

## 合成实验：健康分级、容量 headroom 与维护门禁

本书提供 `scripts/verify-repository-health-capacity.sh`。在仓库根目录执行：

```bash
bash scripts/verify-repository-health-capacity.sh
```

脚本在 `mktemp` 创建本地仓库与明确标注的合成健康/容量 TSV。合成数据用于验证策略计算，不冒充任何平台配额或生产指标；实际 Git 指标来自临时仓库本身。

实验验证：

1. 从真实临时仓库采集 object bytes、refs、reachable commits、object/ref format 和 `fsck` 结果；
2. 任一容量面越过硬限制返回 fail，其他维度有余量不能平均抵消；
3. 当前未越限但按两点合成趋势在行动窗口内耗尽返回 warn；
4. 用量稳定且完整性/备份通过返回 pass，来源不可用返回 inconclusive；
5. `fsck` 失败即使容量很小也返回 fail；
6. 事故 active、备份未验证、scratch 不足或已有维护锁时任务不会启动；
7. 模拟任务失败后组织级锁释放，Git refs/对象/tree 保持；
8. 合法 commit-graph 维护完成后，refs、可达对象、HEAD tree 与 `fsck` 前后一致，并留下开始/完成记录。

实验不测量性能、不预测真实增长，也不验证 LFS、制品、平台 API、磁盘故障、inode、服务并发、OS scheduler 或实际存储配额。两点趋势只用于检验分级逻辑，不能作为生产容量预测方法。

## 小结

仓库健康不是“还能 clone”，而是完整性、可用性、时延、新鲜度、容量、治理和恢复同时有可信证据。容量预算按 Git、refs、LFS、制品、备份、审计和临时空间分层；趋势必须绑定口径与行动 lead time；组织视图关注热点与共同故障域，不用平均值掩盖关键资产。

维护窗口是一项有备份、容量、互斥、事故冻结、停止和验证门禁的变更。任务成功退出不等于状态正确，任务失败也不能靠连续“修复”覆盖现场。下一章将把这些能力接成组织级故障手册和恢复演练，验证 owner、策略、审计、容量与灾备在同一事件中能否真正协作。

## 资料

- [git-count-objects](https://git-scm.com/docs/git-count-objects)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-rev-list](https://git-scm.com/docs/git-rev-list)
- [git-fsck](https://git-scm.com/docs/git-fsck)
- [git-maintenance](https://git-scm.com/docs/git-maintenance)
- [git-commit-graph](https://git-scm.com/docs/git-commit-graph)
- [git-multi-pack-index](https://git-scm.com/docs/git-multi-pack-index)
