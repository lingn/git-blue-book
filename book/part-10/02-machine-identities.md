# 自动化不应借用员工身份：最小权限机器身份

一条流水线只需要读取源码，却拿着某位管理员的个人令牌；一个发布机器人既能创建 tag，又能修改分支保护和仓库 secrets；十几个 runner 共用一枚长期 SSH 私钥。它们平时都能工作，直到员工离职、令牌泄漏或某个不受信任构建步骤读取环境变量，团队才发现自己无法回答三个基本问题：究竟是哪个工作负载执行了动作，这枚凭据还能访问什么，以及怎样只停掉受影响的自动化。

机器身份治理的目标不是“让 CI 登录成功”，而是把一次自动化访问约束为可解释的授权链：哪个工作负载在什么上下文中，由谁签发了什么短期能力，对哪些资源执行哪些动作，到何时失效，在哪里留下审计事件。个人令牌、部署 key、机器人账号、应用安装令牌和工作负载身份只是实现选择；若没有资源、动作、时间和上下文约束，它们都可能成为长期万能密码。

进入本章前，读者应理解远程传输与认证、受保护引用、CI 候选提交、签名边界和凭据泄漏处置。读完后，应能为 clone、状态回报、发布和部署拆分机器身份；判断个人令牌、部署 key、机器人账号与联合身份的适用边界；设计短期凭据的签发、续期、撤销和审计；并为 break-glass 身份建立独立且可演练的应急流程。

本章的 Git 行为在 Git 2.49.0 和 macOS 上验证。工作负载身份与平台令牌是易变控制面事实：GitHub.com 的 deploy key、GitHub App installation token 和 Actions OIDC，以及 GitLab CI/CD ID token 的官方资料均核对于 2026-08-20，详细条件登记在 `docs/FACT-REGISTER.md`。自托管版本、套餐、权限名和默认值可能不同，实施时必须复核当前服务文档。随章实验不访问网络，也不验证真实 SSH、OIDC、托管平台授权或秘密存储。

## 先把主体、凭据与权限拆开

“CI 账号”经常把六个不同状态混为一个名字：

| 层 | 要回答的问题 | 典型证据 |
| --- | --- | --- |
| 人或机器主体 | 谁对这次动作负责 | 不可复用的 principal/workload ID、所有者、用途登记 |
| 工作负载上下文 | 哪个仓库、workflow、commit、ref、环境和 runner 在运行 | 签发声明、CI job/run ID、候选 OID |
| 认证凭据 | 请求者用什么证明自己 | SSH 私钥、访问令牌、客户端证书、OIDC subject token |
| 授权 | 主体可以对哪些资源做哪些动作 | 仓库/namespace、scope、角色、受保护引用与环境策略 |
| 会话 | 这份能力从何时到何时有效 | issued-at、not-before、expiry、token/session ID |
| 审计事件 | 实际做了什么，服务端接受了什么 | actor、来源、旧/新 ref OID、API、结果和关联 run ID |

主体可以长期存在，凭据不应因此长期有效。一个发布机器人可以是稳定 principal，但每次作业只取得十分钟有效、仅能向候选仓库创建 release 的 token。反过来，把一枚每小时轮换的 token 发给所有 runner，虽然“短期”，主体仍不可区分，权限和爆炸半径也没有真正缩小。

Git commit 中的 author、committer 与签名者也不等于远程认证主体。自动化可以推送由人编写的 commit，人也可以推送由机器人生成的 commit。审计链必须同时保存服务端 actor 和对象 OID，不能用 `user.name=release-bot` 代替机器身份。

## 最小权限是五个维度的交集

只缩小 token 的 scope 不够。一次机器授权至少要同时收窄：

```text
有效能力 = 主体 × 资源 × 动作 × 上下文 × 时间
```

- **主体**：每类工作负载使用独立、可归属的身份，不让所有自动化冒充同一员工或共享机器人；
- **资源**：限定组织、项目、仓库、包、环境和云账户，不因“以后可能用到”授权全部仓库；
- **动作**：区分读源码、写功能 ref、回报检查、创建 release、发布包、部署和管理策略；
- **上下文**：约束到受信任 workflow、候选 commit、受保护 ref、环境、事件类型和 runner 边界；
- **时间**：按单次 job 或最短可运行窗口签发，到期自动失败，续期重新评估上下文。

