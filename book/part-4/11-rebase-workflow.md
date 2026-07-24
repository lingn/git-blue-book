# 安全使用 git rebase

## 操作前判断

只在专用练习或你独占的功能分支实验。先确认：

```bash
git status
git branch --show-current
git log --oneline --graph --decorate --all
```

工作区应当干净，当前应是准备重新应用的功能分支。不要站在 `main` 上反向操作。

获取主线最新状态：

```bash
git fetch origin
```

## 把当前功能分支变基到远程主线

```bash
git rebase origin/main
```

Git 找出当前分支与 `origin/main` 的共同祖先，暂时取出当前分支独有提交，把分支起点移到 `origin/main`，再逐个重新应用这些变化。

成功后检查：

```bash
git status
git log --oneline --graph --decorate --all
git diff origin/main...HEAD
```

确认新历史以 `origin/main` 为起点，功能最终差异仍符合预期，并运行测试。

## 变基冲突怎样处理

发生冲突时：

```bash
git status
git diff
```

理解当前正在重放哪条提交，以及主线和该提交分别想实现什么。编辑最终文件后：

```bash
git add <已解决文件>
git rebase --continue
```

`--continue` 继续应用剩余提交，可能打开编辑器确认提交说明。后续提交也可能再次冲突，因为变基按顺序重建。

如果发现起点选错或结果不可控：

```bash
git rebase --abort
```

它把分支和工作区恢复到本次变基开始前。中止后重新检查提交图。

`git rebase --skip` 会跳过当前正在重放的整个提交，可能丢掉其独有变化。只有确认该变化已经包含在新基线或确实不需要时才使用，不能把它当作跳过冲突。

## 变基后的推送

从未推送过的分支可以正常首次推送。已经推送过的分支，因为提交 ID 改变，普通推送通常会拒绝。不要立刻使用无条件强推；第五篇会基于 `origin/<分支>` 介绍带租约保护的更新。

## 验证清单

- 当前分支正确；
- 工作区干净；
- 原功能差异仍在；
- 提交顺序合理；
- 测试通过；
- 明确该分支是否已经被别人使用。
