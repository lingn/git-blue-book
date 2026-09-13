<!-- legacy-redirect -->

# Clone 初始状态正文已迁入 v2 第五篇

本页保留旧 URL。普通 clone、默认分支、空仓库、`--no-checkout`、bare、mirror、本地复制优化和失败目录边界已于 2026-09-14 重构迁移。

请阅读[Clone 初始状态](../part-05/02-clone-and-initial-state.md)。新章明确 clone 不保证复制源工作区、index、reflog、hooks、不可达对象、LFS/submodule 和平台数据，并给出按 clone 模式验收的证据清单。

隔离实验为 `scripts/verify-clone-initial-state.sh`。它不连接网络，不证明真实凭据、平台默认分支或外部对象完整。
