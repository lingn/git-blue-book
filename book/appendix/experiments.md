# 运行本书实验

仓库 `scripts/` 下的验证脚本会使用 `mktemp` 创建隔离临时目录，配置虚构身份，完成后删除临时仓库。它们不会修改当前蓝皮书历史或连接真实远程服务器。

## 运行全部实验

在仓库根目录：

```bash
./scripts/verify-all.sh
```

当前覆盖：

- blob 复用、tree、commit、附注/轻量标签和 repack 后的对象身份；
- 首次提交、身份作用域与条件 include、工作区/index/HEAD 状态矩阵、取消暂存恢复、差异、提交失败与空提交、`.gitignore`、`.gitattributes` 和换行属性；
- 分支、快进、分叉合并、冲突中止与解决、标签；
- index stage 1/2/3、`AUTO_MERGE`、rerere 复用与忘记、rename/delete 和目录重命名；
- 本地 bare 远程、双克隆同步、推送拒绝、变基、cherry-pick；
- `file://` 传输的 clone/fetch/push，以及隔离凭据助手的 approve、fill、路径作用域和 reject；
- 正/负 refspec、显式 push 映射、浅克隆深化、部分克隆按需取对象和稀疏工作区；
- restore、取消暂存和 amend；
- 交互式 rebase 的 reword、fixup、拆分、冲突和中止；
- 普通提交 revert、冲突中止和 merge mainline revert；
- 显式租约拒绝、协调后的条件更新和远程引用恢复；
- reset 三模式、路径 reset、未跟踪路径边界和 reflog 恢复；
- stash、worktree、bisect 和热修复迁移。
- merge、squash 与 rebase merge 的父关系、祖先关系、最终 tree 和 OID 差异，以及带 expected-old 的引用并发更新。
- 分离 HEAD 的 CI 候选、合并提交父节点、可重复源码归档、证据清单和部署副本摘要恢复。
- CI 的 NUL 路径清单、路径选择、过期候选、队列顺序和带期望旧值的条件引用更新。
- 候选 commit/tree 的构造上下文、目标与功能差异、候选过期和合并队列的 expected-old 条件更新（复用上述两组 CI 实验）。
- 可重复源码归档、构建清单、摘要比较和未声明外部输入导致的非确定性检测。
- 附注发布 tag 的对象核对、显式 refspec 推送、制品摘要提升、篡改恢复和同名 tag 原子创建竞态。
- SSH 格式的 commit/tag 签名、无签名拒绝、候选工作区策略与外部信任策略的差异，以及按 candidate OID、fingerprint、principal 和 action 匹配外部 release 授权记录。
- `safe.directory`/bare 发现门禁、clone 的配置与 hook 边界、required filter、tracked hook opt-in 和递归 file 协议限制。
- 仓库规模指标、Trace2 event、commit-graph、MIDX bitmap，以及显式维护前后的逻辑状态一致性。
- Git LFS v1 pointer 的核心模型、payload SHA-256/size、外部对象缺失时 required smudge 失败，以及 Git `fsck` 与 LFS 完整性的边界。
- Submodule gitlink、递归 checkout、未发布依赖 commit 的 push/clone 失败、deinit 恢复，以及 subtree 普通 tree、pull 和可重复 split。
- 合成凭据路径的全 refs 历史改写、`refs/original`/对象保留、远端强制更新，以及旧 clone 通过普通 merge/push 重新污染。
- HTTP 凭据在 host/path 上下文中的复用与隔离、按 path 拒绝，以及 token 嵌入 remote URL 或 Authorization header 时的 local config 落盘边界。
- 第三方 CI 依赖 tag 的强制移动、完整 commit pin、consumer lock，以及顶层 Action 对象不变时传递 branch 继续漂移的边界。
- 秘密扫描与归档实验使用无效合成标记，覆盖当前 tree、旧 refs、notes、reflog、文件名、CI/LFS 外部副本、symlink、大 blob、`git fsck`、`export-ignore`、`--worktree-attributes`、bundle 和归档摘要；不模拟平台 push protection、historic scan、LFS API、CI artifact 保留或压缩炸弹防护。
- 事故现场采集实验覆盖未完成 merge、index stages、工作区与暂存差异、refs、reflog、local config、不可达 blob、操作状态和 SHA-256 清单；验证采集前后状态不变，以及普通 clone 遗漏源 index、未跟踪文件、notes、reflog 和不可达对象的边界。
- 对象取证实验覆盖 reflog 根与 `--no-reflogs` 的不可达对象、`--lost-found` 写入边界、loose blob 缺失、alternate 掩盖与 donor 恢复、replace ref 原始解释、截断 pack/idx 恢复和 recovery ref 验收；只在可销毁副本执行写入。
- 历史归因实验覆盖 line-porcelain blame、纯格式化 ignore-rev、rename/copy 检测、`--follow`、`-S`、`-G`、提交说明搜索、first-parent、逐父 diff、未合入 refs 和调查清单篡改检测。
- 备份恢复实验覆盖完整 refs bundle、空 bare 仓库恢复、annotated tag/notes/自定义 refs、增量 prerequisite、不可达对象遗漏、mirror local 状态遗漏和 prune 删除传播。
- 仓库迁移实验覆盖 staging 最终同步、全 refs mirror push、commit/tree/tag/notes/OID 保持、mailmap 显示边界、目标 symbolic HEAD、源端拒写围栏和客户端 cutover。
- 灾难恢复实验覆盖异步 standby 复制滞后、主站隔离、donor 增量 bundle、recovery namespace、条件 `update-ref` 提升、新主验收、旧主拒写和灾后继续 push。
- 仓库生命周期实验覆盖稳定资产登记、业务/技术双重 owner、默认分支声明与 symbolic HEAD 对账、归档 bundle 与摘要、拒写围栏、待删除审批门禁和空 bare 仓库恢复。
- 权限生命周期实验覆盖自然人、外部协作者、机器与紧急主体的合成登记，区分 `pass`/`fail`/`inconclusive`，并验证开发者功能 ref、发布 tag、离职拒绝和 break-glass 批准/到期的接收端门禁。
- 规则与例外实验覆盖组织/分类 scope 的累积要求、audit 到 enforce 提升、窄规则例外、策略 digest 漂移三态，以及本地非快进更新的 would-deny、拒绝和例外使用记录。
- 审计证据实验覆盖 accepted/denied ref 事件、actor/request/old-new OID 关联、对象与服务时钟边界、cursor 幂等采集、sequence 缺口三态、调查包 manifest 和篡改检测。
- 仓库健康与容量实验覆盖真实 Git 对象/refs/commit/格式指标、合成的分层容量四态、headroom 预警、完整性失败，以及事故/备份/scratch/互斥维护门禁、失败锁恢复和逻辑状态不变量。
- 组织级恢复实验覆盖角色与状态转换门禁、primary 拒写、落后 standby、bundle 候选恢复、审计 inconclusive、控制面 generation 租约、只读提升、单一写入权威和复盘行动闭环。
- 排障快照实验覆盖真实 merge 冲突与 index stage 1/2/3、采集前后状态不变、证据包 pass/fail/inconclusive、remote URL secret 隔离、失败 switch 原文、abort 恢复和 fetch 更新远程跟踪 ref/FETCH_HEAD 的副作用。
- 文件/提交消失实验覆盖未暂存与已暂存删除的不同 restore 来源、sparse 未展开、ignore 可见性、未跟踪内容不入对象库、hard reset 后 reflog/recovery ref，以及 depth=1 浅边界和 unshallow。
- Push/认证/权限边界实验覆盖错误 endpoint、file 传输只读探测、非快进拒绝、fetch 对远程跟踪 ref/FETCH_HEAD 的副作用、受保护 ref 的本地 hook、review ref 替代路径和 remote URL 回滚。
- 性能/容量排障实验覆盖对象、refs、tracked paths、index 和 Trace2 采集，commit-graph/MIDX bitmap 验证，受控 maintenance 前后的逻辑不变量，以及明确标注的 pass/warn/fail/inconclusive 容量 fixture；不声称冷/热缓存、p95、网络、服务端、LFS、制品、备份或真实磁盘收益。
- LFS/子模块/CI 外部依赖实验覆盖 pointer 与 payload 分离、required smudge 缺失和恢复、主仓库 fsck 仍通过、未发布 gitlink 导致递归检出失败、依赖发布后按同一 OID 恢复，以及 detached candidate 和输入清单核对。
- 签名排障实验覆盖签名 commit/tag、无签名拒绝、tag 目标核对、候选自带 allowed signers 的自授权风险、候选之外策略拒绝、历史改写后新对象无签名，以及验证前后引用/工作区不变。
- 远程引用漂移实验覆盖分支重命名、旧 remote-tracking ref 的 prune 与 recovery ref、默认分支 `origin/HEAD` 刷新、标签改指向前后的 OID 保护，以及跨查询竞态。
- 仓库损坏/锁并发实验覆盖活跃 writer 持有 `index.lock`、第二 writer 拒绝、精确 stale index/ref lock、expected-old 更新、截断 pack 的 fsck 失败和 pristine donor 恢复。

