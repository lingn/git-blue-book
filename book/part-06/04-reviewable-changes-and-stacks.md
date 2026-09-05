# 可审查变更：范围、提交序列与堆叠评审

评审效率取决于边界是否清楚。一个很小的 diff 也可能缺少依赖、数据迁移或运行证据，一个跨许多文件的变更也可能只有一个完整意图。把变更机械限制为固定行数，或要求每个文件单独提交，都不能替代范围、依赖和验证设计。

## 进入条件与完成标准

本章从[评审前准备](../part-4/09-review-ready.md)继续，假设候选仍在未共享或明确允许整理的功能分支。命令在开发者 clone 的仓库根目录执行，`base` 和 `candidate` 必须先赋值为完整 OID：

~~~bash
git fetch origin
candidate="$(git rev-parse --verify HEAD^{commit})"
target="$(git rev-parse --verify origin/main^{commit})"
base="$(git merge-base "$target" "$candidate")"
~~~

fetch 会更新本地远程跟踪引用。若当前分支已经被其他人、评审或 CI 引用，后续拆分和 rebase 会改变 OID，开始前要确认共享边界并建立恢复引用。

读完本章后，应能判断单个评审的合理范围，设计可验证提交序列，识别纯格式化、生成物和外部输入污染，并为堆叠评审维护明确的父子候选关系。

## 评审范围由一个意图和一组闭合依赖组成

每个评审请求应有一个能单独作出决定的意图。它可以包含接口、实现、测试、迁移和文档，只要这些变化共同完成同一个行为边界。评审说明至少回答：

- 这项变化解决什么问题，明确不处理什么；
- 从哪个目标 OID 比较，候选 OID 是什么；
- 哪些代码、schema、配置、消息、LFS、子模块或外部服务属于依赖；
- 哪些测试、构建和人工验证已经执行；
- 发布和回退需要哪些额外动作；
- 哪些风险需要特定所有者或专业角色审批。

两个功能可以独立发布和回退时，通常适合拆成两个评审。接口和唯一实现必须同时存在，拆开后任何一半都无法构建或验证时，放在同一评审更容易看清真实边界。

## 先用 Git 固定本地可见范围

~~~bash
git status --short --branch --untracked-files=all
git log --format='%H%x09%P%x09%s' "$base".."$candidate"
git diff --stat "$base"..."$candidate"
git diff --name-status "$base"..."$candidate"
git diff --check "$base"..."$candidate"
git ls-files --others --exclude-standard
~~~

这些命令只覆盖本地 Git 可见状态。三点 diff 从共同祖先比较到候选，适合描述功能变化；两点 log 列出候选可达、基线不可达的提交。未跟踪、忽略路径、LFS payload、子模块内部状态、CI secrets、制品和数据库实际状态都要另外记录。

如果平台展示的 diff 与本地不同，先核对目标 OID、候选类型、merge-base、路径过滤、重命名检测和浅克隆边界。不要先修改代码去迎合未知差异。

## 提交序列服务于评审和恢复

好的提交序列让评审者能逐步理解意图，也让 `bisect`、cherry-pick 和 revert 有可用边界。每个中间提交是否必须可部署，取决于项目约定；至少应可解释，并明确是否能独立构建和测试。

常见的合理顺序是先加入兼容接口或 schema，再切换调用方，最后删除旧路径。纯格式化、大规模重命名和生成物刷新容易淹没行为变化，通常应单独提交，并固定工具版本和输入。

提交原子性、说明、trailers、hook 与签名由[第二篇的提交章节](../part-2/07-commit.md)承担。本章只增加共享评审边界：一旦评审、CI 或子分支绑定某个提交序列，reword、squash、fixup 和 reorder 都会生成新 OID，需要使旧证据过期。

## 什么时候应拆分评审

出现以下信号时，先考虑拆分：

| 信号 | 拆分方向 | 不能忽略的依赖 |
| --- | --- | --- |
| 行为变化和全仓格式化混在一起 | 格式化先行或单独评审 | blame ignore、工具版本和合并顺序 |
| 基础重构与产品功能混在一起 | 先建立等价重构，再实现功能 | 等价性测试和两次候选的目标基线 |
| 多个服务可独立发布 | 按发布单元拆分 | 接口兼容、消息版本和部署顺序 |
| 数据库迁移含可逆准备和不可逆清理 | 按 expand、应用切换、contract 拆分 | 混合版本窗口和清理门禁 |
| 安全修复夹带普通优化 | 安全修复使用受控私密流程 | 泄漏范围、披露时间和回补分支 |
| 评审者集合完全不同 | 按所有权边界拆分 | 跨边界接口和最终集成候选 |

拆分后如果每个子评审都依赖尚未合入的前一个评审，就形成堆叠。堆叠不是问题，但必须显式维护依赖图。

## 堆叠评审需要稳定的父子映射

假设 `feature/api` 基于 `main`，`feature/ui` 又基于 `feature/api`。两个评审分别固定：

~~~text
review A: target=main@T, feature=api@A
review B: target=api@A, feature=ui@B
~~~

评审 B 的 diff 不能直接与 `main@T` 比较，否则会把 A 的变化重复显示。A 合入后，B 需要把目标改为新的主线，并按团队策略 rebase、merge 或重建。任何重建都会让 B 的候选、审批和检查可能过期。

