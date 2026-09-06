# 第五篇：撤销、回滚与找回

这一篇不从命令分类出发，而是先判断两个边界：改动有没有成为提交，相关历史有没有被别人看到。相同的“撤销”在不同边界下会使用不同策略。

## 本篇内容

1. [兼容入口：撤销决策正文已迁入第七篇](01-decision-matrix.md)
2. [兼容入口：restore 工作区正文已迁入第七篇](02-restore-worktree.md)
3. [兼容入口：取消暂存正文已迁入第七篇](03-unstage.md)
4. [兼容入口：amend 内容正文已迁入第七篇](04-amend-content.md)
5. [兼容入口：amend 说明正文已迁入第七篇](05-amend-message.md)
6. [兼容入口：交互式 rebase 正文已迁入第七篇](06-interactive-rebase.md)
7. [兼容入口：revert 正文已迁入第七篇](07-revert.md)
8. [兼容入口：共享历史改写政策已迁入第七篇](08-public-history.md)
9. [兼容入口：显式租约正文已迁入第七篇](09-force-with-lease.md)
10. [兼容入口：reset 正文已迁入第七篇](10-reset.md)
11. [reflog 保存引用移动的本地证据](11-reflog.md)
12. [兼容入口：恢复案例正文已迁入第七篇](12-recovery-cases.md)
13. [兼容入口：提交改写操作手册已迁入第七篇](13-rewrite-commit-playbook.md)
14. [远端历史被重写后为什么同时 ahead 和 behind](14-remote-history-rewrite.md)
15. [综合场景：四类事故的恢复决策](exercise.md)

高风险实验全部在验证脚本创建的临时仓库中运行。真实项目发生事故时，先保护现场和记录提交 ID，不要边搜索边试命令。
