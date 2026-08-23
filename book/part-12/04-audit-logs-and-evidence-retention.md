# 日志不是证据仓库：审计事件、留存与调查导出

一次未经授权的强推发生后，团队在平台里搜到一条 “branch updated”，于是认为证据已经齐全。真正调查时才发现：导出只保留了 30 天，actor 是一个共享机器人，时间使用浏览器本地时区，规则变更和 token 签发在另一个系统，分页中断还漏掉了事故前后的事件。

审计日志只有在覆盖范围、主体关联、时间语义、采集完整性、原始字节、访问控制、留存与导出流程都明确时，才可能成为可用证据。事件数量多、搜索页面好看或存储声称“不可变”，都不能单独证明调查所需事实完整。

本章建设的是长期审计证据系统；第十一篇的[事故现场保护与采集](../part-11/01-preserve-and-acquire.md)处理事故发生后如何冻结并保存现场。前者应在事故之前持续运行，后者在事件中把审计导出与文件系统、Git 逻辑、平台和运行环境证据汇合。两者通过仓库资产 ID、principal、request/session ID、规则版本和对象 OID 关联。

本章使用厂商无关模型。托管平台的事件类型、字段、API、可见性、保留期、导出能力、许可和管理员权限会变化，必须按产品、云/自托管版本、套餐、权限与核对日期登记。随章实验使用 Git 2.49.0、本地 bare 仓库、虚构 actor 和合成 hooks，只验证 Git 接收事件、游标、序列缺口、摘要和调查包边界，不冒充真实平台审计。

进入本章前，读者应理解仓库资产 ID、有效权限、规则/例外、refs、对象 ID、证据摘要和保管链。读完后，应能：

- 定义能关联主体、资源、动作、结果与 old/new OID 的事件模型；
- 区分对象时间、服务端事件时间、采集时间与调查时间；
- 设计可重试且能发现分页/游标缺口的采集流程；
- 分开保存原始事件、规范化索引和脱敏派生物；
- 解释摘要、签名、WORM 与完整采集分别能证明什么；
- 按数据分类、事件类型、法律保留和恢复目标设计留存；
- 导出包含查询、schema、时区、缺口、摘要和保管记录的调查包；
- 在日志不可见、字段未知或采集失败时返回 inconclusive。

## `git log`、reflog 和平台审计不是同一种日志

三类名字相似，证据边界不同：

| 来源 | 主要记录 | 默认看不到 |
| --- | --- | --- |
| `git log` | 当前可达 commit 对象及其父关系、author/committer 字段 | 谁通过哪个会话 push、被拒请求、权限/规则变化 |
| reflog | 某个仓库本地 refs 曾经指向哪里以及本地记录的操作者说明 | 其他 clone、平台 API、服务端隐藏入口；且会过期 |
| 平台/服务审计 | 服务端 actor、API/界面/Git 动作、权限和配置事件 | 未提交工作区、客户端本地 reflog、平台未采集的外部系统 |

Commit 是内容寻址对象，不是服务端接收记录。Author/committer 名称、邮箱与时间属于对象字节，可由创建对象的客户端设置；签名能证明对象与 key 的关系，仍不说明对象何时被某个平台接受。一次 commit 还可能被多个 actor、在多个时间推送到不同 refs。

Reflog 对日常恢复很有价值，却是本地、可过期的引用移动记录。服务器实现是否保留 reflog、保存多久、管理员是否可读，不能从开发者 clone 推断。平台审计又可能把 Git push、Web 合并和管理员更新记录成不同事件。

调查时先问“这个来源机械上记录什么”，再决定它能支持哪条结论。不要用 commit author 时间代替入站时间，也不要用平台页面的一条事件代替 Git 对象和 ref 验证。

## 事件模型要保留“谁通过什么链条做了什么”

一条规范化审计事件至少包含：

