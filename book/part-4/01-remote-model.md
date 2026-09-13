<!-- legacy-redirect -->

# 远程状态模型正文已迁入 v2 第五篇

本页保留旧 URL。服务器 ref、本地 remote-tracking ref、本地分支、upstream、`FETCH_HEAD`、symbolic HEAD 与平台控制面已于 2026-09-14 迁入统一模型。

请阅读[远程状态模型](../part-05/01-remote-state-model.md)。新章还区分 `ls-remote` 查询与 fetch 写入，说明 pull/push 的分层副作用、认证/授权/提交身份，以及本地 bare 实验不能证明的平台事实。

隔离实验为 `scripts/verify-remote-state-model.sh`。它只验证 `file://` Git 数据面，不模拟 SSH/TLS、权限、保护规则、审计或复制。