因此，“read/write”通常仍太粗。写 commit status 不应顺带获得修改源码的能力；创建发布记录不应顺带获得修改 CI 定义的能力；部署生产不应顺带获得仓库管理员权限。平台若只能提供粗粒度角色，就应拆分仓库、入口或服务端代理，而不是把产品限制误称为最小权限。

### 先按动作拆身份

典型流水线至少包含下列信任级别：

| 工作负载 | 通常需要 | 通常不应拥有 |
| --- | --- | --- |
| 候选检查 | 读取候选源码和明确依赖；写自身检查结果 | 写主线、读取生产 secrets、部署、修改 workflow |
| 依赖更新机器人 | 读取目标仓库；创建专用分支或评审请求 | 绕过审批、写生产环境、修改保护策略 |
| 合并协调器 | 读取评审与检查；对目标 ref 做条件更新 | 任意 force push、仓库管理、云生产权限 |
| 发布器 | 读取已批准候选；创建批准范围内的 tag/release/package | 修改候选源码、替换已有不可变制品、管理成员 |
| 部署器 | 读取制品摘要与发布授权；操作一个环境 | 修改 Git 历史、访问其他环境、重建制品 |
| 只读镜像/备份 | 读取约定 refs 与对象 | push、评审、执行部署或管理策略 |

同一 pipeline 文件描述这些 job，不代表它们应共享一个 token。把高权限凭据只注入发布或部署 job，并让这些 job 依赖受保护环境、人工批准和已验证候选，才能让前序不受信任代码无法直接读取能力。

## 六类常见身份不是同一等级的替代品

### 个人访问令牌：适合人的会话，不是默认机器人身份

个人令牌继承人的生命周期和组织关系。它在一次受控迁移或人工维护中可能合理，但长期自动化会产生结构性问题：

- 员工离职、休假、账号冻结、SSO/MFA 策略变化会意外中断服务；
- 人的权限扩大后，自动化可能在没有评审的情况下同步变强；
- 审计记录只能看到员工主体，无法区分哪个 runner 或 workflow 使用了令牌；
- 为避免中断，团队容易给令牌更长有效期、更广 scope，并复制到更多 secret store；
- 安全事件中撤销员工所有会话与只停一个机器人无法独立进行。

若平台暂时没有机器主体，个人令牌只能作为有退出日期的过渡方案：选择专用低权限维护者、固定仓库和动作、设置最短到期时间，登记运行位置与撤销人，并创建迁移任务。不要用离职员工账号“永久托管”生产自动化，也不要通过关闭身份治理避免过期。

### 部署 key：仓库级 SSH 能力，简单但常为长期秘密

Deploy key 通常把一枚 SSH 公钥直接关联到仓库，而非某个员工。它适合单机只读拉取单仓库，尤其是服务端只提供 SSH、没有联合身份时。风险在于私钥常驻服务器、缺少自然到期，并且写权限可能远大于“部署”这个名字暗示的范围。

截至 2026-08-20，GitHub.com 官方文档把 deploy key 定义为单仓库 SSH key，默认只读、可显式开启写入且没有到期日，并推荐在需要更细权限时使用 GitHub App。这是 GitHub 当前实现，不是 Git 协议保证；其他平台可能允许不同范围、复用或生命周期。

部署 key 的安全基线是：每个仓库/用途独立 key；默认只读；私钥只在需要它的运行身份可读；禁止复制到基础镜像、共享 runner 或多环境；登记 fingerprint、服务器、仓库、所有者与轮换日期；删除工作负载时同步移除公钥。需要写入时，先确认服务端能否把 key 限定到专用 ref 或命令；“只有一个仓库”不等于“只能做一个动作”。

### 机器人或服务账号：解决归属，不自动解决凭据

非人账号能提供稳定名称、独立离职流程和清晰审计主体，适合平台没有应用身份而又需要跨仓库操作的场景。但它仍可能持有个人式长期令牌、被加入高权限团队，甚至由多人共享登录。

一个合格的机器人账号需要：禁止日常交互登录或明确例外；独立所有者和备用所有者；不使用个人邮箱/恢复渠道；权限通过专用组授予；凭据由 secret manager 或 broker 管理；API 与 Git 操作可分别授权；定期审查最后使用时间和仓库集合。平台把机器人计入席位、如何强制 MFA、能否禁止 Web 登录均属于易变产品事实，必须单独登记，不能从“账号名叫 bot”推断。