```text
provider / instance / provider_event_id
schema_version / event_type
repository_id / current_locator
actor_principal_id / actor_kind
credential_or_session_id / delegated_actor / workload_id
action / target_type / target_id
old_object_id / new_object_id / object_format
result / reason / rule_id / policy_digest / exception_id
provider_event_time / collector_received_time
request_id / source / network_context
raw_partition / raw_record_digest
```

不是所有事件都有 old/new OID。成员加入、规则修改、token 创建、仓库归档和导出下载可能只有配置前后值或资源 ID；字段缺失要用明确 `not_applicable`/`unknown` 语义，不能统一写空字符串后让查询者猜。

### Actor 要保留委托链

自动化事件可能包含多层主体：某位工程师批准 workflow，CI job 使用 app installation 身份，短期 token 调用平台 API，最终更新 ref。只保留显示名 `release-bot` 会丢失触发者、工作负载和实际认证主体。

推荐分开保存：

- 业务/人类发起 principal；
- 实际通过认证的服务端 actor；
- app、机器人或 workload principal；
- credential/session/token 的不可逆标识或 fingerprint；
- 触发 run/job/request；
- 代表/委托关系及其来源。

不要把真实 token、session cookie 或私钥写进审计。需要关联时保存服务端安全标识、哈希化 ID 或签发器事件引用，并评估这些字段本身的敏感性。

### Result 必须包含拒绝和未知

只收成功更新会漏掉暴力尝试、权限探测和被规则挡住的攻击。结果至少区分：

- `accepted`：服务端确认动作完成；
- `denied`：授权/策略明确拒绝，资源未发生目标变化；
- `failed`：动作因系统、网络、验证或内部错误未完成；
- `partial`：跨多个资源的动作只完成一部分；
- `unknown`：来源没有给出可判定结果。

客户端看到非零退出不等于平台记录 `denied`：TLS 失败可能从未到达服务；hook 拒绝、权限拒绝和传输中断的事件来源不同。调查要关联客户端、边缘接入、身份、Git 服务和平台控制面的 request ID。

## 一条时间线至少有四种时钟

审计排序最常见的错误，是把所有 `timestamp` 当成同一时钟：

| 时间 | 由谁产生 | 主要用途 | 风险 |
| --- | --- | --- | --- |
| 对象 author/committer time | 创建 commit 的客户端 | 解释对象声明的创作时间 | 可任意设置、时区可变、可重写 |
| Provider event time | 接受/拒绝动作的服务 | 说明服务端观察动作的时间 | 服务间时钟偏差、批处理、字段语义不同 |
| Collector received time | 组织采集器 | 发现延迟、乱序和来源中断 | 队列/网络延迟，不是动作发生时间 |
| Investigation/export time | 查询或导出系统 | 记录何时取得这份证据 | 不能替代原事件时间 |

每个时间保存原始值、时区/offset、解析状态和规范化 UTC 值。缺时区时不能擅自按本地时区解释；无法解析就标记 unknown 并保留原字段。

跨来源时间线优先使用同一来源的单调 sequence、cursor 或 request 因果链，再用时间戳辅助。服务端事件晚到采集器、重试重复或跨区域乱序都很正常。若必须推断顺序，明确写出推断依据和不确定区间。

对象时间可能晚于服务端接收时间，也可能早很多年。实验和事故报告不应因为 commit `committer date` 排在前面，就断言该 commit 先进入仓库。

## 先建立覆盖矩阵，再谈统一日志平台

Git 服务相关审计至少盘点下列域：