## 环境要求

- Bash；
- Git 2.28 或更高版本；
- `git subtree`，用于仓库组合实验；不同 Git 发行包可能未安装该 contrib 命令；
- POSIX 常用工具，例如 `mktemp`、`awk`、`sed`、`grep`；
- `sha256sum` 或 `shasum`，用于 CI/CD 制品摘要和 LFS pointer 模型实验。
- `ssh-keygen`，用于签名实验生成一次性 Ed25519 实验 key；不得把实验 key 用于真实身份或生产发布。

LFS pointer 实验使用本书自建的最小 clean/smudge helper，不要求安装 `git-lfs`，也不连接 LFS 服务。它只验证 Git 能观察到的指针与外部对象边界，不能证明真实 Batch API、锁、配额、迁移或平台行为。

敏感历史实验使用无效合成字符串，并仅为构造 Git fixture 调用官方不推荐的 `filter-branch`；它不要求或冒充 `git-filter-repo`，不接触真实凭据、签发器或平台清理 API。

机器身份实验使用无效合成 token 和虚构主机，只验证 Git credential context 与本地配置持久化；它不模拟 OIDC、deploy key、短期签发、真实凭据存储或托管平台权限。

CI 依赖实验只解析本地 Git 对象和 refs，不执行 fixture 中的脚本，也不模拟 Action runner、远程 include、registry、cache、权限或 attestation。

