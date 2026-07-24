# 推送为什么会被拒绝

## 两位开发者从同一点开始

Alice 和 Bob 都从远程 `main` 的 B 开始工作：

```text
A <- B  origin/main
```

Alice 创建提交 C 并先推送，服务器变为：

```text
A <- B <- C  服务器 main
```

Bob 没有先获取，基于 B 创建提交 D：

```text
      C  服务器 main
     /
A <- B
     \
      D  Bob 的 main
```

Bob 执行普通推送时，远程会拒绝 `non-fast-forward` 更新。因为把服务器分支直接从 C 改到 D，会让 C 不再从该分支可达，相当于覆盖 Alice 已公开的工作。

## 拒绝是保护，不是网络故障

典型信息会建议先整合远程变化。此时不要：

- 反复重试同一命令；
- 删除本地仓库；
- 立即使用 `--force`；
- 假设远程提交一定可以丢弃。

先更新证据：

```bash
git fetch origin
git status
git log --oneline --graph --decorate --all
```

再分别查看双方独有提交：

```bash
git log --oneline main..origin/main
git log --oneline origin/main..main
```

## 两种正常整合方式

### 合并

```bash
git merge origin/main
```

保留 C 与 D，并创建合并提交。完成冲突解决和测试后再普通推送。

### 变基

如果 D 尚未分享给其他人，可以把它重新应用到 C 之后，形成新提交 D'。第十、十一章会完整讲解：

```text
A <- B <- C <- D'
```

然后普通推送即可，因为远程 C 是本地历史的祖先。

## 什么时候远程真的应该被覆盖

远程分支可能是你个人专用、团队明确允许改写的评审分支。即使如此，也要先确认远程没有别人新增提交，并使用带保护条件的强制更新，而不是无条件 `--force`。第五篇会在理解远程跟踪引用后介绍 `--force-with-lease`。

## 小结

普通推送拒绝是在告诉你：远程分支包含当前推送无法保留的历史。正确反应是获取、比较、整合和验证，而不是绕过保护。
