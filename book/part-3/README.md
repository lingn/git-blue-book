# 第三篇：用分支组织并行工作

这一篇先解释提交之间如何连接，再引入分支与 `HEAD`。读者不会在理解这些名字之前被要求执行合并。

## 本篇内容

1. [提交如何组成历史](01-commit-graph.md)
2. [分支不是文件夹](02-branch-as-reference.md)
3. [当前所在位置：理解 HEAD](03-head.md)
4. [创建和切换分支](04-switch-branch.md)
5. [把两条历史合到一起：git merge](05-first-merge.md)
6. [快进与合并提交](06-merge-shapes.md)
7. [冲突不是报错：理解三方合并](07-conflict-model.md)
8. [完整处理一次冲突](08-resolve-conflict.md)
9. [给重要提交命名：git tag](09-tags.md)
10. [综合场景：功能开发中插入紧急修复](exercise.md)

完成本篇后，你应当能先画出提交图，再决定切换、合并或解决冲突，而不是根据分支名猜测历史关系。
