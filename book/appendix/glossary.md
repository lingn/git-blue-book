# 术语表

术语表用于回看，不承担首次教学。链接指向正文第一次建立完整工作模型的位置。

| 术语 | 工作定义 | 首次详解 |
| --- | --- | --- |
| 版本控制 | 记录文件变化，使历史可识别、比较、恢复和协作 | [为什么需要版本控制](../part-1/01-why-version-control.md) |
| 分布式版本控制 | 每个参与者可持有完整仓库并交换历史 | [三代方案](../part-1/02-three-generations.md) |
| 快照 | 项目在某个历史节点上的完整内容视图 | [Git 保存快照](../part-1/04-snapshots.md) |
| 仓库 | 保存对象、引用、暂存状态和配置的地方 | [对象与仓库](../part-1/05-first-model.md) |
| blob | 保存文件内容、不保存路径名的不可变对象 | [对象数据库](../part-1/05-first-model.md) |
| tree | 把路径名和模式关联到 blob 或子 tree 的对象 | [对象数据库](../part-1/05-first-model.md) |
| 提交 | 指向快照并包含身份、说明和父关系的不可变记录 | [对象与仓库](../part-1/05-first-model.md) |
| 对象 ID | 由对象类型、长度和内容计算、用于寻址对象的标识 | [内容寻址](../part-1/05-first-model.md) |
| 工作区 | 当前可直接查看和编辑的项目文件 | [三个区域](../part-2/05-three-areas.md) |
| 暂存区 | 为下一次提交准备快照内容的区域，也叫 index | [三个区域](../part-2/05-three-areas.md) |
| 未跟踪文件 | 工作区中存在但尚未纳入 Git 记录集合的文件 | [查看状态](../part-2/04-status.md) |
| 提交图 | 以提交为节点、父提交关系为连线的有向图 | [提交图](../part-3/01-commit-graph.md) |
| 引用 | 指向 Git 对象的名字 | [分支模型](../part-3/02-branch-as-reference.md) |
| 分支 | 指向提交并随当前工作线新提交向前移动的引用 | [分支模型](../part-3/02-branch-as-reference.md) |
| `HEAD` | 表示当前工作位置的特殊引用，通常指向当前分支 | [理解 HEAD](../part-3/03-head.md) |
| 合并 | 把另一条历史中当前分支尚未包含的变化整合进来 | [第一次合并](../part-3/05-first-merge.md) |
| 快进 | 当前提交是目标提交祖先，只需向前移动分支 | [第一次合并](../part-3/05-first-merge.md) |
| 冲突 | Git 无法替人决定最终内容时留下的未完成整合状态 | [冲突模型](../part-3/07-conflict-model.md) |
| index stage | 冲突期间 index 保存的共同祖先、当前侧和合入侧条目；普通 merge 中分别是 stage 1、2、3 | [复杂冲突与 rerere](../part-3/10-complex-conflicts-rerere.md) |
| `ort` | Git 新版本对单分支普通合并采用的三方合并策略，负责组合 tree 和处理 rename 等机械语义 | [复杂冲突与 rerere](../part-3/10-complex-conflicts-rerere.md) |
| `AUTO_MERGE` | `ort` 冲突现场记录初始自动合并工作区内容的临时 tree 引用 | [复杂冲突与 rerere](../part-3/10-complex-conflicts-rerere.md) |
| rerere | 记录冲突 preimage 与已解决 postimage，并在相似冲突中复用编辑结果的机制 | [复杂冲突与 rerere](../part-3/10-complex-conflicts-rerere.md) |
| 标签 | 给特定对象的稳定名字，通常用于发布提交 | [标签](../part-3/09-tags.md) |
| 远程仓库 | 当前仓库通过路径或网络访问的另一个仓库 | [远程模型](../part-4/01-remote-model.md) |
| 远程跟踪分支 | 本地记录最近一次通信时远程分支位置的引用 | [远程跟踪](../part-4/05-remote-tracking.md) |
| 远程引用漂移 | 远端当前 refs、本地远程跟踪缓存、上游配置或平台控制面之间出现未解释差异的状态 | [远程引用漂移](../part-13/07-remote-ref-drift-failures.md) |
| 远端默认分支 | 远端 symbolic `HEAD` 或平台控制面声明的默认入口；不是每个客户端实时读取的值 | [远程引用漂移](../part-13/07-remote-ref-drift-failures.md) |
| 引用快照 | 在明确时间和查询上下文中记录的一组 refs、OID 和 symbolic ref 响应 | [远程引用漂移](../part-13/07-remote-ref-drift-failures.md) |
| lockfile | Git 在替换 index、ref、配置或浅边界前创建的临时锁文件；存在不等于一定有活跃进程 | [仓库损坏、锁与并发](../part-13/08-repository-corruption-locks-concurrency.md) |
| expected old | 引用条件更新中要求当前 ref 必须匹配的旧 OID，用于拒绝并发覆盖 | [仓库损坏、锁与并发](../part-13/08-repository-corruption-locks-concurrency.md) |
| 对象损坏 | loose object、pack、idx 或底层存储无法通过 Git 格式、哈希或读取检查的状态 | [仓库损坏、锁与并发](../part-13/08-repository-corruption-locks-concurrency.md) |
| CI 候选提交 | 一次检查实际验证的精确 commit 或带构造上下文的临时 tree，可能是功能头、临时合并、squash、rebase 或合并队列组合 | [候选提交](../part-08/02-candidate-commits.md) |
| 候选过期 | 因目标/功能 OID、策略、流水线、依赖、信任根或最终写入对象变化而不能继续复用旧检查结果的状态 | [候选提交](../part-08/02-candidate-commits.md) |
| 候选上下文 | 与 candidate OID 一起固定的目标基线、生成策略、检查定义、路径策略、依赖解析、runner 和 attempt | [候选提交](../part-08/02-candidate-commits.md) |
| checkout 合约 | 调度记录要求的候选 OID 与 runner 实际 `HEAD`、tree、工作区和历史边界之间的核对规则 | [触发与 checkout](../part-08/01-triggers-and-checkout.md) |
| 路径过滤 | 根据候选变化路径和依赖策略选择检查的机制；不等于完整构建输入证明 | [触发与 checkout](../part-08/01-triggers-and-checkout.md) |
| 构建证据 | 把源码、流水线、runner、依赖、命令、身份和时间绑定到一次构建的记录 | [制品与部署证据链](../part-08/03-source-artifact-deployment-evidence.md) |
| 制品摘要 | 对最终制品字节计算的内容身份，用于跨存储、提升和部署核对同一输出 | [制品与部署证据链](../part-08/03-source-artifact-deployment-evidence.md) |
| 运行版本核验 | 从实际实例或运行时读取制品 digest/build identity，并与部署记录比较的过程 | [部署与回退](../part-08/06-deploy-and-rollback.md) |
| 可重复构建 | 在声明的输入闭包和过程约束下，多次构建得到逐字节相同输出，或按预先定义的语义比较与来源证明达到发布门槛 | [可重复构建](../part-08/04-reproducible-builds.md) |
| 构建输入闭包 | 影响构建输出的源码、生成器、依赖、工具链、runner、环境、网络、缓存和外部输入的完整集合 | [可重复构建](../part-08/04-reproducible-builds.md) |
| 构建清单 | 把候选、依赖、工具链、命令、环境摘要、制品 digest 和比较结果绑定在一起的不可变记录 | [可重复构建](../part-08/04-reproducible-builds.md) |
| 发布引用 | 为候选或正式版本命名的受控 Git tag/ref；只命名源码对象，不包含制品字节 | [发布引用与制品提升](../part-08/05-release-refs-and-artifact-promotion.md) |
| 制品提升 | 在环境之间复制并核对同一个不可变 artifact digest，而不是按分支重新构建的过程 | [发布引用与制品提升](../part-08/05-release-refs-and-artifact-promotion.md) |
| 发布记录 | 把 tag object、剥离目标、候选上下文、构建清单、制品摘要、审批和环境绑定的追加式证据 | [发布引用与制品提升](../part-08/05-release-refs-and-artifact-promotion.md) |
| rollout | 把一个部署请求按批次、流量和健康门槛推进到目标环境的状态机 | [部署与回退](../part-08/06-deploy-and-rollback.md) |
| 制品回退 | 把运行实例切回已知良好的不可变制品；不等于撤销数据库、消息或外部副作用 | [部署与回退](../part-08/06-deploy-and-rollback.md) |
| 数据库向前修复 | 在不能安全降级 schema 或数据时，使用已演练的兼容修复把状态推进到可运行形态 | [部署与回退](../part-08/06-deploy-and-rollback.md) |
| 旧实例围栏 | 停止旧批次接收新流量或新协议消息，并处理排空、长任务和终止条件的控制措施 | [部署与回退](../part-08/06-deploy-and-rollback.md) |
| 迁移批次 | 一次数据库迁移执行尝试的稳定身份，关联源码、制品、目标环境、执行主体、checkpoint 和状态历史 | [数据库迁移](../part-08/07-database-migrations.md) |
| Expand/contract | 先增加兼容结构、完成回填和切换，再围栏旧消费者并清理旧结构的迁移阶段模型 | [数据库迁移](../part-08/07-database-migrations.md) |
| 回填 checkpoint | 可重放批量迁移保存的进度标记，用于暂停后续跑并避免跳过或重复处理 | [数据库迁移](../part-08/07-database-migrations.md) |
| 向前修复 | 在 schema 或数据已不可逆变化时，把当前状态推进到可运行形态的修复动作 | [数据库迁移](../part-08/07-database-migrations.md) |
| 兼容矩阵 | 对旧/新应用、旧/新 schema、迁移任务和消息协议组合逐一声明可否共存的表 | [数据库迁移](../part-08/07-database-migrations.md) |
| 缓解 | 通过暂停、限流、开关、围栏或回退降低影响，但不等于根因修复 | [从事故到发布](../part-08/08-incident-to-release.md) |
| 事故证据冻结 | 在重现、修复或清理前保存运行、Git、制品、配置、数据和消息的初始快照 | [从事故到发布](../part-08/08-incident-to-release.md) |
| 修复来源提交 | 修复最初完成并被验证的 commit，经过 cherry-pick 后可能与发布目标提交不同 | [从事故到发布](../part-08/08-incident-to-release.md) |
| 修复目标提交 | 修复进入稳定发布线后实际构建和发布的 commit | [从事故到发布](../part-08/08-incident-to-release.md) |
| 事故关闭条件 | 运行版本、业务指标、数据/消息不变量、证据包和后续行动都满足后的状态转换门槛 | [从事故到发布](../part-08/08-incident-to-release.md) |
| 上游分支 | 当前本地分支默认比较、拉取和推送的远程关系 | [推送与上游](../part-4/07-push.md) |
| refspec | 在 fetch 或 push 中选择 source 引用并映射到 destination 引用的表达式 | [Refspec 与受限克隆](../part-4/14-refspec-partial-clone.md) |
| 浅克隆 | 以 shallow boundary 截断部分祖先历史的仓库 | [Refspec 与受限克隆](../part-4/14-refspec-partial-clone.md) |
| 部分克隆 | 由 promisor 远端承诺按需提供被过滤对象的克隆 | [Refspec 与受限克隆](../part-4/14-refspec-partial-clone.md) |
| 变基 | 以新起点重新应用一段变化并生成新提交 | [变基模型](../part-4/10-rebase-model.md) |
| 挑选提交 | 在当前分支重放指定提交变化并创建新提交 | [cherry-pick](../part-4/12-cherry-pick.md) |
| 改写历史 | 生成新提交替换原关系，使旧 ID 离开当前分支 | [恢复决策矩阵](../part-5/01-decision-matrix.md) |
| 回滚变化 | 创建新提交抵消旧提交效果，保留旧历史 | [revert](../part-5/07-revert.md) |
| 引用日志 | 本地记录引用近期移动情况的日志，也叫 reflog | [reflog](../part-5/11-reflog.md) |
| 工作树 | 与仓库关联的一套工作区、暂存状态和当前 HEAD | [worktree](../part-02/12-multiple-worktrees.md) |
| 候选提交（兼容入口） | 旧 CI/CD 章节对 candidate commit 的称呼，权威定义已迁移到第八篇候选提交章 | [候选提交](../part-08/02-candidate-commits.md) |
| 路径过滤 | 根据 changed paths 与依赖策略选择要运行的检查，不代表候选的完整输入 | [触发与 checkout](../part-08/01-triggers-and-checkout.md) |
| 合并队列 | 按目标分支当前状态和队列顺序重建候选、检查后条件更新主线的协调机制 | [候选提交](../part-08/02-candidate-commits.md) |
| 制品 | 由构建过程生成、可被存储和部署的软件输出，不等同于源码提交 | [源码、制品与部署证据链](../part-08/03-source-artifact-deployment-evidence.md) |
| 制品摘要 | 对制品字节计算的内容摘要，用于跨构建、存储和部署阶段核对同一输出 | [源码、制品与部署证据链](../part-08/03-source-artifact-deployment-evidence.md) |
| 对象签名 | 私钥控制者对 commit 或附注 tag 的精确 payload 生成的密码学签名 | [签名与信任策略](../part-10/04-signatures.md) |
| key fingerprint | 从公钥计算、用于稳定标识签名 key 的指纹；不同于可由策略赋予的姓名或 principal | [签名与信任策略](../part-10/04-signatures.md) |
| principal | 验证策略中映射到签名 key 的主体标识；SSH 签名本身不把该名称证明为组织身份 | [签名与信任策略](../part-10/04-signatures.md) |
| 信任根 | 验证器预先信任、用于决定哪些 key 或证书链可接受的策略来源 | [签名与信任策略](../part-10/04-signatures.md) |
| protected configuration | Git 认为不由当前不受信任仓库控制的配置范围；`safe.directory` 等安全门禁只接受该范围的值 | [不受信任仓库](../part-10/05-untrusted-repositories.md) |
| `safe.directory` | 对不同操作系统 owner 的仓库添加精确访问例外的所有权门禁，不是代码安全判定 | [不受信任仓库](../part-10/05-untrusted-repositories.md) |
| filter driver | 由 attribute 选择、在 add/checkout 等路径转换 blob 内容的本机配置程序 | [不受信任仓库](../part-10/05-untrusted-repositories.md) |
| Git hook | 在特定 Git 生命周期点由本地 hooks 目录或 `core.hooksPath` 选择执行的程序 | [不受信任仓库](../part-10/05-untrusted-repositories.md) |
| gitlink | Superproject tree 中 mode 为 `160000`、记录另一个仓库预期 submodule commit OID 的条目 | [Submodule 与 subtree](../part-09/03-submodule-and-subtree.md) |
| 超级项目 | Tree 中以 gitlink 嵌入一个或多个 submodule 的外层仓库 | [Submodule 与 subtree](../part-09/03-submodule-and-subtree.md) |
| submodule | 拥有独立对象库与历史、由超级项目 gitlink 固定到精确 commit 的嵌套仓库 | [Submodule 与 subtree](../part-09/03-submodule-and-subtree.md) |
| subtree | 把另一个项目的文件与可选历史导入当前仓库普通 prefix，并可 pull/split 同步的组合模型 | [Submodule 与 subtree](../part-09/03-submodule-and-subtree.md) |
| commit-graph file | 序列化 commit 拓扑、generation data 与可选 changed-path Bloom filters 的辅助索引；不等同于逻辑提交图 | [性能与维护基线](../part-09/01-measure-before-optimizing.md) |
| MIDX | 为一个 object directory 中多个 pack 建立统一对象索引的 multi-pack-index | [性能与维护基线](../part-09/01-measure-before-optimizing.md) |
| bitmap | 预计算部分对象可达集合、用于加速对象枚举和 pack 生成的辅助数据 | [性能与维护基线](../part-09/01-measure-before-optimizing.md) |
| Trace2 | Git 输出结构化命令、region、child process 与性能事件的诊断框架 | [性能与维护基线](../part-09/01-measure-before-optimizing.md) |
| sparse-checkout | 通过规则选择哪些 tracked paths 展开到工作区，不改变提交 tree 和对象身份 | [稀疏与部分工作流](../part-09/04-sparse-partial-workflows.md) |
| sparse-index | 用 sparse-directory entry 表示未展开目录的 index 表示优化，不改变候选 tree | [稀疏与部分工作流](../part-09/04-sparse-partial-workflows.md) |
| partial clone | 由 promisor remote 和 object filter 延迟取得部分 Git 对象的克隆 | [稀疏与部分工作流](../part-09/04-sparse-partial-workflows.md) |
| shallow clone | 通过 shallow boundary 截断祖先历史的克隆，不能把缺失祖先当作不存在 | [稀疏与部分工作流](../part-09/04-sparse-partial-workflows.md) |
| 构建图 | 把组件、直接/传递依赖、生成输入、测试、制品和所有权连接起来的可版本化关系 | [Monorepo 拓扑治理](../part-09/05-monorepo-topology-and-ownership.md) |
| 变更闭包 | 从直接 changed paths 沿反向依赖、生成输入和发布单元扩展出的受影响组件集合 | [Monorepo 拓扑治理](../part-09/05-monorepo-topology-and-ownership.md) |
| 运行所有权 | 对制品、部署、告警、数据和回退承担责任的稳定主体关系，不等于源码目录 owner | [Monorepo 拓扑治理](../part-09/05-monorepo-topology-and-ownership.md) |
| Monorepo | 在一个 Git 对象/引用边界内维护多个组件，并通过构建图和所有权治理变更的仓库拓扑 | [Monorepo 拓扑治理](../part-09/05-monorepo-topology-and-ownership.md) |
| Git LFS pointer | Git blob 中保存的规范文本，记录外部 payload 的 SHA-256 OID、字节数和规范版本；不是文件本体 | [二进制与 Git LFS](../part-09/02-binary-and-lfs.md) |
| LFS payload | Pointer 引用的原始文件字节，保存在本地 LFS cache、LFS 服务或备份中，不属于普通 Git 对象图 | [二进制与 Git LFS](../part-09/02-binary-and-lfs.md) |
| 水合 | Filter/checkout 用本地或远端 LFS payload 把工作区 pointer 替换为原始文件字节的过程 | [二进制与 Git LFS](../part-09/02-binary-and-lfs.md) |
| LFS 文件锁 | LFS 服务按仓库路径维护的协作记录，可由客户端或服务端策略检查；不是 Git 对象，也不提供二进制合并 | [二进制与 Git LFS](../part-09/02-binary-and-lfs.md) |
| 凭据撤销 | 在签发或身份控制面使旧 token、key、密码、证书或 session 失去认证/授权能力 | [凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md) |
| 凭据轮换 | 向合法消费者分发并验证替代凭据，同时撤销旧值和清理不再需要副本的生命周期操作 | [凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md) |
| 历史清理 | 重写 Git refs 可达的 commits/trees/blobs 以降低敏感内容继续传播；不能替代凭据撤销 | [凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md) |
| 重新污染 | 清理前 clone、ref、cache 或镜像把旧 ancestry 再次合并或推入已改写仓库 | [凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md) |
| 机器主体 | 代表自动化而非自然人的稳定 principal，具有独立所有者、权限和生命周期 | [最小权限机器身份](../part-10/02-machine-identities.md) |
| 工作负载身份 | 签发器依据 job、仓库、workflow、ref、环境等运行声明识别一次自动化工作负载的机制 | [最小权限机器身份](../part-10/02-machine-identities.md) |
| 派生凭据 | 由根身份或 subject token 按资源、动作、上下文和时间约束签发的运行凭据 | [最小权限机器身份](../part-10/02-machine-identities.md) |
| Break-glass 身份 | 常规控制面故障时按预定义事故等级启用、独立保管且使用即告警的紧急身份 | [最小权限机器身份](../part-10/02-machine-identities.md) |
| 依赖 selector | 人或配置声明的 branch、tag、版本范围、URL 等选择条件，本身可以解析到不同内容 | [第三方 CI 依赖](../part-10/03-ci-dependency-supply-chain.md) |
| 解析后依赖 | Resolver 在一次流水线尝试中为 selector 选择的精确 commit、digest 或包身份 | [第三方 CI 依赖](../part-10/03-ci-dependency-supply-chain.md) |
| 传递依赖 | 直接依赖继续声明、下载或运行时发现的依赖；顶层 commit 固定不保证它不漂移 | [第三方 CI 依赖](../part-10/03-ci-dependency-supply-chain.md) |
| 来源证明 | 把产物 digest 与 builder、构建定义、参数、解析依赖和 invocation 关联起来的可验证陈述 | [第三方 CI 依赖](../part-10/03-ci-dependency-supply-chain.md) |
| 扫描输入范围 | 一次秘密或内容扫描实际读取的工作区、差异、refs、对象、外部副本和日志集合 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| 可达历史扫描 | 针对固定 refs 能到达的 commits、trees、blobs 和消息执行的扫描；不自动覆盖 reflog 或平台副本 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| 内容语义安全 | 对脚本、symlink、压缩包、路径、依赖和资源消耗等下游行为的安全判断；不是对象哈希完整性 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| `export-ignore` | `.gitattributes` 中只影响 `git archive` 当前 tree 导出范围的属性，不删除 Git 历史 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| 源码归档 | 从一个固定 tree 生成的文件字节副本，通常不含 `.git` 历史；仍需独立扫描和摘要核验 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| bundle | 包含指定 refs 可达 Git 对象、可供其他仓库导入的离线传输副本；可能保留旧历史 | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| 现场保护 | 在恢复或分析前停止、隔离可能改变工作区、index、refs、reflog、对象库和外部控制面的活动 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 原始证据 | 从受控时间点保存、限制写入并以摘要和保管记录固定的源字节/平台记录；区别于命令输出等派生物 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| Git 逻辑快照 | 从固定现场派生的 HEAD、refs、index、diff、reflog、配置、对象统计和完整性输出集合 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 恢复工作副本 | 从受控证据派生、允许试验且失败后可以销毁重建的仓库副本 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| common Git directory | 多个 linked worktree 共享 refs、对象库等仓库级元数据的目录；不同于每个 worktree 的 Git directory | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| alternates | 让一个对象库从其他 object directories 读取对象的机制；备份和取证必须同时盘点外部依赖 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 保管链 | 记录证据来源、采集者、时间、摘要、每次访问/移交、派生物和销毁批准的可审计链条 | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| dangling object | 不被其他对象直接引用的对象，常作为不可达对象岛的候选末端；不等于损坏 | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| missing object | 解析需要的 OID 在当前对象来源中不可读或不存在；需区分 loose/pack/alternate/promisor 边界 | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| corrupt object | 对象文件、pack 或解压内容不能通过 Git 格式/哈希检查的状态 | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| alternate object store | 通过 `objects/info/alternates` 或环境变量让仓库从外部 object directory 读取对象的机制 | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| replace ref | `refs/replace/` 下把原 OID 映射到替代对象、改变部分 Git 命令解释的本地引用 | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| pack index | `.idx` 文件，把对象 OID 映射到 pack offset 并支持校验和查找 | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| blame 归因 | 把候选 tree 中每一行关联到可见历史里最近写入该行的提交；不是业务责任或决策证明 | [历史归因](../part-11/03-history-attribution.md) |
| pickaxe | `git log -S`/`-G` 从提交差异中按字符串数量变化或差异行正则缩小候选的搜索机制 | [历史归因](../part-11/03-history-attribution.md) |
| rename detection | 比较前后 tree 时根据内容相似度推断 delete/add 可能是 rename/copy 的启发式过程；提交不保存 rename 事件 | [历史归因](../part-11/03-history-attribution.md) |
| first-parent history | 只沿每个 merge commit 第一父提交回溯的主线合入视图，会省略被合入分支的内部提交 | [历史归因](../part-11/03-history-attribution.md) |
| RPO | Recovery Point Objective，可接受的数据丢失上限，应分别约束 Git refs、LFS、平台元数据和制品 | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| RTO | Recovery Time Objective，从宣布故障到恢复并验收目标服务的时间上限 | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| 恢复点 | 由 Git refs/对象、外部 payload、平台导出、制品、策略和密钥版本共同描述的可恢复时间状态 | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| Git bundle | 携带 advertised refs、pack 和可选 prerequisite commits 的逻辑传输/归档文件 | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| Git mirror | 把源 refs namespace 强制映射到 bare 仓库并可传播删除的同步拓扑；本身不提供历史保留策略 | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| OID 保持迁移 | 在对象格式兼容且 commit/tag 原始字节不变时，把同一对象传到目标并保持其对象 ID 的迁移 | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| 身份映射 | 把源 author/committer、平台账号和评审主体分别关联到目标 principal，并记录冲突与未知项的迁移控制表 | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| cutover | 冻结源端、完成最终同步和验收、把读写权威切换到目标端的一组受控事件 | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| 写入围栏 | 阻止旧端或非权威端继续接受 push、合并、标签、LFS、评审或自动化写入的控制措施 | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| 复制滞后 | 副本相对权威端在 refs、对象或外部事件上的已知差距；对象闭包完整不代表副本最新 | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| donor | 提供缺失 commit/tree/blob 或增量历史的可信来源仓库；必须独立验证来源和对象闭包 | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| 故障转移 | 在旧权威端围栏、候选恢复点验收后，将服务读写权威提升到另一个故障域的受控过程 | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| 安全回切 | 新权威运行后，把旧主隔离、重新播种为副本并经再次审批后切换的过程，不是撤销 DNS | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| 仓库资产 ID | 组织内部不可复用、不会随仓库改名或跨平台迁移而变化的资产标识；平台 repository ID 与 URL 是它的可变 locator | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 双重所有权 | 把业务用途、保留和风险接受责任与代码健康、权限、CI、恢复和事故响应责任分别交给业务 owner 与技术 owner | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 声明状态 | Owner、数据分类、生命周期和默认分支等经批准的治理意图；必须与平台、身份、Git 和备份系统的观测事实对账 | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| pending_delete | 仓库保持只读、继续观察消费者与保留要求，并等待删除门禁满足的可撤销状态 | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 删除 tombstone | 仓库删除后独立保留的最小审计记录，包含稳定资产 ID、原 locator、批准、处置范围和执行时间，不等同于源码备份 | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 有效权限 | 组织/团队继承、仓库直授、应用、key 与临时例外形成候选授权后，再与主体状态、资源、动作、上下文和时间门禁求交得到的实际能力 | [权限生命周期](../part-12/02-access-lifecycle.md) |
| 直接授权 | 不通过受治理群组而直接把仓库或平台能力授予单个 principal 的路径；应登记理由、批准、到期和替代方案 | [权限生命周期](../part-12/02-access-lifecycle.md) |
| 权限认证 | 资源 owner 定期比较批准能力与实际有效授权，并对新增、删除、扩大、过期、未知来源和采集缺口分别作出决定的过程 | [权限生命周期](../part-12/02-access-lifecycle.md) |
| inconclusive | 因 API 可见性、分页、身份解析或采集失败而无法证明合规与否的治理结果；不能按 pass 处理 | [权限生命周期](../part-12/02-access-lifecycle.md) |
| Break-glass | 常规控制面不可用或事故需要时，经明确批准、限资源/动作/时间、使用即告警并在事后撤销复盘的紧急访问状态 | [权限生命周期](../part-12/02-access-lifecycle.md) |
| 策略摘要 | 对一份不可变策略内容计算的 digest，用于把求值决定、平台部署与回退版本关联到精确字节 | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| would-deny | 规则在 audit/warn 模式发现要求不满足但尚未阻止动作的结果；它是待处置发现，不是 pass | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| Canary 推广 | 先在经批准、具代表性的有限仓库 cohort 强制执行规则，再按证据与停止条件扩大范围 | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| 策略例外 | 仅在指定主体、资源、动作和期限内豁免明确 rule ID，并绑定批准与补偿控制的独立治理对象 | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| 策略漂移 | 已批准策略声明与平台观测配置或实际行为之间出现未经解释的差异 | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| Provider event time | 事件来源声明其观察或处理动作的时间；需保留原时区/offset，不能与 commit 对象时间或采集时间混用 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| Collector received time | 组织采集器收到事件的时间，用于测量延迟、乱序和中断，不等于动作发生时间 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| 原始审计事件 | 来源返回的原始字节或流记录及其采集元数据；规范化、时区转换和脱敏必须生成可回链派生物 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| 审计缺口 | 查询、权限、分页、sequence、schema 或采集中断导致无法证明某段来源/时段完整的已登记范围 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| Legal hold | 经授权暂停指定证据按常规保留计划销毁的状态；解除后仍需重新计算其他保留义务 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| 调查包 | 固定查询与数据 snapshot 后导出的原始/规范化事件、schema、缺口、manifest 和保管记录集合 | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| 仓库健康快照 | 在固定时间、资产、权威端、指标口径和采集权限下记录完整性、可用性、时延、新鲜度、容量、治理与恢复状态的观测集合 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| Headroom days | 在口径稳定且增长为正时，扣除安全余量后按已观测趋势估算距离容量阈值的时间；不是确定耗尽日期 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| Scratch capacity | Repack、迁移、恢复或导出期间为新旧数据并存、索引、临时文件和失败重试预留的独立峰值空间 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| 维护窗口 | 对具体资产和任务定义前置门禁、容量/互斥、开始停止条件、验证、回退和责任人的受控变更时段 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| 共同故障域 | 多个仓库共享 object pool、存储卷、平台节点、LFS、备份、runner 或身份控制面而形成的相关失效边界 | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| Playbook | 为一类事件规定触发、分流、决策权、状态转换、场景分支和停止/升级条件的组织级故障手册 | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| Incident Commander | 对事件严重度、当前目标、优先级、状态转换、停止/升级和交接承担单一最终决定权的当班角色 | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 恢复状态门禁 | 只有角色、围栏、证据、恢复目标、候选验收和批准等前置条件有证据满足时才允许进入下一状态的控制 | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| Stop condition | 遇到 OID 不符、旧端仍可写、证据缺口、身份失控或范围外影响等情况时，要求暂停并升级而非继续尝试的预定义条件 | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| Inject | 演练负责人按一致底层真相注入给参与者的信息或变化，用于观察发现、判断、通信和停止能力，不用于制造无解谜题 | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 最小排障证据集 | 在不主动连接远端和不执行修复的第一轮，固定环境、布局、HEAD、操作状态、index、refs、图、差异、退出码与缺口的本地材料 | [先别急着修](../part-13/01-evidence-first.md) |
| 第一处破坏的不变量 | 沿环境、操作状态、工作区/index、refs/对象、传输、平台和外部数据面向外检查时，最先被证据证明不满足的预期状态 | [先别急着修](../part-13/01-evidence-first.md) |
| 动作卡 | 在修复前记录假设、前置条件、动作、应改变/不得改变的状态、停止条件、验证和恢复路径的执行契约 | [先别急着修](../part-13/01-evidence-first.md) |
| 路径存在性 | 分别判断目标路径是否存在于文件系统工作区、index、某个提交 tree，以及所指 blob/gitlink/外部 payload 是否可读 | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| skip-worktree | index 路径标志，常由 sparse-checkout 管理，使未展开路径不按普通工作区缺失处理；不是访问控制或通用忽略机制 | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 恢复引用 | 在确认候选对象后先创建于隔离命名空间、用于保持可达和审查而不立即移动正式分支的 ref | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 浅边界 | Shallow repository 把指定提交暂时视作历史根、其父祖先未在本地历史中展开的显式边界 | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 非快进拒绝 | 远端当前 OID 不是待推送 OID 的祖先，直接更新会让已公开历史从目标 ref 不再可达，因此接收端拒绝普通 push | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| 认证 | 远端确认请求对应哪个主体、凭据或委托身份的过程；不等于该主体对资源和动作有授权 | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| 授权 | 服务端依据主体、资源、动作、上下文和时间判断是否允许一次读取或写入 | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| 接收端 hook | 在 receive-pack 处理 ref 更新时执行的服务端脚本入口；本地 bare hook 可验证有限拒写逻辑，不代表托管平台控制面 | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| 性能 workload | 固定命令、输入规模、仓库拓扑、缓存状态、并发和外部依赖后，可重复比较的工作负载定义 | [性能和容量故障](../part-13/04-performance-and-capacity-failures.md) |
| Trace2 | Git 输出结构化命令、region、子进程和退出事件的诊断框架；事件本身不等于根因或优化收益 | [性能和容量故障](../part-13/04-performance-and-capacity-failures.md) |
| Headroom | 当前用量到硬限制之间按固定口径和观测增长估计的可用余量；不是确定耗尽日期 | [性能和容量故障](../part-13/04-performance-and-capacity-failures.md) |
| Scratch space | Repack、维护、迁移或恢复期间为新旧数据、索引、临时文件和失败重试预留的峰值空间 | [性能和容量故障](../part-13/04-performance-and-capacity-failures.md) |
| 逻辑不变量 | 维护前后必须保持的 refs、HEAD、tree、可达对象集合、工作区和完整性条件 | [性能和容量故障](../part-13/04-performance-and-capacity-failures.md) |
| Pointer/payload 分离 | Git 中保存 pointer blob，而原始二进制由 LFS cache、服务或备份按独立 OID 保存的边界 | [LFS、子模块与 CI clone 异常](../part-13/05-lfs-submodule-ci-failures.md) |
| Gitlink | Superproject tree 中 mode 160000、指向外部仓库 commit 的条目；不包含嵌套仓库 tree | [LFS、子模块与 CI clone 异常](../part-13/05-lfs-submodule-ci-failures.md) |
| 依赖发布顺序 | 先让 submodule commit 在读取者可见的远端发布，再发布引用该 commit 的父仓库 gitlink | [LFS、子模块与 CI clone 异常](../part-13/05-lfs-submodule-ci-failures.md) |
| CI candidate gate | 在构建前核对可信候选 commit、实际 HEAD、历史/过滤范围、LFS 水合、gitlink 和构建输入清单的门禁 | [LFS、子模块与 CI clone 异常](../part-13/05-lfs-submodule-ci-failures.md) |
| 签名存在性 | 判断 commit 或 tag 对象是否携带当前格式的签名；不等于密码学有效或组织信任 | [签名无法验证与密钥状态异常](../part-13/06-signature-verification-failures.md) |
| 签名信任根 | 验证器从候选代码之外取得的公钥、allowed signers、证书链或撤销策略集合 | [签名无法验证与密钥状态异常](../part-13/06-signature-verification-failures.md) |
| 签名目标核对 | 同时比较 tag object、剥离后的 target OID、候选 commit、制品和部署记录的过程 | [签名无法验证与密钥状态异常](../part-13/06-signature-verification-failures.md) |
