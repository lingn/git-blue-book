# 第七篇：改写、撤销与恢复

撤销动作的风险取决于它改变哪一层状态，以及相关提交是否已经被别人看到。工作区和 index 可以直接恢复，本地未共享提交可以改写，已经进入共享引用的历史通常要追加新提交或按显式租约协调。引用移动后，还要保留足够的恢复入口。

本篇按状态和共享边界组织，不把 `restore`、`reset`、`revert` 和 `rebase` 当作互相替换的快捷按钮。每章都会说明执行位置、会移动或覆盖的对象、失败状态、恢复来源和不可恢复边界。

## 进入条件

开始前应理解工作区、index、HEAD、分支引用、远程跟踪引用、commit parent 和 reflog。需要评审、必需检查或受保护引用时，先阅读[第六篇](../part-06/README.md)；需要平台、制品和运行状态时，转到[第八篇](../part-08/README.md)。

## 已落地内容

1. [先别急着撤销：用状态矩阵判断位置](01-state-and-sharing-matrix.md)
2. [丢弃工作区修改：restore 的来源与覆盖边界](02-restore-worktree.md)
3. [取消暂存，但保留文件修改：把选择退回工作区](03-unstage.md)
4. [amend 一条提交：先判断有没有共享，再决定改写还是追加](04-amend-one-commit.md)
5. [交互式 rebase：重建一段尚未共享的历史](05-interactive-rebase.md)
6. [rebase 模型与安全工作流：把历史重建变成可回退流程](06-rebase-model-and-workflow.md)
7. [cherry-pick：把一个变化迁移到另一条历史](07-cherry-pick.md)
8. [revert 共享历史：用新提交撤销已经公开的变化](08-revert-shared-history.md)
9. [共享历史改写政策：先保护坐标，再决定动作](09-public-history-policy.md)
10. [显式租约：有条件地改写允许更新的远程分支](10-explicit-force-lease.md)
11. [reset：移动引用，并按模式重置另外两个区域](11-reset.md)
12. [reflog 与 recovery ref：保存引用移动的本地证据](12-reflog-and-recovery-refs.md)
13. [本地与远程恢复：先保留候选，再验证共享状态](13-local-and-remote-recovery.md)

第七篇的正文迁移已经覆盖状态判断、工作区和 index、提交改写、rebase/cherry-pick、revert、显式租约、reset、共享政策、reflog 和恢复案例。旧路径仍保留兼容入口，直到整书主导航完成最终审校。

本篇高风险实验全部在验证脚本创建的临时仓库中执行。实验能证明 Git 数据面行为，不能证明平台审批、远程保留、制品、数据库或生产恢复能力。
