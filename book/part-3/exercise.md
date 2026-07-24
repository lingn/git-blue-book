# 综合场景：功能开发中插入紧急修复

你正在 `feature/search-help` 分支编写搜索说明，尚未合入 `main`。此时主线发现一个紧急文档错误，需要先修复并发布，再继续功能。

本练习不引入新命令，只组合本篇能力。

## 第一阶段：保存功能分支的完整节点

功能工作已经达到可解释状态时，先检查并提交：

```bash
git status
git diff
git add SEARCH.md
git diff --staged
git commit -m "docs: add search help draft"
```

如果工作还不能形成可靠提交，不应把半成品伪装成正式历史。第六篇会学习临时收纳和多个工作目录；当前练习假设它可以形成独立草稿提交。

## 第二阶段：切回主线完成修复

```bash
git switch main
```

修改 `README.md` 中的错误，检查并提交：

```bash
git add README.md
git diff --staged
git commit -m "fix: correct setup instruction"
```

为紧急修复后的主线创建附注标签：

```bash
git tag -a v0.1.1 -m "Correct setup instruction"
```

当前只是在本地标记。发布远程标签要等第四篇。

## 第三阶段：让功能分支取得修复

切回功能分支，把 `main` 合入：

```bash
git switch feature/search-help
git merge main
```

如果修改不同位置，Git 会自动整合；如果发生冲突，按照上一章完成“观察两侧意图—编辑最终结果—暂存—提交—测试”闭环。

功能分支现在既包含草稿，也包含紧急修复。继续完成 SEARCH 文档并提交。

## 第四阶段：把功能合回主线

```bash
git switch main
git merge feature/search-help
```

由于功能分支已经包含当前 `main`，且主线在修复后没有继续前进，这次通常可以快进。验证：

```bash
git status
git log --oneline --graph --decorate --all
git show v0.1.1 --no-patch
```

## 结果判断

你应能从提交图证明：

1. 紧急修复属于 `main` 的独立提交；
2. `v0.1.1` 稳定指向修复后的发布节点，不随功能合并移动；
3. 功能历史包含紧急修复；
4. 最终 `main` 同时包含修复和完整功能；
5. 删除功能分支名字不会删除已经合入的提交。

如果只能说“文件看起来都在”，证据还不够。分支工作的核心是理解提交可达关系，而不是只查看当前目录。