### 应用安装身份：把应用权限、安装范围和运行令牌分层

一些托管平台提供一等应用主体。管理员先批准应用可申请的权限，再把应用安装到特定组织/仓库；运行时由应用取得短期 installation token，还可以进一步缩小到部分仓库和权限。这比“创建一个假员工”更适合跨仓自动化，但应用的私钥、client secret 或签发服务成为新的高价值根凭据。

截至 2026-08-20，GitHub.com 的 GitHub App installation token 最长使用已授予给该 app/installation 的仓库和权限，请求时可以进一步限制 `repositories`/`repository_ids` 与 `permissions`，并在一小时后到期。这个一小时是当前厂商事实，不是所有应用令牌的通用 TTL。应用私钥仍需进入受控签发器；若把它复制给每个 job，短期 installation token 只缩短了派生凭据寿命，没有保护根凭据。

### 工作负载身份：用运行声明换取短期能力

联合工作负载身份不预置目标系统长期 secret。CI 平台为一次 job 签发带 `iss`、`sub`、`aud`、`exp` 等声明的 subject token；目标系统或安全令牌服务验证签名和信任策略，再签发面向具体资源的短期访问 token。

```text
CI job
  -> 请求 subject token（仓库 / workflow / ref / run / audience）
  -> 目标签发器验证 issuer、签名、时钟与 claims
  -> 签发 resource token（角色 / scope / audience / TTL）
  -> job 调用目标服务
  -> 到期或撤销，下一次运行重新评估
```

RFC 8693 的 OAuth 2.0 Token Exchange 给出了 `subject_token`、`actor_token`、`resource`、`audience` 和 `scope` 等通用语义，但实际 CI 与云平台不一定逐字实现该 grant。核心设计仍相同：输入凭据证明工作负载上下文，输出凭据只面向目标资源和短窗口；不要因为都使用 JWT 就假定协议、声明或撤销行为完全一致。

截至 2026-08-20，GitHub Actions 官方 OIDC 文档说明每个 job 可取得唯一 JWT，云提供方依据 subject 等 claims 决定是否发短期访问 token；GitLab CI/CD 官方文档通过 `id_tokens` 为第三方服务生成 ID token，并允许给不同 token 配置不同 `aud`。这些实例说明厂商共同抽象，不代表两者的 claim 名称、默认 subject、版本或自托管支持相同。

工作负载身份消除了目标系统的静态 secret，却没有消除信任配置。安全策略至少要绑定：

- 精确 issuer 和签名 key 来源，不接受任意 CI 实例；
- 目标服务预期 audience，避免给 A 服务的 token 被 B 服务接受；
- 稳定的组织/项目/仓库标识，优先使用不可复用 ID，再辅以可读路径；
- 受信任 workflow/config 的身份和版本，不能只看仓库名；
- 允许的 ref、环境、事件类型、派生仓库和保护状态；
- 输出角色、资源、scope 和最长 TTL；
- 失败关闭策略、时钟偏差、重试与审计关联 ID。

只校验 `iss`、允许整个组织，或用可被删除后重新注册的路径作为唯一 subject，都会把大量不受信任 job 放进信任边界。给 job “请求 OIDC token”的权限也不等于授予云资源；真正的授权发生在目标签发器的 claim policy。两侧策略必须共同评审。

### Break-glass：独立应急身份，不是隐藏的万能机器人

常规身份系统、CI 或平台控制面故障时，组织可能需要紧急恢复权限。Break-glass 身份必须与日常自动化分离：它不保存在 runner，不被普通 workflow 引用，不用于绕过偶发失败，也不因为“只在保险箱里”就免于审计。

最低控制包括：明确允许的事故等级；两人或多方批准；硬件保护或分片保管；独立通知通道；取用即告警；最短会话；仅开放恢复所需资源；全程记录命令/引用 OID；使用后立即撤销或轮换；复盘所有动作和常规控制缺口。若身份从未演练，事故时才发现 MFA 设备失效、密码过期或审计不工作，它不是恢复方案。

## “短期”不是安全结论

短期 token 仍可能在有效窗口内被窃取、重放和滥用。TTL 要从完成最小动作所需时间倒推，而不是统一设成平台最大值；长任务应在受控边界续期，并在每次续期重新检查 workload、候选 OID 和环境状态。

还要辨认根凭据：

