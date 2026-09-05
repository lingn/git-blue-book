# v1 六篇到 v2 十三篇的章节迁移映射

> 状态：v2 目录实施基线，建立于 2026-08-20。本文件服从 `docs/MASTER-OUTLINE.md` 的内容范围，负责回答每个现有页面怎样迁移、目标文件叫什么，以及旧链接怎样保留。

## 为什么不立即批量移动

建立本映射时 GitBook 有 83 个公开页面；当前数量随已验收的新章增长，以 `docs/PROGRESS.md` 最近一次全量回归为准。内部链接、根 README、`book/SUMMARY.md` 和外部读者都可能引用现有 `part-1` 至 `part-6` 路径。一次性改名会同时制造内容重写、链接迁移和导航切换三类变量，出错后很难判断是文字问题还是路径问题。

迁移采用“先完成目标章，再移动权威内容，最后切换导航”的顺序。未达到单章验收标准的页面继续保留在旧路径；不为了得到十三个目录而生成短篇占位。

## 目标目录约定

v2 最终使用零填充目录，避免现有目录名冲突，并让文件排序与篇章顺序一致：

```text
book/part-01/  版本历史解决什么问题
book/part-02/  建立可靠的本地工作循环
book/part-03/  对象模型决定命令行为
book/part-04/  分支、合并与冲突
book/part-05/  远程仓库、协议与认证
book/part-06/  共享历史的协作与评审
book/part-07/  改写、撤销与恢复
book/part-08/  发布与 CI/CD 集成
book/part-09/  大仓库、二进制与仓库组合
book/part-10/  安全、签名与供应链
book/part-11/  取证、迁移与灾难恢复
book/part-12/  组织级运维与治理
book/part-13/  故障排查手册
```

`book/appendix/` 继续使用现有路径。首页、前言、阅读路线和 `SUMMARY.md` 仍位于 `book/` 根目录。

## 迁移动作定义

| 动作 | 含义 | 旧页面处理 |
| --- | --- | --- |
| 保留重写 | 一对一迁移，沿用主体但按 v2 标准重写 | 目标章验收后，旧页改为迁移说明 |
| 合并 | 多个旧页收束为一个权威章 | 每个旧页分别链接到新章对应小节 |
| 拆分 | 一个旧页的不同职责进入多个新章 | 旧页保留导航，不能复制两份权威定义 |
| 过渡新增 | 已在六篇目录中新增，但最终属于 v2 其他篇 | 完成目标篇时移动，当前链接保持可读 |
| 历史保留 | 仅为兼容旧教程或记录 v1 设计 | 放入附录或历史文档，不进入 v2 主线 |
| 新写 | v1 没有可承担权威解释的内容 | 从总纲、官方来源和实验建立新章 |

## 根页面与导航

| 当前文件 | v2 目标 | 动作与要求 |
| --- | --- | --- |
| `book/README.md` | 原路径 | 保留重写；展示十三篇能力范围和真实完成状态 |
| `book/preface.md` | 原路径 | 保留重写；补充目标读者、事实边界与实验契约 |
| `book/reading-map.md` | 原路径 | 保留重写；改为基础、团队、SRE、事故四条路径 |
| `book/SUMMARY.md` | 原路径 | 最后切换；迁移期间只收录已落盘页面，不预列占位章 |

## 第一篇现有页面

| 当前文件 | v2 目标 | 动作 |
| --- | --- | --- |
| `book/part-1/README.md` | `book/part-01/README.md` | 保留重写 |
| `book/part-1/01-why-version-control.md` | `book/part-01/01-versioned-engineering.md` | 保留重写，补可追溯、可审查、可恢复三类目标 |
| `book/part-1/02-three-generations.md` | `book/part-01/02-centralized-and-distributed.md` | 保留重写，压缩代际优劣的重复判断 |
| `book/part-1/03-birth-of-git.md` | `book/part-01/03-git-design-constraints.md` | 保留重写，区分历史背景与当前工程结论 |
| `book/part-1/04-snapshots.md` | `book/part-01/04-snapshots-and-diffs.md`、`book/part-03/01-object-model.md` | 拆分；第一篇保留直觉，第三篇承担对象事实 |
| `book/part-1/05-first-model.md` | `book/part-01/05-first-repository-map.md`、`book/part-03/01-object-model.md`、`book/part-03/02-object-format.md` | 拆分；当前重构稿主体成为第三篇权威来源 |
| `book/part-1/exercise.md` | `book/part-01/exercise.md` | 保留重写 |

