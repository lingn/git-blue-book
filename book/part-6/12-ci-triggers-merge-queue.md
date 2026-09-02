<!-- legacy-redirect -->

# CI 触发、候选与合并队列正文已迁移

本页保留旧 URL。原来的触发器、路径过滤和合并队列正文已于 2026-08-30 按职责迁入第八篇，并与受保护分支入口建立唯一事实来源。

请按问题阅读：

- [触发与 checkout](../part-08/01-triggers-and-checkout.md)，解释 push、评审、标签、定时和手工事件怎样固定 old/new OID，路径过滤如何选择检查，以及 runner 实际检出什么。
- [候选提交](../part-08/02-candidate-commits.md)，解释功能头、目标头、临时合并、squash、rebase 和队列候选，以及检查结果为什么会过期。
- [必需检查与合并队列](../part-06/06-required-checks-and-merge-queues.md)，解释检查身份、候选过期、队列 generation 和 expected-old 更新。
- [受保护引用与例外](../part-06/08-protected-refs-and-exceptions.md)，解释一次主线引用更新需要哪些评审、检查、身份和服务端裁决。
- [规则不是开关](../part-12/03-policy-rules-and-exceptions.md)，解释组织级作用域、组合语义、渐进执行和例外生命周期。

本地实验继续由 scripts/verify-ci-trigger-queue.sh 验证路径选择、候选过期、队列顺序和 expected-old 条件引用更新。它不模拟托管平台事件字段、检查身份、合并队列权限、套餐或审计日志。