可重复构建实验只验证本地 Git 源码归档、摘要和清单字段，以及未声明字节变化会被发现。它不证明任何语言编译器、容器镜像、远程依赖、缓存、签名服务、制品库、CI runner 或跨平台构建已经逐字节可重复；生产结论必须在目标工具链和代表性 runner 中重新采集。

发布引用与制品提升实验只验证本地附注 tag、bare 接收端、显式 refspec、文件摘要、清单映射和同名 tag 的创建竞态。它不模拟托管平台 protected tags、审批控制面、制品仓库授权、签名服务、保留/计费、部署编排、数据库或运行实例；生产发布必须在目标平台的专用环境中验证这些边界。

部署与回退实验只验证临时 Git 仓库、制品文件、实例观察文件和状态清单之间的摘要与状态不变量。它覆盖金丝雀失败后暂停、已知良好制品回退、配置独立回退、主线前进不改变已部署摘要和长任务 digest 围栏；不模拟真实实例探针、流量切分、编排器、数据库事务、消息队列、权限、审计或 RPO/RTO。

数据库迁移实验只验证临时 Git 仓库和文本 fixture 中的 expand、可续跑回填、旧应用围栏、contract 门禁、schema/数据状态记录和 Git 回退边界。它不模拟真实数据库事务、锁、DDL、复制、备份、权限、在线变更、数据类型、触发器、消息队列或跨服务一致性；生产迁移必须在目标引擎和代表性数据规模下演练。

