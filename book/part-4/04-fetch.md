<!-- legacy-redirect -->

# Fetch 与 FETCH_HEAD 正文已迁入 v2 第五篇

本页保留旧 URL。Fetch 的对象传输、remote-tracking 更新、`FETCH_HEAD`、prune、atomic、标签和失败分流已于 2026-09-14 重构迁移。

请阅读[Fetch 与 FETCH_HEAD](../part-05/04-fetch-and-fetch-head.md)。新章明确 fetch 不移动本地工作分支，并区分短期 `FETCH_HEAD`、持久 remote-tracking ref 与服务器实时状态。

隔离实验为 `scripts/verify-fetch-remote-tracking.sh`。它不模拟真实网络、凭据、平台审计或服务端隐藏 refs。
