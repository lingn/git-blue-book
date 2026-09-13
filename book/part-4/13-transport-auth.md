<!-- legacy-redirect -->

# 传输与认证正文已迁入 v2 第五篇

本页保留旧 URL。URL、Git wire protocol、SSH/HTTPS、本地传输、服务器身份、客户端认证、仓库授权、凭据助手和连接失败分流已于 2026-09-14 重构迁移。

请阅读[传输与认证：连接、身份和授权必须分层排查](../part-05/08-transport-and-authentication.md)。凭据泄漏与历史清理见[凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md)，按症状排查见[Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md)。

实验入口为 `scripts/verify-remote-transport-auth.sh`。本地 `file://` 和虚构 credential helper 只验证 Git 数据面与协议边界，不模拟真实主机密钥、TLS、令牌、SSO、平台授权或审计。
