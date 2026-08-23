# 从事故到发布：把缓解、修复和复盘串成一条证据链

线上故障发生时，团队通常同时面对三个压力：先把影响压住，尽快找到造成问题的变化，还要让修复经过可审计的构建和发布。只把这三件事混在一个“回滚”按钮里，容易丢失现场、把错误候选再次发布，或让一个服务修好而另一个共享依赖的服务仍运行旧逻辑。

本章把第八篇前七章组合成一条软件交付链，重点是事故中的发布决策，不重复第十一篇的取证细节或第十二篇的组织级演练。第十一篇负责如何保护现场和采集对象，第十三篇负责症状分流，第十二篇负责事件角色、通信和恢复演练；本章负责把已确认的运行事实转成修复候选、制品、发布、部署和关闭证据。

本章以 Git 2.49.0、Bash 和本地隔离仓库为实验基线，核对日期为 2026-08-23。实验只验证 Git 对象、候选提交、制品摘要、部署清单和状态机，不连接真实 CI、制品库、数据库、队列或托管平台。真实事故必须遵守组织的权限、隐私、证据保留和变更审批制度。

## 进入条件和退出能力

进入本章前，读者应理解候选与 checkout、可重复构建、发布引用、rollout、数据库迁移和长任务边界。读完后，应能：

- 把缓解动作、根因假设、修复提交、发布制品和运行验证分开记录；
- 在不覆盖现场的前提下，固定线上制品、配置、schema、实例、消息和影响窗口；
- 用受控的历史搜索或 `bisect` 缩小候选，并区分首个坏提交、修复来源提交和发布分支目标提交；
- 选择直接制品回退、配置缓解、队列围栏、源码修复、数据库向前修复或数据恢复；
- 把共享库或多服务修复构造成一个可以核对的候选和部署范围；
- 以运行实例、业务指标、消息积压和数据不变量证明事故已缓解、修复已生效并且可以关闭。

## 事故发布状态机

事故中的状态不能只用 `open` 和 `closed`。一个最小但可审计的状态机如下：

```text
detected
  -> triaged
  -> evidence_frozen
  -> mitigated
  -> root_candidate_identified
  -> fix_candidate_built
  -> release_approved
  -> rollout_observing
  -> resolved
  -> closed

triaged / evidence_frozen / mitigated / rollout_observing
  -> stopped
  -> rollback_or_forward_fix
  -> inconclusive
```

每次转换都要记录主体、时间、输入摘要、决策理由和下一步验证。`mitigated` 表示影响暂时下降，不表示根因已经修复；`resolved` 表示修复在运行环境和业务指标上通过；`closed` 还需要证据包、行动项和消费者通知完成。缺少关键证据时使用 `inconclusive`，不能为了结束工单把它改成成功。

事故记录的最小字段可以是：

```text
incident_id / severity / detected_at / impact_window
observed_environments / affected_components
runtime_artifact_digests / configuration_versions
database_schema_and_migration_batch / queue_or_task_state
evidence_bundle_digest / access_scope
mitigation_actions / rollback_target
root_candidate / fix_source_commit / fix_target_commit
build_manifest_digest / release_tag / deployment_id
validation_window / business_metrics
decision_actor / approval_id / status / closure_reason
```

记录中不得写入 token、私钥、完整环境变量或未经脱敏的用户数据。证据包的保管链、访问和法律保留见第十一篇；本章只要求发布记录引用稳定的证据包 ID 和摘要。

## 第一步是固定运行事实，不是猜根因

发现故障后，先记录当前事实，再讨论代码。至少固定：

- 受影响环境、区域、集群、实例和流量比例；
- 实例实际 `artifact_digest`、build identity、配置/secret 版本和数据库 schema/migration 批次；
- 请求、任务、消息、重试、积压和外部副作用的时间线；
- 首次出现、峰值、缓解和当前观察窗口；
- 监控查询定义、样本量、时区和是否存在采样/缓存；
- 当前 Git 候选、发布 tag、构建清单和部署记录的完整 OID。

如果需要采集工作区、index、refs、reflog 或不可达对象，先按[事故现场保护与证据采集](../part-11/01-preserve-and-acquire.md)执行。不要在生产 clone 中为了“复现一次”运行会写 refs、清理对象、执行 hook 或下载未知过滤器的命令。第十三篇的[最小排障证据集](../part-13/01-evidence-first.md)提供症状入口，但不能替代运行平台和业务数据。

