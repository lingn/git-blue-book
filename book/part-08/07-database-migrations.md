# 数据库迁移：把 schema 状态纳入发布和回退决策

Git 提交可以固定迁移脚本和应用代码，却不能说明目标数据库已经执行了哪一步。一次发布可能同时改变二进制、配置、表结构、数据语义、消息格式和外部副作用。只把迁移脚本放进仓库，再用“回退到上一个 commit”代替数据库计划，通常会把运行事故扩大成数据事故。

本章承接[部署与回退](06-deploy-and-rollback.md)。第六章负责 rollout、实例和流量状态，本章负责数据库 schema、数据内容和迁移执行状态。两章共同使用同一条发布记录：制品 digest、配置版本、数据库兼容窗口和迁移批次必须能够相互核对。

本章以 Git 2.49.0、Bash 和本地文本 fixture 为实验基线，核对日期为 2026-08-23。实验不连接数据库，也不伪造事务、锁、复制、在线 DDL、权限或云数据库输出。真实迁移必须在目标数据库引擎、版本、拓扑、数据规模和备份策略下单独演练。

## 进入条件和退出能力

进入本章前，读者应理解部署请求、rollout 状态、制品 digest、配置版本和长任务边界。读完后，应能：

- 区分迁移代码、已应用迁移、实际 schema、数据回填进度和应用兼容范围；
- 用兼容矩阵判断旧应用、新应用、旧 schema 和新 schema 的组合是否允许同时运行；
- 设计 expand、回填、切换和 contract 阶段，写出每阶段的停止条件与回退动作；
- 处理幂等、断点续跑、锁等待、事务边界、长任务和消息重试；
- 识别不可逆 schema/data 变化，选择向前修复、制品回退或数据恢复，而不是盲目降级；
- 说明本地 fixture 能证明哪些状态机不变量，哪些必须由真实数据库和运行平台补证。

## Git 保存的是意图，数据库保存的是事实

迁移相关的身份至少有五种：

| 身份 | 说明 | 主要证据 |
| --- | --- | --- |
| 迁移代码身份 | 仓库中定义步骤、校验和回退说明的对象 | migration commit/tree、文件摘要、评审记录 |
| 迁移批次身份 | 某次执行尝试和执行主体 | batch ID、runner、开始结束时间、退出原因 |
| 已应用迁移 | 数据库登记已经成功完成的版本或步骤 | 数据库 migration table、执行日志、校验查询 |
| 实际 schema | 当前数据库能接受哪些列、索引、约束和类型 | 受信任 schema introspection、DDL 审计 |
| 数据语义状态 | 数据是否完成回填、校验和切换 | 行数、抽样、约束、校验和、业务指标 |

同一个 Git commit 可以被执行多次，也可能只执行一半；migration table 有记录也不代表数据回填和业务切换完成。发布系统应把 `migration_batch_id`、目标 schema 版本、回填 checkpoint 和验证结果追加到部署记录，不能从分支名或迁移文件名推断数据库事实。

## 先写兼容矩阵，再决定顺序

滚动和金丝雀部署会让旧应用与新应用同时存在。至少要检查四种组合：

| 应用 | 旧 schema | 新 schema | 默认结论 |
| --- | --- | --- | --- |
| 旧应用 | 已验证 | 需要验证 | 只有 expand 后仍保留旧字段、约束和语义时才允许 |
| 新应用 | 需要验证 | 已验证 | 新应用应先兼容旧 schema，再使用新字段 |
| 混合版本 | 需要验证 | 需要验证 | 读写协议、消息和事务必须覆盖整个窗口 |
| 迁移任务 | 需要验证 | 需要验证 | 任务本身不能破坏仍在运行的应用 |

矩阵中的“需要验证”不是默认通过。验证应包括读路径、写路径、索引/约束、事务隔离、消息序列化、重试和权限。若某个组合不能工作，就必须改变 rollout 顺序、延长兼容窗口或先做独立的 expand 步骤。

