# 仓库也有生命周期：创建、归档、转移与删除

仓库常被当成一个随时可以创建的目录：起个名字、选个可见性、推入第一条 commit。几年后，服务下线了，团队重组了，原 owner 离职了，却没人敢删除；机器人仍在跑，依赖仍在拉，备份仍在计费，安全扫描仍在报警。这个问题不是 Git 命令不够熟，而是仓库从未被当成资产管理。

生命周期治理要让每个仓库回答：为什么存在、谁对业务和技术负责、包含什么数据、谁依赖它、允许怎样写入、如何恢复、保留多久，以及何时可以归档或删除。平台上的 “Archive” 或 “Delete” 按钮只是状态变化的一个执行入口，不承担这些决策。

本章以 Git 2.49.0、Bash、本地 bare 仓库和 TSV 治理登记表验证 Git 能证明的部分。托管平台的归档语义、软删除窗口、fork 关系、套餐、审计留存和管理员权限会变化，必须按厂商、产品版本、权限与核对日期登记。本地 receive hook 只模拟拒写门禁，不冒充真实平台规则。

进入本章前，读者应理解 refs、symbolic HEAD、bundle、对象完整性、机器身份、保护规则、迁移 cutover 和灾难恢复。读完后，应能：

- 为仓库定义稳定资产身份、双重所有权与数据分类；
- 设计 proposed、active、archived、pending_delete 等状态及合法转换；
- 在创建时建立默认分支、权限、恢复、依赖和退出契约；
- 把组织转移与简单 remote URL 变化区分开；
- 在归档前固定 refs、生成可验证备份并阻断所有写入入口；
- 在删除前核对法律保留、依赖、外部副本、恢复证据和双人审批；
- 用治理登记门禁发现无主、漂移和证据缺口。

## 仓库资产 ID 不应等同于可变路径

仓库名称、组织路径和托管平台会变化。若所有审计、备份和依赖都只记录 `team-a/payment-api`，转移到 `platform/payment-service` 后就可能被当成两个资产，旧权限和备份也难以关联。

治理登记应使用不可复用的稳定 `repository_id`，另存当前平台 ID、URL 和历史别名：

| 字段 | 作用 |
| --- | --- |
| `repository_id` | 组织内部稳定资产 ID，不随改名/转移复用 |
| 当前 locator | 厂商、实例、namespace、repository 平台 ID、clone URL |
| 历史 locator | 曾用名称、URL、迁移/转移日期和映射 |
| 业务所有者 | 决定业务用途、保留、下线和风险接受 |
| 技术所有者 | 负责代码健康、依赖、权限、CI、恢复和响应 |
| 数据分类 | 公开、内部、机密、受监管等组织定义等级 |
| 生命周期 | proposed、active、archived、pending_delete 等受控状态 |
| 依赖与消费者 | 构建、部署、submodule、package、文档、外部集成 |
| 恢复契约 | RPO/RTO、备份范围、演练记录和恢复负责人 |
| 保留契约 | 源码、评审、审计、LFS、制品和备份的分别期限 |

平台 repository ID 可能比路径稳定，但跨平台迁移时仍会改变；内部资产 ID 负责连接迁移前后的记录。资产 ID 也不能回收给另一个同名项目，否则历史审批和审计会串线。

## 所有权不是一个可能已离职的用户名

至少区分业务所有权和技术所有权：

- 业务所有者决定仓库是否仍有价值、数据要保留多久、谁是合法消费者；
- 技术所有者负责默认分支、依赖、CI、漏洞、容量、备份和事故响应；
- 安全、合规、平台团队提供规则和复核，不自动成为所有业务仓库的 owner。

所有权应指向可持续的团队/岗位 principal，并列出当前 accountable person 与备用联系人。只填一个自然人会把休假、转岗、离职变成控制面单点；只填一个大部门又会让实际响应无人负责。

所有者门禁至少检查：

