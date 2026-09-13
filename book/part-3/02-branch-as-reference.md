<!-- legacy-redirect -->

# 分支引用正文已拆入 v2 第三、四篇

本页保留旧 URL。原来的引用数据模型和分支工作流已于 2026-09-14 分开迁移，旧页不再复制引用格式、分支操作和恢复说明。

权威阅读顺序：

1. [引用、HEAD 与 reflog](../part-03/03-refs-head-and-reflog.md)，解释逻辑引用、符号引用、条件更新、日志和 linked worktree。
2. [分支与分离 HEAD](../part-04/01-branches-and-detached-head.md)，解释分支工作线、可达性、本地/远程跟踪/upstream、命名、占用和删除恢复。

本地实验继续由 `scripts/verify-refs-head-reflog.sh` 和 `scripts/verify-branch-switching.sh` 验证。远端分支保护、命名策略、权限和审计仍需目标平台实测。
