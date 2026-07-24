# 必须更新远程历史时：force-with-lease

## 场景边界

你独占的功能分支已经推送，评审要求整理提交。团队允许该分支改写，确认没有同事基于旧提交工作。变基后普通推送因非快进被拒绝。

无条件 `git push --force` 会直接请求覆盖远程位置。更安全的选择是：

```bash
git push --force-with-lease origin feature/search
```

它只在远程引用仍符合本地预期时更新。如果远程出现你不知道的新提交，推送应被拒绝。

## 默认租约依据什么

不带显式预期值时，Git 通常用本地 `origin/feature/search` 作为“我认为远程还在这里”的依据。

这比 `--force` 安全，但不是绝对锁。后台工具或你自己执行 `git fetch` 后，远程跟踪引用可能前移；即使你没有把新提交整合进功能分支，默认租约也可能认为你已经知晓它们。

## 显式记录远程预期位置

在改写前获取并检查：

```bash
git fetch origin
git log --oneline --graph --decorate --all
git rev-parse origin/feature/search
```

保存输出的完整提交 ID，例如 `<改写前远程提交ID>`。完成变基和测试后：

```bash
git push --force-with-lease=refs/heads/feature/search:<改写前远程提交ID> origin feature/search
```

这个显式租约要求服务器上的 `feature/search` 仍等于记录的 ID。若期间有人推送，服务器拒绝。请替换占位符，不要输入尖括号。

## 被拒绝后怎么做

停止重试并重新获取证据：

```bash
git fetch origin
git log --oneline --graph --decorate --all
```

找到远程新增提交的作者和意图，决定合并、重新变基或请对方迁移。不要把租约失败当作需要升级到 `--force` 的障碍。

## 操作清单

- 只改写明确允许的分支；
- 改写前记录远程提交 ID；
- 确认没有共享依赖和发布标签；
- 完成变基后检查差异和测试；
- 使用 `--force-with-lease`，高风险时指定显式预期值；
- 推送后读取远程提交 ID并通知协作者。

## 仍不能做什么

租约只保护远程引用位置，不判断新历史是否功能正确，也不理解谁“应该”拥有分支。它不能把未经协调的主分支改写变成安全操作。
