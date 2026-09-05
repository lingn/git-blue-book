# 工作场景索引

先选择最接近的现场，再进入正文判断细节。

| 现场 | 默认入口 |
| --- | --- |
| 文件改坏但还没 add | [丢弃工作区修改](../part-5/02-restore-worktree.md) |
| add 了不该提交的文件，但要保留修改 | [取消暂存](../part-5/03-unstage.md) |
| 最近本地提交漏文件 | [补充最近提交](../part-5/04-amend-content.md) |
| 最近本地提交说明写错 | [修改提交说明](../part-5/05-amend-message.md) |
| 多条未推送提交需要改说明或合并 | [交互式变基](../part-5/06-interactive-rebase.md) |
| 提交后继续改代码，想保留一条提交 | [提交后又想改](../part-5/13-rewrite-commit-playbook.md) |
| 想删除远端提交、拆分混合提交或修订已推送提交 | [提交后又想改](../part-5/13-rewrite-commit-playbook.md) |
| fetch 后突然显示 `ahead N, behind M`，怀疑远端历史被改写 | [远端历史改写](../part-5/14-remote-history-rewrite.md) |
| rebase abort 后又回到旧分支状态 | [远端历史改写](../part-5/14-remote-history-rewrite.md) |
| 已推送错误需要回滚 | [git revert](../part-5/07-revert.md) |
| 个人评审分支变基后要更新远程 | [force-with-lease](../part-5/09-force-with-lease.md) |
| 错误 reset 或误删分支 | [恢复案例](../part-5/12-recovery-cases.md) |
| push 被拒绝 | [推送拒绝](../part-4/08-push-rejection.md) |
| pull 后发生冲突 | [冲突模型](../part-3/07-conflict-model.md) |
| 冲突已经解决，需向同事说明 | [可审查变更中的冲突报告](../part-06/04-reviewable-changes-and-stacks.md) |
| 开发中途需要处理紧急任务 | [stash](../part-02/11-stash.md) 或 [worktree](../part-02/12-multiple-worktrees.md) |
| 需要把一个修复迁到发布分支 | [事故到发布中的热修复](../part-08/08-incident-to-release.md) |
| 不知道哪条提交引入缺陷 | [历史归因与 bisect](../part-11/03-history-attribution.md) |
| 想知道当前一行最后由哪个提交写入，以及逻辑何时首次出现 | [历史归因](../part-11/03-history-attribution.md) |
| 判断 manager、worker 是否都要部署 | [事故到发布与部署范围](../part-08/08-incident-to-release.md) |
| 判断是否需要优雅停机 | [部署与回退](../part-08/06-deploy-and-rollback.md) |
| 仓库变慢但不知道瓶颈在哪一层 | [性能与维护基线](../part-09/01-measure-before-optimizing.md) |
| LFS 路径只检出 pointer 或 payload 缺失 | [二进制与 Git LFS](../part-09/02-binary-and-lfs.md) |
| Submodule 目录为空、OID 不匹配或固定提交取不到 | [Submodule 与 subtree](../part-09/03-submodule-and-subtree.md) |
| 在 monorepo、多仓库包、submodule 与 subtree 之间选型 | [Submodule 与 subtree](../part-09/03-submodule-and-subtree.md) |
| CI 或开发环境使用 shallow、partial 或 sparse 后，无法证明完整构建输入 | [稀疏与部分工作流](../part-09/04-sparse-partial-workflows.md) |
| 需要区分 refspec、历史边界、对象缺失和工作区未展开 | [稀疏与部分工作流](../part-09/04-sparse-partial-workflows.md) |
| 共享库变化没有触发所有消费者，或路径过滤无法证明构建闭包 | [Monorepo 拓扑治理](../part-09/05-monorepo-topology-and-ownership.md) |
| Monorepo 中所有权缺失、跨团队审批不完整或敏感目录需要隔离 | [Monorepo 拓扑治理](../part-09/05-monorepo-topology-and-ownership.md) |
| 需要在 monorepo、多仓库包、submodule 和 subtree 之间作出拓扑决策 | [Monorepo 拓扑治理](../part-09/05-monorepo-topology-and-ownership.md) |
| 令牌、密码、私钥或生产配置误入 Git | [凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md) |
| Force push 清理后担心 tag、评审 ref 或旧 clone 残留 | [凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md) |
| CI 正在使用员工个人令牌、共享 SSH key 或长期管理员凭据 | [最小权限机器身份](../part-10/02-machine-identities.md) |
| OIDC audience/subject 不匹配、短期 token 过期或机器身份需要回收 | [最小权限机器身份](../part-10/02-machine-identities.md) |
| 同一候选重跑却取得不同 Action、模板、镜像或工具 | [第三方 CI 依赖](../part-10/03-ci-dependency-supply-chain.md) |
| 第三方 Action/tag 被移动或失陷，需要枚举受影响 run、cache 与制品 | [第三方 CI 依赖](../part-10/03-ci-dependency-supply-chain.md) |
| 只扫描合并请求 diff，却担心仓库已有秘密 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| `git fsck` 通过，但仍需判断秘密、恶意脚本、symlink 或超大对象 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| `git archive` 排除了文件，却不确定历史、LFS 或 CI 副本是否干净 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| 发布源码归档前需要固定提交、清单、摘要和路径安全检查 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| 历史清理后 bundle、mirror、artifact 或旧 clone 仍可能重新污染 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| 仓库事故刚发生，还没确定该运行恢复命令还是先保存现场 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 仓库正在 merge/rebase，担心 abort、reset 或 IDE 覆盖证据 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 需要保全 linked worktree、submodule、alternates 或 partial clone 的完整依赖 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 已有普通 clone、mirror 或 bundle，但不确定能否充当事故现场副本 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 证据文件需要摘要、访问控制、脱敏副本和移交记录 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 分支删除或 reset 后需要判断对象是否仍可恢复 | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| `fsck` 报 missing、dangling、unreachable 或 corrupt，不知道各自代表什么 | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| `--lost-found`、alternate 或 replace ref 改变了你看到的对象 | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| pack/idx 截断、delta 链或 MIDX 异常，需要选择可信 donor | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| partial/shallow clone 在远端不可用时无法读取祖先或 blob | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| blame 只显示格式化、移动或复制提交，无法解释逻辑来源 | [历史归因](../part-11/03-history-attribution.md) |
| `-S`、`-G`、`--grep` 或 path history 给出不同候选 | [历史归因](../part-11/03-history-attribution.md) |
| merge 的 first-parent、完整提交图和逐父 diff 结论不一致 | [历史归因](../part-11/03-history-attribution.md) |
| 需要把 Git 提交与评审、CI、制品、部署和运行记录对齐 | [历史归因](../part-11/03-history-attribution.md) |
| 已有 mirror，但担心误删或强推会同步覆盖最后好状态 | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| bundle verify 通过，却不知道 refs、LFS 和平台数据是否能完整恢复 | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| 增量 bundle 提示缺少 prerequisite commit | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| 需要为 Git 服务定义 RPO/RTO 并设计空环境恢复演练 | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| 从旧 Git 服务迁移后缺少 tag、notes、默认分支或隐藏 refs | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| 本地远程分支仍显示旧名字，或 prune 后担心提交也被删除 | [远程引用漂移](../part-13/07-remote-ref-drift-failures.md) |
| `origin/HEAD` 仍指向旧默认分支，平台已切换入口 | [远程引用漂移](../part-13/07-remote-ref-drift-failures.md) |
| 远端标签改指向、普通 fetch 未更新或需要核对发布 OID | [远程引用漂移](../part-13/07-remote-ref-drift-failures.md) |
| `ls-remote`、平台页面和本地 refs 互相矛盾，怀疑隐藏/权限或查询竞态 | [远程引用漂移](../part-13/07-remote-ref-drift-failures.md) |
| Git 报 `index.lock`/`cannot lock ref`，不确定是否有活跃进程或并发 writer | [仓库损坏、锁与并发](../part-13/08-repository-corruption-locks-concurrency.md) |
| `fsck`、pack/index 或对象读取失败，需要区分 missing、corrupt、alternate 和存储 I/O | [仓库损坏、锁与并发](../part-13/08-repository-corruption-locks-concurrency.md) |
| 多个 worktree、备份、GC 或维护任务互相阻塞，担心盲删锁造成二次损坏 | [仓库损坏、锁与并发](../part-13/08-repository-corruption-locks-concurrency.md) |
| CI 触发了但不知道实际检出了什么，或事件快照不完整 | [触发与 checkout](../part-08/01-triggers-and-checkout.md) |
| 功能头、临时合并、squash/rebase 或队列候选的结果归属不清 | [候选提交](../part-08/02-candidate-commits.md) |
| 目标分支前进、策略变化或条件更新失败后，旧候选仍显示绿色 | [候选提交](../part-08/02-candidate-commits.md) |
| runner 处于分离 HEAD、浅克隆或 checkout 与调度候选不一致 | [触发与 checkout](../part-08/01-triggers-and-checkout.md) |
| 路径过滤跳过了检查，或合并队列顺序改变了候选 | [触发与 checkout](../part-08/01-triggers-and-checkout.md)、[候选提交](../part-08/02-candidate-commits.md) |
| 构建日志不知道执行了哪一版流水线、runner 或依赖 | [制品与部署证据链](../part-08/03-source-artifact-deployment-evidence.md) |
| 制品文件名相同但摘要变化，或发布 tag 与制品来源不一致 | [制品与部署证据链](../part-08/03-source-artifact-deployment-evidence.md) |
| 平台显示部署成功但实例仍运行旧版本，或旧制品无法回退 | [制品与部署证据链](../part-08/03-source-artifact-deployment-evidence.md) |
| 同一候选在两次构建中得到不同摘要，不知道是时间、依赖、工具链还是缓存造成的 | [可重复构建](../part-08/04-reproducible-builds.md) |
| 只能证明本地归档相同，无法证明代表性 runner 或容器构建相同 | [可重复构建](../part-08/04-reproducible-builds.md) |
| 想在测试、预发布和生产重新构建，却没有定义制品提升和来源证明边界 | [可重复构建](../part-08/04-reproducible-builds.md) |
| 需要创建不可移动的发布 tag，并核对 tag object、剥离目标和制品来源 | [发布引用与制品提升](../part-08/05-release-refs-and-artifact-promotion.md) |
| 同名发布 tag 已存在、制品摘要失配或第二个候选抢先发布 | [发布引用与制品提升](../part-08/05-release-refs-and-artifact-promotion.md) |
| 要把同一制品提升到多个环境，却担心 `latest`、重新构建或审批对象漂移 | [发布引用与制品提升](../part-08/05-release-refs-and-artifact-promotion.md) |
| 控制面接受部署但实例仍运行旧 digest，或金丝雀指标失败 | [部署与回退](../part-08/06-deploy-and-rollback.md) |
| 不确定该回退制品、配置、源码、数据库还是消息任务 | [部署与回退](../part-08/06-deploy-and-rollback.md) |
| 滚动、蓝绿或金丝雀发布需要暂停、旧实例围栏和恢复验证 | [部署与回退](../part-08/06-deploy-and-rollback.md) |
| migration table、实际 schema 和应用版本互相矛盾，无法判断是否执行完成 | [数据库迁移](../part-08/07-database-migrations.md) |
| 回填中断、锁超时或 contract 后旧应用无法启动 | [数据库迁移](../part-08/07-database-migrations.md) |
| 需要判断制品回退、配置回退、向前修复还是数据恢复 | [数据库迁移](../part-08/07-database-migrations.md) |
| 线上事故需要同时做缓解、根因定位、热修复、发布和关闭验证 | [从事故到发布](../part-08/08-incident-to-release.md) |
| `bisect`、`cherry-pick` 或共享库修复后，来源提交和发布目标提交归属不清 | [从事故到发布](../part-08/08-incident-to-release.md) |
| manager、worker、队列、数据库和长任务必须一起观察才能关闭事故 | [从事故到发布](../part-08/08-incident-to-release.md) |
| SVN 的 branch/tag、属性、外部依赖和空目录不知道怎样映射 | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| `.mailmap` 显示正确，但平台账号、评审作者或权限没有关联 | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| 迁移切换期间新旧两端都出现提交、评审或机器人写入 | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| 主仓库不可用，但 standby、备份或开发 clone 可能持有不同最新提交 | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| 需要判断副本是否落后、donor 是否可信或 RPO 是否已超限 | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| 故障转移后旧主恢复在线，担心 stale mirror 覆盖灾后新历史 | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| 区域故障恢复需要冻结写入、条件提升、只读验收和安全回切 | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| 仓库改名、跨组织转移或迁移后，资产记录和 owner 对不上 | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 仓库长期没有人类提交，不确定能否归档或删除 | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 平台显示 Archived，但机器人、tag、release 或其他入口仍可能写入 | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 删除仓库前需要核对依赖、保留、恢复点、观察窗口和审批 | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 归档仓库需要恢复为活动资产，而旧 CI、凭据和依赖已经过期 | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 员工已经转岗或离职，但仍可能通过团队、直授、key 或会话访问仓库 | [权限生命周期](../part-12/02-access-lifecycle.md) |
| 外部协作者合同到期，却仍在继承权限的群组中 | [权限生命周期](../part-12/02-access-lifecycle.md) |
| 删除个人 token 后仍能 push，不确定实际使用了哪个认证入口 | [权限生命周期](../part-12/02-access-lifecycle.md) |
| 权限采集返回空集合，不确定是真正零权限还是 API/分页不可见 | [权限生命周期](../part-12/02-access-lifecycle.md) |
| 需要设计或审查 break-glass 的申请、使用、到期和复盘 | [权限生命周期](../part-12/02-access-lifecycle.md) |
| 全局规则一启用就让旧仓库、镜像或机器人无法工作 | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| 规则部署成功却匹配零仓库，无法判断是零违规还是 scope/采集错误 | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| 仓库级规则或管理员例外可能静默取消组织基线 | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| required check 改名后长期 pending，团队准备暂时关闭全部保护 | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| 策略仓库是最新版本，但平台观测或实际拒绝行为不一致 | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| 临时例外被频繁续期、范围过宽或过期后仍可使用 | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| 平台能搜到 ref 更新，却无法关联 actor、request、old/new OID 或规则版本 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| 事故时段查询为零事件，不确定是真空窗还是权限、分页或采集中断 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| Committer time 与服务端事件顺序矛盾，无法建立可靠时间线 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| 审计导出摘要通过，但仍不能证明来源没有漏事件 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| 平台日志即将过期，需要建立 legal hold 或可移交调查包 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| 平台迁移或区域故障后，旧审计 schema、cursor 和解密 key 无法恢复 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| 仓库还能 clone，但磁盘、LFS、制品或备份容量即将耗尽 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| 总容量看似健康，单仓库或某个 LFS namespace 已开始拒绝写入 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| 仓库大小突然下降，不确定是真实清理还是指标口径/采集变化 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| Repack/GC 前需要估算临时空间、互斥、备份和停止条件 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| 自动维护与备份、镜像或事故取证同时运行 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| 维护退出成功，但需要证明 refs、可达对象和 HEAD tree 未改变 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| 故障手册写了“切换灾备”，但没人知道谁能宣布、围栏或接受数据损失 | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 主站失联、standby 落后、开发 clone 又持有更新提交，需要组织恢复决策 | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 候选 Git `fsck` 通过，但审计、LFS、CI、制品或身份验收仍 inconclusive | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 演练需要设计 inject、终止口令、停止条件和观察员证据 | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 切换后旧主重新上线，必须证明单一写入权威和受控开放 | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 复盘已经列出问题，但没有 owner、截止日期或能力验证 | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 仓库状态混乱，不知道从哪里开始，或需要生成最小求助材料 | [最小排障证据集](../part-13/01-evidence-first.md) |
| 不确定 status、diff、fetch 或 fsck 是否会改变现场 | [最小排障证据集](../part-13/01-evidence-first.md) |
| 多个 clone/linked worktree/IDE 目录让 HEAD 和状态结论互相矛盾 | [最小排障证据集](../part-13/01-evidence-first.md) |
| 需要保留原始错误、命令退出码、脱敏副本和采集缺口 | [最小排障证据集](../part-13/01-evidence-first.md) |
| 工作区文件不见了，不确定是删除、稀疏检出、ignore、分支还是 LFS | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 文件删除已暂存，需要从明确提交只恢复这一条路径 | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 当前 log 看不到提交，不确定是筛选范围、ref 移动、reflog 还是对象丢失 | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 浅克隆看不到更早祖先，准备 deepen 或 unshallow | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| push 报 non-fast-forward，不确定是远端分叉还是认证失败 | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| SSH host key、TLS、DNS、代理或 HTTP 401/403 失败，需要按层分流 | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| 已能 clone 但不能 push，想判断认证成功后是否缺仓库/ref 授权 | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| 受保护分支拒绝直接 push，需要转评审或专用 ref | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| push 成功但 CI、制品或部署没有对应新 OID | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| `status`、`log`、switch/checkout 或 clone/fetch 变慢，需要先定位工作区、历史、对象、传输还是外部数据面 | [性能和容量故障](../part-13/04-performance-and-capacity-failures.md) |
| 对象、refs、index、LFS、制品、备份或 scratch 容量告急，不能把所有字节合成一个健康分 | [性能和容量故障](../part-13/04-performance-and-capacity-failures.md) |
| 准备写入 commit-graph、MIDX 或运行 maintenance，需要维护前后验证逻辑不变量 | [性能和容量故障](../part-13/04-performance-and-capacity-failures.md) |
| 文件是 LFS pointer 但工作区无法水合，或 Git fsck 通过而二进制仍缺失 | [LFS、子模块与 CI clone 异常](../part-13/05-lfs-submodule-ci-failures.md) |
| 子模块目录为空、detached HEAD、gitlink commit 未发布或递归更新失败 | [LFS、子模块与 CI clone 异常](../part-13/05-lfs-submodule-ci-failures.md) |
| CI checkout 成功但候选 OID、浅/部分历史、LFS、子模块或构建输入无法证明 | [LFS、子模块与 CI clone 异常](../part-13/05-lfs-submodule-ci-failures.md) |
| commit 没有签名、verify-commit 失败或 key/principal 无法映射 | [签名无法验证与密钥状态异常](../part-13/06-signature-verification-failures.md) |
| 签名在本机通过但 CI/发布环境失败，或候选提交修改了自己的信任策略 | [签名无法验证与密钥状态异常](../part-13/06-signature-verification-failures.md) |
| tag 签名有效但目标 OID、制品或部署版本不一致 | [签名无法验证与密钥状态异常](../part-13/06-signature-verification-failures.md) |
