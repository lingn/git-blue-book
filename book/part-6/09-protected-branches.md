<!-- legacy-redirect -->

# 受保护分支与团队协作正文已迁入 v2 第六篇

本页保留旧 URL。原来的受保护分支正文已于 2026-08-31 按职责拆入 v2 第六篇，旧页不再复制评审、检查、合并队列和引用保护定义。

权威阅读顺序：

1. [评审请求状态机](../part-06/02-review-state-machine.md)，固定功能头、目标基线、候选、审批和策略版本。
2. [所有权和审批](../part-06/05-ownership-approvals-and-stale-decisions.md)，解释路径、构建图、运行责任、角色独立性和审批失效。
3. [必需检查与合并队列](../part-06/06-required-checks-and-merge-queues.md)，绑定检查报告者、候选、队列 generation 和 expected-old 更新。
4. [受保护引用与例外](../part-06/08-protected-refs-and-exceptions.md)，说明单仓引用保护、窄例外、行为探针和安全回退。
5. [组织级规则与例外治理](../part-12/03-policy-rules-and-exceptions.md)，处理跨仓作用域、组合、渐进执行、漂移和例外生命周期。

本地 Git 实验继续由 `scripts/verify-part-6-collaboration.sh` 验证 merge、squash、rebase 和 expected-old 引用更新。它不模拟托管平台的评审、身份、检查、队列、保护规则或审计事件。
