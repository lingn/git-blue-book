# 丢弃工作区修改：git restore

## 事故现场

你修改了已跟踪的 `README.md`，尚未执行 `git add`，现在确认这些修改全部不要。

先查看将要失去的内容：

```bash
git status
git diff -- README.md
```

确认后执行：

```bash
git restore README.md
```

`git restore <路径>` 默认恢复工作区文件，来源是暂存区中的版本。命令成功通常没有输出。

## 为什么来源不一定是最新提交

如果文件的一版内容已经暂存，之后又继续编辑，三个区域可能是：

```text
最新提交：版本 A
暂存区：  版本 B
工作区：  版本 C
```

此时 `git restore README.md` 会把工作区从 C 恢复成 B，不是 A。它丢弃的是工作区相对暂存区的修改。

若明确要从当前提交同时恢复工作区，可以写出来源和目标：

```bash
git restore --source=HEAD --worktree README.md
```

`--source=HEAD` 指定来源提交，`--worktree` 指定只更新工作区。暂存区仍保持原样。

## 只恢复部分修改

```bash
git restore --patch README.md
```

短写是 `-p`。Git 逐块询问是否恢复，适合一个文件中有些改动要保留、有些要丢弃。先理解终端展示的差异，再回答；不确定时退出，不要连续输入 `y`。

## 未跟踪文件不会被 restore 删除

`git restore` 面向 Git 已知路径。新建但从未跟踪的文件通常不会被它删除。对于重要未跟踪文件，先备份；确定无用后用操作系统文件工具移除，而不是寻找一个能“清空仓库”的 Git 命令。

## 恢复后的验证

```bash
git status
git diff -- README.md
```

差异应消失或回到预期范围。还要打开文件检查内容。

## 无法依赖 Git 找回的情况

未暂存修改从未进入 Git 对象或提交，执行恢复后通常不能靠 `reflog` 找回。编辑器本地历史、文件系统快照或备份可能有帮助，但不属于 Git 保证。

因此 `restore` 不是试试看按钮。执行前必须阅读差异。
