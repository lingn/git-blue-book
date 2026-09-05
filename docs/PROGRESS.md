# v2 重构进度

> 最近更新：2026-09-05。状态只描述已经落盘并验证的工作。

## 当前里程碑

阶段 0 已完成。现有基础教程和实验保持可用，v2 第二篇补充、第七篇首批章节、第六篇与第八至十三篇已经落入权威路径，其余旧目录按逐章迁移表继续收束。当前共有 151 个公开页面、21 个兼容迁移页和 54 组隔离实验；正文尚未达到出版标准。

## 已完成

- [x] 盘点 79 个公开页面和 8 组隔离实验。
- [x] 执行原始基线 `./scripts/verify-all.sh`，全部通过。
- [x] 建立 `docs/MASTER-OUTLINE.md`，覆盖个人、团队、底层原理、平台、CI/CD、规模、安全、恢复、迁移和治理。
- [x] 建立 `docs/AUDIT-2026-08-20.md`，记录资产、缺口和成熟度判断。
- [x] 建立 `docs/REWRITE-ROADMAP.md`，定义七个阶段和逐章循环。
- [x] 将验收口径从“首版页面完整”升级为“内容、证据、实验与出版”四类门槛。
- [x] 实质重写第二篇工作区、index 与 `HEAD` 操作模型，补齐 ` M`/`M `/`MM` 状态矩阵、`git diff HEAD`、未跟踪/忽略边界和取消暂存恢复。
- [x] 重写第二篇仓库发现与初始化章节，补齐执行位置、父目录发现、嵌套仓库、初始分支、裸仓库和分离 Git 目录边界。
- [x] 重写第二篇状态章节，补齐短状态两列、porcelain/NUL、未跟踪扫描、忽略可见性、上游缓存和锁/所有权故障分流。
- [x] 重写第二篇路径选择章节，补齐显式 pathspec、子目录 `add .` 范围、`-u`/`-A`、交互式 patch、intent-to-add、删除和 filter 失败恢复。
- [x] 重写第二篇差异审查章节，补齐三种比较边界、退出码、空白检查、二进制、未跟踪、属性、外部 diff 和提交前证据顺序。
- [x] 重写第二篇历史阅读章节，补齐本地 refs 范围、`A..B`/`A...B`、父提交、路径追踪、浅克隆和远程平台证据边界。
- [x] 重写第二篇综合练习，贯通混合改动拆分、忽略规则、误暂存恢复、`MM` 状态、历史验收和失败分流。
- [x] 扩展 `verify-part-2.sh`，新增初始化前后发现、初始分支、子目录 `add .` 路径范围、历史范围、路径历史和差异检查断言。
- [x] 重写第三篇提交图、分支、`HEAD`、切换、第一次合并和合并形状章节，补齐父提交、可达性、`merge-base`、分离 `HEAD`、工作区保护、快进/非快进策略和合并父顺序。
- [x] 重写第三篇冲突模型与完整解决流程，补齐三方输入、ours/theirs 视角、`MERGE_HEAD`、index 未合并状态、abort/continue、业务验收和报告证据。
- [x] 重写第三篇标签章节与综合练习，补齐轻量/附注/签名标签边界、target OID、标签竞态、紧急修复插入功能开发和本地/远程发布分层。
- [x] 扩展第三篇分支、合并和冲突实验，新增根提交、祖先关系、分离 `HEAD`、ff-only 拒绝、合并父顺序和轻量标签断言。
- [x] 重写第四篇远程模型、clone、remote、fetch、远程跟踪、pull 和 push 章节，分开服务器 refs、本地远程跟踪缓存、本地工作分支、对象传输、认证、授权和平台控制面。
- [x] 扩展远程基础实验，验证 clone 初始 OID、remote URL、fetch 不移动本地分支、`FETCH_HEAD`、upstream 配置和附注标签 target。
- [x] 重写第四篇 push 拒绝、评审准备、cherry-pick 和综合练习，补齐非快进因果链、候选/base OID、共享历史边界、来源/目标提交和评审证据。
- [x] 重写第四篇 rebase 模型与安全工作流，补齐恢复引用、range-diff、`--onto`、冲突状态、continue/skip/abort/quit、自动暂存、签名与评审绑定及显式租约边界。
- [x] 重写第六篇 stash、worktree 和 bisect 章节，补齐临时对象与 `refs/stash`、linked worktree 共享/隔离、good/bad/skip 判定契约、恢复边界和外部依赖限制。
- [x] 扩展第六篇工程实验，新增 stash 对象类型、worktree common directory、工作树清单和 bisect 判定轨迹断言。
- [x] 重写第六篇历史检索和热修复章节，补齐 blame/pickaxe/rename/copy/merge 父视角的证据边界、source/target/picked OID、依赖闭包、部署范围和共享发布回退。
- [x] 重写第六篇冲突报告、提交质量和统一排障章节，补齐 merge/rebase/squash/cherry-pick 报告差异、提交原子性、身份与 hook 边界、命令副作用、证据包和故障分流。
- [x] 重写第五篇撤销入口决策矩阵、restore、unstage、amend 内容、amend 说明和公开历史章节，补齐 source/target、index/工作区保护、OID 重建、恢复引用、共享边界和 revert/租约分流。
- [x] 重写第五篇综合恢复练习，贯通工作区丢弃、取消暂存、私有 amend、共享 revert、分支恢复、远程租约操作卡和进行中状态机，并修正连续执行前置条件。
- [x] 新增第五篇提交改写操作手册，贯通未推送和已推送 amend、提交说明修订、合并、拆分、删除、显式租约与共享历史边界。
- [x] 新增远端历史改写事故章与隔离实验，复现 `ahead 3, behind 9`，验证 forced-update、补丁等价、rebase abort reflog 和恢复分支同步。
- [x] 重写第一篇五个基础页面，补齐版本控制与备份边界、方案比较维度、Git 设计约束、快照/差异/物理存储分层和可执行决策练习。
- [x] 同步根 README、全书阅读路线和受保护分支职责链接，修正 129 个公开页面与 52 组实验的当前统计，并增加基础、发布、规模、安全、取证、治理和排障角色路径。
- [x] 修正阅读路线中现行第五/六篇兼容入口与第七篇 v2 目标篇的迁移标识，避免撤销与恢复主题出现无说明的重复入口。
- [x] 完成第一批旧正文迁移：第六篇发布、CI 证据链、CI 触发与队列三页改为 `legacy-redirect` 兼容入口，权威内容收束到第八篇并更新 glossary、场景索引、治理章和子模块章入站链接。
- [x] 扩写第二篇忽略与属性章节，补齐 `.gitignore` 规则优先级、已跟踪文件、`.gitattributes`、换行规范化和 filter 选择器边界。
- [x] 重写第二篇身份与提交章节，补齐配置来源、条件 include、author/committer 与认证边界、local hook 拒绝、空提交和 `--no-verify` 风险。
- [x] 重构对象模型章节，补齐 tag 对象、引用、index、可达性、对象格式和物理存储边界。
- [x] 新增对象模型隔离实验并接入总验证，实验总数增至 9 组。
- [x] 重构显式租约章节，补齐条件更新、后台 fetch 竞态、拒绝分流和错误更新恢复。
- [x] 将显式租约实验从综合恢复脚本拆出，覆盖拒绝、协调更新和恢复，实验总数增至 10 组。
- [x] 重构 reset 与 reflog 章节，补齐分离 HEAD、ORIG_HEAD、路径形式、未跟踪路径和日志过期边界。
- [x] 拆出 reset/reflog 隔离实验，覆盖三模式、路径形式和恢复引用，实验总数增至 11 组。
- [x] 重构交互式 rebase 章节，补齐 todo 动作、拆分、冲突方向、空提交、range-diff 和签名边界。
- [x] 拆出交互式 rebase 隔离实验，覆盖成功改写、提交拆分、冲突和中止，实验总数增至 12 组。
- [x] 重构 revert 章节，补齐冲突序列、批量撤销、merge mainline、再次启用和运行状态边界。
- [x] 重构综合恢复案例，按进行中操作、本地引用事故和远端误更新分流。
- [x] 用独立 revert 实验替换旧综合脚本，覆盖普通、冲突和 merge 三条路径。
- [x] 新增远程 URL、传输协议与认证章节，区分 Git wire protocol、SSH/HTTPS、本地传输、身份和授权层。
- [x] 新增传输与凭据隔离实验，覆盖 `file://` 的 clone/fetch/push 和 credential helper 的 approve/fill/reject，实验总数增至 13 组。
- [x] 新增 refspec、协商与受限克隆章节，区分引用范围、祖先深度、对象过滤和工作区筛选。
- [x] 新增 refspec/clone 隔离实验，覆盖负 refspec、浅克隆恢复、部分克隆按需取对象和 sparse-checkout，实验总数增至 14 组。
- [x] 建立 `docs/CHAPTER-MIGRATION-MAP.md`，为当前 83 个公开页面登记 v2 目标、合并/拆分动作和旧链接门禁。
- [x] 新增 CI/CD 证据链章节，贯通候选提交、checkout、流水线版本、制品摘要、部署记录和运行版本。
- [x] 新增 CI 证据隔离实验，覆盖分离 HEAD、合并候选、可重复源码归档、证据清单和部署摘要恢复，实验总数增至 15 组。
- [x] 重构发布章节，补齐候选提交固定、标签竞态与核验、制品提升、部署回退、数据库兼容和长任务边界。
- [x] 新增 CI 触发与合并队列章节，建立事件、候选、路径策略、检查结果和条件引用更新状态机。
- [x] 新增 CI 队列隔离实验，覆盖路径 diff、过期候选、队列顺序和条件 `update-ref`，实验总数增至 16 组。
- [x] 新增复杂冲突章节，补齐 `ort`、index stage、`AUTO_MERGE`、rename/delete、目录重命名和 rerere 的工程边界。
- [x] 新增复杂冲突隔离实验，覆盖 abort、rerere 复用与忘记、路径冲突和最终 tree，实验总数增至 17 组。
- [x] 直接建立 v2 第十篇入口并新增签名与信任策略章节，区分对象签名、身份映射、组织授权和供应链证据。
- [x] 新增 SSH 对象签名隔离实验，覆盖签名 commit/tag、无签名拒绝、候选自授权信任策略风险，以及候选之外的 release 授权投影，实验总数增至 18 组。
- [x] 新增不受信任仓库章节，区分 clone 对象传输、local config、tracked selectors 与程序实际执行。
- [x] 新增仓库执行边界实验，覆盖 owner/bare 门禁、filters、hooks、clone 和递归协议，实验总数增至 19 组。
- [x] 直接建立 v2 第九篇入口并新增性能与维护基线章节，先测量历史、对象、refs、index、工作区和网络，再选择优化。
- [x] 新增性能机制隔离实验，覆盖规模指标、Trace2、commit-graph、MIDX bitmap 和维护正确性，实验总数增至 20 组。
- [x] 新增二进制与 Git LFS 章节，建立 Git pointer blob、LFS payload、cache/服务和工作区水合的分层模型。
- [x] 新增 LFS pointer 模型隔离实验，验证外部对象缺失时 required smudge 失败而 Git `fsck` 仍可通过，实验总数增至 21 组。
- [x] 新增 submodule 与 subtree 章节，覆盖 gitlink、递归检出、跨仓库发布顺序、普通 tree 导入、split 与拓扑迁移。
- [x] 新增仓库组合隔离实验，覆盖未发布 submodule commit 的 push/clone 故障以及 subtree pull/split，实验总数增至 22 组。
- [x] 新增凭据泄漏与历史清理章节，区分签发器撤销、Git 可达历史、对象物理保留和外部副本处置。
- [x] 新增敏感历史边界实验，覆盖部分 ref 漏改、`refs/original`/GC、远端残留和旧 clone 重新污染，实验总数增至 23 组。
- [x] 新增最小权限机器身份章节，建立 principal、工作负载上下文、凭据、授权、会话与审计六层模型。
- [x] 新增机器凭据边界实验，覆盖 host/path 匹配、按路径拒绝，以及 remote URL/Authorization header 的本地持久化，实验总数增至 24 组。
- [x] 新增第三方 CI 依赖与来源证明章节，建立 selector、解析身份、实际字节、传递依赖、执行权限和 provenance 的分层模型。
- [x] 新增 CI 依赖固定实验，覆盖 tag 强制移动、完整 commit lock、传递 branch 漂移和显式 lock 更新，实验总数增至 25 组。

