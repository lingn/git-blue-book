# 当前所在位置：HEAD 如何连接分支与工作区

仓库可以有很多分支，但一个工作区在某一时刻只有一个当前历史位置。Git 用特殊引用 HEAD 保存这个上下文。理解 HEAD 的关键是分清两种形态：它通常是指向分支的符号引用，也可以直接指向某个提交。

## 进入条件与完成标准

在至少有一条提交的练习仓库根目录执行：

~~~bash
git status --short --branch
git rev-parse --verify HEAD^{commit}
~~~

如果工作区有未提交内容，先保存状态和差异。切换或分离 HEAD 可能覆盖工作区，不能把“教程需要下一步”当作覆盖现有内容的授权。

读完本章后，你应能：

- 读取 HEAD 的原始内容和最终 commit OID；
- 区分附着在分支上的 HEAD 与分离 HEAD；
- 使用 HEAD~n、HEAD^n 和 @{-1} 进行相对定位；
- 判断切换操作会改变哪些状态区域；
- 在分离状态创建提交前建立恢复引用；
- 处理找不到 HEAD、切换冲突和 linked worktree 的边界。

## 附着状态：HEAD 指向分支

普通检出状态可以画成：

~~~text
HEAD
  |
  v
refs/heads/main -> C
~~~

查看它：

~~~bash
cat .git/HEAD
git symbolic-ref --quiet HEAD
git branch --show-current
git rev-parse HEAD
~~~

在普通仓库中，.git/HEAD 通常包含 ref: refs/heads/main。symbolic-ref 返回完整符号引用，branch --show-current 返回短分支名，rev-parse HEAD 返回当前分支所指向的 commit OID。

创建提交时，Git 以当前 HEAD 为父提交创建新对象，然后更新 refs/heads/main。HEAD 文件本身仍指向 main，因此看起来是分支向前移动。

如果仓库刚初始化还没有提交，symbolic-ref 可能成功，但 rev-parse HEAD 会失败。此时是“有分支名、无分支目标”，不能把 HEAD 当成可比较的 commit。

## 分离状态：HEAD 直接指向提交

查看旧提交而不切换任何分支：

~~~bash
git switch --detach <full-commit-id>
~~~

状态变成：

~~~text
HEAD -> B
main -> C
~~~

此时 .git/HEAD 保存的是一个 OID，而不是 ref: ...。检查：

~~~bash
git symbolic-ref --quiet HEAD
printf 'symbolic-ref exit=%s\n' "$?"
git branch --show-current
git rev-parse HEAD
git status --short --branch
~~~

前两条中的 symbolic-ref 和 branch --show-current 会以非零状态或空输出表示没有当前分支，rev-parse HEAD 仍能解析出 B。分离状态适合检查旧快照、运行一次性测试和构造临时候选。

如果在分离状态创建提交，新的 commit 会以 B 为父提交，但没有本地分支自动指向它：

~~~text
B <- D
      ^
     HEAD
main -> C
~~~

离开前建立名字：

~~~bash
git branch recovery/detached-work HEAD
~~~

这条命令只创建引用，不切换工作区。先用 git show --no-patch recovery/detached-work 检查 OID，再切回目标分支。没有恢复引用的分离提交可能只依赖 HEAD reflog 和对象保留窗口。

## 相对提交名称

常见相对语法：

| 写法 | 含义 | 适用前提 |
| --- | --- | --- |
| HEAD~1 | 沿第一个父提交走一步 | 当前提交有父提交 |
| HEAD~2 | 连续沿第一个父提交走两步 | 至少有两代父提交 |
| HEAD^1 | 选择第一个父提交 | 普通提交或合并提交 |
| HEAD^2 | 选择合并提交的第二父提交 | 当前提交必须有第二父提交 |
| @{-1} | 上一次检出的分支或提交 | 本地 checkout/switch 记录存在 |
| HEAD@{yesterday} | reflog 中按时间查找的旧位置 | reflog 尚未过期且时间可解析 |