| 域 | 关键事件示例 |
| --- | --- |
| 身份与认证 | 登录、MFA/SSO、token/key/app 创建撤销、会话、失败认证 |
| 授权 | 组织/团队/仓库成员、角色、直接 grant、外部协作者、绕过变化 |
| Git 数据面 | clone/fetch（若可得）、push、ref create/update/delete、force、hook/策略拒绝 |
| 评审 | 评审请求、审批/撤销、CODEOWNERS 命中、merge actor 与候选 OID |
| CI/CD | workflow/config、job actor、候选、检查、runner、secret/environment、部署 |
| 规则与配置 | 默认分支、保护规则、required checks、例外、可见性、hook/app/webhook |
| 供应链资产 | tag/release、package、container、artifact、attestation、LFS/锁 |
| 生命周期 | 创建、改名、转移、归档、恢复、删除、导出和备份恢复 |
| 审计系统自身 | 采集器身份、配置、查询、导出、访问、保留、hold 与销毁 |

并非所有平台能记录 clone 内容、每次 fetch 或管理员查看 secret 的行为。覆盖矩阵要明确 `available`、`not_provided`、`not_enabled`、`permission_denied` 与 `unknown`，不能把不可获得写成“无事件”。关键缺口需要补偿控制，例如网络/身份日志、只读代理、制品下载日志或更严格的数据隔离。

审计系统自身也要被审计。谁修改采集 scope、暂停 collector、搜索敏感日志、下载调查包、解除 legal hold 或删除分区，往往比普通代码事件更敏感。

## 采集管道要能发现漏页、重复和 schema 变化

一个可恢复的采集路径：

```text
Provider/API/stream
  -> collector（权限、cursor、重试、限流）
  -> raw immutable partition
  -> completeness/checkpoint ledger
  -> normalized events + schema registry
  -> query index
  -> investigation export
```

Collector 每次运行记录：来源实例、查询起止、调用 principal、API/schema 版本、cursor/page、返回数量、速率限制、重试、首末 event ID/time、原始响应摘要、退出状态和下一 checkpoint。

### “HTTP 200 + 空数组”不是完整性证明

空结果可能是真的没有事件，也可能是权限变小、时间窗口错误、筛选器漂移、分页 token 失效或 API 返回截断。采集器要有来源心跳和预期基线，例如持续活跃平台突然整小时零事件，必须进入 inconclusive 告警。

分页采集先持久化当前页原始字节，再推进 durable cursor。若先写 cursor 后写数据，进程崩溃会永久跳过一页；若先写数据后 cursor，重试可能重复，因此规范化层必须按 provider event ID/来源复合键幂等去重，同时保留原始重复记录。

序列不连续不一定代表丢失：有些 sequence 是全租户共享、某些事件当前身份不可见。必须按厂商语义解释。来源承诺连续序列时，缺口就是 fail；语义未知时是 inconclusive，不能自行补造事件。

### Schema 漂移应失败显式

字段改名、枚举新增、时间格式变化、嵌套对象迁移和 null 语义改变都可能让 parser 静默丢字段。原始层先保存字节，规范化器对未知 schema/version 隔离并告警；不要把无法解析行丢弃后继续报告“采集成功”。

Schema registry 保存字段定义、版本、解析器、上线/退役时间和兼容测试。对调查包，附带实际 schema 与解析器版本，避免半年后用新含义解释旧字段。

## 原始、规范化和脱敏数据是三种资产

- **原始事件**：来源返回的字节或流记录，附来源、采集时间、响应元数据和摘要；用于重放与争议核对；
- **规范化事件**：映射到组织事件模型，便于跨平台查询；必须能回链原始 partition/record；
- **脱敏派生物**：移除 token、IP、邮箱、路径或业务内容后供更广团队分析；记录转换规则和新摘要。

规范化不能覆盖原始数据。时区换算、actor 映射和 action 分类都可能出错；有原始字节才能用新 parser 重放。脱敏副本也不能冒充原件，尤其当被移除字段正是调查关联所需信息时。

原始响应可能含秘密、个人数据、内部地址、提交说明和文件路径。落盘前先确定加密、最小访问、区域、备份与销毁策略；不要为了“以后可能有用”无限复制到普通数据湖。

## 摘要、签名和不可变存储各自证明什么