## 第二篇现有页面

| 当前文件 | v2 目标 | 动作 |
| --- | --- | --- |
| `book/part-2/README.md` | `book/part-02/README.md` | 保留重写 |
| `book/part-2/01-install.md` | `book/part-02/01-install-version-help.md` | 保留重写，增加平台与版本边界 |
| `book/part-2/02-identity.md` | `book/part-02/02-identity-and-config.md` | 保留重写，增加配置作用域与条件包含 |
| `book/part-2/03-init.md` | `book/part-02/03-repository-discovery-and-init.md` | 保留重写 |
| `book/part-2/04-status.md` | `book/part-02/04-observe-status.md` | 保留重写 |
| `book/part-2/05-three-areas.md` | `book/part-02/05-worktree-index-commit.md`、`book/part-03/05-index-internals.md` | 拆分；第二篇讲操作模型，第三篇讲数据结构 |
| `book/part-2/06-add.md` | `book/part-02/06-stage-a-change.md` | 保留重写 |
| `book/part-2/07-commit.md` | `book/part-02/07-atomic-commit-and-hooks.md` | 合并扩写 |
| `book/part-2/08-diff.md` | `book/part-02/08-read-diffs.md` | 保留重写 |
| `book/part-2/09-history.md` | `book/part-02/09-read-history.md` | 保留重写，取证高级用法转第十一篇 |
| `book/part-2/10-ignore.md` | `book/part-02/10-ignore-attributes-and-eol.md` | 扩写 `.gitattributes`、换行符与过滤器边界 |
| `book/part-2/exercise.md` | `book/part-02/exercise.md` | 保留重写 |

## 第三篇现有页面

| 当前文件 | v2 目标 | 动作 |
| --- | --- | --- |
| `book/part-3/README.md` | `book/part-04/README.md` | 保留重写；对象模型内容由新第三篇承担 |
| `book/part-3/01-commit-graph.md` | `book/part-03/04-commit-graph-and-reachability.md`、`book/part-04/03-merge-base.md` | 拆分 |
| `book/part-3/02-branch-as-reference.md` | `book/part-03/03-refs-head-and-reflog.md`、`book/part-04/01-branches-and-detached-head.md` | 拆分 |
| `book/part-3/03-head.md` | `book/part-03/03-refs-head-and-reflog.md` | 合并 |
| `book/part-3/04-switch-branch.md` | `book/part-04/02-create-and-switch-branches.md` | 保留重写 |
| `book/part-3/05-first-merge.md` | `book/part-04/03-merge-base.md` | 合并扩写 |
| `book/part-3/06-merge-shapes.md` | `book/part-04/04-fast-forward-and-merge-commits.md` | 保留重写 |
| `book/part-3/07-conflict-model.md` | `book/part-03/05-index-internals.md`、`book/part-04/05-three-way-merge-and-ort.md` | 拆分冲突阶段与策略语义 |
| `book/part-3/08-resolve-conflict.md` | `book/part-04/07-resolve-abort-and-verify.md` | 保留重写 |
| `book/part-3/09-tags.md` | `book/part-04/09-tags-and-release-refs.md`、`book/part-10/04-signatures.md` | 拆分；签名证明进入第十篇 |
| `book/part-3/10-complex-conflicts-rerere.md` | `book/part-04/05-three-way-merge-and-ort.md`、`book/part-04/06-complex-path-conflicts.md`、`book/part-04/08-rerere.md` | 过渡新增后拆分；index stage、策略、路径冲突和解决复用各归入唯一权威章 |
| `book/part-3/exercise.md` | `book/part-04/exercise.md` | 保留重写 |

## 第四篇现有页面