## Expand/contract 是一组状态，不是一条 SQL

推荐把结构和数据变化拆成可观察的阶段：

```text
design and compatibility review
  -> expand: add nullable/new structure
  -> deploy code that can read old and new
  -> dual-write or derive new value
  -> resumable backfill with checkpoints
  -> verify counts, constraints and business invariants
  -> switch reads/writes behind an audited control
  -> fence old applications and consumers
  -> contract: remove old structure only after the window
```

每个箭头都需要执行前检查、执行中指标、失败停止条件和恢复动作。`contract` 不是 `revert` 的同义词，一旦删除列、压缩数据、改变枚举含义或发送不可逆外部副作用，旧制品和旧脚本可能已经无法恢复。

### Expand：先增加，不要先删除

Expand 阶段新增结构通常应保持旧应用可用，例如增加可空列、兼容索引或新表。新增约束要考虑旧数据是否已经满足，默认值是否会触发表重写，DDL 是否会长时间持锁。迁移前要记录预计锁范围、超时、取消方式和对线上流量的影响。

Expand 成功后，不能只看 migration table。应通过 schema introspection 和小范围读写确认结构真的存在、权限正确、复制链路可见，并把实际 schema 摘要写入批次记录。

### 双写和回填：把不一致当成显式状态

新字段需要从旧字段推导时，可以采用双写、异步回填或重建新表。双写期间必须定义失败策略：旧写成功而新写失败时，是拒绝整次事务、进入补偿队列，还是标记待修复。静默吞掉失败会让回填完成后仍有不可见缺口。

回填要可分批、可重试、可暂停，并保存稳定 checkpoint。checkpoint 不是简单的最后一个自增 ID，分片、删除、更新和排序规则可能让它跳过行；需要使用可重放的范围、版本或业务键，并记录每批输入和结果。回填过程中要持续观察锁等待、复制延迟、错误率、行数和业务指标。

### 切换：先验证，再改变读路径

切换读写路径应是一个有审计的控制面动作。切换前至少核对：新字段覆盖率、旧新值差异、空值和异常值、索引命中、旧消费者兼容和回退目标。切换后保留对照查询或抽样校验，在观察窗口内不要删除旧字段。

特性开关可以控制切换，但开关本身也属于配置版本和权限边界。不能因为开关可瞬时关闭，就跳过数据校验；新代码可能已经写入旧代码无法理解的值。

### Contract：最后清理，并承认不可逆

Contract 阶段删除旧列、旧索引、旧表或兼容分支。开始前要确认：旧应用、旧任务、旧消费者和旧报表均已围栏；备份和恢复演练覆盖新 schema；依赖搜索没有遗漏动态 SQL、ETL 或外部客户端；观察窗口已经结束。执行后要重新采集 schema 和关键数据不变量。

如果 contract 失败，通常可以修复迁移本身并重试；如果 contract 已成功而旧应用随后启动失败，优先恢复兼容配置或执行向前修复，不能假定切回旧制品就会恢复被删除的结构。

## 迁移契约至少包含这些字段

迁移文件旁边应有机器可读或等价受保护的契约，字段语义要比一个版本号更完整：

```text
migration_id / migration_code_digest
repository / source_commit / artifact_digest
database_identity / environment / region
precondition_schema / target_schema
compatibility_matrix / rollout_window
transaction_scope / lock_budget / timeout
batch_size / checkpoint_format / retry_policy
validation_queries / business_invariants
irreversible_steps / rollback_class
requested_by / approved_by / executed_by
started_at / finished_at / status / failure_reason
```

`rollback_class` 可以取 `reversible`、`forward-fix`、`data-restore` 或 `unknown`。未知不应自动放行。契约中的查询、脚本和参数不能包含秘密；执行器必须使用最小数据库权限，迁移主体与应用读写主体分离，并把实际授权和审计事件关联到批次。

