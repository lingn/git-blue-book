<!-- legacy-redirect -->

# 首次合并正文已拆入 v2 第四篇

本页保留旧 URL。原来的合并方向、共同祖先、快进和状态边界已于 2026-09-14 拆入两个权威章节。

阅读顺序：

1. [Merge base 与三方合并](../part-04/03-merge-base.md)，固定 receiver、incoming、共同祖先和三棵 tree。
2. [快进与合并提交](../part-04/04-fast-forward-and-merge-commits.md)，区分快进 ref 移动、`--ff-only` 拒绝、`--no-ff` 合并节点和 `--no-commit` 边界。

隔离实验为 `scripts/verify-merge-shapes.sh`。Git 合并成功只证明本地提交图和 tree 结果，不能替代评审、CI、业务测试和发布证据。
