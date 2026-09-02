# 综合场景：从线上缺陷到修复发布与复盘

一次线上故障往往同时涉及 Git 历史、构建制品、部署状态和数据兼容。只把错误提交 revert 了，不能证明运行实例已经切回；只在生产分支 cherry-pick 了修复，也不能证明主线和其他支持分支已经包含同一逻辑。

本练习把第六篇的本地工具和第八篇的发布证据链串起来。Git 命令在临时仓库中运行，制品和运行状态用明确的合成记录表示，不伪造托管平台或生产系统输出。

## 练习边界

- 执行位置：临时 Git 仓库根目录及其两个工作树；
- 前置条件：Git 2.28 或兼容版本、Bash、可写临时目录；
- 身份：合成开发者、发布者和 CI 记录；
- 网络：可使用本地 bare 仓库，也可以只模拟提交图；
- 安全：不使用真实服务、客户数据、凭据或生产引用；
- 完成标准：找到候选坏提交，形成目标修复提交，固定制品摘要，记录部署和关闭条件。

## 1. 固定线上故障现场

故障单至少包含：

~~~text
incident: INC-2026-001
symptom: retry request creates duplicate settlement
first_seen: <带时区时间>
known_good: <正常版本 OID>
known_bad: <异常版本 OID>
runtime: <实例、制品摘要和配置版本>
data_state: <是否已经产生外部副作用>
scope: <受影响服务和请求条件>
~~~

先冻结证据，不要在生产分支反复提交或清理：

~~~bash
git status --short --branch
git rev-parse HEAD
git show --no-patch --format=fuller HEAD
git for-each-ref --format='%(refname) %(objectname)'
git reflog --all -5
~~~

第十一篇负责原始现场和证据清单。此处只固定 Git 候选和运行记录的关联，不把提交作者当作事故责任结论。

## 2. 用 bisect 缩小第一个坏提交

在有稳定回归测试的隔离 clone 中：

~~~bash
git bisect start
git bisect bad <known-bad>
git bisect good <known-good>
git bisect run ./scripts/reproduce-incident.sh
git bisect log > bisect.log
git show --format=fuller --stat <first-bad>
git bisect reset
~~~

reproduce-incident.sh 必须固定输入、依赖、数据库 fixture 和退出码。无法测试的提交返回 125，不能把环境缺失标成 bad。

bisect 结果说明“在这个范围和判定下第一个使症状出现的提交”。保存候选 OID、脚本版本、环境、输入摘要和日志。它可能不是最终根因，下一步还要阅读候选 diff、依赖和运行时间线。

## 3. 选择缓解、修复和回退

先区分三种动作：

| 动作 | 目的 | Git 形态 | 外部状态 |
| --- | --- | --- | --- |
| 缓解 | 降低当前影响 | 配置、feature flag 或部署控制 | 需要运行验证 |
| 修复 | 改变源码行为 | 新 commit、cherry-pick 或 merge | 需要构建和测试 |
| 回退 | 恢复已知良好行为 | revert 或部署旧制品 | 数据和消息另算 |

如果错误提交已经进入共享主线，通常不 reset 或强推，而是先用已知良好制品缓解，再准备修复提交。代码 revert 只能撤销 Git tree 的变化，不能撤销已经发送的消息、外部 API 调用或数据库写入。

## 4. 在维护分支迁移修复

假设修复已经在 main 的 fix_commit，release/1.x 需要同一变化：

~~~bash
git switch release/1.x
git status --short --branch
target_before="$(git rev-parse HEAD)"
git show --format=fuller --stat <fix_commit>
git cherry-pick <fix_commit>
picked_commit="$(git rev-parse HEAD)"
git show --no-patch --format='%H%n%P%n%T%n%s' "$picked_commit"
git diff "$target_before" "$picked_commit"
~~~

记录 source 和 picked 两个 OID。目标分支的上下文、配置、schema 和依赖可能不同，不能只看补丁能否应用。冲突按第四篇的来源/目标和第六篇的报告模板处理。

如果修复依赖主线前序重构，停止单独 cherry-pick，改为补齐依赖或选择合并策略。跳过一个提交会丢掉整个提交的变化，不能用来绕过业务冲突。

