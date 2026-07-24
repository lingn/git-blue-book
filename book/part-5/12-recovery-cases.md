# 恢复误删分支、错误重置和失败变基

本章把引用日志应用到三类事故。原则始终是：先找到候选提交并创建恢复分支，再决定怎样放回正式历史。

## 误删尚未合并的分支

删除后立即运行：

```bash
git reflog
```

找到你最后位于该分支或创建其提交的记录，检查：

```bash
git show --stat <候选提交ID>
```

恢复名字：

```bash
git branch feature/restored <候选提交ID>
```

切换并验证：

```bash
git switch feature/restored
git status
git log --oneline --graph --decorate -6
```

## 错误 reset --hard

先不要继续编辑。`reset --hard` 前已经提交的节点通常可从 reflog 找到：

```bash
git reflog
git branch recovery/before-hard-reset <原提交ID>
```

这能找回提交快照。`reset --hard` 覆盖的未提交工作区修改不属于原提交，Git 不保证恢复；需要查看编辑器历史或备份。

确认恢复分支正确后，选择：

- 在当前分支合并恢复分支；
- 挑选所需提交；
- 若历史未分享且确实要恢复原位置，再重置当前分支。

不要一找到候选 ID 就再次 `reset --hard`，先建立名字保留证据。

## 变基进行中发现错误

如果仍处于变基状态：

```bash
git status
git rebase --abort
```

优先用操作自身的中止机制回到开始前。不要在进行中的变基里混用 `reset`。

如果变基已完成但结果错误，查看：

```bash
git reflog
```

找到 `rebase (start)` 前的分支位置，创建：

```bash
git branch recovery/before-rebase <原提交ID>
```

比较两边最终内容和提交图，再决定保留哪一套。

## 恢复后的检查

- 候选提交内容与事故前证据一致；
- 恢复引用已经创建；
- 当前工作区没有被二次覆盖；
- 测试通过；
- 若远程历史受影响，已与协作者核对；
- 记录了事故命令、恢复依据和最终处理。

恢复成功不等于可以删除所有线索。保留恢复分支到评审和发布完成后再清理。