| 当前文件 | v2 目标 | 动作 |
| --- | --- | --- |
| `book/part-4/README.md` | `book/part-05/README.md` | 保留重写；评审和历史改写内容拆出 |
| `book/part-4/01-remote-model.md` | `book/part-05/01-remote-state-model.md` | 保留重写 |
| `book/part-4/02-clone.md` | `book/part-05/02-clone-and-initial-state.md` | 保留重写 |
| `book/part-4/03-remote.md` | `book/part-05/03-remotes-and-refspecs.md` | 与 refspec 内容合并 |
| `book/part-4/04-fetch.md` | `book/part-05/04-fetch-and-fetch-head.md` | 合并扩写 |
| `book/part-4/05-remote-tracking.md` | `book/part-05/04-fetch-and-fetch-head.md` | 合并 |
| `book/part-4/06-pull.md` | `book/part-05/05-pull-as-composition.md` | 保留重写 |
| `book/part-4/07-push.md` | `book/part-05/06-push-upstream-and-ref-updates.md` | 保留重写 |
| `book/part-4/08-push-rejection.md` | `book/part-05/07-rejection-atomic-push-and-options.md` | 扩写原子推送与 push options |
| `book/part-4/09-review-ready.md` | `book/part-06/02-review-request-model.md`、`book/part-06/04-reviewable-changes.md` | 拆分 |
| `book/part-4/10-rebase-model.md` | `book/part-07/06-rebase-model-and-workflow.md` | 合并 |
| `book/part-4/11-rebase-workflow.md` | `book/part-07/06-rebase-model-and-workflow.md` | 合并；保留当前冲突语义补强 |
| `book/part-4/12-cherry-pick.md` | `book/part-07/07-cherry-pick.md` | 保留重写 |
| `book/part-4/13-transport-auth.md` | `book/part-05/08-transport-and-authentication.md`、`book/part-10/01-credentials.md` | 过渡新增后拆分；传输章权威解释身份分层 |
| `book/part-4/14-refspec-partial-clone.md` | `book/part-05/03-remotes-and-refspecs.md`、`book/part-05/09-negotiation-and-limited-clones.md`、`book/part-09/04-sparse-partial-workflows.md` | 过渡新增后拆分；性能决策只在第九篇扩展 |
| `book/part-4/exercise.md` | `book/part-05/exercise.md`、`book/part-06/exercise.md` | 拆分远程同步与评审准备 |

## 第五篇现有页面

| 当前文件 | v2 目标 | 动作 |
| --- | --- | --- |
| `book/part-5/README.md` | `book/part-07/README.md` | 保留重写 |
| `book/part-5/01-decision-matrix.md` | `book/part-07/01-state-and-sharing-matrix.md` | 保留重写 |
| `book/part-5/02-restore-worktree.md` | `book/part-07/02-restore-worktree.md` | 保留重写 |
| `book/part-5/03-unstage.md` | `book/part-07/03-unstage.md` | 保留重写 |
| `book/part-5/04-amend-content.md` | `book/part-07/04-amend-one-commit.md` | 合并 |
| `book/part-5/05-amend-message.md` | `book/part-07/04-amend-one-commit.md` | 合并 |
| `book/part-5/06-interactive-rebase.md` | `book/part-07/05-interactive-rebase.md` | 保留当前重构稿 |
| `book/part-5/07-revert.md` | `book/part-07/08-revert-shared-history.md` | 保留当前重构稿 |
| `book/part-5/08-public-history.md` | `book/part-07/09-public-history-policy.md` | 保留重写，并链接第六篇团队规则 |
| `book/part-5/09-force-with-lease.md` | `book/part-07/10-explicit-force-lease.md` | 保留当前重构稿 |
| `book/part-5/10-reset.md` | `book/part-07/11-reset.md` | 保留当前重构稿 |
| `book/part-5/11-reflog.md` | `book/part-07/12-reflog-and-recovery-refs.md`、`book/part-11/02-evidence-and-reflog.md` | 拆分日常恢复与取证证据 |
| `book/part-5/12-recovery-cases.md` | `book/part-07/13-local-and-remote-recovery.md`、`book/part-13/02-missing-commits.md` | 拆分 |
| `book/part-5/exercise.md` | `book/part-07/exercise.md` | 保留重写 |

## 第六篇现有页面