## 5. 构建一次并固定制品

构建记录至少包含：

~~~text
source_commit: <picked 或主线候选 OID>
pipeline_revision: <流水线配置 OID>
runner: <镜像和工具版本>
dependencies: <锁文件和外部来源>
inputs_manifest: <输入清单>
artifact_digest: <制品摘要>
tests: <命令和结果>
sbom/provenance: <来源证明>
~~~

同一候选在测试和生产环境应提升同一个不可变制品。不要让每个环境重新读取 main、重新解析浮动依赖或重新生成带时间戳的字节。制品摘要与 source_commit 的关系由第八篇证据链验证。

## 6. 部署和回退证据

部署请求绑定制品摘要、配置版本和数据库兼容状态：

~~~text
deployment: <请求 ID>
candidate: <源码 OID>
artifact: <digest>
config: <版本>
schema_before/after: <实际 schema>
rollout: canary -> paused -> resumed
instances: <实例实际 digest>
rollback_target: <已知良好制品>
stop_condition: <指标或错误阈值>
~~~

金丝雀发现错误时，先停止继续扩大范围，确认旧实例围栏和回退目标，再执行制品回退。数据库 expand/contract 和异步消息可能要求向前修复，不能只把代码分支退回旧提交。

实例实际 digest 与 Git 标签不一致时，以运行系统证据为准调查。发布标签、制品、部署和运行状态需要分别核对。

## 7. 主线和支持分支收束

修复完成后确认来源和目标分支：

~~~bash
git branch --contains <fix_commit>
git branch --contains <picked_commit>
git log --cherry-mark --oneline <fix_commit>...<picked_commit>
git log --first-parent --oneline main
git log --first-parent --oneline release/1.x
~~~

等价补丁可能有不同 OID，--cherry-mark 只是启发式提示。每条支持分支都要绑定自己的测试、制品和部署证据，不能用 main 已包含来代替 release 已发布。

合并或 cherry-pick 后运行对应服务和数据测试，记录未迁移的分支、外部依赖和后续行动。

## 8. 关闭事故

关闭前确认：

~~~text
evidence_frozen: yes/no
mitigation_verified: yes/no
first_bad_reviewed: yes/no
fix_source_and_target: <OID map>
artifact_verified: yes/no
deployment_instances: <实际 digest>
data_reconciliation: <结果>
monitoring_window: <观察周期>
follow_up: <回归测试、规则、容量和文档行动>
~~~

事故关闭不等于“提交已经合并”。还需要确认运行影响消失、数据和消息对账完成、回退目标仍可用、权限和临时开关已回收。

## 失败路径和恢复

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| bisect 结果不稳定 | 测试脚本、环境、输入、skip | 固定判定或停止自动结论 |
| fix_commit 无法 cherry-pick | source/target OID、依赖、冲突 | 补依赖或改用合并，不选一边 |
| 制品摘要与源码不匹配 | 构建 manifest、pipeline、缓存 | 隔离制品，重新构建候选 |
| 金丝雀失败 | 实例 digest、指标、配置、schema | 停止 rollout，回退已知良好制品 |
| 代码回退但数据仍异常 | migration、消息、外部调用 | 对账并执行向前修复或数据恢复 |
| 主线修复未迁移到维护分支 | branch contains、等价补丁、发布记录 | 按依赖顺序迁移并重新测试 |
| 事故证据不完整 | 原始日志、事件、OID、清单 | 保留 inconclusive，不提前关闭 |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-6-engineering.sh
./scripts/verify-incident-to-release.sh
./scripts/verify-reproducible-build.sh
./scripts/verify-deploy-rollback.sh
~~~

这些实验验证 bisect、worktree、cherry-pick、候选 OID、构建摘要和部署回退的合成状态。它们不证明真实生产实例、数据库、消息、平台审计、制品权限或业务恢复。

## 小结

事故到发布的可靠路径是：先冻结现场和运行证据，再用稳定判定缩小候选，分开缓解、源码修复和回退，记录 source/picked OID，构建并提升同一制品，最后按实例、数据和观察窗口关闭。Git 是源码坐标，不是整个事故状态机；任何没有外部证据支撑的“已恢复”都只能标为未知。
