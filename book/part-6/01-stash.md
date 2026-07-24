# 工作做到一半需要切任务：git stash

## 场景：当前修改还不适合提交

功能写到一半，线上问题需要立即处理。当前修改不能形成可构建、可解释的提交，又不希望混入热修复分支。

先查看现场：

```bash
git status
git diff
git diff --staged
```

把已跟踪文件的暂存和未暂存变化放入一条本地临时记录：

```bash
git stash push -m "wip: search filter draft"
```

`stash` 是本地仓库中的临时修改记录。`push` 创建记录，`-m` 提供可识别说明。完成后检查工作区是否达到预期状态。

## 未跟踪文件默认不包含

普通 stash 不包含未跟踪文件。需要连同它们收纳：

```bash
git stash push -u -m "wip: search filter with new files"
```

`-u` 表示包含未跟踪文件。被忽略文件仍不默认包含。不要为了让状态变干净就收纳日志、凭据或大型构建产物。

## 查看与检查

```bash
git stash list
git stash show --stat stash@{0}
git stash show -p stash@{0}
```

`stash@{0}` 是最新记录。序号会随新记录变化，因此重要工作应依靠说明并及时恢复，不要长期记固定编号。

## apply 与 pop

恢复但保留 stash 记录：

```bash
git stash apply stash@{0}
```

恢复成功后仍保留原记录，适合先验证。确认工作区内容、测试和提交都正确后，再删除：

```bash
git stash drop stash@{0}
```

快捷方式：

```bash
git stash pop
```

它尝试应用最新记录，并在成功时删除记录。遇到复杂或重要工作时优先 `apply`，验证后 `drop`，恢复路径更清楚。

## 冲突与边界

如果当前分支上下文已变化，应用 stash 可能冲突。按合并冲突方式理解双方意图、编辑、暂存和测试。冲突时记录通常不会自动删除。

stash 不会上传远程，也不是长期备份。需要跨天协作或评审的工作，应放在明确分支和提交中。下一章介绍更适合长时间并行任务的额外工作目录。
