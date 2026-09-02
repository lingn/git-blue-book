# 综合场景：两项并发变更怎样安全进入主线

本练习把分支状态、评审候选、合并方式、审批、必需检查和 expected-old 更新连起来。Git 部分可以在本地隔离仓库复现；评审、身份、检查和队列部分使用证据表推演，不伪造任何托管平台输出。

## 场景与目标

团队的 `main` 由合并服务更新，普通开发者不能直接推送。变更 A 修改共享校验库，变更 B 修改调用方并依赖 A。两项变更几乎同时完成：A 已通过代码所有者审批，B 的单元测试也通过，但主线在这段时间又进入了一项无关修复 C。

需要回答：

- A、B 是拆成独立评审还是合并成一个评审；
- 每个评审的目标、功能头和候选是什么；
- C 进入主线后，哪些审批和检查仍可使用；
- 选择 merge、squash 或 rebase merge 会留下哪些对象；
- 合并服务怎样避免用旧基线覆盖新提交；
- 发生检查服务故障时，能否以及怎样使用例外。

## 前置条件和安全边界

- Git 2.28 或更高版本；
- POSIX shell、`mktemp` 和本地文件系统；
- 不需要网络、真实账号、令牌或托管平台；
- 所有写操作只发生在脚本创建的临时目录；
- 本地 hook 或 `update-ref` 结果只证明 Git 数据面，不证明平台评审和授权。

先运行自动实验：

~~~bash
./scripts/verify-part-6-collaboration.sh
~~~

脚本成功时输出各阶段名称和最终 `PASS`，临时目录由 trap 清理。失败时会保留当前阶段的错误输出，脚本退出非零；它不会修改当前书稿仓库。

## 第一阶段：固定事件快照

假设事件到达时：

~~~text
main@T0
A feature head@A1, target=T0
B feature head@B1, parent dependency=A1, target=A1
C feature head@C1, target=T0
~~~

A 与 B 是堆叠关系。B 的直接比较基线是 A1，不是 T0；若平台把 B 直接与 main 比较，diff 会重复包含 A。先为两项评审写 candidate record：

| 字段 | 评审 A | 评审 B |
| --- | --- | --- |
| review ID | `R-A` | `R-B` |
| target ref | `refs/heads/main` | A 的功能 ref 或明确依赖目标 |
| target OID | `T0` | `A1` |
| feature OID | `A1` | `B1` |
| merge-base | `T0` | `A1` |
| candidate type | 由团队策略填写 | 由团队策略填写 |
| required owners | 共享库 owner | 调用方 owner，加共享库影响确认 |
| checks | 共享库测试、反向依赖 | 调用方测试、集成测试 |

如果构建图证明 B 不能在没有 A 的情况下构建，保持堆叠；如果 A 与 B 只能一起发布和回退，也可以合并成一个评审，但要说明为什么一个决定比两个独立决定更准确。不能只因“平台不方便展示堆叠”就隐藏依赖。

## 第二阶段：检查本地 Git 边界

在实验脚本创建的临时仓库里，三种合并方式都从同一组内容构造。脚本断言：

- merge commit 有两个父，原功能头仍是祖先；
- squash commit 只有目标父，原功能头不是祖先；
- rebase 后新功能头 OID 改变，最终 tree 与预期集成结果一致；
- expected-old 不匹配时，`git update-ref` 拒绝覆盖并发更新。

手工查看任一临时实验时，先复制脚本并注释 cleanup，再只在临时仓库执行：

~~~bash
git log --graph --decorate --oneline --all
git show --no-patch --format='%H%n%P%n%T%n%s' <final-oid>
git merge-base --is-ancestor <feature-oid> <final-oid>
~~~

不要在真实 `main` 上复现，也不要把示例占位符原样执行。

## 第三阶段：C 进入主线后使候选过期

C 先把主线从 `T0` 更新到 `T1`。A 的功能头仍是 `A1`，但基于 `T0` 的组合候选已经过期。A 的代码所有者审批是否保留，要按团队规则判断；集成检查必须基于 `T1+A1` 重建。

为 A 生成新记录：