事故到发布实验只验证临时 Git 仓库、`bisect` 候选、来源/目标修复提交、附注 tag、制品摘要、双组件部署清单和关闭状态。它覆盖证据冻结、缓解、旧实例围栏、主线继续前进和关闭条件；不模拟真实日志、CI、制品库、数据库、队列、流量、业务指标、权限或组织审批。

稀疏与部分工作流实验复用 `scripts/verify-refspec-partial-clone.sh`，验证负 refspec、shallow deepen/unshallow、partial clone 按需取得 blob 和 sparse-checkout 展开/关闭。它不模拟真实服务端 filter、权限、费用、LFS、子模块、CI runner 或生产构建完整性。

Monorepo 拓扑实验只验证临时 Git 仓库、文本构建图、所有权快照、变更闭包和候选制品摘要。它覆盖共享库反向依赖、图缺边的 `inconclusive`、原子候选、审批缺失和主线前进边界；不执行真实构建、评审平台、身份目录、缓存、制品库或迁移切换。

事故现场实验只采集合成仓库的 Git 逻辑状态，不创建磁盘法证镜像，也不验证 APFS/ZFS/LVM/云盘一致性、内存取证、平台审计、LFS 服务或恶意主机；真实事件必须使用组织批准的取证流程。

历史归因实验只验证当前对象库和 refs 可见范围内的 Git 机制。它不模拟平台评审、工单、服务器接收时间、CI run、制品、部署事件或运行遥测，也不把合成作者身份当作责任证明。

备份恢复实验只验证本地 Git bundle 与 mirror 机制，不验证托管平台数据库、隐藏 refs、LFS、对象存储、加密、跨区域复制、访问控制或真实 RPO/RTO。生产恢复能力必须由组织专用环境的空环境演练证明。

仓库迁移实验不安装或模拟 SVN，也不连接托管平台、LFS 或 CI。它只验证 Git 到 Git 无转换迁移的数据面和本地拒写 hook；SVN revision/copy/property、平台 issue/评审/权限、LFS payload 和服务端只读模式必须在专用环境验证。

灾难恢复实验只验证本地 bare 仓库的数据面状态机，不模拟区域、DNS/TLS、负载均衡、同步存储、平台数据库、LFS、对象存储、身份、CI 或真实 RPO/RTO；本地 hook 仅代表实验围栏，不能替代服务端维护/条件提升机制。

仓库生命周期实验只验证本地 bare 仓库、TSV 登记和 receive hook 能表达的 Git 数据面门禁，不连接身份目录、法务系统、托管平台、LFS、package、CI 或审计服务，也不执行真实删除。平台 Archive/Delete、软删除窗口和管理员绕过必须按实际产品版本、权限与套餐另行验收。

权限生命周期实验通过合成环境变量向本地 receive hook 传入虚构 actor，只证明接收端可以按主体、ref、批准和时限拒绝更新。真实服务必须从认证会话取得 actor，并分别验证 SSO/SCIM、嵌套群组、应用、key、API、LFS、合并、会话撤销与审计；客户端自报环境变量绝不是生产认证机制。

规则与例外实验使用本地 TSV 求值器、模式文件和合成 receive hook，不验证托管平台的规则继承、优先级、评估模式、检查报告者、管理员绕过、API/LFS/合并入口、缓存传播或套餐。环境变量中的 actor、事故单和例外只是假数据，生产执行器必须从可信控制面取得并验证。

审计证据实验的 actor、request、provider/collector time 和 sequence 均由本地环境变量构造，只验证事件模型、Git ref 结果、采集游标和字节摘要。它不证明真实平台事件覆盖、认证主体、时钟、分页语义、schema、保留、legal hold、WORM、签名或跨区域恢复。

仓库健康与容量实验中的 Git 指标来自临时仓库，LFS/制品用量、硬限制和两点增长趋势是明确标注的策略 fixture。它不测性能、不预测生产容量，也不验证真实 LFS/平台 API、磁盘/inode、服务并发、OS scheduler、配额或计费。

