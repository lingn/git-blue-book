<!-- legacy-redirect -->

# 远程跟踪正文已迁入 v2 第五篇

本页保留旧 URL。远程跟踪 ref、ahead/behind、prune、远端重命名、默认分支缓存和恢复边界已于 2026-09-14 与 fetch 合并重构。

请阅读[Fetch 与 FETCH_HEAD](../part-05/04-fetch-and-fetch-head.md)和[远程状态模型](../part-05/01-remote-state-model.md)。新章节分开服务器 ref、本地缓存、upstream、`FETCH_HEAD` 和平台控制面。

隔离实验为 `scripts/verify-fetch-remote-tracking.sh` 与 `scripts/verify-remote-ref-drift-failures.sh`。它们不模拟平台默认分支、SSO、审计或复制延迟。
