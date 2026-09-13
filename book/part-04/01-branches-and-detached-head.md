# 分支与分离 HEAD：工作线是可移动入口，不是提交容器

分支是 `refs/heads/` 下指向 commit 的引用。它保存当前尖端 OID，不保存一份独立目录，也不把一组 commit 装进命名容器。所谓“分支上的历史”，是从尖端沿父边可达的提交集合。

`HEAD` 决定当前工作树从哪个位置继续。它可以附着到本地分支，也可以直接指向 commit；刚初始化的仓库还可能有分支名却没有首个 commit。对象和引用的数据格式见第三篇，本章讨论这些状态对开发工作线的影响。

## 进入条件与完成标准

只读观察可在普通仓库运行。创建、移动、删除分支和分离 `HEAD` 只在一次性实验仓库操作。开始前固定：

~~~bash
git status --short --branch
git symbolic-ref --quiet HEAD
git rev-parse --verify 'HEAD^{commit}'
git for-each-ref refs/heads/ --format='%(refname) %(objectname)'
~~~

`symbolic-ref` 在分离状态返回非零，`rev-parse` 在 unborn 状态返回非零。这两类结果有不同含义，不能统一报成“仓库没有分支”。

读完本章后，应能区分附着、分离和 unborn `HEAD`，解释分支可达集合，分开本地分支、远程跟踪引用与 upstream 配置，判断 linked worktree 对分支占用的影响，并在删除或离开工作线前保存可验证恢复入口。

## 分支只保存尖端 OID

线性历史可以画成：

~~~text
A <- B <- C
          ^
          refs/heads/main
~~~

创建 D 后，Git 写新 commit，再把当前分支从 C 移到 D：

~~~text
A <- B <- C <- D
               ^
               refs/heads/main
~~~

A、B、C 没有被修改，`main` 也没有“拥有”它们。从另一个 ref 指向 D，两个名字会暂时拥有相同可达历史。查看：

~~~bash
git show-ref --heads
git for-each-ref refs/heads/ \
  --format='%(refname) %(objectname) %(upstream)'
git rev-list --count refs/heads/main
~~~

`rev-list --count` 统计从该尖端可达的 commit，并不读取平台评审、隐藏 refs 或其他 clone。分支创建时间也不是 commit 字段；平台可能另存事件，本地 Git ref 本身不提供永久创建时间。

## 一个工作树有三种常见 HEAD 状态

### 附着在本地分支

~~~text
HEAD -> refs/heads/main -> D
~~~

~~~bash
git symbolic-ref --quiet HEAD
git branch --show-current
git rev-parse 'HEAD^{commit}'
~~~

三条命令分别读取完整分支 ref、短分支名和最终 commit。提交成功时当前分支移动，`HEAD` 仍保存这个分支名。

### 分离在具体 commit

~~~text
HEAD -> B
refs/heads/main -> D
~~~

`git symbolic-ref --quiet HEAD` 返回非零，`git branch --show-current` 输出空，`git rev-parse HEAD` 仍返回 B。分离状态适合固定 OID 的检查、CI checkout、旧版本复现和临时候选构造，不表示仓库损坏。

在分离状态创建 commit E 时，只有当前 worktree 的 `HEAD` 移到 E，没有本地分支自动保留它。离开前先建立明确名字：

~~~bash
candidate="$(git rev-parse 'HEAD^{commit}')"
git branch recovery/detached-review "$candidate"
git show --no-patch --format='%H%n%P%n%T%n%s' \
  recovery/detached-review
~~~

创建恢复分支不切换工作区。候选仍需验证父提交、tree、说明和业务内容；仅因为它来自 `HEAD` reflog 不能直接合入主线。

### Unborn 分支尚无 commit

刚初始化时可能是：

~~~text
HEAD -> refs/heads/main -> 不存在
~~~

`symbolic-ref HEAD` 成功而 `HEAD^{commit}` 失败。此时分支名只是首个提交将要更新的目标。自动化需要可构建候选时，必须同时验证 commit，不能把 `branch --show-current` 有输出当成已有历史。完整模型见[引用、HEAD 与 reflog](../part-03/03-refs-head-and-reflog.md)。

## 分支关系由可达性决定

给定 `topic` 和 `main`：

~~~bash
topic_oid="$(git rev-parse 'refs/heads/topic^{commit}')"
main_oid="$(git rev-parse 'refs/heads/main^{commit}')"
git merge-base --is-ancestor "$topic_oid" "$main_oid"
git rev-list --left-right --count "$main_oid...$topic_oid"
~~~

祖先判断退出 0 表示 topic 尖端已经从 main 可达；退出 1 表示不成立，其他非零表示查询失败。左右数量显示两端独有 commit，不证明补丁等价、评审通过或运行结果一致。

`git branch --merged main` 以本地可见提交图列出尖端已从 main 可达的本地分支。Squash 或 rebase merge 会创建不同 commit，原功能尖端可能不成为主线祖先，即使最终 tree 包含同样变化。删除源分支前应按实际整合方式验证，不能把 `--merged` 当成所有工作流的统一判据。

日期、提交说明和文件当前内容也不能替代父关系。两条分支可以 tree 相同而历史不同，或 commit 时间倒退但仍保持祖先关系。

## 本地分支、远程跟踪引用和 upstream 是三类状态

| 状态 | 例子 | 谁更新 | 作用 |
| --- | --- | --- | --- |
| 本地分支 | `refs/heads/topic` | 当前提交、merge、reset 等本地操作 | 可检出的工作线 |
| 远程跟踪引用 | `refs/remotes/origin/topic` | fetch、remote update 等 | 本地保存的远端观察点 |
| Upstream 配置 | `branch.topic.remote/merge` | switch/branch/config 等 | 告诉 status、pull、push 默认比较谁 |

