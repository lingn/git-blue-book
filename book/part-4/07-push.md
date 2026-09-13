<!-- legacy-redirect -->

# Push 正文已迁入 v2 第五篇

本页保留旧 URL。Push 的 source/destination、对象与 ref 两阶段、upstream、显式 refspec、dry-run、标签、删除和成功后证据已于 2026-09-14 重构迁移。

请阅读[Push 与远端引用更新](../part-05/06-push-upstream-and-ref-updates.md)。Push 被拒绝、原子更新和 push options 见[Push 拒绝、原子更新与 options](../part-05/07-rejection-atomic-push-and-options.md)。涉及共享历史时，再看[显式租约](../part-07/10-explicit-force-lease.md)；涉及受保护引用，转到[受保护引用与例外](../part-06/08-protected-refs-and-exceptions.md)；涉及症状分流，转到[Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md)。

隔离实验入口为 `scripts/verify-push-ref-updates.sh`。本地 bare/`file://` 实验不模拟真实认证、平台保护、评审、CI、制品或部署。