| 表面上的短期凭据 | 背后的长期信任根 | 应放在哪里 |
| --- | --- | --- |
| App installation token | App private key 或签发服务身份 | KMS/HSM、专用 broker，不复制到每个 job |
| 云临时角色 token | CI OIDC issuer 与云 trust policy | 身份控制面、策略即代码与双人评审 |
| SSH certificate | SSH CA key | 隔离签发器或硬件安全边界 |
| OAuth access token | client secret、refresh token 或用户会话 | 受控 OAuth client/credential manager |

自动过期也不等于可撤销。某些自包含 token 在过期前没有逐枚即时撤销能力，事故时只能禁用主体、签发 key、trust policy 或目标角色。设计时必须实际演练“停一个 job”“停一个仓库”“停整个 issuer”三种粒度，而不是在文档里写一句“可快速撤销”。

## Git 凭据路由不会替服务端缩小权限

Git 的 credential 子系统按 URL 上下文寻找用户名与密码。它帮助选择和保存凭据，但不签发 token，也不知道 token 的服务器端 scope。默认的 HTTP 凭据匹配可能忽略 path，于是同一主机下多个仓库会收到同一条凭据；`credential.useHttpPath=true` 能让助手把仓库路径纳入索引，却不能阻止服务端接受一枚本来就有全组织权限的 token。

在目标仓库中先做只读盘点：

```bash
git config --show-origin --show-scope --get-all credential.helper
git config --show-origin --show-scope --get-regexp \
  '^(credential\.|http\..*extraHeader|remote\..*\.(url|pushurl))'
git remote get-url --all origin
```

前两条读取最终配置及来源，第三条读取 `origin` URL；它们不连接远端、不改变对象、refs、index 或工作区。无输出可能只是该层没有配置，不能证明 IDE、环境变量、外部 agent 或平台 checkout 组件没有注入凭据。输出也可能含内部 URL、用户名或完整 secret，必须在受控终端查看，不能原样贴入工单。

若发现 URL 中嵌入 token，先按泄漏流程撤销或轮换，再把 remote 改为不含 secret 的可信 URL。若发现 `http.<url>.extraHeader` 保存 Authorization header，先确认配置来源和使用者，再在同一作用域删除；不要用更高优先级空值掩盖旧 secret 后声称已经清理。

### 删除凭据助手中的一条旧凭据

只有在已准备好重新认证、并准确知道协议/主机/路径时，才在受控终端执行：

```bash
printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/repository.git' \
  'username=machine-principal' \
  '' | git credential reject
```

示例主机无效，必须替换为实际目标。命令可在任意目录执行；它把 `erase` 请求交给当前配置的 credential helpers，可能删除匹配记录，但不撤销服务端 token、不修改仓库，也不保证每个 helper 都成功删除。若 `credential.useHttpPath` 没有启用，helper 可能忽略 path，影响同一主机的更宽凭据集合。执行后应在不打印 secret 的前提下重新认证，并从签发器/平台撤销旧值。

不要用真实 token 运行 `git credential fill` 来“看看 Git 选了什么”：该命令会把密码字段写到标准输出。随章实验只用合成值，正是为了验证协议而不暴露真实凭据。

## 为一个发布机器人设计授权

下面的流程适用于 GitHub、GitLab、自托管平台或内部 Git 服务，具体产品字段由实现映射。

### 1. 先写操作清单，不先创建 token

以“把已批准制品发布为版本”为例，明确列出：

- 读取哪个仓库的哪个候选 OID、tag 和发布元数据；
- 是否真的要创建 Git tag，还是只创建平台 release；
- 是否写 package registry、对象存储或部署系统；
- 哪些现有 tag 不可覆盖，失败时是否允许删除新 tag；
- 谁批准，哪个检查结果必须存在，哪个环境可以触发；
- 审计中怎样把 Git ref update、release、制品摘要和 CI run 串起来。

“需要 write 权限”不是操作清单。它必须展开成资源与 API/ref 动作，才能识别不需要的管理员、workflow、secret 或绕过权限。

### 2. 为信任级别建独立主体

不要让依赖更新、检查回报、release 和生产部署共用身份。至少让生产发布器拥有独立 principal、所有者、凭据来源和撤销入口。若平台提供应用安装身份或 workload federation，优先让 job 按需取得派生 token；否则用专用机器人账号并限制到项目组。

### 3. 让服务端执行不可变条件

