# 第五篇：撤销、回滚与找回

这一篇不从命令分类出发，而是先判断两个边界：改动有没有成为提交，相关历史有没有被别人看到。相同的“撤销”在不同边界下会使用不同策略。

## 本篇内容

1. [先别急着撤销：用状态矩阵判断位置](01-decision-matrix.md)
2. [丢弃工作区修改：git restore](02-restore-worktree.md)
3. [取消暂存，但保留文件修改](03-unstage.md)
4. [补充最近一次本地提交](04-amend-content.md)
5. [只修改最近一次提交说明](05-amend-message.md)
6. [交互式 rebase 重建一段私有历史](06-interactive-rebase.md)
7. [revert 用新提交撤销共享历史中的变化](07-revert.md)
8. [为什么已公开历史不应随意改写](08-public-history.md)
9. [用显式租约更新允许改写的远程分支](09-force-with-lease.md)
10. [reset 会移动引用，并按模式重置另外两个区域](10-reset.md)
11. [reflog 保存引用移动的本地证据](11-reflog.md)
12. [从误删分支、错误 reset 和失败 rebase 中恢复](12-recovery-cases.md)
13. [综合场景：四类事故的恢复决策](exercise.md)

高风险实验全部在验证脚本创建的临时仓库中运行。真实项目发生事故时，先保护现场和记录提交 ID，不要边搜索边试命令。