| 当前文件 | v2 目标 | 动作 |
| --- | --- | --- |
| `book/part-6/README.md` | 多篇 README | 拆分；不保留“真实工程杂项篇”作为 v2 结构 |
| `book/part-6/01-stash.md` | `book/part-02/11-stash.md` | 保留重写 |
| `book/part-6/02-worktree.md` | `book/part-02/12-multiple-worktrees.md` | 保留重写 |
| `book/part-6/03-bisect.md` | `book/part-11/03-history-attribution.md`、`book/part-08/08-incident-to-release.md` | 已于 2026-09-02 收束迁移；旧页保留 `legacy-redirect` 兼容入口，权威章补齐 bisect 候选边界 |
| `book/part-6/04-history-search.md` | `book/part-11/03-history-attribution.md` | 已于 2026-09-02 收束迁移；旧页保留 `legacy-redirect` 兼容入口 |
| `book/part-6/05-hotfix.md` | `book/part-08/08-incident-to-release.md` | 已于 2026-09-02 收束迁移；旧页保留 `legacy-redirect` 兼容入口 |
| `book/part-6/06-release.md` | `book/part-08/03-source-artifact-deployment-evidence.md` 至 `book/part-08/08-incident-to-release.md` | 已于 2026-08-30 拆分迁移；旧页保留 `legacy-redirect` 兼容入口 |
| `book/part-6/07-conflict-report.md` | `book/part-3/10-complex-conflicts-rerere.md`、`book/part-06/04-reviewable-changes-and-stacks.md` | 已于 2026-09-02 拆分迁移；旧页保留 `legacy-redirect` 兼容入口 |
| `book/part-6/08-commit-quality.md` | `book/part-2/07-commit.md`、`book/part-06/04-reviewable-changes-and-stacks.md` | 已于 2026-09-02 拆分迁移；旧页保留 `legacy-redirect` 兼容入口 |
| `book/part-6/09-protected-branches.md` | `book/part-06/02-review-state-machine.md`、`book/part-06/05-ownership-approvals-and-stale-decisions.md`、`book/part-06/06-required-checks-and-merge-queues.md`、`book/part-06/08-protected-refs-and-exceptions.md`、`book/part-12/03-policy-rules-and-exceptions.md` | 已于 2026-08-31 拆分迁移；旧页保留 `legacy-redirect` 兼容入口 |
| `book/part-6/10-troubleshooting.md` | `book/part-13/README.md`、`book/part-13/01-evidence-first.md` | 拆分后全面扩写 |
| `book/part-6/11-ci-evidence-chain.md` | `book/part-08/01-triggers-and-checkout.md` 至 `book/part-08/05-release-refs-and-artifact-promotion.md` | 已于 2026-08-30 收束迁移；旧页保留 `legacy-redirect` 兼容入口 |
| `book/part-6/12-ci-triggers-merge-queue.md` | `book/part-08/01-triggers-and-checkout.md`、`book/part-08/02-candidate-commits.md`、`book/part-06/06-required-checks-and-merge-queues.md`、`book/part-06/08-protected-refs-and-exceptions.md` | 已于 2026-08-30 拆分迁移；旧页保留 `legacy-redirect` 兼容入口 |
| `book/part-6/exercise.md` | `book/part-08/exercise.md` | 保留案例因果链，重写制品与运行证据 |

后续在六篇兼容目录中新增的 CI/CD 章节，统一登记到第八篇目标，不把兼容位置视为最终归属。

## 附录现有页面

| 当前文件 | v2 目标 | 动作 |
| --- | --- | --- |
| `book/appendix/glossary.md` | 原路径 | 持续扩写，术语首次定义仍以正文权威章为准 |
| `book/appendix/command-map.md` | 原路径 | 改为读取/写入对象、引用和风险级别索引 |
| `book/appendix/scenario-index.md` | 原路径 | 扩展为事故路径索引 |
| `book/appendix/checkout.md` | 原路径 | 历史保留；只承担旧教程兼容 |
| `book/appendix/experiments.md` | 原路径 | 扩展实验契约、依赖和不可验证边界 |
| `book/appendix/sources.md` | 原路径 | 增加来源分级、版本和核对日期 |

## v2 新写章节清单

下面只列 v1 没有权威来源的主要章节；名称可以在写作中微调，但主题不能无记录地删除。

