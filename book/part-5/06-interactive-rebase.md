# 修改多个本地提交：交互式变基

## 适用边界

你有三条尚未分享的本地提交，需要修改前两条说明、合并重复提交或调整顺序。普通 `--amend` 只能替换最新一条，交互式变基可以重建一段提交。

开始前：

```bash
git status
git log --oneline --graph --decorate -6
```

确保工作区干净，并记录当前提交 ID。最好再创建临时保护分支：

```bash
git branch backup/before-history-edit
```

## 打开最近三条提交计划

```bash
git rebase -i HEAD~3
```

`-i` 表示交互式。编辑器中提交按从旧到新排列，例如：

```text
pick a1b2c3d add parser
pick d4e5f6a fix typo
pick 7a8b9c0 add parser tests
```

这不是 `git log` 的新到旧顺序。每行开头是要对该提交执行的动作。

## 常用动作

- `pick`：保留提交；
- `reword`：保留内容，修改说明；
- `edit`：暂停，让你修改内容或拆分；
- `squash`：合入前一条并编辑合并后的说明；
- `fixup`：合入前一条，通常丢弃当前说明；
- `drop`：删除该提交及其独有变化。

需要只修改两条说明时，把对应 `pick` 改成 `reword`，保存退出。Git 依次重新创建提交，并在需要时打开说明编辑器。

## 修改顺序与删除行的风险

移动整行可以重排提交，但后一个提交可能依赖前一个，重排会冲突或让中间状态无法构建。删除一行通常等同于丢弃该提交，不是“暂时不编辑”。

## 冲突和中止

发生冲突时先查看：

```bash
git status
```

解决、暂存后继续：

```bash
git add <已解决文件>
git rebase --continue
```

如果计划错误：

```bash
git rebase --abort
```

中止后检查保护分支和提交图。完成后比较：

```bash
git log --oneline --graph --decorate -6
git diff backup/before-history-edit...HEAD
```

若只是整理说明或合并提交，最终文件差异通常应为空或符合预期。

## 第一条提交也要修改

`HEAD~3` 要求范围前还有父提交。需要包含根提交时可使用 `git rebase -i --root`，但整个本地历史都会被重建。只有在未分享的练习或新仓库中使用。

## 共享边界

交互式变基会改变被编辑提交及其后续提交 ID。已经有同事依赖的历史，不能未经协调执行。