### 缓解动作与修复动作分开

缓解动作优先减少影响，可能包括暂停队列、降低流量、关闭特性、隔离租户、切回已知良好制品或限制写入。修复动作要改变代码、配置、schema 或数据，使根因不再发生。两者都要记录作用范围和副作用：

| 动作 | 可能立即减少什么 | 不代表什么 | 需要补的验证 |
| --- | --- | --- | --- |
| 暂停任务/队列 | 新的重复执行或积压增长 | 已运行任务已安全完成 | 活跃任务、重试、幂等键、积压和恢复顺序 |
| 关闭 feature flag | 暴露流量或新写路径 | 已写入新格式的数据已被修复 | 旧路径读写、配置版本、缓存传播 |
| 回退制品 | 新二进制继续产生错误 | schema、消息和外部副作用已经恢复 | 实例 digest、兼容矩阵和业务指标 |
| 限制流量/隔离入口 | 受影响请求数量 | 根因已经定位 | 流量分布、未受影响范围和容量 |
| 数据补偿/向前修复 | 已产生的数据异常 | 代码错误不再产生新异常 | 校验、幂等、重放和审计 |

缓解完成后，状态应为 `mitigated`，并保留仍未解决的问题列表。不要因为错误率下降就删除原始指标或覆盖当前制品记录。

## 用历史证据缩小根因候选

根因定位要把运行时间线与提交图对齐。线上制品对应的提交不是“最近提交”，而是部署记录中已经核对的 `source_commit`。先固定已知正常和已知异常版本，再选择 `git log`、`git diff`、`git blame`、`-S`/`-G` 或 `git bisect`。

在一个受控的诊断 clone 中，已知测试可在每个提交上运行时，才适合使用 `bisect`：

```bash
git status --short --branch
git bisect start
git bisect bad <KNOWN_BAD_COMMIT>
git bisect good <KNOWN_GOOD_COMMIT>
git bisect run ./scripts/reproduce-incident.sh
git bisect log > /restricted/evidence/bisect.log
git bisect reset
```

前置条件是 `KNOWN_BAD_COMMIT` 和 `KNOWN_GOOD_COMMIT` 已从运行记录或验证环境取得，测试脚本能区分 good、bad 和无法判断三种结果，当前 clone 没有需要保留的未提交修改。`bisect` 会移动当前 `HEAD` 并改写工作区，脚本也可能执行构建、网络或数据库操作；只在可销毁副本中运行。保存 `bisect log`、每次测试退出码、实际检出 OID 和脚本版本。

成功输出只说明在给定 good/bad 范围和测试判定下找到一个候选边界。它不证明候选是唯一根因，也不证明平台配置、依赖、数据或并发条件没有参与。脚本返回无法判断时应退出 125 或组织约定的 neutral 状态，不能把环境失败算作 bad。完成后执行 `git bisect reset`，检查原始引用和工作区是否回到预期。

如果不能稳定重现，就不要为了让 `bisect` 运行而把线上数据或秘密复制到本地。改用运行日志、部署时间线、提交差异和受控回放建立候选集合，并把结论标成“相关”而不是“已证明因果”。

## 修复来源和发布目标必须分开

紧急修复经常先在一个分支完成，再迁移到稳定发布线。`cherry-pick` 会产生新的目标提交，不能把来源 OID 当成发布 OID：

```bash
git switch --create hotfix/incident-<ID> <RELEASE_BASE>
# 在受控工作区编辑并测试修复
git add -- <changed-paths>
git commit -m "fix: make task execution idempotent"
fix_source_commit="$(git rev-parse HEAD)"

git switch <RELEASE_BRANCH>
git cherry-pick "$fix_source_commit"
fix_target_commit="$(git rev-parse HEAD)"
git show --no-patch --format='%H%n%P%n%s' "$fix_target_commit"
```

前置条件是发布基线和稳定分支已经冻结，修复范围、测试和变更审批已明确，工作区没有未保存内容。`cherry-pick` 会在目标分支创建新提交，可能冲突、产生空提交或改变上下文；冲突时保存状态，按[冲突与恢复](../part-5/12-recovery-cases.md)处理，不能跳过测试直接继续。来源提交和目标提交都要写入事故记录、构建清单和发布记录。

