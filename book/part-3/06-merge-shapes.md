<!-- legacy-redirect -->

# 合并历史形状正文已迁入 v2 第四、六篇

本页保留旧 URL。快进、分叉、二父合并、squash 与团队整合策略已于 2026-09-14 按操作和协作职责拆分。

权威阅读顺序：

1. [快进与合并提交](../part-04/04-fast-forward-and-merge-commits.md)，解释本地祖先关系、ref 移动、父顺序、结果 tree 和恢复时点。
2. [Merge、squash 与 rebase merge](../part-06/03-merge-strategies-and-history.md)，比较三种平台整合方式对 OID、评审映射、签名、回滚和归因的影响。

本地实验由 `scripts/verify-merge-shapes.sh` 和 `scripts/verify-part-6-collaboration.sh` 覆盖。它们不模拟平台审批转移、服务端签名、合并队列或审计事件。
