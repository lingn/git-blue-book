<!-- legacy-redirect -->

# 标签正文已拆入 v2 第四、八、十篇

本页保留旧 URL。原来的轻量/附注/签名标签、远端发布和发布边界已于 2026-09-14 按职责拆分，不再维护第二份正文。

权威阅读顺序：

1. [标签与发布引用](../part-04/09-tags-and-release-refs.md)，解释 tag ref/object、peel、短名歧义、显式 push、同名竞态和删除。
2. [签名与信任策略](../part-10/04-signatures.md)，解释签名格式、密码学验证、principal、组织授权和密钥生命周期。
3. [发布引用与制品提升](../part-08/05-release-refs-and-artifact-promotion.md)，把标签与候选、制品摘要、审批和环境提升连接起来。

本地实验由 `scripts/verify-tags-release-refs.sh`、`scripts/verify-signatures-trust.sh` 和 `scripts/verify-release-promotion.sh` 覆盖。它们不模拟真实平台保护、签名服务、制品库或部署。