1. 业务与技术 owner 均存在，不能用相同占位值敷衍两种责任；
2. Owner principal 在身份目录有效，团队至少有组织规定数量的活跃维护者；
3. 最近一次 owner 确认未超过审查周期；
4. On-call、升级路径和替补在仓库不可用时仍可取得；
5. Owner 变化触发权限、机器人、规则例外、数据分类和恢复联系人复核。

CODEOWNERS 一类文件表达路径评审路由，不等于资产所有权。候选分支可以修改 tracked owner 文件，平台规则也可能允许绕过；资产登记必须位于候选仓库不能单方面授权自己的控制面。

## 生命周期是状态机，不是标签列表

一个可用的最小模型：

~~~text
PROPOSED
  -> PROVISIONING
  -> ACTIVE
      -> READ_ONLY_HOLD
      -> ARCHIVED
      -> TRANSFERRING

READ_ONLY_HOLD -> ACTIVE
TRANSFERRING -> ACTIVE_AT_TARGET
ARCHIVED -> ACTIVE（经恢复/重新启用审批）
ARCHIVED -> PENDING_DELETE -> DELETED_TOMBSTONE
~~~

`READ_ONLY_HOLD` 适用于事故、法律保留或临时下线，不应和长期归档混用。`TRANSFERRING` 表示源端冻结、目标未完全接管的窗口。`DELETED_TOMBSTONE` 不是仍可 clone 的仓库，而是一条最小删除记录：资产 ID、原 locator、批准、执行时间、处置范围、保留例外和不可恢复声明。

每条转换定义：

- 谁可以申请、批准和执行；
- 前置证据和自动门禁；
- Git、平台、LFS、CI、制品、身份和审计的状态变化；
- 预期输出、失败/超时判定和通知对象；
- 可逆窗口、恢复来源和不可逆门槛；
- 下一次复核日期。

把状态写进仓库内一个 YAML 文件可以帮助发现和评审，却不能成为唯一权威。仓库管理员可能在删除仓库时连同声明一起删除，也可能改分支绕过；组织登记系统应从平台/身份/备份等源采集事实并保留独立审计。

## 创建仓库前先回答“为什么不能复用已有资产”

仓库泛滥会扩大权限、依赖、扫描、备份和维护面。创建申请至少说明：

- 业务能力和预计寿命，是产品源码、库、基础设施、数据还是临时实验；
- 为什么不适合现有 monorepo、已有服务仓库、package 或制品库；
- 变更原子性、发布边界、权限隔离和数据驻留要求；
- 业务/技术 owner、数据分类、消费者和成本中心；
- 默认分支、合并方式、发布和支持策略；
- 机器身份、外部依赖、LFS/submodule 和 CI/制品需求；
- RPO/RTO、保留期、归档触发器与预计退出方式。

短期实验也需要到期日和 owner。最危险的“临时仓库”往往在无人注意时进入生产依赖，既没有保护规则，也没有恢复计划。

## Provisioning 应建立一个完整基线

创建动作应由受控自动化完成，并产生可审计结果；不要要求每个团队手工点击二十个设置。一个厂商无关的基线包括：

| 控制面 | 创建时必须确定 |
| --- | --- |
| 身份 | 稳定资产 ID、owner/team、管理员和 break-glass 边界 |
| Git | 对象格式、默认分支、允许 refs、tag/force/delete 策略 |
| 评审 | 必需检查、审批、所有权、过期审批和 merge queue 策略 |
| 安全 | 可见性、秘密扫描、依赖更新、签名/来源策略和不受信任执行边界 |
| 自动化 | 机器人/app/OIDC、runner、webhook、环境与最小权限 |
| 数据 | LFS、package、artifact、日志、附件和数据分类 |
| 运维 | 备份、RPO/RTO、容量预算、监控、审计和恢复演练 |
| 生命周期 | 审查周期、归档条件、保留与删除批准路径 |

基线是最低条件，不是所有仓库使用相同 workflow 的理由。开源库、生产基础设施和受监管模型仓库风险不同；例外应明确偏离哪条规则、理由、补偿控制、批准人与到期日，而不是复制一个永不过期的“特殊仓库”模板。