| 目标篇 | 必须新写或大幅补齐 |
| --- | --- |
| 第三篇 | 对象格式与哈希迁移；index 冲突阶段；pack/delta/GC；porcelain 与 plumbing |
| 第四篇 | ort 策略；重命名/删除和目录冲突；rerere；签名标签边界 |
| 第五篇 | 原子推送、push options；托管平台控制面抽象 |
| 第六篇 | 工作流拓扑；合并请求状态机；所有权与审批；合并队列；过期检查 |
| 第八篇 | CI checkout；候选提交；制品证据；可重复构建；数据库迁移；运行版本核验 |
| 第九篇 | 性能测量；commit-graph/MIDX/bitmap；LFS；子模块；subtree；拓扑决策 |
| 第十篇 | 最小权限身份；签名与验证；不受信任仓库；hooks/CI 供应链；秘密扫描 |
| 第十一篇 | 现场保护；fsck/pack 取证；bundle/mirror；平台迁移；损坏和区域故障恢复 |
| 第十二篇 | 仓库生命周期；权限回收；审计留存；容量预算；策略即代码；恢复演练 |
| 第十三篇 | 按症状组织的工作区、引用、认证、性能、LFS、子模块、签名和损坏排障 |

## 已直接落入 v2 目标路径的章节

| 当前文件 | v2 目标 | 动作 |
| --- | --- | --- |
| `book/part-06/README.md` | 原路径 | 新写；第六篇只导航已经落盘的共享历史、评审与受保护更新正文，不预列占位章 |
| `book/part-06/01-branch-models-and-integration.md` | `book/part-4/09-review-ready.md`、`book/part-6/05-hotfix.md` | 新写并建立分支状态与整合拓扑的权威来源；承担主干、功能、发布、维护和堆叠分支的状态、责任与恢复契约 |
| `book/part-06/02-review-state-machine.md` | `book/part-4/09-review-ready.md`、`book/part-6/09-protected-branches.md` | 新写并建立厂商无关评审请求状态机；承担功能头、目标基线、候选、审批、检查、策略版本和条件引用更新的失效与重算 |
| `book/part-06/03-merge-strategies-and-history.md` | `book/part-3/06-merge-shapes.md`、`book/part-4/10-rebase-model.md`、`book/part-6/09-protected-branches.md` | 新写；承担 merge、squash、rebase merge 对 OID、父关系、签名、回滚、归因和评审映射的协作后果，基础命令仍由第三、四篇负责 |
| `book/part-06/04-reviewable-changes-and-stacks.md` | `book/part-4/09-review-ready.md`、`book/part-6/07-conflict-report.md`、`book/part-6/08-commit-quality.md` | 新写；承担评审范围、冲突结果报告、风险密度、提交序列、堆叠依赖、反馈吸收和候选重绑定，提交对象质量仍由第二篇提交章负责 |
| `book/part-06/05-ownership-approvals-and-stale-decisions.md` | `book/part-6/09-protected-branches.md`、`book/part-09/05-monorepo-topology-and-ownership.md` | 新写；承担路径/构建图/运行责任映射、审批角色、独立性、候选绑定、失效与替补机制 |
| `book/part-06/06-required-checks-and-merge-queues.md` | `book/part-6/09-protected-branches.md`、`book/part-6/12-ci-triggers-merge-queue.md`、`book/part-08/02-candidate-commits.md` | 新写；承担必需检查身份、结果状态、候选过期、队列 generation 与 expected-old 主线更新，第八篇继续承担 CI 候选生成细节 |
| `book/part-06/07-ci-identities-and-status-reports.md` | `book/part-10/02-machine-identities.md`、`book/part-08/01-triggers-and-checkout.md` | 新写；承担 runner、状态报告、合并与发布主体的权限分层、候选外信任根和结果撤销，凭据与执行细节仍引用第八、十篇 |
| `book/part-06/08-protected-refs-and-exceptions.md` | `book/part-6/09-protected-branches.md`、`book/part-12/03-policy-rules-and-exceptions.md` | 新写并建立单仓受保护引用权威来源；承担 old/new OID、主体、评审、检查、窄例外、行为探针和安全回退，组织级组合与推广继续由第十二篇负责 |
| `book/part-06/exercise.md` | `book/part-4/exercise.md`、`book/part-6/exercise.md` | 新写；用 A/B 堆叠变更、并发主线、候选失效、队列和窄例外贯通第六篇，并明确本地实验不模拟平台控制面 |
| `book/part-09/README.md` | 原路径 | 新写；第九篇只导航已经落盘的正文，不预列占位章 |
| `book/part-09/01-measure-before-optimizing.md` | 原路径 | 新写；承担规模维度、workload、Trace2、辅助索引和维护验收的权威解释 |
| `book/part-09/02-binary-and-lfs.md` | 原路径 | 新写；承担二进制边界、pointer/payload、水合、锁、迁移和灾难恢复的权威解释 |
| `book/part-09/03-submodule-and-subtree.md` | 原路径 | 新写；承担 gitlink、递归操作、发布顺序、subtree 历史复制、拓扑选型和迁移的权威解释 |
| `book/part-09/04-sparse-partial-workflows.md` | `book/part-4/14-refspec-partial-clone.md` | 新写；承担 refspec、shallow、partial clone、sparse-checkout、sparse-index 的组合边界、受限输入契约和恢复顺序 |
| `book/part-09/05-monorepo-topology-and-ownership.md` | `book/part-09/03-submodule-and-subtree.md`、`book/part-6/09-protected-branches.md`、`book/part-6/12-ci-triggers-merge-queue.md` | 新写并建立 monorepo 拓扑权威来源；承担构建图、变更闭包、所有权/运行责任、路径过滤、原子变更、拆分/合并和恢复责任，submodule/subtree 机制仍由第三章负责 |
| `book/part-10/README.md` | 原路径 | 新写；第十篇只导航已经落盘的正文，不预列占位章 |
| `book/part-10/01-credential-leak-history-cleanup.md` | 原路径 | 新写；承担凭据撤销、泄漏调查、全 ref 改写、对象回收、平台副本和重新污染治理的权威解释 |
| `book/part-10/02-machine-identities.md` | 原路径 | 新写；承担个人令牌、deploy key、机器人、应用安装、工作负载身份、短期凭据和 break-glass 的权威解释 |
| `book/part-10/03-ci-dependency-supply-chain.md` | 原路径 | 新写；承担第三方 Action/plugin、复用 workflow、远程模板、镜像、传递依赖、cache 和来源证明的权威解释 |
| `book/part-10/04-signatures.md` | 原路径 | 新写；承担 commit/tag 签名、格式选择、信任策略和密钥生命周期的权威解释 |
| `book/part-10/05-untrusted-repositories.md` | 原路径 | 新写；承担 owner 门禁、配置执行入口、filters、hooks 与递归依赖信任边界的权威解释 |
| `book/part-10/06-secret-scanning-and-exports.md` | 原路径 | 新写；承担扫描范围、发现与撤销边界、fsck 完整性、恶意对象/路径、archive/export-ignore、bundle 和下游副本治理的权威解释 |
| `book/part-11/README.md` | 原路径 | 新写；第十一篇只导航已经落盘的取证、迁移与灾难恢复正文，不预列占位章 |
| `book/part-11/01-preserve-and-acquire.md` | 原路径 | 新写；承担事故分流、写入冻结、文件系统/逻辑/平台/运行证据分层、布局盘点、逻辑采集、摘要保管链和恢复副本边界的权威解释 |
| `book/part-11/02-object-forensics-and-recovery.md` | 原路径 | 新写；承担 fsck 根和状态解释、lost-found、unreachable/dangling、alternates/promisor、replace refs、loose/pack/idx、donor 恢复和对象层验收的权威解释 |
| `book/part-11/03-history-attribution.md` | 原路径 | 新写；承担 blame、pickaxe、提交说明/pathspec 搜索、rename/copy 推断、merge 历史简化、逐父 diff 和 Git/外部证据边界的权威解释 |
| `book/part-11/04-bundle-mirror-backup.md` | 原路径 | 新写；承担恢复契约、完整/增量 bundle、prerequisite、mirror 删除传播、物理快照与 Git/LFS/平台分层恢复演练的权威解释 |
| `book/part-11/05-repository-platform-migration.md` | 原路径 | 新写；承担 Git/SVN 历史模型、OID/身份映射、LFS/submodule、平台协作数据、权限/CI 和单一写入权威 cutover 的权威解释 |
| `book/part-11/06-disaster-failover-and-failback.md` | 原路径 | 新写；承担主备复制滞后、故障分类、donor 恢复、条件提升、只读验收、旧主围栏和安全回切的权威解释 |
| `book/part-12/README.md` | 原路径 | 新写；第十二篇只导航已经落盘的组织级治理正文，不预列占位章 |
| `book/part-12/01-repository-lifecycle.md` | 原路径 | 新写；承担稳定资产身份、双重所有权、生命周期状态机、创建基线、转移、归档、待删除、恢复和治理登记门禁的权威解释 |
| `book/part-12/02-access-lifecycle.md` | 原路径 | 新写；承担有效授权图、入职/转岗/离职、外部协作者、机器 owner、直授例外、权限认证和 break-glass 生命周期的权威解释 |
| `book/part-12/03-policy-rules-and-exceptions.md` | 原路径 | 新写；承担组织规则 scope、组合语义、audit/canary 推广、窄例外、策略即代码信任边界、漂移检测与安全回退的权威解释 |
| `book/part-12/04-audit-logs-and-evidence-retention.md` | 原路径 | 新写；承担审计事件模型、多时钟、覆盖矩阵、游标/缺口/schema 完整性、原始与规范化证据、访问/留存/legal hold、调查包和审计灾备的权威解释 |
| `book/part-12/05-repository-health-capacity-maintenance.md` | 原路径 | 新写；承担多维仓库健康、分层容量预算、headroom、SLI/SLO、组织热点/故障域、维护状态机、scratch/互斥/事故门禁和维护后不变量的权威解释 |
| `book/part-12/06-incident-playbooks-and-drills.md` | 原路径 | 新写；承担事件分类与指挥角色、组织状态门禁、分层恢复验收、通信、停止条件、inject、演练层级和改进行动闭环的权威解释 |
| `book/part-13/README.md` | 原路径 | 新写；第十三篇只导航已经落盘的按症状排障正文，不预列占位章 |
| `book/part-13/01-evidence-first.md` | 原路径 | 从旧排障流程扩写；承担普通排障/安全/取证/组织事件分流、六坐标报障、八层诊断、命令副作用、最小证据包、三态结论、脱敏和动作卡的权威解释 |
| `book/part-13/02-missing-files-and-commits.md` | 原路径 | 新写；承担 worktree/index/tree/blob/外部 payload 路径诊断、restore 来源与目标、ignore/sparse、日志观察范围、ref/reflog/recovery ref、shallow/对象来源和不可恢复边界的权威解释 |
| `book/part-13/03-push-auth-and-permission-failures.md` | 原路径 | 新写；承担 endpoint/传输、服务器身份、客户端认证、仓库授权、非快进、保护规则、fetch/URL 副作用、force-with-lease 和 push 后发布证据链的症状排障解释 |
| `book/part-13/04-performance-and-capacity-failures.md` | 原路径 | 新写；按 status/log/switch/clone/fetch 症状分流性能与容量证据，覆盖 workload、规模指标、Trace2、Git/LFS/制品/备份/scratch 分层、辅助索引和维护后逻辑不变量 |
| `book/part-13/05-lfs-submodule-ci-failures.md` | 原路径 | 新写；按 pointer/payload、gitlink/嵌套仓库、candidate/checkout/构建输入分流 LFS、子模块与 CI clone 故障，覆盖 OID 保留、依赖发布顺序、浅/部分克隆、缓存与外部服务边界 |
| `book/part-13/06-signature-verification-failures.md` | 原路径 | 新写；按签名存在、密码学、key/principal、有效期/撤销和组织授权分流，覆盖 candidate 外部信任根、tag target、历史改写和 CI/发布验证边界 |
| `book/part-13/07-remote-ref-drift-failures.md` | 原路径 | 新写；按远端 refs、本地远程跟踪缓存、上游配置和平台控制面分流，覆盖分支重命名、prune、默认分支 symbolic ref、标签改指向、隐藏/权限边界和查询竞态 |
| `book/part-13/08-repository-corruption-locks-concurrency.md` | 原路径 | 新写；按锁与写入者、expected-old 引用并发、对象/pack 完整性、linked worktree 和维护互斥分流，覆盖 stale lock、fsck、donor 恢复和停止条件 |
| `book/part-08/README.md` | 原路径 | 新写；第八篇只导航已经落盘的发布与 CI/CD 正文，不预列占位章 |
| `book/part-08/01-triggers-and-checkout.md` | `book/part-6/12-ci-triggers-merge-queue.md`、`book/part-6/11-ci-evidence-chain.md` | 新写并收束入口职责；承担事件快照、checkout、路径过滤和权限边界，候选对象与结果过期迁入下一章 |
| `book/part-08/02-candidate-commits.md` | `book/part-6/11-ci-evidence-chain.md`、`book/part-6/12-ci-triggers-merge-queue.md` | 新写并建立候选对象权威来源；承担 feature/merge/squash/rebase/queue 候选、构造上下文、结果绑定、过期与条件更新 |
| `book/part-08/03-source-artifact-deployment-evidence.md` | `book/part-6/11-ci-evidence-chain.md`、`book/part-6/06-release.md` | 新写并收束证据链后半段职责；承担流水线/runner/依赖输入、制品摘要、发布引用、部署观测、数据库兼容和回退边界，可重复构建单独归入下一章 |
| `book/part-08/04-reproducible-builds.md` | `book/part-6/11-ci-evidence-chain.md`、`book/part-6/06-release.md` | 新写并建立构建确定性权威来源；承担输入闭包、非确定性、构建清单、逐字节/语义比较、缓存和构建一次提升同一制品 |
| `book/part-08/05-release-refs-and-artifact-promotion.md` | `book/part-6/06-release.md`、`book/part-6/11-ci-evidence-chain.md` | 新写并建立发布引用与制品提升权威来源；承担附注 tag、远端核对、发布清单、审批、同名竞态和跨环境提升，部署回退与数据库迁移留给后续章 |
| `book/part-08/06-deploy-and-rollback.md` | `book/part-6/06-release.md`、`book/part-6/05-hotfix.md`、`book/part-6/exercise.md` | 新写并建立运行控制面与回退权威来源；承担 rollout 状态、实例实际 digest、金丝雀/蓝绿/滚动策略、旧实例围栏、制品/配置/源码/数据库/数据回退和长任务边界，数据库迁移细节留给后续章 |
| `book/part-08/07-database-migrations.md` | `book/part-6/06-release.md`、`book/part-6/exercise.md` | 新写并建立数据库迁移权威来源；承担迁移批次与实际 schema 事实、兼容矩阵、expand/contract、回填 checkpoint、锁/事务边界、不可逆步骤、向前修复和跨服务消息边界 |
| `book/part-08/08-incident-to-release.md` | `book/part-6/05-hotfix.md`、`book/part-6/06-release.md`、`book/part-6/exercise.md` | 新写并建立事故发布综合权威来源；承担证据冻结、缓解/修复状态机、根因候选、bisect、hotfix/cherry-pick 来源与目标提交、共享依赖部署范围、运行验证和关闭复盘条件；现场取证、组织指挥和症状分流分别引用第十一、十二、十三篇 |