~ 表示沿第一个父提交重复移动，^n 表示在一个提交上选择第 n 个父节点。合并提交使用 HEAD^1 和 HEAD^2 时必须先读取父列表：

~~~bash
git rev-list --parents -n 1 HEAD
~~~

相对名称是查询表达式，不会改变引用。表达式解析失败时保留原始错误，不要为了让命令通过而创建无意义提交。

## 切换 HEAD 会发生什么

切换到已有分支：

~~~bash
git switch main
~~~

Git 需要完成三件事：

1. 更新 HEAD，让它指向 refs/heads/main；
2. 用目标提交的 tree 更新 index；
3. 把目标快照写入工作区中不会覆盖用户修改的路径。

如果目标分支会覆盖未提交的工作区或 index 内容，Git 通常拒绝切换。拒绝是保护信号，先保存：

~~~bash
git status --short
git diff
git diff --staged
~~~

不要使用 git switch -f 或旧式 checkout -f 绕过它，除非已明确备份要覆盖的内容并完成风险审批。强制切换可能直接丢失未提交字节。

## HEAD 与远程跟踪分支

执行：

~~~bash
git switch --detach origin/main
~~~

会让 HEAD 分离在本地远程跟踪引用当前的 OID 上。它不会把远端变成可写分支，也不会自动刷新 origin/main。要从该位置开始开发，应创建本地分支：

~~~bash
git switch --create review/origin-main
~~~

origin/main 是本地缓存的 remote-tracking ref，远端服务器是否已经变化要通过 fetch 或远端查询核对。分离 HEAD 不能绕过认证和授权。

## Linked worktree 的特殊位置

一个仓库可以有多个 linked worktree。它们共享对象库和大多数 refs，但每个工作树有自己的 HEAD、index 和进行中操作状态。不要用主工作树的 .git/HEAD 代表所有工作树当前分支。

在任一工作树中查询真实路径：

~~~bash
git rev-parse --git-dir
git rev-parse --git-common-dir
git worktree list --porcelain
~~~

切换或恢复前先确认命令针对哪个 worktree。一个工作树正在执行 merge/rebase 时，另一个工作树仍可能处于普通状态，但共享 ref 更新仍会产生并发竞态。

## 失败路径与恢复

| 现象 | 先收集 | 处理边界 |
| --- | --- | --- |
| bad revision HEAD | cat .git/HEAD、symbolic-ref、show-ref | 可能是无提交仓库、损坏 ref 或错误目录 |
| 切换被拒绝 | status、工作区/index diff、目标提交 tree | 保存或提交后再切换，不用强制覆盖 |
| 分离提交找不到 | HEAD reflog、其他 refs、对象统计 | 先用完整 OID 建恢复分支 |
| cannot lock ref | 进程、ref lock、linked worktree 状态 | 停止并发写入，按锁处理流程恢复 |
| 工作树分支显示错误 | --git-dir、--git-common-dir、worktree list | 以当前 worktree 的 git dir 为准 |
| symbolic-ref 空输出 | 当前 HEAD 是分离状态 | 读取 rev-parse HEAD，不要把空分支名当作丢失提交 |

恢复的第一动作是保存引用和工作区证据。不要直接删除 .git、.git/worktrees 或 reflog；这些目录可能是唯一的本地恢复入口。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-3-basics.sh
~~~

现有实验验证普通分支切换时 HEAD 与分支关系、功能提交的分支归属，以及快进合并后的引用值。它不覆盖真实 linked worktree 并发、强制切换的数据丢失或远程跟踪新鲜度；这些要在目标环境单独演练。

## 小结

HEAD 是当前工作上下文。附着状态中它指向分支，分离状态中它直接指向提交；两种状态都能读取历史，但只有分支会自动保留新提交。切换会同时影响 HEAD、index 和工作区，遇到未提交内容先保护现场，再决定是否移动。