## 幂等、事务和长时间操作

幂等不等于“重复执行不会报错”。安全的重复执行应能识别已经完成的结构和批次，验证数据不变量后继续，而不是跳过失败步骤。对不可重试的外部副作用，要把副作用 ID 写入可查询记录，避免网络重试造成重复操作。

事务边界要按数据库引擎和操作规模设计。一个大事务可能阻塞在线请求、耗尽日志或触发复制延迟；拆成小批次又会暴露中间状态。迁移契约必须说明每批提交、失败重试、读写隔离和部分成功时的恢复动作，不能只写“事务安全”。

长时间 DDL、索引构建和回填应有锁等待上限、取消信号和降速策略。取消后要检查数据库实际状态，不能从客户端退出码推断没有改变。若平台提供在线 DDL、低优先级或影子表机制，也要记录产品和版本，不能把某个引擎的选项写成通用 SQL 事实。

## 发布、回退和向前修复的决策矩阵

| 观察到的状态 | 首选动作 | 仍需核对 | 不要做的事 |
| --- | --- | --- | --- |
| Expand 尚未开始 | 停止 rollout，修正契约 | 兼容矩阵、锁预算、备份 | 直接执行 contract |
| Expand 成功，应用尚未切换 | 可以回退制品或配置 | 新结构是否影响旧应用、schema 摘要 | 删除新结构制造“干净”状态 |
| 回填部分完成 | 暂停并保存 checkpoint | 覆盖率、失败行、双写差异 | 从头覆盖或删除半成品数据 |
| 读路径已切换，旧结构仍在 | 可回退配置或制品，视兼容矩阵决定 | 新值是否被旧应用理解 | 立刻 contract |
| Contract 已完成 | 通常向前修复或数据恢复 | 备份点、迁移日志、业务不变量 | 只 `git revert` 再部署旧制品 |
| 数据已被错误重写或删除 | 冻结写入，按恢复点恢复或补偿 | RPO/RTO、跨服务副作用、重放 | 用旧 schema 覆盖当前数据 |

制品回退解决代码和二进制问题，配置回退解决开关和连接问题，源码 `revert` 解决共享历史，向前修复解决当前 schema/data 的可运行性，数据恢复解决丢失或损坏的数据。它们可能需要组合，但每个动作都要有独立审批、验证和停止条件。

## 异步消息和跨服务迁移

数据库兼容不能脱离消息和其他服务。新生产者可能发送旧消费者无法解析的字段，新消费者可能依赖尚未回填的数据。协议演进要遵守可接受的读取窗口，消息应带 schema/protocol 版本和幂等键，失败消息进入可审计的重试或隔离流程。

跨服务迁移要明确顺序和所有权：谁先增加字段，谁负责回填，谁切换读取，谁围栏旧消费者，谁确认积压清零。Git 中的多个仓库 commit 只能作为候选证据，不能替代服务端实际版本和消息观测。

## 迁移故障分流

| 症状 | 先固定 | 安全动作 | 停止条件 |
| --- | --- | --- | --- |
| migration table 显示完成，但字段不存在 | 批次日志、schema introspection、数据库节点 | 标记 `inconclusive`，停止应用切换 | 只相信客户端退出码 |
| 迁移等待锁超时 | 持锁会话、等待时间、流量和复制延迟 | 取消或降速，重新安排窗口 | 盲目提高超时继续占锁 |
| 回填失败行不断增加 | checkpoint、失败原因、双写差异 | 暂停新写入或进入补偿，修复后续跑 | 删除失败记录 |
| 新应用能读，新旧值不一致 | 抽样、覆盖率、业务校验和消息 | 保留旧结构，回退读取开关或向前修复 | 直接 contract |
| 旧应用无法启动 | 当前 schema、启动日志、配置和依赖 | 恢复兼容配置或执行已演练向前修复 | 强行降级二进制 |
| Contract 后发现遗漏消费者 | 依赖清单、访问日志、报表和任务 | 围栏受影响入口，恢复或补偿数据 | 认为删除列等于删除依赖 |
| 数据已跨服务传播 | 写入时间线、消息 ID、外部副作用 | 冻结、去重、补偿或按恢复点重放 | 只恢复单个数据库 |