## 每个页面的迁移门禁

一个旧页面只有同时满足以下条件才可移出原目录：

1. 目标章已经落盘，内容达到 `docs/ACCEPTANCE.md` 的单章门槛；
2. 旧页面中的事实、案例、图和实验均有“迁入、废弃或历史保留”结论；
3. 新章的前置知识在目标阅读顺序中已经出现；
4. 所有入站相对链接和 `SUMMARY.md` 导航已经找到新目标；
5. 高风险命令的隔离实验在新位置通过；
6. 旧路径留下明确迁移页，链接到新章而不是静默 404；
7. `./scripts/verify-all.sh`、链接覆盖和 `git diff --check` 通过；
8. `docs/PROGRESS.md` 记录迁移日期、目标和仍保留的旧路径。

旧路径迁移页使用统一标记 `<!-- legacy-redirect -->`，正文说明权威内容的新位置和迁移日期。迁移页不复制完整正文，避免双份事实漂移。链接检查器在真正开始移动页面时再增加对该标记的专门规则；在此之前不得提前放宽公开页面覆盖检查。

## 分批实施顺序

1. 先创建全新内容占比最高的第八至十三篇，不移动现有基础路径；
2. 将已经重构成熟的对象、远程和恢复章节迁入第三、五、七篇；
3. 重构并迁移第一、二、四篇，保持基础读者路径连续；
4. 最后拆分协作与治理内容到第六、十二篇；
5. 全部目标篇具备 README、进入条件、退出能力和综合案例后，切换主 `SUMMARY.md`；
6. 完成旧链接迁移页、跨章去重和外部链接复核后，才删除“六篇基础结构”的状态表述。

这一顺序允许正文持续增长，同时避免目录先行造成“十三篇看似齐全、实际仍是占位”的假完成。