### 验证默认分支和对象基线

对组织控制的 bare 仓库，可在只读审计副本中执行：

~~~bash
git -C "$repo" rev-parse \
  --is-bare-repository --show-object-format --show-ref-format
git -C "$repo" symbolic-ref HEAD
git -C "$repo" show-ref --verify refs/heads/main
git -C "$repo" fsck --full --strict --no-progress
~~~

第一条读取布局与格式；第二条输出默认 symbolic HEAD；第三条要求 main ref 存在；第四条验证当前对象根的连接和格式。它们不连接平台、不修改 refs，但不能证明保护规则、权限、LFS、评审或备份有效。

默认分支名来自治理登记，不一定永远是 `main`。实际 HEAD 与登记不一致时，应先判断合法改名、迁移漂移还是错误配置；不要让审计脚本自动改 HEAD 后掩盖变更来源。

## 定期认证比“创建时合规”更重要

仓库会随组织变化漂移。认证周期按风险分层，至少复核：

- Owner、活跃维护者、最后业务使用和下线计划；
- 可见性、直接成员、团队、外部协作者、管理员和绕过权限；
- 机器人、deploy key、app、OIDC trust、最后使用和撤销入口；
- 默认分支、保护规则、required checks、例外与过期时间；
- 未修复漏洞、秘密告警、第三方 CI 依赖和不受信任执行入口；
- refs/对象/LFS/制品/附件规模、增长率与配额；
- 备份最近成功时间、恢复演练和实际 RPO/RTO；
- 下游消费者、submodule/package/deployment 和外部链接。

“最近 90 天没有 commit”只能作为归档候选信号。稳定库、法规策略和基础镜像可能长时间不变却仍是关键依赖；相反，持续由机器人提交的仓库也可能早已无人负责。使用证据要组合最后人类变更、clone/download、构建/部署、依赖图、告警与 owner 认证。

## 组织转移会改变控制面，即使 OID 不变

仓库在同一平台改 namespace，Git commit OID 通常不变，但可能改变：

- URL、平台 repository ID 或重定向期限；
- 团队/外部协作者权限继承；
- 保护规则、审批、所有权和管理员绕过；
- app 安装、deploy key、webhook、OIDC subject 和 CI secret；
- package/image 名称、environment、pages/wiki/release 和审计归属；
- 相对 submodule URL、文档链接和外部消费者。

因此转移使用上一篇的迁移 cutover 模型：先盘点，保持单一写入端，验证目标，再更新客户端和自动化。不能因为平台提供自动 URL 重定向就省略身份、CI、LFS、制品和审计验收。

若业务 owner 改变但平台位置不变，也应走轻量转移：新 owner 接受责任、旧 owner 权限回收、机器人和例外复核、资产登记与升级路径更新。仅在聊天中宣布“以后归 B 组”无法形成治理证据。

## 归档是可恢复的只读状态

归档前先证明仓库不再承担活动写入：

1. Owner 批准用途终止或进入长期冻结；
2. 枚举源码、package、submodule、部署、文档和外部 API 消费者；
3. 迁移/下线 CI、webhook、机器人、schedule、环境和发布入口；
4. 固定全 refs、默认 HEAD、对象格式、LFS、附件、制品和平台导出；
5. 生成不可变恢复点、摘要和恢复演练证据；
6. 禁止 push、merge、tag、release、issue/comment 和自动写入；
7. 更新 catalog、README/banner、搜索和支持入口；
8. 设置保留、复核与候选删除日期。

### 创建 Git 逻辑归档

在受控、自包含且已冻结的备份仓库中：

~~~bash
archive_dir=/srv/archive/repositories/asset-123/2026-08-21T020000Z
install -d -m 0700 "$archive_dir"

git -C "$repo" for-each-ref \
  --format='%(refname)%00%(objecttype)%00%(objectname)%00%(*objectname)%00' \
  > "$archive_dir/refs.nul"