客户端脚本中的 `if branch == main` 可被修改或绕过。高风险条件应在签发器、受保护环境、受保护引用或服务端 hook/策略中执行：只接受批准的 workflow；只从指定 ref/候选 OID 签发；禁止覆盖已有发布 tag；生产环境需要独立批准；机器人不能修改这些规则本身。

### 4. 正向和反向验证

在专用测试仓库/环境使用真实平台证据验证：允许的只读操作成功；对未授权仓库失败；写功能分支与写受保护分支分别符合策略；过期 token 被拒绝；来自未受信任 ref/fork/workflow 的签发失败；撤销主体后新旧会话行为符合预案。

对 Git 读路径，可在已配置测试 remote 的仓库执行：

```bash
git ls-remote --exit-code origin refs/heads/main
```

命令连接远端但不下载对象、不更新本地 refs。成功且目标 ref 存在时输出实际 OID/ref；认证成功但 ref 不存在会以特定非零状态结束，网络、TLS/SSH、认证和授权也都可能失败。它只证明当前身份可读取这一入口，不证明可 push、可读 LFS/子模块、可访问 API 或不能读取其他仓库。

写权限测试必须使用批准的测试 ref 和预期 old OID，并在服务端审计中确认 actor；不要向生产 main 试推，也不要把 `git push --dry-run` 当作平台所有保护规则的完整证明。测试结束删除专用 ref 并验证审计仍保留。

### 5. 登记生命周期和退出动作

身份登记至少包含：稳定 principal ID、显示名、业务/技术所有者、用途、运行位置、仓库/环境、允许动作、凭据/签发方式、TTL、根凭据位置、创建/最后使用时间、轮换/撤销步骤、审计查询和 break-glass 依赖。每次权限扩大必须重新批准；无最后使用记录、所有者离职或 workload 下线时应自动进入回收队列。

## CI 中最容易扩大权限的边界

### 不受信任代码和秘密不能同处一个 job

来自 fork、外部贡献者、未审查分支或可变第三方 action 的代码可以读取环境、修改 Git 配置、调用网络和篡改日志。即使平台对 secret 做字符串 mask，攻击者仍可能编码、分片或通过网络发送。生产凭据应只在已批准候选之后进入独立 job，并让部署器消费不可变制品，而不是重新执行候选仓库中的任意脚本。

### Checkout、submodule、LFS 和 package 是不同资源

主仓库 clone 成功不表示 submodule 或 LFS payload 可读，也不表示 package registry 有权限。反过来，为了让递归 checkout 简单而给主 token 全组织读取，会扩大第三方依赖和横向移动面。分别盘点 URL、协议和资源，使用独立只读凭据或受控代理；检查 checkout 工具是否把 token 留在 `.git/config`、credential helper、工作区或缓存中。

### 写检查结果与写源码要拆开

测试 job 常需报告 status/check，却不需要 push。若平台的内置 job token 支持细粒度权限，把内容设为只读或无权限，只开放检查回报；若产品无法拆分，由受信任的汇总 job 读取测试结果并回报。不要让每个并行测试 shard 都持有主线写权限。

### 环境变量只是传递渠道，不是 secret store

环境变量可能被子进程继承、调试 dump、崩溃采集或 `/proc` 类接口读取。把 token 放进变量有时是平台规定的短时注入方式，但仍要缩小可见步骤、关闭 shell trace、禁止上传环境、在 job 后销毁 runner，并确保 token 不进入命令参数、URL、Git config、cache 和 artifact。

## 轮换、撤销与中断恢复

### 长期凭据轮换

需要无中断切换时，先确认服务是否允许短暂双凭据。创建新值后只分发给合法消费者，观察它实际被使用，再撤销旧值并扫描残留。双凭据窗口必须有结束时间；不能因为“旧的也许还有机器在用”永久保留。若无法列出消费者，说明当前分发体系已经不可审计，应先限制权限和监控，再逐一迁移。

### 短期签发故障

Broker 或 OIDC 不可用时，不要自动回退到仓库里保存的万能 PAT。发布应安全失败、保留已批准候选和制品，等待身份服务恢复。只有达到预定义事故等级时，才进入 break-glass 流程；使用应急身份后不补跑未知步骤，而是重新确认当前 ref、制品摘要和环境状态。

### 令牌疑似泄漏