## 正在处理

- [x] 新写秘密扫描、恶意对象与归档导出章节，区分工作区/diff/可达 refs/reflog/LFS/CI 副本，补齐 `fsck` 完整性边界、路径与对象语义安全、`export-ignore`、bundle 和归档摘要验证；新增隔离实验，实验总数增至 26 组。
- [x] 建立第十一篇入口并新增事故现场保护与证据采集章节，区分文件系统原始现场、Git 逻辑快照、平台控制面和运行环境；新增采集非变异、clone 遗漏和摘要篡改检测实验，实验总数增至 27 组。
- [x] 新增对象取证与恢复章节，区分 fsck 根、可达/不可达/dangling/missing/corrupt、lost-found、alternate/promisor、replace refs、pack/idx 和 donor 恢复；新增四类对象故障隔离实验，实验总数增至 28 组。
- [x] 新增历史归因章节，把 blame、pickaxe、rename/copy、first-parent、merge 逐父 diff 与评审/CI/部署证据边界接成调查链；新增归因清单篡改检测实验，实验总数增至 29 组。
- [x] 新增 bundle、mirror 与备份恢复演练章节，区分完整/增量 prerequisite、mirror prune、物理快照、LFS/submodule/平台控制面和空环境验收；新增备份恢复隔离实验，实验总数增至 30 组。
- [x] 新增仓库与托管平台迁移章节，区分 OID 保持/重写、SVN 历史模型、身份映射、LFS/submodule、平台数据、权限/CI 和单一写入 cutover；新增全 refs 迁移与源端围栏实验，实验总数增至 31 组。
- [x] 新增故障转移与安全回切章节，区分不可用/损坏/安全/控制面故障，覆盖复制滞后、donor、条件提升、只读验收、旧主围栏与重播种；新增多副本切换实验，实验总数增至 32 组。
- [x] 建立第十二篇入口并新增仓库生命周期章节，覆盖稳定资产 ID、业务/技术双重 owner、创建基线、组织转移、只读归档、待删除观察窗口与恢复；修正 TSV 空字段负例并新增治理登记、归档围栏、摘要和恢复实验，实验总数增至 33 组。
- [x] 新增权限生命周期章节，建立有效授权并集/门禁模型，覆盖入职、转岗、离职、外部协作者、机器 owner、权限认证与 break-glass；新增三态对账和接收端 ref 权限实验，实验总数增至 34 组。
- [x] 新增规则集与例外治理章节，定义 scope、累积/deny-dominant 组合、audit/canary 推广、窄例外、策略即代码信任边界、漂移与条件回退；新增确定性求值和 receive 门禁实验，实验总数增至 35 组。
- [x] 新增审计日志与证据留存章节，覆盖事件/主体/old-new OID、多时钟、覆盖矩阵、cursor/sequence/schema 完整性、原始与规范化证据、访问/留存/legal hold、调查包和审计灾备；新增接收事件与调查包实验，实验总数增至 36 组。
- [x] 新增仓库健康、容量预算与维护窗口章节，建立完整性/可用性/时延/新鲜度/容量/治理/恢复七维模型，覆盖分层预算、headroom、SLI/SLO、共同故障域、scratch/互斥/事故门禁和维护后不变量；新增健康与维护实验，实验总数增至 37 组。
- [x] 新增组织级故障手册与恢复演练章节，建立事件分类、单一 IC、组织状态门禁、分层验收、停止条件、inject 与行动闭环；新增 bundle 候选恢复、条件提升、只读验收和单一写入权威实验，实验总数增至 38 组。
- [x] 建立第十三篇入口并实质性重构“证据优先”首章，建立六坐标报障、八层诊断、普通排障/安全/取证/组织事件分流、命令副作用、三态证据包与动作卡；新增冲突现场无变异采集、脱敏、abort 恢复和 fetch 写入实验，实验总数增至 39 组。
- [x] 新增文件/提交消失症状章，分开 worktree/index/tree/blob/外部 payload 与 log/ref/reflog/object source，覆盖精确路径、ignore/sparse、restore 来源、recovery ref、浅边界和不可恢复范围；新增四类路径与三类提交可见性实验，实验总数增至 40 组。
- [x] 新增 push/认证/权限失败症状章，分层 endpoint、服务器身份、客户端认证、仓库授权、Git 引用规则和平台控制面；新增非快进、fetch 副作用、保护 ref、review ref 和 URL 回滚实验，实验总数增至 41 组。
- [x] 新增性能/容量故障症状章，按 `status`、`log`、switch/checkout、clone/fetch 分流 workload、规模、缓存和 Trace2 证据，区分性能/容量/完整性/证据缺口；新增辅助索引、受控 maintenance、不变量和容量四态实验，实验总数增至 42 组。
- [x] 新增 LFS/子模块/CI clone 故障症状章，分开 pointer/payload、gitlink/嵌套仓库和 candidate/checkout/构建输入，覆盖 OID 保留、依赖发布顺序、浅/部分克隆与 cache 边界；新增外部依赖隔离实验，实验总数增至 43 组。
- [x] 新增签名验证/密钥状态故障症状章，分开签名存在、密码学、key/principal、有效期/撤销和组织授权，覆盖候选之外信任根、tag target、历史改写与 CI/发布门禁；新增签名排障隔离实验，回归后总计 116 个公开页面与 44 组隔离实验。
- [x] 新增远程引用漂移故障症状章，分开远端 refs、本地远程跟踪缓存、上游配置和平台控制面，覆盖分支重命名、prune、默认分支 symbolic ref、标签改指向、隐藏/权限边界和查询竞态；新增远程引用隔离实验。
- [x] 新增仓库损坏、锁文件和并发故障症状章，分开活跃/残留 lock、expected-old 引用竞争、对象/pack 完整性、linked worktree 和维护互斥，覆盖精确锁处理、fsck、pristine donor 恢复与停止条件；新增损坏与锁并发隔离实验，回归后总计 118 个公开页面与 46 组隔离实验。
- [x] 建立第八篇入口并新增“触发与 checkout”权威章节，收束事件快照、分离 HEAD、浅/部分克隆、路径过滤和不受信任代码的权限边界；候选对象与结果归属单独迁入下一章。
- [x] 新增第八篇“候选提交：把一次检查绑定到精确对象”权威章节，收束 feature/merge/squash/rebase/queue 候选、构造上下文、结果绑定、过期和条件更新；复用 CI 证据链与队列隔离实验。
- [x] 新增第八篇“从源码到运行版本：制品与部署证据链”权威章节，收束流水线/runner/依赖输入、制品摘要、发布引用、部署观测、数据库兼容和回退边界；复用 CI 证据链隔离实验，回归后总计 122 个公开页面与 46 组隔离实验。
- [x] 新增第八篇“可重复构建：把同一输入变成可比较的输出”权威章节，收束输入闭包、非确定性、构建清单、摘要比较、缓存边界和构建一次提升同一制品；新增源码归档与未声明输入检测实验，回归后总计 123 个公开页面与 47 组隔离实验。
- [x] 新增第八篇“发布引用与制品提升：把版本名、摘要和审批连起来”权威章节，收束附注 tag、远端核对、发布清单、审批、同名竞态和跨环境提升；新增发布 tag 与制品摘要隔离实验，回归后总计 124 个公开页面与 48 组隔离实验。
- [x] 新增第八篇“部署与回退：把 rollout 状态和恢复动作分开”权威章节，收束部署请求、实例实际 digest、金丝雀/蓝绿/滚动状态机、旧实例围栏、制品/配置/源码/数据库/数据回退和长任务边界；新增部署回退隔离实验，回归后总计 125 个公开页面与 49 组隔离实验。
- [x] 新增第八篇“数据库迁移：把 schema 状态纳入发布和回退决策”权威章节，收束迁移批次、实际 schema、兼容矩阵、expand/contract、可续跑回填、锁/事务边界、不可逆步骤和向前修复；新增数据库迁移隔离实验，回归后总计 126 个公开页面与 50 组隔离实验。
- [x] 新增第八篇“从事故到发布：把缓解、修复和复盘串成一条证据链”权威章节，收束证据冻结、缓解与修复状态机、bisect、hotfix/cherry-pick 来源与目标提交、共享依赖部署范围和关闭条件；新增事故到发布隔离实验，回归后总计 127 个公开页面与 51 组隔离实验。
- [x] 新增第九篇“稀疏与部分工作流：减少本地负担，不削弱候选证据”权威章节，收束 refspec、shallow、partial clone、sparse-checkout、sparse-index 的组合边界、受限输入契约和恢复顺序；复用受限克隆隔离实验，回归后总计 128 个公开页面与 51 组隔离实验。
- [x] 新增第九篇“Monorepo 拓扑治理：用构建图和所有权决定边界”权威章节，收束构建图、变更闭包、所有权/运行责任、路径过滤、原子变更、拆分/合并和恢复责任；新增 monorepo 拓扑隔离实验，回归后总计 129 个公开页面与 52 组隔离实验。
- [x] 建立 v2 第六篇权威目录并新增八章正文与综合场景，贯通分支状态、评审状态机、三种合并方式、可审查变更、所有权审批、必需检查、CI 身份、合并队列、受保护引用与窄例外。
- [x] 新增第六篇协作隔离实验，验证 merge、squash、rebase merge 的父关系、祖先关系、tree/OID 差异和 expected-old 引用更新；实验总数增至 53 组。
- [x] 将旧 `book/part-6/09-protected-branches.md` 拆分迁入 v2 第六篇和第十二篇，旧页改为 `legacy-redirect`，同步导航、迁移映射、事实登记和入站链接；回归后总计 139 个公开页面与 4 个兼容迁移页。
- [x] 将旧第六篇 bisect、历史检索和热修复正文分别收束到第十一篇历史归因与第八篇事故发布，旧页改为 `legacy-redirect`；第十一篇补充 bisect 的可重复判定、125/skip、工作区变异和“候选不等于根因”边界，导航和迁移映射同步完成。
- [x] 将旧第六篇冲突报告与提交质量正文分别收束到 v2 第六篇可审查变更和第二篇提交章节，旧页改为 `legacy-redirect`；补充冲突结果报告模板、候选重绑定和职责边界，导航、场景索引和迁移映射同步完成，兼容页总数增至 9 个。
- [x] 将旧第六篇通用排障与工程综合场景分别收束到第十三篇证据优先和第八篇事故到发布，旧页改为 `legacy-redirect`；保留症状索引、实验入口和平台行为边界，导航、迁移映射和进度记录同步完成，兼容页总数增至 11 个。
- [x] 将旧第六篇 stash 与 worktree 正文迁入 v2 第二篇补充，旧页改为 `legacy-redirect`；新增 v2 第二篇补充入口，保留临时对象、linked worktree、共享 refs、并发和恢复边界，导航与迁移映射同步完成，兼容页总数增至 13 个。
- [x] 建立 v2 第七篇入口并迁入状态/共享矩阵、工作区 restore、取消暂存三章；首批回归完成后旧页已按迁移门禁改为兼容入口。
- [x] 将第五篇状态矩阵、restore、取消暂存、amend 内容/说明和提交改写手册合并迁入 v2 第七篇前四章，旧入口改为 `legacy-redirect`；命令地图、场景索引、术语表和迁移映射同步完成。
- [x] 将第五篇交互式 rebase 与第四篇 cherry-pick 迁入 v2 第七篇，旧入口改为 `legacy-redirect`；保留 todo 重建、冲突、中止、来源/目标 OID、顺序和共享边界，导航、迁移映射和进度记录同步完成。