对完成写入的分区计算摘要，可以检测之后字节变化；对 manifest 使用组织信任根签名，可以证明某个签名主体认可该摘要；对象锁/WORM 可以限制存储期内覆盖或删除。它们都不能证明：

- 来源没有漏事件；
- Collector 的查询 scope、权限和时钟正确；
- 原始事件本身真实而非来源被攻陷；
- 签名前数据没有被删减；
- 所有副本都遵守同一保留与删除策略。

完整性需要多层证据：来源 sequence/cursor、数量/时间基线、采集状态、raw partition digest、manifest chain、独立存储审计和行为探针。不要用“存到不可变桶”一句话替代采集完整性设计。

Manifest 至少列出相对路径、字节数、摘要算法与 digest、生成时间、工具版本和上一个 manifest ID。链式 manifest 能发现受控链中的替换/缺页，却仍依赖链起点与签名/存储控制。

摘要算法、签名 key 和证书也有生命周期。迁移算法时保留旧摘要和交叉签名，不要重算后删除原证据；key 撤销后历史验证需要可信时间、当时的授权和撤销状态。

## 访问控制要保护日志，也要允许受控调查

审计日志经常比源码更敏感：它汇总用户、IP、仓库名、失败操作、规则例外、token ID、调查查询和数据下载。平台管理员不应自动拥有所有日志内容，日志管理员也不应能修改被审计平台而不留独立记录。

最小控制包括：

- 采集身份只有读取所需事件、写入指定 raw 分区和 checkpoint 的权限；
- 查询者按事件域、时间、资产与案件授权，默认不能导出全组织；
- 导出需要 case ID、理由、审批、范围、到期和水印/摘要；
- 高敏字段按需解密或 reveal，每次访问单独审计；
- 原件、规范化索引和脱敏副本使用不同角色；
- Break-glass 查询取用即告警，结束后撤销并复盘；
- 审计管理员的策略和删除操作写入独立故障域或外部审计源。

调查人员需要足够信息关联事件，但不代表可以把完整日志贴进普通工单或聊天。对外分享生成最小脱敏派生物，原件保留在受控证据库，二者通过 case manifest 关联。

## 留存策略按证据类别和恢复目标制定

单一“所有日志保留一年”通常既不准确也不经济。至少考虑：

- 数据分类、法律/监管义务与地域限制；
- 检测窗口、事故发现延迟和调查周期；
- Git refs/对象、评审、CI、制品、身份和配置之间的关联窗口；
- 平台源端最长可回溯时间与组织采集频率；
- 热查询、冷归档、恢复时间和成本；
- 员工/外部主体个人数据的最小化与删除要求；
- Legal hold、诉讼/事故冻结与正常销毁的优先级；
- 加密 key、schema、parser 和验证工具的同期保留。

保留期从哪个时间起算要写清：provider event time、采集完成、案件关闭或 legal hold 解除会得到不同结果。跨系统事件不要因为某一层先过期而失去关联，例如 ref 更新保留两年、身份会话只保留七天，会让长期调查无法解释 actor。

Legal hold 是阻止符合范围的数据按常规计划销毁，不是把所有日志无限期复制。Hold 记录授权、范围、起止、通知、存储位置和解除人；解除后重新计算合法处置，不直接立刻删除。

销毁也要有证据：分区/对象范围、政策依据、批准、执行结果、失败/副本、加密 key 处置和 tombstone。摘要清单仍可能泄漏文件名或标识，是否保留也需政策决定。

## 查询必须可复现，失败也要进入结果

调查结论要保存精确查询：时间范围及边界、时区、仓库资产 ID/历史 locator、actor 映射版本、event types、结果过滤、分页/cursor、查询系统和数据 snapshot/partition 列表。

查询页面显示 10,000 条上限、超时、索引延迟或权限过滤时，不能导出可见部分后声称“全部事件”。结果至少有：