组织级恢复实验中的角色、审批、审计、外部系统、容量状态和 control-plane generation 都是 fixture；只有 refs、bundle、`fsck`、本地 receive hook 和 push 是真实 Git 行为。它不验证真实 DNS/TLS、负载均衡、数据库、身份、LFS、CI、制品、通信、值班响应、区域故障或 RPO/RTO，生产演练必须取得组织授权并使用目标平台的围栏、提升与审计机制。

排障快照实验只处理本书生成的受信任本地仓库；它不证明采集器能安全进入恶意仓库，不连接真实远端、平台、身份或 LFS，也不替代磁盘取证、平台审计和组织级事故流程。URL 中的 secret 是无法使用的合成字符串；真实凭据不得放入实验，发生泄漏时必须先撤销和隔离。

文件/提交消失实验会在临时仓库真实执行路径恢复、sparse-checkout、`reset --hard` 和 unshallow，并用实验外部副本演示未跟踪字节的 Git 边界。它不验证真实删除后的磁盘恢复、编辑器历史、对象过期/GC、托管平台、服务端 reflog、LFS 或 submodule；破坏性步骤不得在日常仓库为了复现而执行。

Push/认证/权限边界实验只验证本地 `file://` 传输、bare 接收端的非快进规则、receive hook 和本地 remote 配置。它不模拟 SSH host key、HTTPS TLS、真实凭据、SSO、平台规则、评审、CI、配额、审计或服务端隐藏存在性；认证与授权必须按目标平台版本、权限、套餐和核对日期另行验收。

性能/容量排障实验只在临时仓库验证 Git 规模指标、Trace2 事件、commit-graph、MIDX bitmap、maintenance 和 refs/HEAD/tree/可达对象/工作区不变量；容量状态使用明确的合成 TSV。它不测量或预测生产性能，不模拟冷/热缓存、文件系统、网络、服务端负载、LFS、制品、备份、inode、磁盘故障、后台调度、平台配额或计费；生产结论必须在代表性副本和目标环境重新采集。

LFS/子模块/CI 外部依赖实验只在临时仓库验证自建 filter 的 pointer/payload 层次、本地 file 传输的 gitlink 发布顺序和 candidate checkout；它不模拟 Git LFS 服务 API、真实凭据、SSH/TLS、锁、配额、平台缓存、CI runner、合并请求、制品库或审计。file URL 的协议开关不是托管平台授权证据，真实外部数据面必须在目标环境按版本、权限、套餐和核对日期验收。

签名排障实验只在临时仓库使用一次性 SSH key、外部 allowed signers 文件和合成 release 授权清单验证 Git 对象签名、信任策略切换、tag 目标、候选之外的授权匹配和历史改写边界；它不模拟 OpenPGP/X.509、硬件 key、撤销/时间戳服务、真实组织授权服务、托管平台徽章或真实发布门禁。

远程引用漂移实验只在临时 seed、bare 远端和客户端 clone 中验证 Git refs、symbolic HEAD、tag ref、fetch/prune 和查询时序；它不模拟平台隐藏 refs、默认分支控制面、分支保护、评审/合并队列、SSO、审计事件或真实网络竞态。

仓库损坏/锁并发实验只在临时本地仓库和可销毁副本中验证 Git lockfile、expected-old ref、pack/idx 和 fsck 边界；它不模拟网络文件系统租约、reftable、真实进程崩溃、磁盘坏道、服务端对象池或组织调度器。

第六篇协作实验只在临时仓库验证 merge、squash、rebase 和 `update-ref` 的 Git 数据面。它不连接评审平台，也不验证审批、代码所有者、检查报告者、合并队列、服务端身份、保护规则、套餐或审计事件；这些控制面行为必须在目标平台的专用测试仓库中按版本、权限和核对日期验收。

验证脚本是正文事实的回归测试，不是让读者在真实项目照抄的发布脚本。高风险操作只应在脚本生成的临时仓库中观察。
