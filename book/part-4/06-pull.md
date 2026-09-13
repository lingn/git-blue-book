<!-- legacy-redirect -->

# Pull 正文已迁入 v2 第五篇

本页保留旧 URL。Pull 的 fetch/整合两阶段、ff-only、merge、rebase、autostash、上游缺失和失败恢复已于 2026-09-14 重构迁移。

请阅读[Pull 是 fetch 加本地整合](../part-05/05-pull-as-composition.md)。新章要求在发布、取证和共享主线场景拆开 fetch、审查和整合，保留每阶段 OID。

隔离实验为 `scripts/verify-pull-composition.sh`。它不模拟真实凭据、平台保护、合并队列或业务测试。
