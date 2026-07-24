# 生成第一条提交：git commit

## 提交前检查

一次提交只会采用暂存区内容。先执行：

```bash
git status
```

确认 `README.md` 位于 `Changes to be committed` 下，而且没有不应进入历史的文件。

创建提交：

```bash
git commit -m "docs: add project introduction"
```

`git commit` 根据暂存区创建提交。`-m` 后面的文本是提交说明，`m` 来自 message。引号让整句话作为一个参数传入。

输出类似：

```text
[main (root-commit) 1a2b3c4] docs: add project introduction
 1 file changed, 3 insertions(+)
 create mode 100644 README.md
```

实际提交 ID 和行数可能不同。`root-commit` 表示这是当前历史的第一条提交。

## 提交说明写什么

提交说明应表达“为什么要做这次变化”或“这次变化完成了什么意图”。

较弱的说明：

```text
update
修改文件
work
```

较清楚的说明：

```text
docs: add project introduction
fix: reject orders with negative quantity
refactor: isolate price rounding policy
```

前缀并不是 Git 强制语法，只是许多团队用来帮助扫描历史的约定。优先遵循所在团队规范；没有规范时，至少使用清楚、具体的动词。

## 提交后的状态

```bash
git status
```

如果工作区、暂存区和最新提交内容一致，会看到：

```text
nothing to commit, working tree clean
```

“干净”不代表仓库没有文件，而是没有尚未记录的差异。

## 提交是本地操作

这条历史目前只存在于 `git-first-lab` 本地仓库。`git commit` 不会自动上传到 GitHub，也不需要联网。第四篇才会连接远程仓库并发布提交。

## 提交失败时怎么判断

### 身份未配置

Git 会提示设置 `user.name` 和 `user.email`。回到身份配置章节设置后，重新执行提交。失败尝试不会生成半条提交。

### 没有暂存内容

如果只修改了工作区却没有 `git add`，Git 会提示没有可提交内容。先用 `git status` 判断哪些变化应进入下次提交，不要为了消除提示而盲目执行 `git add .`。

### 提交说明写错

先不要删除仓库或重做文件。第五篇会介绍 `git commit --amend`，用于替换尚未公开的最近一次提交。当前先保留这条正确提交，避免提前进入历史改写。

## 小结

`git add` 准备快照，`git commit` 根据准备结果创建不可变历史节点。下一章开始比较三个区域之间的内容，而不只看状态标签。