- [x] 扩写受保护分支章节，建立平台控制面与 Git 引用更新的分层模型。
- [x] 为平台事实建立版本与核对登记表。
- [x] 把根 README 的状态改为“基础稿完成，v2 重构中”。

## 下一批任务

- [x] 审计并重构 `book/part-1/05-first-model.md`，建立对象与引用的权威解释。
- [x] 扩写远程协议与认证，并明确本地实验不能验证 SSH 主机、HTTPS TLS、真实令牌或平台权限。
- [x] 补齐 refspec、浅克隆、部分克隆和 sparse-checkout 的工程边界与本地验证。
- [x] 设计新的篇章目录与文件迁移表，迁移前保持旧链接可用。
- [x] 建立本地 CI/CD 案例仓库结构，不伪造平台输出。
- [x] 重构发布章节，把标签、制品提升、部署回退和数据库兼容接入证据链。
- [x] 新增 CI 触发器、路径过滤与合并队列的厂商无关状态机章节。
- [x] 重构复杂冲突章节，补齐 ort、重命名/删除、目录重命名和 rerere。
- [x] 建立签名存在、密码学有效、身份映射与组织授权的分层模型，并验证候选信任策略不能自授权。
- [x] 重构不受信任仓库边界，覆盖 `safe.directory`、本地配置、attributes/filters、hooks 与递归依赖的供应链入口。
- [x] 建立第九篇大仓库性能测量基线，先定义对象、引用、index、工作区、冷热缓存和命令时延口径，再讨论优化。
- [x] 新写二进制与 Git LFS 章节，覆盖 pointer、filter/process、对象可用性、锁、配额、迁移和灾难恢复边界。
- [x] 新写 submodule 与 subtree 章节，覆盖 gitlink、递归 fetch/checkout、URL 信任、固定依赖、更新评审和迁移取舍。
- [x] 新写凭据泄漏与历史清理章节，区分撤销/轮换、历史重写、平台缓存与下游 clone 处置。
- [x] 新写最小权限机器身份章节，覆盖个人令牌、部署 key、机器人账号、工作负载身份、短期凭据和 break-glass。
- [x] 新写第三方 CI 依赖与流水线供应链章节，覆盖 action/plugin 固定、可变引用、构建脚本执行、权限继承和来源证明。
- [x] 新写秘密扫描、恶意对象与归档导出章节，覆盖扫描范围、结果访问、路径/对象攻击面和导出净化边界。
- [x] 新写事故现场保护与证据采集章节，覆盖事故分流、写入冻结、worktree/common directory、alternates、逻辑快照、保管链以及 clone/mirror/bundle 的遗漏边界。
- [x] 新写对象取证与恢复章节，覆盖 `fsck` 根与检查级别、不可达对象、`lost-found` 写入、alternate 掩盖、replace ref 原始视角、pack/idx 损坏和可信 donor 恢复。
- [x] 新写历史归因章节，覆盖固定候选、line-porcelain、ignore-rev、`-S`/`-G`、pathspec、rename/copy 推断、merge 历史简化和外部证据边界。
- [x] 新写 bundle、mirror 与备份恢复章节，覆盖恢复范围、RPO/RTO、refs manifest、完整/增量 bundle、mirror 删除传播和 Git/LFS/平台分层恢复。
- [x] 新写仓库与平台迁移章节，覆盖 Git/SVN 模型、作者/平台 principal、mailmap 边界、OID map、issue/评审/权限、最终同步、目标验收和切换回退。
- [x] 新写故障转移与安全回切章节，覆盖主备 checkpoint、RPO/RTO 分层、donor 恢复、`refs/recovery`、条件 `update-ref`、端到端验收、旧主 quarantine 和安全 failback。
- [x] 新写仓库生命周期章节，覆盖稳定资产身份、双重所有权、声明/观测事实、创建、认证、转移、归档、待删除、tombstone 与恢复。
- [x] 新写权限生命周期章节，覆盖入职、转岗、离职、外部协作者、机器人回收、定期认证和 break-glass 审计。
- [x] 新写规则集与例外治理章节，覆盖策略作用域、优先级、评估模式、渐进推广、绕过到期、漂移检测和回退。
- [x] 新写审计日志与证据留存章节，覆盖事件模型、时钟与主体关联、完整性、访问控制、保留/导出、查询失败和调查包验收。
- [x] 新写仓库健康、容量预算与维护窗口章节，覆盖对象/refs/LFS/制品增长、服务 SLO、阈值与预测、维护互斥、回退和组织级异常分流。
- [x] 新写组织级故障手册与恢复演练章节，覆盖事件分级、角色/RACI、通信、证据冻结、权限/策略/容量联动、桌面与技术演练、注入、停止条件和改进闭环。
- [x] 建立第十三篇入口并重构最小排障证据集，覆盖仓库布局、运行中操作、工作区/index、refs/对象、传输/平台/外部数据面、命令副作用、原始错误、脱敏与求助模板。
- [x] 新写“文件不见了/提交不见了”症状章，覆盖工作区/index/tree/blob、稀疏与忽略、精确 restore、日志范围、reflog/recovery ref、浅克隆和对象取证分流。
- [x] 新写“push 被拒绝/认证失败/权限不足”症状章，覆盖传输、主机身份、客户端认证、仓库授权、non-fast-forward、保护规则和 push 后发布证据链。
- [x] 新写“仓库变慢/对象膨胀/磁盘告急”症状章，覆盖 workload、p50/p95、工作区/index、历史/对象、传输/服务端、Git/LFS/制品/备份/scratch 分层，辅助索引与维护前后逻辑不变量，以及 prune/pack 删除停止条件。
- [x] 新写“LFS/子模块/CI clone 异常”症状章，覆盖 pointer/payload 水合、gitlink 固定提交与依赖发布顺序、candidate OID、shallow/partial 历史、cache provenance 和外部服务恢复边界。
- [x] 新写“签名无法验证/密钥状态异常”症状章，覆盖无签名、密码学失败、未知/未授权/撤销 key、tag 目标错误、历史改写、候选自授权和 CI 外部信任根。
- [x] 新写“远程引用过期/默认分支变化/删除引用残留”症状章，覆盖远端与本地缓存分离、分支重命名、prune、symbolic HEAD、标签 OID、隐藏/权限和查询竞态。
- [x] 新写“仓库损坏/锁文件残留/并发操作”症状章，覆盖 writer 识别、index/ref/packed refs 锁、expected-old、对象完整性、linked worktree、维护互斥和恢复停止条件。
- [x] 新写第八篇“触发与 checkout”章节，覆盖事件与候选分离、实际 HEAD 合约、浅/部分克隆、NUL 路径、路径依赖闭包和验证/发布信任域。
- [x] 新写第八篇“候选提交”章节，覆盖候选对象形状、构造上下文、merge-base、结果绑定、过期和合并队列条件更新。
- [x] 新写第八篇“从源码到运行版本：制品与部署证据链”章节，覆盖构建输入、流水线和 runner 身份、制品 digest、发布 tag、部署实例、数据库兼容和回退决策。
- [x] 新写第八篇“可重复构建”章节，覆盖输入闭包、非确定性、构建清单、摘要比较、缓存边界和构建一次提升同一制品。
- [x] 新写第八篇“发布引用与制品提升”章节，覆盖附注 tag、远端核对、发布清单、审批、同名竞态和跨环境提升。
- [x] 完成旧第六篇 bisect、历史检索和热修复入口迁移，保留实验链接和平台行为不可验证说明；兼容页总数增至 7 个。
- [ ] 审计旧第六篇的 bisect 与历史检索页，把尚未迁入的基础推演收束到第十一篇历史归因权威章，并为旧 URL 留兼容入口。
- [x] 审计旧第六篇的排障与综合场景，分别迁入第十三篇和第八篇，避免工程杂项目录继续承担多篇职责。
- [ ] 建立 v2 第七篇目标路径，把第五篇现行恢复正文按迁移表合并、拆分并留下旧链接兼容页，完成第六至八篇的连续导航。
- [ ] 继续迁移第五篇 rebase 模型与工作流、revert、显式租约、reset、reflog 和恢复案例，处理与远端历史改写新增章节的职责重叠。
- [ ] 在专用托管平台测试仓库验证第六篇的审批失效、代码所有者、同名检查报告者、合并队列、管理员/API 绕过和审计事件，并把产品、版本、权限、套餐和核对日期写入事实登记表。

