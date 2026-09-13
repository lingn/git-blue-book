<!-- legacy-redirect -->

# 冲突解决正文已迁入 v2 第四篇

本页保留旧 URL。原来的现场采集、逐路径解决、abort、continue、最终 tree 和冲突报告内容已于 2026-09-14 重构迁移。

请阅读[解决、中止与验收](../part-04/07-resolve-abort-and-verify.md)。新章补充：

- `merge --abort`、`merge --quit` 与 `merge --continue` 的不同后果；
- `--autostash` 恢复及再次冲突边界；
- hook、签名、编辑器失败后的可重试状态；
- stage 0、两父 diff、最终 tree、业务测试和平台候选的分层验收；
- 可审计冲突报告字段。

隔离实验为 `scripts/verify-merge-resolution-control.sh` 和 `scripts/verify-part-3-conflicts.sh`。旧 URL 保留不表示旧输出样例是固定 Git 行为。
