# 常用命令地图

这不是从零学习入口。第一次阅读请按正文顺序；遇到工作问题时，可从这里回到命令首次解释和风险边界。

## 建立仓库和记录

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 确认版本 | `git --version` | [安装与版本](../part-2/01-install.md) |
| 配置身份 | `git config` | [身份配置](../part-2/02-identity.md) |
| 初始化仓库 | `git init` | [创建仓库](../part-2/03-init.md) |
| 查看状态 | `git status` | [状态](../part-2/04-status.md) |
| 准备内容 | `git add` | [暂存](../part-2/06-add.md) |
| 创建提交 | `git commit` | [提交](../part-2/07-commit.md) |
| 比较内容 | `git diff` | [差异](../part-2/08-diff.md) |
| 查看历史 | `git log`、`git show` | [历史](../part-2/09-history.md) |

## 分支与整合

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 查看或创建分支 | `git branch` | [分支模型](../part-3/02-branch-as-reference.md) |
| 切换分支 | `git switch` | [切换分支](../part-3/04-switch-branch.md) |
| 合并历史 | `git merge` | [合并](../part-3/05-first-merge.md) |
| 标记版本 | `git tag` | [标签](../part-3/09-tags.md) |
| 重建功能提交 | `git rebase` | [安全变基](../part-4/11-rebase-workflow.md) |
| 迁移独立提交 | `git cherry-pick` | [挑选提交](../part-4/12-cherry-pick.md) |

## 远程协作

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 复制仓库 | `git clone` | [克隆](../part-4/02-clone.md) |
| 管理远程地址 | `git remote` | [远程配置](../part-4/03-remote.md) |
| 只获取远程历史 | `git fetch` | [获取](../part-4/04-fetch.md) |
| 获取并整合 | `git pull` | [拉取](../part-4/06-pull.md) |
| 发布提交或标签 | `git push` | [推送](../part-4/07-push.md) |

## 撤销与恢复

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 丢弃未暂存修改 | `git restore <路径>` | [恢复工作区](../part-5/02-restore-worktree.md) |
| 取消暂存 | `git restore --staged` | [取消暂存](../part-5/03-unstage.md) |
| 替换最近本地提交 | `git commit --amend` | [补充提交](../part-5/04-amend-content.md) |
| 重置最近提交署名 | `git commit --amend --reset-author` | [重置署名](../part-5/05-amend-message.md) |
| 变基时逐条执行命令 | `git rebase --exec` | [逐条执行](../part-5/06-interactive-rebase.md) |
| 撤销已公开提交 | `git revert` | [公开回滚](../part-5/07-revert.md) |
| 有条件更新个人远程分支 | `git push --force-with-lease` | [租约保护](../part-5/09-force-with-lease.md) |
| 移动分支并选择区域更新范围 | `git reset` | [reset 三模式](../part-5/10-reset.md) |
| 查找引用旧位置 | `git reflog` | [引用日志](../part-5/11-reflog.md) |

## 工程调查

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 临时收纳修改 | `git stash` | [stash](../part-6/01-stash.md) |
| 多个工作目录 | `git worktree` | [worktree](../part-6/02-worktree.md) |
| 二分定位缺陷 | `git bisect` | [bisect](../part-6/03-bisect.md) |
| 查询行来源 | `git blame` | [历史检索](../part-6/04-history-search.md) |
| 搜索内容演变 | `git log -S`、`git log -G` | [历史检索](../part-6/04-history-search.md) |
