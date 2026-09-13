<!-- legacy-redirect -->

# 提交图正文已拆入 v2 第三、四篇

本页保留旧 URL。原来的提交对象、父关系、可达性和 merge base 内容已于 2026-09-14 按职责拆分，旧页不再维护第二份定义。

权威阅读顺序：

1. [提交图与可达性](../part-03/04-commit-graph-and-reachability.md)，解释 commit 父边、revision 集合、merge base、浅边界与 commit-graph。
2. [Merge base 与三方合并](../part-04/03-merge-base.md)，把共同祖先用于 receiver、incoming 和 base 三棵 tree 的合并判断。

本地提交图实验继续由 `scripts/verify-commit-graph-reachability.sh` 和 `scripts/verify-merge-shapes.sh` 验证。它们不模拟平台评审、隐藏引用、CI 或发布状态。