停止受影响 job，保存 run/principal/token ID 与签发时间，不复制 token 本体；撤销派生 token 或禁用主体/角色；检查有效窗口内的 API、ref update、下载和部署；修复泄漏入口；重新签发最小能力；必要时按上一章处理进入 Git 历史、日志、cache 或 artifact 的值。等自然过期只能缩短未来风险，不能代替窗口调查。

## 按证据诊断失败

| 现象 | 优先检查 | 恢复与安全边界 |
| --- | --- | --- |
| 没有凭据、交互提示被禁用 | job 是否获得请求 token 的权限、helper/broker 是否可用 | 修复签发链；不把长期 token 写入 URL |
| OIDC issuer/audience/subject 不匹配 | 实际 issuer、aud、稳定 workload ID、ref/environment claim 与 trust policy | 先确定预期上下文，再同步策略；不要放宽为通配整个组织 |
| Token expired/not yet valid | runner 时钟、签发/到期时间、排队与任务时长 | 校时并重新签发；不要扩大长期 TTL 掩盖队列问题 |
| 401/认证失败 | token 是否过期/撤销、凭据路由、SSH key 选择 | 取得新短期凭据；不修改 commit 身份 |
| 403/not found | 仓库安装范围、scope/role、SSO/策略、服务隐藏资源存在性 | 与操作清单比对；不直接授予 admin |
| Protected ref/hook 拒绝 | ref old/new OID、候选检查、主体是否允许该动作 | 走评审/队列/条件更新；不借 break-glass 绕过普通冲突 |
| 主仓可读，submodule/LFS/package 失败 | 每个资源的 URL、协议、凭据与权限 | 为依赖配置独立最小读取；不扩成全组织 token |
| 撤销后任务仍能访问 | 自包含 token TTL、缓存会话、多个凭据副本、服务端传播延迟 | 禁用更上层主体/角色，扩大调查并记录实际失效时间 |

错误信息会随平台、代理和版本变化。诊断记录应保存时间、run/job ID、principal、目标资源、动作、ref/OID、HTTP/SSH 阶段和服务端审计 ID，不保存 bearer token、私钥或完整 Authorization header。

## 隔离实验验证了什么

在本书仓库根目录运行：

```bash
./scripts/verify-machine-credential-boundaries.sh
```

前置条件是 Bash、Git 2.49 或兼容实现、`grep`、`mktemp` 和可写临时目录。脚本隔离 system/global Git config，使用 `git.example.invalid`、合成用户名和 `SYNTHETIC-*` 无效 token；不访问网络、真实 credential manager、SSH agent、OIDC issuer 或托管平台。退出时删除实验目录。

实验先在 `credential.useHttpPath=false` 时把一枚凭据批准给同一 HTTPS 主机，并证明另一个仓库路径也会取得该凭据；这验证 Git 默认凭据上下文的复用风险，不表示服务端一定接受 token。随后启用 path，把只读与发布合成 token 分别绑定两个仓库路径，证明读取、拒绝和保留按 path 分离。

实验还故意把合成 token 嵌入 remote URL、把合成 Authorization header 写入 local config，断言两者会出现在 `.git/config`，再改回无 secret URL并删除 header。这个过程只为了给门禁提供可观察 fixture，绝不是生产注入方式。

成功时只输出：

```text
Git credential context and local persistence boundaries passed.
```

实验没有验证 token scope、expiry、server-side revoke、GitHub/GitLab 权限、deploy key、应用安装身份、OIDC claims、secret masking 或 break-glass。真实验证必须在专用测试组织/仓库记录产品、版本、套餐、管理员角色、策略、服务端审计和负向测试结果。

## 小结

可靠的机器身份不是一枚“CI token”，而是一条可还原的授权链。稳定 principal 负责归属，工作负载声明限定上下文，短期凭据承载最小能力，服务端策略约束资源与动作，审计把 actor、job 和对象 OID 连接起来。任何一层缺失，短 TTL 或好看的机器人名称都不能补足。

个人令牌只应是有期限的例外；deploy key 适合简单的单仓只读场景；机器人账号解决非人归属，但仍需凭据治理；应用安装身份和 workload federation 能缩短派生秘密寿命，却把保护重点移到根 key 与 trust policy。Break-glass 则必须独立、双人、告警、限时并在使用后轮换。这样，一个工作负载失陷时，团队才能只停它、证明它做过什么，并让其他交付链继续运行。
