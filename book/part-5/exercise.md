# 综合场景：四类事故的恢复决策

以下四个现场表面都可以叫“回滚”，但安全策略不同。先判断区域和共享边界，再看参考处理。

## 事故一：尚未暂存的配置修改不要了

证据：`git status` 显示 `config.yml` 已修改，`git diff` 能看到变化，`git diff --staged` 无输出。

处理：

```bash
git diff -- config.yml
git restore config.yml
git status
```

理由：变化只在工作区。执行前必须确认差异，因为 Git 通常不能找回被覆盖的未提交内容。

## 事故二：最近本地提交漏了测试

证据：提交尚未推送，测试文件与该提交属于同一意图。

处理：

```bash
git add <测试文件>
git diff --staged
git commit --amend --no-edit
git show --stat HEAD
```

理由：替换私有的最近提交可以保持一个完整意图；新提交 ID 改变是预期结果。

## 事故三：错误提交已经进入 main

证据：远程和同事都包含该提交，后续还有其他正确提交。

处理：

```bash
git fetch origin
git show <错误提交ID>
git revert <错误提交ID>
```

解决可能的冲突、运行完整测试后普通推送。

理由：新反向提交保留共享坐标和后续历史。不能通过 `reset` 加强推让事故从图中消失。

## 事故四：未合并功能分支被误删

证据：提交曾在本地创建，但没有其他分支名指向。

处理：

```bash
git reflog
git show --stat <候选提交ID>
git branch recovery/deleted-feature <候选提交ID>
```

理由：先恢复引用，不立即移动当前分支。确认内容和测试后再决定怎样合入。

## 额外判断：个人远程分支变基后要更新

只有在分支允许改写、无人依赖旧历史并记录了远程预期 ID 时，才使用显式租约：

```bash
git push --force-with-lease=refs/heads/feature/search:<改写前远程提交ID> origin feature/search
```

若租约拒绝，说明远程状态与预期不同，应重新获取和协调，不应升级为无条件强推。

## 回看本篇

你应能在不看命令表的情况下回答：

1. 哪些操作会丢弃未提交内容？
2. 哪些操作会生成新提交 ID？
3. 为什么已推送错误优先 `revert`？
4. `--force-with-lease` 的预期值来自哪里？
5. `reset --soft`、`--mixed`、`--hard` 分别改变哪几个区域？
6. 为什么 reflog 恢复的第一步通常是创建分支？

答案都应包含作用对象、共享边界和验证方法，而不只是命令名称。
