# 第四篇：分支、合并与冲突

对象、引用、提交图和 index 决定了分支操作的底层结果。本篇把这些模型放回开发工作流：如何建立和切换工作线，怎样判断快进与分叉，三方合并选择什么 base，`ort` 如何处理内容与路径冲突，以及团队怎样中止、验证和复用解决结果。

本篇只讨论本地 Git 数据面。共享分支的评审、所有权、必需检查与合并队列属于第六篇；rebase、cherry-pick、revert 和 reset 属于第七篇；发布标签、制品和部署证据属于第八篇。

## 进入条件

开始前应能区分对象与引用，读懂 commit 父关系、可达性和 index stage，并能使用第二篇的 `status`、`diff`、`add`、`commit` 基本循环。涉及切换、合并、冲突和标签的实验都在 `mktemp` 创建的临时仓库运行。

## 已落地内容

1. [分支与分离 HEAD：工作线是可移动入口，不是提交容器](01-branches-and-detached-head.md)
2. [创建和切换分支：先证明本地内容不会被覆盖](02-create-and-switch-branches.md)
3. [Merge base 与三方合并：先固定共同历史，再计算两侧变化](03-merge-base.md)
4. [快进与合并提交：引用移动和新对象是两种历史结果](04-fast-forward-and-merge-commits.md)
5. [`ort` 三方合并：策略生成候选 tree，不替团队判断业务](05-three-way-merge-and-ort.md)
6. [复杂路径冲突：先还原每一侧做了什么，再决定最终布局](06-complex-path-conflicts.md)
7. [解决、中止与验收：冲突消失只是结构条件](07-resolve-abort-and-verify.md)
8. [Rerere：复用编辑结果，但每次重新验证语义](08-rerere.md)
9. [标签与发布引用：稳定名字仍需目标、签名和远端证据](09-tags-and-release-refs.md)
10. [综合练习：功能开发期间插入主线热修复](exercise.md)

第四篇规划主题已经落盘，旧第三篇全部页面也已迁为兼容入口。后续执行跨章重复、术语和出版审校。自动检查通过只能证明当前实验不变量和链接完整，不能替代技术编辑与目标环境验收。

## 实验边界

当前实验验证本地分支、切换保护、merge base、快进、`ort`/`ours`、复杂 stages、abort/quit/continue、rerere、轻量/附注标签与一条完整热修复集成路径。它不连接真实托管平台，不模拟分支保护、评审、合并队列或审计，也不证明业务测试和发布条件成立。