- `complete`：查询覆盖的分区、schema 和权限已验证，分页完成；
- `partial`：明确哪些页、来源、时段或字段缺失；
- `inconclusive`：无法确定缺失范围或查询系统不可用；
- `failed`：查询未产生可用结果，但错误和尝试被保留。

零命中同样记录查询和覆盖证明。把 UI 截图当证据会丢失查询、分页、时区和隐藏列；截图可辅助说明，原始导出与 manifest 才能重放。

## 一个可移交的调查包包含什么

调查导出目录建议包含：

```text
case.json / case.txt
scope-and-query.txt
source-inventory.tsv
raw/
normalized/events.tsv
schema/
collector-and-parser-versions.txt
gaps-and-unknowns.tsv
timeline-notes.md
MANIFEST.sha256
manifest-signature-and-trust.txt
chain-of-custody.tsv
```

`timeline-notes` 记录分析者判断与不确定性，不改原始事件。`gaps-and-unknowns` 明确未提供的事件类型、不可见时间窗、解析失败、时钟偏差和待补证来源。一个诚实标注缺口的调查包比“导出成功”但范围未知的压缩包更可靠。

导出前固定数据 snapshot/partition，避免同一查询在持续摄入时每页看到不同集合。导出后计算摘要，从只读原件派生分析副本；转换 CSV、时区或脱敏会生成新 manifest。移交记录接收者、时间、方式、摘要核对和访问到期。

恢复演练还要验证多年后的可读性：能否取得解密 key、schema、parser、信任根和对象关联数据；只证明压缩包可解压不够。

## 审计管道也需要 SLO、备份与灾难恢复

监控至少包括采集延迟、最后成功 cursor、每来源事件率、重复率、解析隔离数、未知 schema、raw/normalized 数量差、manifest 失败、查询延迟、导出失败和即将过期分区。

RPO/RTO 要分层：可以接受平台事件晚采五分钟，不代表可以丢五分钟；查询索引可重建，不代表 raw 分区、checkpoint ledger 和 schema registry 可丢。恢复演练从空环境重建索引，核对事件数、digest、cursor 和代表性查询。

审计系统与被审计平台位于同一管理员、区域和凭据边界时，一次入侵或误删可能同时破坏行为和记录。高风险组织至少把原始审计副本、manifest/签名和删除控制放到独立身份与故障域。

平台迁移时不要只迁源码。旧平台审计在源端保留多久、能否持续查询、principal/repository ID 怎样映射、旧 schema 如何解析、谁支付长期存储，都要进入迁移退出门禁。

## 平台专项验收

对每个平台/实例记录版本、套餐、权限、核对日期和官方来源，并实际验证：

1. 哪些 Git、Web、API、身份、规则、CI、LFS/package 和生命周期事件可得；
2. 成功、拒绝、失败与管理员绕过分别怎样记录；
3. Actor、delegation、request、repository ID、old/new OID 和时间字段语义；
4. API/stream 分页、顺序、去重、限流、延迟和 schema version；
5. 默认/可配置保留、导出上限、legal hold、删除与计费；
6. 哪些角色可查询、导出、修改审计配置或删除数据；
7. 仓库改名、转移、归档和删除后事件怎样检索；
8. 审计读取与导出本身是否留下独立事件；
9. 区域故障、平台停服或许可证变化时如何取得历史；
10. 行为探针能否在审计中找到唯一对应事件且字段正确。

结果进入事实登记后再写产品实例。没有验证过的 UI 标签、默认天数和套餐名称不进入核心论述。

## 常见失败与恢复