git -C "$repo" symbolic-ref -q HEAD > "$archive_dir/head.symref"
git -C "$repo" bundle create "$archive_dir/repository.bundle" --all
git -C "$repo" bundle verify "$archive_dir/repository.bundle" \
  > "$archive_dir/bundle.verify.txt"
~~~

命令读取源 refs 并写归档目录，不移动源引用。`bundle create` 失败可能是 refs 为空、对象缺失、权限/空间不足或路径已存在；保留旧恢复点，修复源/目标后生成新目录，不覆盖已验证文件。Bundle 不包含 LFS payload、平台元数据、hook、权限或不可达对象，这些资产分别归档。

平台的 archive 功能是否拒绝 issue、actions、packages 或 release 写入是易变事实。归档后必须用普通成员、机器人和管理员旁路做反向测试；“页面显示 Archived”不是写入围栏证据。

## 删除前先进入可观察的 pending_delete

删除的风险来自分布式副本和跨系统关系。平台仓库删除后，以下内容可能仍存在：

- 开发者 clone、fork、mirror、bundle 和对象存储备份；
- LFS payload、package、container image、release artifact；
- CI log/cache/artifact、部署环境和运行实例；
- issue/评审导出、审计、法务保留和事故证据；
- 搜索索引、归档站、依赖代理和第三方服务。

因此“彻底删除”必须定义系统范围和合理保证，不能承诺 Git 无法证明的全世界删除。

`pending_delete` 提供一段观察窗口：仓库保持只读，消费者和告警有时间暴露遗漏；删除单包含资产 ID、理由、owner 双重确认、安全/法务复核（按分类）、最后恢复点、恢复演练、依赖清零证据、处置范围、执行人和不可逆时间。

任何新读取/构建/部署、法律保留、未解决事故、唯一依赖对象或备份验证失败都应取消/延期删除。不要让“已过日期”自动压过新的证据。

### 删除动作与 tombstone

正式删除由平台支持的 API/UI 或基础设施流程执行，不在通用脚本中直接递归删除目录。执行后：

- 验证生产 URL、API、Git/LFS/package 入口不可用；
- 按批准范围处理 fork、镜像、备份和制品；
- 撤销机器人、key、token、webhook、runner 和云角色；
- 保留最小 tombstone 和删除审计，但不保留不应继续存在的源码副本；
- 明确软删除/可恢复窗口、最终清除时间和负责方；
- 监控名称被重用、旧凭据写入、依赖拉取和重新创建。

名称重用会让旧 URL、package、OIDC subject 或依赖声明指向新资产。组织应限制被删除 repository/namespace 的复用，或把稳定 platform ID/资产 ID 纳入信任策略。

## 恢复归档仓库是新一次风险评估

恢复不应简单关闭 archived 标记。先从空环境恢复 Git/LFS/平台导出，验证 refs、对象、依赖和权限，再决定：

- 原用途是否仍合法，数据分类和 owner 是否变化；
- 历史依赖、CI action、基础镜像和 secret 是否已过期/失陷；
- 保护规则、身份、签名和扫描是否达到当前基线；
- 是恢复原资产、迁移到新仓库，还是只提供只读证据访问。

恢复后重新开放写入属于 `ARCHIVED -> ACTIVE` 的审批转换，应有新的基线报告和复核日期。旧机器人 token、deploy key 和 webhook 不应因“省事”自动复活。

## 治理登记表应把事实与声明分开

下面是一份最小结构，实际系统可使用数据库或策略引擎：

~~~text
repository_id
repository_locator
lifecycle_declared
business_owner
technical_owner
data_class
default_branch_declared
backup_object
backup_digest
deletion_case
last_certified_at
~~~

其中 owner、分类和生命周期是治理声明；平台实际可见性、symbolic HEAD、refs、成员、hook/规则和备份摘要是观测事实。门禁比较两者：一致才通过，漂移必须产生工单/例外，不能让采集器静默覆盖声明。

