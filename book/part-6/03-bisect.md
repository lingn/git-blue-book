<!-- legacy-redirect -->

# bisect 归因正文已迁入权威章节

本页保留旧 URL。原来的 bisect 正文已于 2026-09-02 收束到第十一篇历史归因和第八篇事故发布章节，旧页不再复制 good/bad 判定、退出码、浅克隆和线上根因边界。

权威阅读顺序：

1. [历史归因、搜索与证据边界](../part-11/03-history-attribution.md)，说明 blame、pickaxe、merge 父视角和 `bisect` 怎样缩小候选，以及为什么候选不等于根因。
2. [从事故到发布](../part-08/08-incident-to-release.md)，说明如何把已知正常/异常版本、`bisect` 结果、修复来源和运行验证接成事故证据链。

本地实验由 `scripts/verify-history-attribution.sh` 和 `scripts/verify-incident-to-release.sh` 验证。实验只证明本地 Git 提交图和合成判定，不模拟生产数据、真实服务或平台责任证据。`bisect` 会改变当前 `HEAD` 和工作区，只能在可销毁副本中运行。
