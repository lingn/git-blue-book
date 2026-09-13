# 第二篇（v2）：建立可靠的本地工作循环

这一篇把第一篇的版本历史模型落到本机操作。主线是“先观察状态，再选择写入范围，最后用对象和差异验收”，补充章节再处理临时收纳和多个工作树。每个命令都要能回答执行位置、读取什么、改变什么、怎样失败以及怎样恢复。

本篇只讨论本地 Git 数据面。stash 和 linked worktree 不提供远程备份、权限隔离、构建环境隔离或生产恢复能力；共享历史、评审、发布和平台控制面分别由第六篇和第八篇承担。

## 进入条件

开始前应理解工作区、index、HEAD、提交对象和分支引用。需要处理共享历史、评审或发布时，转到[第六篇](../part-06/README.md)和[第八篇](../part-08/README.md)；需要事故证据或恢复时，转到[第十三篇](../part-13/README.md)。

## 本篇内容

1. [安装 Git，并确认当前版本与能力边界](01-install-version-help.md)
2. [配置身份与 Git 配置：记录者不是登录者](02-identity-and-config.md)
3. [发现并创建仓库：`git rev-parse` 与 `git init`](03-repository-discovery-and-init.md)
4. [先观察再操作：`git status` 的状态证据](04-observe-status.md)
5. [工作区、暂存区与提交：先判断差异在哪一层](05-worktree-index-commit.md)
6. [选择并准备内容：`git add` 的路径边界](06-stage-a-change.md)
7. [生成提交：把已审查的 index 写进本地历史](07-atomic-commit-and-hooks.md)
8. [审查差异，而不是猜测：`git diff` 的三条比较边界](08-read-diffs.md)
9. [阅读本地历史：`git log`、`git show` 与范围](09-read-history.md)
10. [忽略规则、属性与换行：仓库策略不等于安全边界](10-ignore-attributes-and-eol.md)
11. [工作做到一半需要切任务：stash 的临时状态与恢复边界](11-stash.md)
12. [同时维护多个工作目录：worktree 的共享与隔离](12-multiple-worktrees.md)
13. [综合练习：把一次混合修改拆成可复核历史](exercise.md)

前十章的实验复用 `scripts/verify-part-2.sh`，stash/worktree 两章复用 `scripts/verify-part-6-engineering.sh`。实验都在临时仓库中运行，不能证明真实凭据、容器、端口、数据库、网络文件系统或平台控制面行为。
