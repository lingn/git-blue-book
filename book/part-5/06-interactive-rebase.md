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

## 重放后逐条执行命令：--exec

还有一类需求不是编辑提交计划，而是让每条提交重建后都跑一遍检查，或做一次相同的机械修改。`--exec` 接受一条 shell 命令，变基每重放一个提交，就在刚重放出的新提交上执行一次：

```bash
git rebase -i HEAD~3 --exec 'make test'
```

把 `make test` 换成项目实际的测试命令。执行时工作区是干净的，HEAD 指向刚重放出的提交。在交互式计划中，这些命令会显示为提交行之间的 `exec` 行。命令以非零状态退出（例如测试失败）时，变基会像遇到冲突一样暂停：检查现场并修复后用 `git rebase --continue` 继续，或用 `git rebase --abort` 整体放弃。

`--exec` 也能与非交互式变基联用，例如把功能分支移到新基线后逐条验证：

```bash
git rebase origin/main --exec 'make test'
```

一个典型的机械修改场景：整条本地历史的作者身份都配错了，需要逐条重置。先修正身份配置，确认历史从未分享，在专用沙盒或确认无人依赖的仓库中执行：

```bash
git branch backup/before-history-edit
git rebase --root --exec 'git commit --amend --no-edit --reset-author'
```

`--root` 让重放范围包含根提交；上一章介绍的 `--reset-author` 把 author 重置为当前配置身份。每重放一条，`--exec` 立即对它执行一次保留说明的 amend。为什么必须逐条：author 是提交内容的一部分，改掉任何一条都会改变其 ID，而后续提交记录父提交 ID，于是从第一条起整条链全部重建，没有一个提交 ID 保持不变。

完成后核对署名，并确认内容未被改动：

```bash
git log --format='%h %an <%ae> %s'
git diff backup/before-history-edit HEAD
```

所有行的署名应一致，最终文件差异应为空。注意这里用两个点：从根提交重写后，新旧历史没有共同祖先，三点写法会因找不到合并基线而报错。确认无误前保留保护分支。这种整条重写只适合未分享的私有历史：如果历史已经推送，先按本篇第 8 章判断它是否公开，确需更新远程时走第 9 章的租约保护流程。

## 共享边界

交互式变基会改变被编辑提交及其后续提交 ID。已经有同事依赖的历史，不能未经协调执行。
