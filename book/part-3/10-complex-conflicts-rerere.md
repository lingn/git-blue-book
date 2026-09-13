<!-- legacy-redirect -->

# 复杂冲突与 rerere 正文已拆入 v2 第四篇

本页保留旧 URL。原来的 `ort`、路径冲突、解决控制和 rerere 内容已于 2026-09-14 按职责拆分，避免策略、数据结构和操作流程继续混在一章。

权威阅读顺序：

1. [`ort` 三方合并](../part-04/05-three-way-merge-and-ort.md)，负责 strategy/option、`AUTO_MERGE` 和 rename 推断。
2. [复杂路径冲突](../part-04/06-complex-path-conflicts.md)，负责 add/delete/rename、目录、mode、二进制、LFS 和 submodule。
3. [解决、中止与验收](../part-04/07-resolve-abort-and-verify.md)，负责 stages 到最终 tree 的状态机与证据。
4. [Rerere](../part-04/08-rerere.md)，负责 preimage/postimage、autoupdate、forget、保留与共享风险。

本地实验继续由 `scripts/verify-complex-conflicts-rerere.sh`、`scripts/verify-ort-path-conflicts.sh` 和 `scripts/verify-merge-resolution-control.sh` 执行。平台冲突页面、IDE、真实 LFS/submodule 服务和业务测试仍需目标环境验证。