| 症状 | 常见原因 | 安全动作 |
| --- | --- | --- |
| 查询显示事故时段零事件 | 时区、权限、事件类型、分页或采集中断 | 标记 inconclusive，保存查询；核对 cursor、raw 分区、身份/边缘日志和行为探针 |
| 同一事件出现多次 | Collector 在持久化数据后、提交 cursor 前重试 | 原始重复保留；规范化按来源事件 ID 幂等，调查重试原因 |
| Event sequence 有缺口 | 漏页、不可见租户事件或来源语义非连续 | 先查厂商 sequence 语义；能证明连续则 fail，否则登记 unknown |
| Actor 只显示机器人 | 委托链、run/request 或 token 签发事件未关联 | 固定机器人事件，再从 CI/身份源补 human/workload 链；不要猜责任人 |
| 时间线出现“先接收后提交” | Committer time 可控、时区或跨服务乱序 | 分离四种时钟，按来源 sequence/request 因果链重建 |
| Manifest 校验通过但事件仍缺 | 摘要只证明已导出字节未变化 | 回查 scope、cursor、数量基线、来源覆盖和缺口清单 |
| 规范化字段为空 | Schema 漂移被 parser 静默吞掉 | 隔离受影响分区，从 raw 用固定/修复 parser 重放，标注历史查询影响 |
| 导出包含 token/IP/个人数据 | 原始响应直接进入广泛共享目录 | 收紧访问，记录暴露；从受控原件生成脱敏派生物并轮换真实 secret |
| Legal hold 解除后数据立即全删 | 未重新计算其他保留、案件或副本义务 | 暂停销毁，重建范围和批准；记录已删/未删与可恢复性 |
| 审计平台与 Git 同时不可用 | 共用区域、管理员或根凭据 | 启用独立原始副本和 manifest；按灾备恢复并登记不可恢复窗口 |

## 合成实验：接收事件、游标缺口与调查包

本书提供 `scripts/verify-audit-evidence-retention.sh`。在仓库根目录执行：

```bash
bash scripts/verify-audit-evidence-retention.sh
```

脚本在 `mktemp` 下创建本地工作仓库、bare 远端、虚构 actor 和合成 `pre-receive`/`post-receive` hooks。事件使用固定 provider/collector 时间和 sequence，不依赖本机账号或当前时钟。

实验验证：

1. 成功 push 由 post-receive 记录 `accepted`，被非快进规则拒绝的 push 记录 `denied`；
2. 两条事件都关联 repository ID、actor、request、ref、old/new OID、对象格式、规则/policy digest 和两类时间；
3. 被拒更新后服务端 main OID 不变，事件内容与实际 Git 状态一致；
4. Committer time 可晚于服务端接收时间，证明对象时间不能排序入站事件；
5. Collector 先保存事件再推进 cursor，第二次采集不重复已持久化 event ID；
6. 连续 sequence 的导出通过，人工制造缺口返回 fail，来源不可用返回 inconclusive；
7. 调查包包含查询、schema、gap register、events 和 SHA-256 manifest；篡改事件后摘要验证失败。

本地 hooks 从环境变量读取虚构 actor、request 和时间，只为构造可核对 fixture。真实服务必须从认证/平台控制面产生这些字段；hook 也不覆盖 clone/fetch、Web/API 管理、评审、CI、LFS、package、审计访问或平台保留。实验摘要不能证明来源完整或时间真实。

## 小结

可用审计证据来自一条完整链：来源覆盖明确，事件能关联稳定主体和资产，old/new OID 与结果可核对，多种时钟不混用，collector 能发现漏页和 schema 漂移，原始字节与规范化索引分离，摘要和保管记录可以验证派生过程，留存/导出又满足访问与销毁边界。

日志存得久、存储不可变或查询有结果，都只是其中一环。真正成熟的系统会明确说出自己看不到什么，并在缺证时返回 partial/inconclusive。下一章将进入仓库健康、容量预算和维护窗口，把对象、refs、LFS、制品和平台增长变成可行动的运维信号。

## 资料

- [git-log](https://git-scm.com/docs/git-log)
- [git-reflog](https://git-scm.com/docs/git-reflog)
- [git-receive-pack](https://git-scm.com/docs/git-receive-pack)
- [githooks](https://git-scm.com/docs/githooks)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-show](https://git-scm.com/docs/git-show)