失败重试要生成新的 batch attempt，保留原始迁移日志、schema 摘要、checkpoint 和审批。没有足够证据判断实际状态时，状态为 `inconclusive`，不能改成 `success` 让部署器继续。

## 隔离实验与真实边界

在仓库根目录运行：

```bash
bash scripts/verify-database-migrations.sh
```

前置条件是 Bash、Git 2.28 或更高版本，以及 `awk`、`grep` 和 `sha256sum` 或 `shasum`。实验用文本文件模拟 schema、行数据、迁移批次和应用围栏，使用 `mktemp` 隔离目录，不连接任何数据库，不修改本书仓库。

实验验证：

1. 把迁移脚本和应用版本提交到 Git，并保存 source commit 与代码摘要；
2. 执行可重复的 expand，验证旧应用仍能读取旧字段，新字段可以为空；
3. 中断一次回填，再用 checkpoint 续跑，确认重复执行不会丢失已处理行；
4. 在旧应用围栏前拒绝 contract，围栏后完成切换并核对 schema 与数据摘要；
5. 回到旧 Git commit 不会恢复已改变的外部 schema，实验把状态标为 `forward-fix-required`；
6. 主线继续前进不改变已记录的迁移批次和数据库状态。

成功输出为：

```text
Expand/contract fixture, resumable backfill, compatibility gate, and forward-fix boundary passed.
```

实验只证明文本 fixture 中的状态机、幂等和 Git 证据边界。它不证明真实数据库的事务、锁、DDL、复制、备份、权限、在线变更、性能、数据类型、触发器、消息队列或跨服务一致性；出版前必须在目标引擎和代表性数据规模下重新验证。

## 综合练习：一次不可逆迁移后的事故

某团队完成了 expand 和部分回填，随后切换了新应用的读取开关。旧实例仍在处理长任务，消息中出现了新字段，数据库 contract 因锁等待被取消，但监控只显示应用进程健康。请写出处理方案，至少回答：

1. 如何固定 migration batch、schema、回填 checkpoint、实例 digest、消息和锁证据；
2. 哪些状态应暂停，旧实例和长任务如何围栏；
3. 是否能直接回退制品，还是应先回退读取配置或执行向前修复；
4. 如何验证新旧值、消息重试和外部副作用没有继续扩大；
5. 哪些结论必须来自真实数据库和平台，而不是 Git 日志。

合理方案会先停止 contract 和流量扩大，保留旧结构与回填 checkpoint，确认新字段对旧实例和消费者的兼容性，再决定回退配置、制品或执行向前修复。它不会把取消客户端进程当作迁移没有改变，也不会用 `git revert` 假装数据库已经恢复。

## 小结

迁移脚本是意图，已应用迁移、实际 schema、回填进度和数据语义才是运行事实。expand/contract 把不可逆变化拆成可观察阶段，兼容矩阵决定部署顺序，checkpoint、幂等、锁预算和业务校验决定能否安全续跑。

数据库事故中，制品回退、配置回退、源码 `revert`、向前修复和数据恢复各自作用在不同状态。先停止影响并固定证据，再选择已经演练的最小动作，最后从真实 schema、数据不变量、实例 digest、消息和业务指标验证恢复。下一章将把这些迁移状态接入从事故到修复、发布和复盘的综合证据链。

## 资料

- [git-archive](https://git-scm.com/docs/git-archive)
- [git-cat-file](https://git-scm.com/docs/git-cat-file)
- [git-rev-parse](https://git-scm.com/docs/git-rev-parse)
- [git-update-ref](https://git-scm.com/docs/git-update-ref)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
