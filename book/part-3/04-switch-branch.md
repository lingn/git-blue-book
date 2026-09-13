<!-- legacy-redirect -->

# 创建和切换分支正文已迁入 v2 第四篇

本页保留旧 URL。原来的 `branch`、`switch`、分离检出和工作区保护内容已于 2026-09-14 重构，不再在旧路径维护并行版本。

请阅读[创建和切换分支](../part-04/02-create-and-switch-branches.md)。新章区分：

- 只创建 ref 与创建后立即切换；
- 可以安全携带的本地修改与必须拒绝的 tracked/staged 覆盖；
- 目标分支跟踪同名路径时的未跟踪文件保护；
- 显式起点、upstream、分离候选和 linked worktree 占用；
- 旧 `checkout` 分支操作与路径恢复的不同迁移方式。

隔离实验为 `scripts/verify-branch-switching.sh`。它不模拟 LFS/filter、平台权限、网络认证或真实文件系统故障。
