# 第五篇：撤销、回滚与找回

这一篇不从命令分类出发，而是先判断两个边界：改动有没有成为提交，相关历史有没有被别人看到。相同的“撤销”在不同边界下会使用不同策略。

## 本篇内容

1. [先别急着撤销：用状态矩阵判断位置](01-decision-matrix.md)
2. [丢弃工作区修改：restore 的来源与覆盖边界](02-restore-worktree.md)
3. [取消暂存，但保留文件修改：把选择退回工作区](03-unstage.md)
4. [补充最近一次本地提交：amend 会生成替代对象](04-amend-content.md)
5. [只修改最近一次提交说明：文字变化也会改变 OID](05-amend-message.md)
6. [交互式 rebase 重建一段私有历史](06-interactive-rebase.md)
7. [revert 用新提交撤销共享历史中的变化](07-revert.md)
8. [为什么已公开历史不应随意改写：共享坐标比图形整洁更重要](08-public-history.md)
9. [用显式租约更新允许改写的远程分支](09-force-with-lease.md)
10. [reset 会移动引用，并按模式重置另外两个区域](10-reset.md)
11. [reflog 保存引用移动的本地证据](11-reflog.md)
12. [从误删分支、错误 reset 和失败 rebase 中恢复](12-recovery-cases.md)
13. [提交之后又想改：先判断有没有共享，再决定改写还是追加](13-rewrite-commit-playbook.md)
14. [远端历史被重写后为什么同时 ahead 和 behind](14-remote-history-rewrite.md)
15. [综合场景：四类事故的恢复决策](exercise.md)

高风险实验全部在验证脚本创建的临时仓库中运行。真实项目发生事故时，先保护现场和记录提交 ID，不要边搜索边试命令。