本地查看堆叠边界：

~~~bash
parent="$(git rev-parse --verify feature/api^{commit})"
child="$(git rev-parse --verify feature/ui^{commit})"
git merge-base --is-ancestor "$parent" "$child"
git log --oneline "$parent".."$child"
git diff --stat "$parent"..."$child"
~~~

第一条成功只证明父对象是子对象的祖先。它不证明评审 B 的平台目标、审批、CI 或发布依赖配置正确。

## 变更大小要结合风险密度

行数可以用来提示评审负担，不能作为唯一门禁。更值得观察的是：独立行为数量、所有权边界数量、外部依赖、不可逆步骤、生成物比例、测试耗时、发布单元和失败影响。

一个 20 行权限变化可能需要安全、平台和服务 owner 共同评审；一个 1000 行生成文件更新，如果来源、工具和摘要可复现，人工逐行审查的价值可能很低。评审模板应要求作者解释哪些内容需要语义审查，哪些内容由自动生成和摘要验证承担。

## 评审反馈怎样进入历史

评审中发现问题后，可以追加修正提交，也可以在未共享边界内重建提交序列。追加提交保留讨论与 OID 的连续关系，适合多人已开始评审或子分支依赖当前候选；重建能改善最终历史，但会使旧位置失效。

团队应明确何时允许作者自行整理，何时必须先通知评审者。平台的“更新分支”按钮也会改变候选，使用前要知道它执行 merge、rebase 还是其他策略，以及旧审批如何处理。

不要把“所有反馈都 squash 掉”当成评审完成条件。需要保留的设计决定、失败实验和风险接受应进入评审记录、提交说明或决策文档，不能只存在于随后被删除的临时提交里。

## 冲突解决结果也属于评审输入

冲突标记被删除、测试变绿，只能说明当前工作区可以继续。评审还需要知道：冲突发生在哪个共同祖先、哪些路径有多个候选版本、最终选择怎样满足接口或数据约束，以及解决后的候选是否在干净环境重新验证。

在完成 merge、rebase 或 cherry-pick 后，先在最终候选所在的临时分支固定对象。具体的 index stage、AUTO_MERGE 和 rerere 机制见[第三篇复杂冲突](../part-3/10-complex-conflicts-rerere.md)。

~~~bash
git status --short --branch
candidate="$(git rev-parse --verify HEAD^{commit})"
git show --no-patch --format='%H%n%P%n%T%n%s' "$candidate"
git diff-tree --no-commit-id --name-status -r -M -C "$candidate^" "$candidate"
git diff --check "$candidate^" "$candidate"
~~~

合并提交有多个父，`$candidate^` 只表示第一父；报告需要另外列出完整 parent 列表，并按每个父比较最终 tree。rebase 或 cherry-pick 的候选通常只有一个父，但来源提交、目标提交和冲突解决仍要分别记录。命令失败时先保存 `MERGE_HEAD`、`REBASE_HEAD` 或 `CHERRY_PICK_HEAD`、index stages 和原始 stderr，不要用 `reset --hard` 清掉现场。

一份最小冲突报告可以写成：

~~~text
operation: merge | rebase | cherry-pick
base_or_source: <完整 OID>
target_before: <完整 OID>
candidate_after: <完整 OID>
parents: <按顺序列出>
conflicted_paths: <NUL 安全的路径清单>
decisions: <按路径写最终语义，不只写 ours/theirs>
validation: <命令、环境、结果和未覆盖范围>
review_impact: <哪些评论/审批因候选变化而失效>
rollback_or_forward_fix: <共享边界下的动作>
limitations: <无法从 Git 恢复的事实>
~~~

“选 ours”只描述了一个实现细节，不能说明最终行为；“冲突已解决”也不能替代测试、构建、数据库和部署证据。报告中的路径来自 Git 输出，跨进程传递时使用 NUL 分隔或结构化文件，避免换行路径被截断。

## 失败方式和恢复

| 现象 | 先固定 | 安全动作 |
| --- | --- | --- |
| 评审 diff 混入父评审变化 | 父/子目标和功能 OID、merge-base | 修正目标或重建堆叠映射，不手工忽略重复路径 |
| 拆分后中间提交不能构建 | 提交序列、依赖和测试结果 | 合并依赖步骤或明确阅读型提交，不能伪造绿色结果 |
| rebase 后旧评论找不到位置 | 旧新 OID、range-diff、评论锚点 | 保存映射并请求重新确认高风险意见 |
| 格式化掩盖行为变化 | 工具版本、纯格式化基线、语义 diff | 拆分或提供可复核辅助差异 |
| 生成物与源码不一致 | 生成工具、输入、摘要和干净构建 | 从固定输入重建，停止评审猜测产物 |
| 评审很小却影响多个发布单元 | 构建图、服务 owner、制品和部署计划 | 扩大所有权与发布验证范围，不按行数降级 |

## 小结

可审查变更由明确意图、闭合依赖、固定候选和真实验证组成。提交序列帮助理解与恢复，堆叠评审帮助拆分大型变化，两者都会引入 OID 和证据重绑定成本。评审大小要按风险密度判断，不能用行数或提交数量替代工程边界。