共享库被 manager、worker、CLI 或多个服务使用时，先从构建图和制品清单确定部署范围。目录名、提交说明和“改动看起来只在一个模块”都不能证明其他服务不受影响。若多个服务必须同时升级，把它们作为一个候选和 rollout 计划观察；若协议允许错峰，记录混合版本窗口和兼容性证据。

## 从修复候选到生产验证

修复候选应重复使用前七章定义的门禁：

1. 固定目标提交、源码 tree、流水线定义、依赖、工具链和 runner；
2. 运行回归测试和事故复现测试，保存原始输出与退出码；
3. 构建一次并保存 `build_manifest_digest`、`artifact_digest` 和来源提交；
4. 创建候选发布记录和必要的附注 tag，不移动已共享错误 tag；
5. 在 staging 或受控环境验证实例 digest、配置、schema、消息和回退目标；
6. 按 rollout 计划部署受影响的全部组件，先观察再扩大流量；
7. 以版本维度的错误率、重复率、积压、数据校验和关键业务结果判断是否 resolved。

发布批准只允许把“这组输入可以部署”写入状态。生产控制面接受请求、任务定义指向目标 digest 和少量探针通过，都不能单独证明事故已经解决。运行版本、业务指标和时间窗口必须与事故机制对应。

## 一次完整事故的证据顺序

可以用以下顺序组织发布记录：

```text
incident detected
  -> runtime baseline fixed
  -> mitigation applied and verified
  -> candidate range and first-bad evidence
  -> fix source/target commits reviewed
  -> build manifest and artifact digest verified
  -> release ref and approval recorded
  -> all affected components deployed
  -> instance and traffic observations pass
  -> data/message/task invariants pass
  -> rollback target confirmed
  -> closure evidence and follow-up actions
```

每一步都要能指向一个原始记录。时间线不能只写“下午发布修复”，而应包含事件时间、日志时间、Git 提交时间、构建时间、部署批次和观测窗口，并标注时钟来源。若多个系统时钟不同，保存原始时间和规范化时间，不用后者覆盖前者。

## 关闭条件和复盘输出

事故只有在以下条件同时满足时才能关闭：

- 新旧实例实际 digest 与部署记录一致，旧版本已按计划围栏；
- 受影响请求、任务和消息在观察窗口内没有继续产生同类错误；
- 数据库 schema、回填、约束和关键业务不变量通过校验；
- 外部副作用、补偿、重试和积压有明确结论；
- 回退或向前修复目标仍可取得，证据包和访问范围已经登记；
- 根因、促成条件、检测缺口和修复范围有证据支持；
- 长期修复、测试、监控、权限或流程行动项有 owner、截止日期和验收方式。

复盘应区分四类内容：事实时间线、因果解释、不确定性和行动项。不要把“某个提交是第一处失败”直接写成“某个人造成事故”，也不要把没有被检测到的条件当成不存在。提交图、构建证据和运行证据回答不同问题，复盘必须把它们分开引用。

一个可复用的关闭摘要可以是：

```text
incident_id:
impact_window:
mitigation_and_effect:
runtime_baseline:
first_bad_candidate_and_method:
fix_source_commit / fix_target_commit:
artifact_digest / build_manifest_digest:
affected_components_and_rollout:
database_and_message_validation:
rollback_or_forward_fix_target:
remaining_uncertainty:
follow_up_actions / owners / due_dates:
closure_approval:
```

## 故障分流与恢复

| 症状 | 先固定 | 当前动作 | 关闭前还要证明 |
| --- | --- | --- | --- |
| 错误率下降但根因不明 | 版本维度指标、缓解开关、制品和配置 | 保持 `mitigated`，继续定位 | 修复候选和反事实验证 |
| `bisect` 找到候选但线上仍失败 | 测试范围、数据/配置差异、依赖和并发 | 标记候选而非根因，扩大受控复现 | 运行证据与代码差异一致 |
| 修复来源提交已通过，目标分支冲突 | 来源/目标 OID、冲突文件、测试范围 | 解决冲突并重新验证目标候选 | 目标提交独立构建和评审 |
| manager 已更新，worker 仍旧版本 | 构建图、实例 digest、任务和消息协议 | 暂停新任务或同步 rollout | 所有受影响组件和长任务状态一致 |
| 数据修复成功但仍有重复消息 | 消息 ID、重试、幂等记录、消费者版本 | 围栏/去重/补偿，保留新旧协议 | 积压清零且无新增副作用 |
| 新制品已部署但业务指标未恢复 | 实例实际 digest、配置、schema、流量分布 | 停止扩大，回退或向前修复 | 机制相关指标和数据不变量通过 |
| 指标恢复但证据包不完整 | 时间线、访问日志、原始产物和主体 | 状态为 `inconclusive`，补采证据 | 证据完整性和保管链通过 |