## 回归状态

| 日期 | 命令 | 结果 | 说明 |
| --- | --- | --- | --- |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | v2 文档落盘前的原始基线 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 总纲、验收标准和受保护分支章节改写后回归，79 页与 8 组实验正常 |
| 2026-08-20 | Write 中文标点门禁 | 通过 | 本轮 9 个新增或修改的中文文档均通过 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 对象模型重构后回归，79 页与 9 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 显式租约章节重构后回归，79 页与 10 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | reset 与 reflog 重构后回归，79 页与 11 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 交互式 rebase 重构后回归，79 页与 12 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | revert 与综合恢复重构后回归，79 页与 12 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 远程传输与认证章节落盘后回归，80 页与 13 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | refspec 与受限克隆章节落盘后回归，81 页与 14 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 迁移映射与 CI/CD 证据链落盘后回归，82 页与 15 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 发布引用、制品提升与回退章节重构后回归，82 页与 15 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | CI 触发、路径过滤与合并队列章节落盘后回归，83 页与 16 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 复杂冲突、index stage、`AUTO_MERGE` 与 rerere 章节落盘后回归，84 页与 17 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 第十篇签名与信任策略章节落盘后回归，86 页与 18 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 不受信任仓库、filters、hooks 与递归协议章节落盘后回归，87 页与 19 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 第九篇性能测量、Trace2 与维护基线章节落盘后回归，89 页与 20 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 二进制与 Git LFS pointer/payload 边界章节落盘后回归，90 页与 21 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | Submodule gitlink、跨仓发布顺序与 subtree 历史复制章节落盘后回归，91 页与 22 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 凭据泄漏、全 ref 历史清理和重新污染章节落盘后回归，92 页与 23 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 最小权限机器身份、工作负载身份与 break-glass 章节落盘后回归，93 页与 24 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 第三方 CI 依赖固定、传递输入、cache 隔离与来源证明章节落盘后回归，94 页与 25 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 秘密扫描、恶意对象与归档导出章节及实验落盘，95 页与 26 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 第十一篇入口、事故现场保护与逻辑证据采集章节及实验落盘，97 页与 27 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 对象取证与恢复章节及实验落盘，98 页与 28 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 历史归因、pickaxe、merge 逐父比较与调查清单实验落盘，99 页与 29 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | bundle/mirror、增量 prerequisite、空环境恢复与删除传播实验落盘，100 页与 30 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | Git 全 refs/OID 保持迁移、默认分支、mailmap、源端拒写与客户端切换实验落盘，101 页与 31 组隔离实验正常 |
| 2026-08-20 | `./scripts/verify-all.sh` | 通过 | 复制滞后、donor bundle、条件提升、灾后验收与旧主围栏实验落盘，102 页与 32 组隔离实验正常 |
| 2026-08-21 | `./scripts/verify-all.sh` | 通过 | 仓库资产登记、owner/默认分支对账、归档摘要、拒写围栏、删除审批与空仓恢复实验落盘，104 页与 33 组隔离实验正常 |
| 2026-08-21 | `./scripts/verify-all.sh` | 通过 | 权限快照三态、离职残留、开发者/发布机器人 ref 范围与 break-glass 到期实验落盘，105 页与 34 组隔离实验正常 |
| 2026-08-21 | `./scripts/verify-all.sh` | 通过 | 规则 scope 组合、audit/enforce 推广、窄例外、digest 漂移三态与非快进接收门禁实验落盘，106 页与 35 组隔离实验正常 |
| 2026-08-21 | `./scripts/verify-all.sh` | 通过 | accepted/denied 接收事件、cursor 幂等、sequence 缺口、对象/服务时钟和调查包 manifest 实验落盘，107 页与 36 组隔离实验正常 |
| 2026-08-21 | `./scripts/verify-all.sh` | 通过 | 健康四态、分层容量/headroom、事故/备份/scratch/互斥维护门禁、失败锁恢复与逻辑不变量实验落盘，108 页与 37 组隔离实验正常 |
| 2026-08-21 | `./scripts/verify-all.sh` | 通过 | 组织角色/状态门禁、primary 围栏、bundle 候选、审计 inconclusive、generation 条件提升、单一写入权威和行动闭环实验落盘，109 页与 38 组隔离实验正常 |
| 2026-08-21 | `./scripts/verify-all.sh` | 通过 | 第十三篇入口、六坐标/八层诊断、冲突现场无变异采集、证据三态、脱敏、abort 恢复与 fetch 副作用实验落盘，111 页与 39 组隔离实验正常 |
| 2026-08-21 | `./scripts/verify-all.sh` | 通过 | worktree/index/tree 路径恢复、sparse/ignore、未跟踪边界、reflog recovery ref 和 shallow/unshallow 实验落盘，112 页与 40 组隔离实验正常 |
| 2026-08-22 | `./scripts/verify-all.sh` | 通过 | push/认证/权限边界与性能/容量故障章节接入，endpoint/non-fast-forward/fetch/hook/URL 回滚、workload/Trace2/辅助索引/maintenance/容量四态实验正常，114 页与 42 组隔离实验正常 |
| 2026-08-22 | `./scripts/verify-all.sh` | 通过 | LFS/子模块/CI clone 故障章节接入，pointer/payload 缺失与恢复、未发布 gitlink、detached candidate 和外部依赖输入清单实验正常，115 页与 43 组隔离实验正常 |
| 2026-08-22 | `./scripts/verify-all.sh` | 通过 | 签名验证/密钥状态故障章节接入，签名存在性、密码学、外部信任根、tag 目标、历史改写和验证不变性实验正常，116 页与 44 组隔离实验正常 |
| 2026-08-22 | `./scripts/verify-all.sh` | 通过 | 远程引用漂移章节接入，分支重命名、prune 恢复、默认分支刷新、标签改指向和查询竞态实验正常，117 页与 45 组隔离实验正常 |
| 2026-08-22 | `./scripts/verify-all.sh` | 通过 | 仓库损坏/锁/并发章节接入，活跃 writer、stale lock、expected-old、pack 损坏分类和 donor 恢复实验正常，118 页与 46 组隔离实验正常 |
| 2026-08-22 | `./scripts/verify-all.sh` | 通过 | 第八篇入口与触发/候选/checkout 权威章节接入，SUMMARY、候选与队列实验、标点和链接门禁正常，120 页与 46 组隔离实验正常 |
| 2026-08-22 | `./scripts/verify-all.sh` | 通过 | 第八篇源码/制品/部署证据章节接入，候选归档、摘要清单、部署副本篡改检测和主线前进不变量实验正常，121 页与 46 组隔离实验正常 |
| 2026-08-23 | `./scripts/verify-all.sh` | 通过 | 第八篇可重复构建、发布引用、部署与回退章节及三组实验接入，金丝雀停止、已知良好制品回退、配置回退和长任务围栏验证正常，125 页与 49 组隔离实验正常 |
| 2026-08-23 | Write 中文标点门禁 | 通过 | 第八篇第六章、导航、附录和迁移文档通过中文标点检查 |
| 2026-08-23 | `ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | 125 个公开页面的链接、SUMMARY 覆盖和差异空白检查正常 |
| 2026-08-23 | `./scripts/verify-all.sh` | 通过 | 第八篇数据库迁移章节及实验接入，expand/contract、可续跑回填、旧应用围栏、contract 门禁和向前修复边界验证正常，126 页与 50 组隔离实验正常 |
| 2026-08-23 | `./scripts/verify-incident-to-release.sh` | 通过 | `bisect` 首个坏提交、hotfix 来源/目标提交、双组件制品提升、旧任务围栏和事故关闭条件验证正常 |
| 2026-08-23 | `./scripts/verify-all.sh` | 通过 | 第八篇事故到发布综合章节及实验接入，证据冻结、缓解、首个坏提交、来源/目标修复、双组件 rollout 和关闭条件验证正常，127 页与 51 组隔离实验正常 |
| 2026-08-23 | `./scripts/verify-refspec-partial-clone.sh` | 通过 | 第九篇稀疏与部分工作流复用实验，负 refspec、shallow、partial blob 按需取得和 sparse 展开/关闭边界验证正常 |
| 2026-08-23 | `./scripts/verify-monorepo-topology.sh` | 通过 | 共享库反向依赖闭包、图缺边 `inconclusive`、原子候选、所有权审批和主线前进边界验证正常 |
| 2026-08-23 | `./scripts/verify-all.sh` | 通过 | 第九篇稀疏/部分工作流与 Monorepo 拓扑章节接入，129 页与 52 组隔离实验正常 |
| 2026-08-23 | Write 中文标点门禁 | 通过 | 第八篇第八章、导航、附录、总纲、迁移映射和进度文档通过中文标点检查 |
| 2026-08-23 | `ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | 129 个公开页面的链接、SUMMARY 覆盖和差异空白检查正常 |
| 2026-08-23 | `./scripts/verify-signatures-trust.sh` | 通过 | 签名存在、密码学验证、候选之外信任策略，以及 candidate OID/fingerprint/principal/action 的 release 授权匹配正常 |
| 2026-08-23 | `./scripts/verify-all.sh` | 通过 | 签名章组织授权投影实验接入后整库回归，129 个公开页面与 52 组隔离实验正常 |
| 2026-08-23 | `./scripts/verify-part-2.sh` | 通过 | 第二篇身份条件 include、local 覆盖、工作区/index/HEAD 状态矩阵、提交失败恢复、忽略规则和 index/工作树属性边界验证正常 |
| 2026-08-23 | `./scripts/verify-all.sh` | 通过 | 第二篇工作区/index/HEAD、忽略规则和属性章节接入后整库回归，129 个公开页面与 52 组隔离实验正常 |
| 2026-08-23 | `./scripts/verify-all.sh` | 通过 | 第二篇身份/配置、原子提交、local hook 拒绝和空提交章节接入后整库回归，129 个公开页面与 52 组隔离实验正常 |
| 2026-08-23 | Write 中文标点门禁 | 通过 | 第二篇十个章节和综合练习通过中文标点检查，代码块与 Git 输出未被改写 |
| 2026-08-23 | `./scripts/verify-part-2.sh` | 通过 | 仓库发现、初始化不变量、子目录 `add .` 范围、三层差异、历史范围和混合提交恢复断言正常 |
| 2026-08-23 | `./scripts/verify-all.sh` | 通过 | 第二篇六章正文重构和实验扩展接入整库回归，129 个公开页面与 52 组隔离实验正常 |
| 2026-08-27 | Write 中文标点门禁 | 通过 | 第三篇十个正文页面和综合练习通过中文标点检查，冲突示例使用可渲染转义，不触发差异门禁 |
| 2026-08-27 | `./scripts/verify-part-3-basics.sh`、`verify-part-3-conflicts.sh`、`verify-complex-conflicts-rerere.sh` | 通过 | 提交图、分支引用、分离 `HEAD`、快进/分叉、冲突 abort/resolve、标签对象和复杂冲突实验正常 |
| 2026-08-27 | `ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | 第三篇导航同步、129 个公开页面链接覆盖和新增正文差异检查正常 |
| 2026-08-27 | Write 中文标点门禁 | 通过 | 第四篇远程基础七章通过中文标点检查，命令代码块保持原样 |
| 2026-08-27 | `./scripts/verify-part-4-remotes.sh` | 通过 | clone、remote URL、fetch/远程跟踪、pull、upstream、push 和 tag target 断言正常 |
| 2026-08-27 | Write 中文标点门禁 | 通过 | 第四篇 push 拒绝、评审准备、cherry-pick 和综合练习通过中文标点检查 |
| 2026-08-27 | `./scripts/verify-part-4-history.sh`、`verify-part-4-remotes.sh`、`verify-remote-transport-auth.sh`、`verify-refspec-partial-clone.sh` | 通过 | 非快进、rebase/cherry-pick、远程传输认证和受限克隆实验继续通过 |
| 2026-08-28 | Write 中文标点门禁 | 通过 | 第四篇 rebase 模型、工作流和前置协作章节通过中文标点检查 |
| 2026-08-28 | `./scripts/verify-part-4-history.sh`、`verify-interactive-rebase.sh`、`verify-force-with-lease.sh` | 通过 | 普通 rebase 的旧/新 OID、最终 tree、主线祖先关系、range-diff、交互式重建和租约恢复断言正常 |
| 2026-08-28 | `./scripts/verify-all.sh` | 通过 | 第三篇和第四篇阶段性正文重构接入整库回归，129 个公开页面与 52 组隔离实验正常 |
| 2026-08-28 | Write 中文标点门禁 | 通过 | 第六篇 stash、worktree 和 bisect 正文通过中文标点检查 |
| 2026-08-28 | `./scripts/verify-part-6-engineering.sh` | 通过 | stash 恢复、linked worktree 共同目录、bisect 自动判定和 cherry-pick 工程实验正常 |
| 2026-08-29 | Write 中文标点门禁 | 通过 | 第六篇历史检索、热修复、冲突报告、提交质量和统一排障章节通过中文标点检查 |
| 2026-08-29 | `./scripts/verify-part-6-engineering.sh`、`verify-history-attribution.sh`、`verify-troubleshooting-snapshot.sh` | 通过 | stash/worktree/bisect、历史归因、证据采集和 fetch 副作用实验正常 |
| 2026-08-29 | Write 中文标点门禁 | 通过 | 第五篇撤销决策、restore、unstage、amend 和公开历史章节通过中文标点检查 |
| 2026-08-29 | `./scripts/verify-part-5-local-history.sh`、`verify-reset-reflog.sh`、`verify-revert.sh`、`verify-interactive-rebase.sh`、`verify-force-with-lease.sh` | 通过 | 工作区/index 恢复、私有对象重建、共享历史回滚、交互式 rebase 和租约边界实验正常 |
| 2026-08-29 | Write 中文标点门禁 | 通过 | 第一篇五个基础页面和综合练习通过中文标点检查 |
| 2026-08-29 | `./scripts/verify-object-model.sh`、`./scripts/verify-all.sh` | 通过 | 第一篇、第五篇和第六篇正文重构接入整库回归，129 个公开页面与 52 组隔离实验正常 |
| 2026-08-29 | `./scripts/verify-all.sh`、`ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | 阅读路线、根 README 统计和受保护分支职责链接同步后整库回归仍正常 |
| 2026-08-31 | `./scripts/verify-part-6-collaboration.sh` | 通过 | merge、squash、rebase merge 的父关系、祖先关系、最终 tree、OID 重建和 expected-old 并发更新断言正常 |
| 2026-08-31 | `./scripts/verify-all.sh` | 通过 | v2 第六篇八章、综合场景和新实验接入整库回归，139 个公开页面与 53 组隔离实验正常 |
| 2026-08-31 | Write 中文标点门禁 | 通过 | v2 第六篇、导航、实验索引、迁移映射和事实登记通过中文标点检查，代码块保持原样 |
| 2026-08-31 | `ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | 139 个公开页面、4 个兼容迁移页、SUMMARY 覆盖和差异空白检查正常 |
| 2026-09-02 | `./scripts/verify-all.sh` | 通过 | 第十一篇历史归因补充 bisect 边界，旧第六篇 bisect/历史检索/热修复迁移为兼容页，139 个公开页面与 53 组隔离实验正常 |
| 2026-09-02 | Write 中文标点门禁、`ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | 新增兼容页、历史归因章节、导航和迁移文档通过标点、链接、SUMMARY 覆盖和差异空白检查，7 个兼容迁移页 |
| 2026-09-02 | `./scripts/verify-all.sh` | 通过 | 第六篇冲突报告与提交质量迁移、可审查变更补充和旧页兼容入口接入整库回归，139 个公开页面与 53 组隔离实验正常 |
| 2026-09-02 | Write 中文标点门禁、`ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | 冲突报告、提交质量兼容页、场景索引、导航和迁移文档通过标点、链接、SUMMARY 覆盖和差异空白检查，9 个兼容迁移页 |
| 2026-09-05 | `./scripts/verify-all.sh` | 通过 | 旧第六篇排障与综合场景迁移后整库回归，141 个公开页面、11 个兼容迁移页与 54 组隔离实验正常 |
| 2026-09-05 | Write 中文标点门禁、`ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | 排障与综合场景兼容页、导航、迁移映射和进度文档通过标点、链接、SUMMARY 覆盖与差异空白检查 |
| 2026-09-05 | Write 中文标点门禁、`ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | stash/worktree v2 第二篇补充、旧页兼容入口、导航、迁移映射和进度文档通过标点、链接、SUMMARY 覆盖与差异空白检查，144 个公开页面与 13 个兼容页 |
| 2026-09-05 | Write 中文标点门禁、`ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | v2 第七篇入口与首批三章、第五篇迁移映射和导航通过标点、链接、SUMMARY 覆盖与差异空白检查，148 个公开页面与 13 个兼容页 |
| 2026-09-05 | Write 中文标点门禁、`ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | v2 第七篇 amend 章、旧入口兼容页、附录索引和迁移映射通过标点、链接、SUMMARY 覆盖与差异空白检查，149 个公开页面与 19 个兼容页 |
| 2026-09-05 | Write 中文标点门禁、`ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | v2 第七篇交互式 rebase/cherry-pick、旧入口兼容页、导航和迁移映射通过标点、链接、SUMMARY 覆盖与差异空白检查，151 个公开页面与 21 个兼容页 |
| 2026-09-05 | `./scripts/verify-all.sh` | 通过 | v2 第七篇交互式 rebase/cherry-pick 迁移后整库回归，151 个公开页面、21 个兼容迁移页与 54 组隔离实验正常 |
| 2026-09-04 | `./scripts/verify-all.sh` | 通过 | 提交改写与远端历史重写场景接入整库回归，141 个公开页面、7 个兼容迁移页与 54 组隔离实验正常 |
| 2026-09-04 | Write 中文标点门禁、`ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | 新增第五篇正文、索引、实验说明和验收规则通过中文标点、链接覆盖与差异空白检查 |
| 2026-09-05 | `./scripts/verify-all.sh` | 通过 | 合并远端第五篇历史改写内容后重新验证，141 个公开页面、9 个兼容迁移页与 54 组隔离实验正常 |
| 2026-09-05 | Write 中文标点门禁、`ruby scripts/check-book-links.rb`、`git diff --check` | 通过 | 合并远端内容并保留第六篇迁移后的导航、实验和进度记录，标点、链接、SUMMARY 覆盖与差异空白检查正常 |

## 已知风险

- 当前旧的六篇基础结构与第八篇至第十三篇新权威章节仍并列；迁移目标和旧链接策略已登记，但尚未达到最终导航切换门禁。
- 现有章节的 Git 版本统一写作 2.28+，不足以约束后续新增能力。
- 平台能力只核对了正文已经使用的少量事实；新增套餐、权限或界面细节仍须先进入 `docs/FACT-REGISTER.md`。
- 自动实验覆盖 Git 核心行为，不覆盖托管平台、CI、LFS 服务和组织审计能力。
- 本地没有安装 `git-lfs`；当前 LFS 实验只证明 pointer 与外部对象模型，真实 fetch、锁、配额和迁移仍需专用环境验证。
- 本地没有安装 `git-filter-repo`；敏感历史实验只证明 Git refs、objects 与 clone 边界，真实工具和平台 purge 仍需专用环境验证。
- 事故现场实验只验证合成仓库的 Git 逻辑采集，不验证文件系统/云盘崩溃一致性、平台审计、内存或恶意主机取证；真实流程仍需专用环境和组织授权。
- 历史归因实验只验证本地可见 refs 和对象，不证明平台评审决定、服务端接收时间、CI/制品/部署事件或业务责任；真实调查必须补齐外部证据。
- 备份恢复实验只验证本地 Git bundle/mirror 机制，不证明托管平台、LFS、加密、跨区域复制或真实 RPO/RTO；全书仍需组织专用环境的恢复演练和出版审校。
- 本地未安装 SVN/`git-svn`，迁移实验也不连接托管平台、LFS 或 CI；SVN revision/copy/property、平台 issue/评审/权限和服务端只读切换仍需专用环境验证。
- 灾难恢复实验只验证本地 Git 数据面状态机，不证明区域基础设施、DNS/TLS、负载均衡、同步存储、平台数据库、身份、LFS、CI 或真实 RPO/RTO；真实 failover/failback 仍需专用环境演练。
- 仓库生命周期实验只验证本地 bare 仓库、TSV 登记、bundle 和 receive hook；身份目录、法律保留、平台 Archive/Delete、LFS/package/CI 处置、软删除和真实删除仍需组织专用环境按版本、权限与套餐验收。
- 权限生命周期实验使用合成登记和客户端进程传给本地 receive hook 的虚构 actor，不证明真实认证、SSO/SCIM、嵌套组、会话撤销、管理员/API/LFS/合并入口或审计留存；平台专项验收仍是缺口。
- 规则与例外实验只验证本地 TSV 求值、策略 digest、Git 祖先关系和 receive hook；平台继承/优先级、audit 模式、管理员绕过、检查报告者、配置传播、API/LFS/合并入口和审计完整性仍需按产品版本、权限与套餐专项验证。
- 审计证据实验只验证本地 hook 生成的合成事件、cursor/sequence、Git OID 和 SHA-256 manifest；真实平台的 actor/委托链、事件覆盖、时钟、分页/schema、保留/legal hold、访问、签名/WORM 和审计灾备仍需按产品与组织制度验收。
- 健康与容量实验只验证临时仓库的 Git 指标/maintenance 和合成的 LFS/制品预算；真实平台指标、增长预测、服务 SLO、存储/inode、LFS/制品配额、并发调度、计费和故障域仍需目标环境采集与演练。
- 组织级恢复实验只验证本地 Git refs/bundle/fsck/receive hook 和合成状态门禁；真实平台围栏、身份、审计、LFS、CI、制品、通信、值班响应、区域故障及 RPO/RTO 仍需获批目标环境演练。
- 排障快照实验只验证受信任临时仓库的本地 Git 状态、证据摘要与 fetch 副作用；恶意仓库、真实凭据、平台权限、LFS、磁盘取证和组织级现场仍需使用对应安全/取证流程。
- 文件/提交消失实验只验证临时仓库的路径状态、reflog 和 shallow 机制；未跟踪字节的真实磁盘恢复、对象过期/GC、服务端保留、平台可见性、LFS 与 submodule 仍需外部证据和专项环境。
- 性能/容量排障实验只验证临时仓库的 Git 规模指标、Trace2、commit-graph、MIDX bitmap、maintenance 和逻辑不变量；冷/热缓存、真实 p95、文件系统、网络/服务端、LFS、制品、备份、inode、磁盘故障、后台调度、平台配额和计费仍需目标环境验证。
- LFS/子模块/CI 外部依赖实验只验证自建 filter、Git pointer/payload、file 传输 gitlink 发布顺序和 detached candidate；真实 LFS API、SSH/TLS、凭据、锁/配额、平台缓存、CI runner、制品和审计仍需目标环境验证。
- 签名排障实验只验证一次性 SSH key、外部 allowed signers、合成 release 授权清单、Git verify-commit/verify-tag 和对象/引用不变；OpenPGP/X.509、硬件 key、撤销/时间戳服务、平台徽章、真实组织授权服务和真实发布门禁仍需目标环境验证。
- 远程引用漂移实验只验证本地 seed/bare/client 的 refs、symbolic HEAD、tag ref、fetch/prune 和查询时序；平台隐藏 refs、默认分支控制面、分支保护、评审/队列、SSO、审计事件和真实网络竞态仍需目标环境核对。
- 仓库损坏/锁并发实验只验证本地 files ref backend、index/ref lock、expected-old、pack/idx 和 fsck 边界；reftable、网络文件系统租约、真实崩溃、磁盘坏道、服务端对象池、维护调度和跨节点并发仍需专用环境演练。
- 第八篇已落盘八章；第九篇已落盘五章，覆盖性能、LFS、submodule/subtree、受限工作流和 monorepo 拓扑治理。真实运行平台核验、跨篇旧页面迁移和出版级综合审校仍需按总纲继续推进。
- 第六篇的发布、CI 证据链、CI 触发与队列、受保护分支、bisect、历史检索、热修复、冲突报告、提交质量、排障、综合场景、stash 和 worktree 旧页，以及第五篇前七个改写/状态入口已改为兼容迁移页；第五篇 rebase 模型与工作流、revert、显式租约、reset、reflog 和恢复案例仍需逐章迁移，旧目录暂时不能移出导航。
- v2 第六篇的本地实验只证明 Git 合并形状和 expected-old 引用更新，不证明真实平台的评审、所有者、检查报告者、合并队列、绕过、权限或审计行为；这些易变事实仍需在专用平台环境按版本、权限、套餐和核对日期验收。
- Push/认证/权限边界实验只验证本地 `file://`、bare receive、非快进、hook 和 URL 配置边界；真实 SSH/TLS/凭据/SSO/平台授权、规则、评审、CI、配额和审计仍需目标环境专项验收。
