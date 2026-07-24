# 工作场景索引

先选择最接近的现场，再进入正文判断细节。

| 现场 | 默认入口 |
| --- | --- |
| 文件改坏但还没 add | [丢弃工作区修改](../part-5/02-restore-worktree.md) |
| add 了不该提交的文件，但要保留修改 | [取消暂存](../part-5/03-unstage.md) |
| 最近本地提交漏文件 | [补充最近提交](../part-5/04-amend-content.md) |
| 最近本地提交说明写错 | [修改提交说明](../part-5/05-amend-message.md) |
| 多条未推送提交需要改说明或合并 | [交互式变基](../part-5/06-interactive-rebase.md) |
| 已推送错误需要回滚 | [git revert](../part-5/07-revert.md) |
| 个人评审分支变基后要更新远程 | [force-with-lease](../part-5/09-force-with-lease.md) |
| 错误 reset 或误删分支 | [恢复案例](../part-5/12-recovery-cases.md) |
| push 被拒绝 | [推送拒绝](../part-4/08-push-rejection.md) |
| pull 后发生冲突 | [冲突模型](../part-3/07-conflict-model.md) |
| 冲突已经解决，需向同事说明 | [冲突说明](../part-6/07-conflict-report.md) |
| 开发中途需要处理紧急任务 | [stash](../part-6/01-stash.md) 或 [worktree](../part-6/02-worktree.md) |
| 需要把一个修复迁到发布分支 | [热修复迁移](../part-6/05-hotfix.md) |
| 不知道哪条提交引入缺陷 | [bisect](../part-6/03-bisect.md) |
| 想知道一行代码为什么出现 | [历史检索](../part-6/04-history-search.md) |
| 判断 manager、worker 是否都要部署 | [热修复与部署范围](../part-6/05-hotfix.md) |
| 判断是否需要优雅停机 | [发布策略](../part-6/06-release.md) |
| 仓库状态混乱，不知道从哪里开始 | [排障流程](../part-6/10-troubleshooting.md) |