本地 `topic` 不会因为同名 `origin/topic` 前进而自动移动。远程跟踪引用也只是最近一次成功通信后的缓存。Upstream 不是第三个分支对象，它把本地分支关联到 remote/refspec 上下文。

查看三者：

~~~bash
git for-each-ref refs/heads/topic refs/remotes/origin/topic \
  --format='%(refname) %(objectname) %(upstream) %(upstream:track)'
git config --get-regexp '^branch\.topic\.(remote|merge)$'
~~~

没有 upstream 时第二条返回非零，不影响本地分支存在。Upstream 指向不存在或过期的远程跟踪引用时，`status` 的 ahead/behind 也无法代表服务器当前状态。

## 分支名是逻辑标识，不是权限边界

本地验证：

~~~bash
git check-ref-format --branch feature/payment-retry
~~~

退出 0 只表示符合本地分支名语法。托管平台还可能限制前缀、长度、大小写、Unicode、保留名、创建者或规则作用域。分支名中的 `/` 只是 ref 名的一部分，不自动产生目录权限、代码所有权或发布环境。

自动化不要把不受信任分支名直接拼入 shell、路径或部署命名。先验证 refname，使用参数数组和 `--`，再映射到经过转义和长度限制的外部标识。即使 Git 名合法，也可能包含对日志、URL 或文件系统不安全的字节。

## Linked worktree 会占用分支

每个 linked worktree 有独立 `HEAD`、index 和工作区，却共享大多数 `refs/heads/*`。Git 默认不允许同一个本地分支同时在两个工作树检出，因为两个独立 index 都可能尝试移动同一 ref。

~~~bash
git worktree list --porcelain
git branch --show-current
git rev-parse --path-format=absolute --git-common-dir
~~~

创建、切换、删除或强制移动分支前，先读 worktree 清单。看到 “already checked out at” 是并发保护信号，应切换到拥有该分支的工作树，或使用新的本地分支；不要用 `--ignore-other-worktrees` 绕过。

Worktree 不是权限或进程隔离。共享 refs、对象、hooks 和部分配置仍会互相影响，完整边界见[多个工作树](../part-02/12-multiple-worktrees.md)。

## 删除分支删除的是入口

已验证完成的本地分支可以尝试：

~~~bash
git branch -d topic
~~~

小写 `-d` 会按 Git 的合并关系检查并拒绝部分未合入尖端。它不查询平台评审、squash 映射、发布制品或其他远端。当前分支或被另一个 worktree 检出的分支也会受到保护。

`-D` 跳过合并检查，只删除 ref。对象不会在同一瞬间被逐层擦除，但恢复入口减少，reflog 会过期，后续维护可能清理不可达对象。只有已经保存完整尖端 OID、确认外部依赖和恢复来源，并明确接受丢弃历史时才考虑强制删除。

误删后停止 `gc`、`prune` 和继续改写，先从保存的 OID、`HEAD` reflog、其他 refs、评审候选、远端或同事 clone 找候选。验证后创建新的 `refs/recovery/*`，具体流程见[reflog 与 recovery ref](../part-07/12-reflog-and-recovery-refs.md)。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| `branch --show-current` 为空 | `rev-parse HEAD`、`symbolic-ref -q HEAD` | 能解析 commit 时是分离状态，先保留需要的工作 |
| 有当前分支名但 `HEAD^{commit}` 失败 | unborn 状态、ref 文件和对象库 | 新仓库创建经审查首个提交；其他情况按损坏分流 |
| `branch --merged` 没列出已完成评审 | 实际 merge/squash/rebase 方式和最终 OID | 按拓扑、patch/tree 和平台映射联合验证 |
| 本地分支和 `origin/*` 不同 | fetch 时间、refspec、远端权限和服务器 refs | 分开记录缓存与远端，不让本地名字互相覆盖 |
| 分支已在另一个 worktree | worktree 路径、owner、运行任务和状态 | 到原工作树处理或建新分支，不强占 |
| 删除后找不到尖端 | reflog、保存 OID、其他 refs/clone/平台 | 先建 recovery ref，不运行对象清理 |
| 本地名字合法但远端拒绝 | 平台命名/权限/规则和原始错误 | 按服务端约束修正，不伪造同名本地成功 |

分支关系异常时先保存完整 OID、父关系、refs 和 worktree 清单。不要使用 `reset --hard`、`branch -D` 或无条件 `update-ref` 把图形改成预期形状。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-branch-switching.sh
~~~

实验验证创建分支不切换当前工作树，功能提交只移动当前分支，分离提交不移动任何本地分支，建立 recovery ref 后候选继续可达。它还创建 linked worktree，断言同一分支不能被第二个工作树占用。

脚本同时覆盖切换保护和 upstream，由下一章解释。它只使用临时本地/bare 仓库和虚构身份，不验证平台分支保护、远程审计、squash 评审映射或真实协作者并发。

## 小结

分支是 commit 尖端的可移动名字，历史集合由父关系决定。`HEAD` 可以附着、分离或处于 unborn 状态；本地分支、远程跟踪缓存和 upstream 配置各有独立生命周期。离开或删除工作线前固定完整 OID、整合方式和恢复来源，linked worktree 与平台控制面还要分别核对。

## 资料

- [git-branch](https://git-scm.com/docs/git-branch)
- [git-symbolic-ref](https://git-scm.com/docs/git-symbolic-ref)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-check-ref-format](https://git-scm.com/docs/git-check-ref-format)
- [git-worktree](https://git-scm.com/docs/git-worktree)