策略结果至少有 `pass`、`fail`、`inconclusive`。API 无权限、分页中断、平台超时或摘要工具缺失属于 inconclusive，不得当成没有违规。

## 常见失败与恢复

| 症状 | 原因 | 安全动作 |
| --- | --- | --- |
| 登记有 owner，但无人响应 | 填的是离职用户、空团队或大部门 | 冻结高风险变更，指定临时 accountable owner 并修复身份目录 |
| 默认分支登记为 main，实际 HEAD 指向旧分支 | 改名/迁移未更新或目标初始化错误 | 对照变更记录决定修正声明还是控制面；用普通 clone 验证 |
| 归档后仍有机器人提交 | 只改 UI 状态，未围栏 token/webhook/schedule | 撤销写身份，盘点归档后 refs 和平台事件，重新生成恢复点 |
| Bundle verify 通过但恢复缺大文件 | 只保存 Git pointer，没有 LFS payload | 保持 archived，补齐 LFS/制品并从空缓存恢复 |
| Pending-delete 出现新消费者 | 依赖图/使用监控不完整 | 取消删除，登记消费者和退出计划，重新开始观察窗口 |
| 删除后旧 URL 被新仓库复用 | 名称复用且消费者未固定资产身份 | 隔离新资产，修复依赖和身份信任策略，保留事故审计 |
| 转移后权限比原来更宽 | 目标组织继承、app/团队映射或例外漂移 | 保持源拒写/目标受限，按 principal/action 差异修复再开放 |
| 审计采集失败却显示合规 | 工具把空输出当零结果 | 状态改为 inconclusive，阻断高风险转换并修复采集权限 |

## 合成实验：登记、归档围栏与删除门禁

本书提供 `scripts/verify-repository-lifecycle-governance.sh`。实验在 `mktemp` 下使用本地 bare 仓库、虚构团队和 TSV 登记，不连接身份目录或托管平台，也不实际删除仓库。

在仓库根目录执行：

~~~bash
bash scripts/verify-repository-lifecycle-governance.sh
~~~

脚本验证：

1. Active 仓库必须有不同的业务/技术 owner、数据分类、真实 bare 仓库和匹配 symbolic HEAD；
2. 缺技术 owner 或登记默认分支与实际 HEAD 不一致时门禁失败；
3. 归档前固定 refs、HEAD、完整 bundle 和 SHA-256 摘要；
4. Archived 状态必须同时具备可验证 bundle、正确摘要和可执行拒写 hook；
5. 归档后客户端 push 被拒绝，服务端 main 不移动；
6. 伪造备份摘要不能通过，pending_delete 缺审批单也不能通过；
7. 归档 bundle 在空 bare 仓库恢复后 refs 和 `fsck` 一致。

本地 receive hook 只是合成门禁，不能证明 GitHub/GitLab 等托管平台的 archived 状态、管理员绕过、API 写入、LFS/package/issue/CI 行为。实验也不验证身份目录、法务保留、软删除、备份加密或真实删除；这些必须在组织专用环境按平台版本验收。

## 小结

仓库治理的起点不是更多规则，而是稳定资产身份、持续所有权和有证据的状态转换。创建时就定义恢复与退出，Active 期间定期认证，转移时保持单一写入权威，归档时冻结并证明可恢复，删除前给依赖和保留要求充分的观察窗口。

Git 能证明 refs、对象、HEAD、bundle 和拒写结果；它不能证明平台权限、法律保留、外部副本或全局删除。组织治理必须把声明与多个系统的观测事实连接起来。下一章将深入权限生命周期，处理入职、转岗、离职、机器人回收和 break-glass 审计。

## 资料

- [gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)
- [git-symbolic-ref](https://git-scm.com/docs/git-symbolic-ref)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-show-ref](https://git-scm.com/docs/git-show-ref)
- [git-fsck](https://git-scm.com/docs/git-fsck)
- [git-bundle](https://git-scm.com/docs/git-bundle)
- [githooks](https://git-scm.com/docs/githooks)