恢复动作失败时不要覆盖原始部署或迁移记录。为每次重试生成新的 attempt，引用原 incident、candidate 和 rollback target，确保后续能区分“第一次修复没生效”和“第二次修复改变了结果”。

## 隔离实验与真实边界

在仓库根目录运行：

```bash
bash scripts/verify-incident-to-release.sh
```

前置条件是 Bash、Git 2.28 或更高版本，以及 `awk`、`grep` 和 `sha256sum` 或 `shasum`。实验在临时仓库中创建已知正常提交、引入重复执行缺陷的提交和独立修复来源；使用 `git bisect` 找到候选，再把修复 `cherry-pick` 到稳定分支，生成制品摘要、候选 tag、双服务部署清单和关闭记录。

实验验证：

1. 事故记录固定运行基线、影响窗口、当前制品和缓解状态；
2. `bisect` 的首个坏提交、修复来源提交和稳定分支目标提交分别保存；
3. manager 与 worker 的部署清单引用同一不可变制品摘要，旧任务被围栏；
4. 主线在发布后继续前进不会改变已部署摘要和事故记录；
5. 只有实例 digest、重复率、积压和数据校验满足条件时，状态才从 `rollout_observing` 进入 `resolved` 和 `closed`。

成功输出为：

```text
Incident evidence freeze, first-bad isolation, cherry-picked hotfix, dual-service promotion, and closure checks passed.
```

实验只证明本地 Git 数据面、文件摘要和状态清单的不变量。它不证明真实日志平台、CI runner、制品库、数据库、消息系统、流量网关、权限、通知、业务指标或组织审批；生产事故必须在对应系统中保留原始证据，并使用第十一、十二、十三篇的专用流程。

## 综合练习：重复任务事故

某个结算任务出现重复执行。线上 manager 和 worker 都运行同一公共 SDK，但发布记录只有一个版本字符串，数据库完成了部分 expand，队列中还有旧消息。错误率在关闭特性开关后下降，但重复率没有立即归零。

请写出从发现到关闭的处理方案，至少回答：

1. 先固定哪些运行、Git、制品、数据库、消息和外部副作用证据；
2. 哪些动作属于缓解，哪些动作才是修复，如何防止缓解掩盖根因；
3. 如何选择 good/bad 边界并验证 `bisect` 结果，不能稳定复现时怎么办；
4. 修复先在开发分支完成时，如何保存来源提交和稳定分支目标提交；
5. manager、worker、长任务和旧消息如何安排 rollout 与围栏；
6. 哪些实例、业务指标、数据和证据条件满足后才可以关闭事故。

合理方案会先固定运行版本和数据边界，暂停新增任务或启用幂等围栏，再建立独立修复候选。它不会把关闭开关当成根因修复，不会只部署 manager，也不会因为一个绿色测试或平台页面状态就宣布事故结束。

## 小结

事故发布不是“找到一个提交并打标签”，而是从运行事实到修复候选、制品、部署和关闭证据的连续状态机。缓解、根因定位、修复、数据库/消息处理和回退各自有边界，必须在同一条记录中关联而不互相替代。

先保护现场和固定基线，再缩小候选并区分来源/目标提交；构建一次、提升不可变制品，部署所有受影响组件，观察实例和业务不变量，最后以完整证据包和行动项关闭。这样复盘留下的是可验证的因果链，而不是一组无法重现的命令和结论。

## 资料

- [git-bisect](https://git-scm.com/docs/git-bisect)
- [git-cherry-pick](https://git-scm.com/docs/git-cherry-pick)
- [git-revert](https://git-scm.com/docs/git-revert)
- [git-archive](https://git-scm.com/docs/git-archive)
- [git-update-ref](https://git-scm.com/docs/git-update-ref)
