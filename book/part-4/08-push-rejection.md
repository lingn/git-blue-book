<!-- legacy-redirect -->

# Push 拒绝正文已迁入 v2 第五篇

本页保留旧 URL。拒绝分层、non-fast-forward、显式租约、`--force-if-includes`、`--atomic`、多 ref 部分成功、push options 和 receive hooks 已于 2026-09-14 重构迁移。

请阅读[Push 拒绝、原子更新与 options](../part-05/07-rejection-atomic-push-and-options.md)。需要理解显式共享历史改写时，看[显式租约](../part-07/10-explicit-force-lease.md)和[共享历史改写政策](../part-07/09-public-history-policy.md)；需要理解受保护引用，看[受保护引用与例外](../part-06/08-protected-refs-and-exceptions.md)；按错误症状排查，看[Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md)。

实验由 `scripts/verify-push-ref-updates.sh` 覆盖，验证范围仅限本地 Git receive-pack 和合成 hook，不代表 GitHub、GitLab 或其他托管平台的实际策略。