~~~text
review_id: R-A
feature_oid: A1
old_target_oid: T0
new_target_oid: T1
new_candidate_oid: A2
candidate_type: <merge/squash/rebase/queue>
invalidation:
  - old integration check expired
  - release/integration approval reevaluated
~~~

B 同时受两层变化影响。A 合入后会产生最终对象 `A-final`，B 要把父依赖从 `A1` 更新到 `A-final`。如果 rebase，B1 会重建为 B2；旧评论、审批和检查需要按旧新 OID 映射处理。

## 第四阶段：审批与检查分别求值

对每项证据写出“属于哪个候选”，不要只写状态：

| 证据 | 绑定对象 | C 进入后的处理 |
| --- | --- | --- |
| A 共享库 owner 审批 | `A1` 的路径变化 | 按审批保留规则决定，保留也要记录目标变化 |
| A 集成检查 | 基于 `T0+A1` 的旧候选 | 过期，必须在 `T1` 重建 |
| B 单元测试 | `B1` | B rebase 或依赖变化后过期 |
| B 集成检查 | `A1+B1` | A 最终对象变化后过期 |
| 规则版本 | `P1` | 若规则变更为 `P2`，全部按新策略重新求值 |

审批和检查不是同一种证据。代码 owner 可能确认 A 的实现没有变化，集成检查仍必须覆盖新基线；安全或发布审批也可能因目标和依赖变化而失效。

## 第五阶段：队列和条件更新

假设 A、B 最终都进入合并队列：

~~~text
generation G7
position 1: QA = integrate(T1, A1)
position 2: QB = integrate(QA, B2)
~~~

QA 的检查只属于 A 所在位置，QB 的检查属于包含 A 的 B 候选。A 离队或更新后，QB 必须重建。队列准备写主线时，先比较服务器当前值是否仍是 `T1`；不匹配就使 generation 过期。

本地实验使用：

~~~bash
git update-ref refs/heads/main <new-oid> <expected-old-oid>
~~~

命令必须在隔离仓库中执行。成功会移动本地引用；expected-old 不匹配时退出非零并保持引用不变。托管平台还需要把审批、检查和身份决定接到同一次服务端更新，本地命令不证明这部分原子性。

## 第六阶段：检查服务故障时的决策

集成检查服务不可用，现有结果属于旧候选。安全选项依次是恢复检查服务、切换到事先批准的等价检查，或按预定义事故流程申请窄例外。例外不得把所有必需检查永久关闭。

一次窄例外记录：

~~~text
exception_id: EX-2026-017
incident_id: INC-2026-084
repository_id: payments
target_ref: refs/heads/main
expected_old: T1
allowed_actor: merge-service
allowed_action: update current queue candidate only
waived_rule: integration-check-v3
compensating_controls: independent approval, manual regression, canary stop gate
expires_at: <短时限>
~~~

实际是否允许例外由团队风险和平台能力决定。没有预定义流程、无法固定候选或无法保留审计时，应停止合并，不现场授予全员管理员权限。

## 结果验收

完成推演后，应能交付一份记录：

- T0、T1、A1、B1、B2、QA、QB 和最终主线的完整 OID 或明确占位；
- A、B 的依赖关系和拆分理由；
- 每条审批、检查和例外绑定的候选与策略版本；
- 合并方式及最终父关系；
- expected-old 条件更新的结果；
- 本地实验能证明和不能证明的边界；
- 若进入发布，第八篇要求的制品摘要、rollout 和运行验证入口。

以下情况不能通过验收：只保存分支名和评审编号；把 `T0` 的绿色结果转给 `T1` 候选；用功能头检查代替组合候选；用管理员强推解决 expected-old 失败；或把本地 hook 输出写成托管平台行为。

## 恢复

自动实验自行清理临时目录。推演文档写错时，修正记录即可，不应操作真实仓库。若在真实评审中发现候选错绑，先停止合并和发布，固定当前功能头、目标头、队列 generation、检查与审批事件，再从正确基线重建。已经错误进入主线的提交按共享历史使用 revert 或向前修复，并将源码、制品、数据库和运行状态分别处理。
