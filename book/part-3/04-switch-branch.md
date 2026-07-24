# 创建和切换分支

现在为一个功能建立独立工作线。开始前确认练习仓库干净：

```bash
git status
```

如果有未提交修改，先判断它们属于什么意图。不要为了继续教程而直接丢弃。

## 只创建分支

```bash
git branch feature/quick-start
```

这会让新分支指向当前提交，但不会切换过去：

```text
HEAD -> main
          |
          v
          C <- feature/quick-start
```

查看列表：

```bash
git branch
```

星号仍在 `main` 前。

## 切换到已有分支

```bash
git switch feature/quick-start
```

`git switch` 用于切换分支。成功后，`HEAD` 改为指向 `feature/quick-start`，工作区会更新为该分支当前提交的快照。

验证：

```bash
git branch --show-current
git status
```

## 创建并立即切换

日常更常见的写法是：

```bash
git switch -c feature/another-example
```

`-c` 表示创建新分支并切换。由于本实验已经有 `feature/quick-start`，不要执行这条示例，否则会多创建一条无用分支。

旧教程常写：

```bash
git checkout -b feature/another-example
```

它也能创建并切换分支。现代 Git 把切换职责拆到 `git switch`，意图更清楚；本书后续使用 `switch`，阅读旧资料时再把两者对应起来。

## 在功能分支创建提交

创建 `QUICKSTART.md`：

```markdown
# Quick Start

先查看状态，再选择内容并提交。
```

然后执行：

```bash
git add QUICKSTART.md
git diff --staged
git commit -m "docs: add quick start guide"
```

查看图形：

```bash
git log --oneline --graph --decorate --all
```

新选项含义：

- `--decorate` 显示分支名等引用；
- `--all` 不只从当前分支出发，而是显示所有本地引用可达的历史。

图形应显示 `feature/quick-start` 比 `main` 多一个提交。

## 工作区不干净时切换

Git 有时允许携带未提交修改切换，有时会因为目标分支会覆盖这些文件而拒绝。拒绝是在保护内容，不应立刻强制操作。

安全处理顺序：

1. `git status` 和 `git diff` 确认修改；
2. 如果工作完整且属于当前分支，提交；
3. 如果工作不完整，后面学习 `git stash` 或使用额外工作目录；
4. 如果修改无用，等第五篇学会恢复边界后再丢弃。

## 小结

`git branch` 管理分支名字，`git switch` 改变当前分支和工作区视图。功能提交只推动当前分支，`main` 仍停在原位置。
