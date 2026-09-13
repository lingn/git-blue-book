# 引用、HEAD 与 reflog：名字怎样移动，旧位置怎样留下证据

提交对象不会因为成为“当前版本”而改变。Git 通过引用给对象一个可移动的名字，再由 `HEAD` 表示当前工作树从哪个历史位置继续。引用移动后，旧提交可能离开普通历史视图；reflog 在本地记录这次移动，为诊断和恢复保留一段有期限的证据。

这三个层次需要分开观察：对象回答“内容和父关系是什么”，引用回答“哪个名字现在指向它”，reflog 回答“这个本地名字曾经怎样移动”。平台分支保护、评审批复和远端审计属于引用更新之外的控制面，不在本章实验中模拟。

## 进入条件与完成标准

正文中的观察命令可在普通仓库执行。涉及 `switch`、`commit`、`update-ref`、`pack-refs` 和 worktree 的命令只在一次性实验仓库执行。观察真实仓库前先固定位置和对象格式：

~~~bash
git status --short --branch
git rev-parse --show-toplevel
git rev-parse --show-object-format
git rev-parse --show-ref-format
~~~

后两条分别报告对象格式和引用存储格式。输出由 Git 版本与仓库决定，不能用 `sha1` 推断引用一定存放在 loose files，也不能看到 `files` 就假设所有引用都位于 `.git/refs`。

读完本章后，应能判断引用的逻辑名称与物理存储、附着/分离/unborn `HEAD`、普通引用与操作状态文件、`HEAD`/分支 reflog、linked worktree 日志范围，以及条件引用更新失败时的安全处理。

## 引用是名字到对象的映射

常见引用位于以下命名空间：

| 逻辑名称 | 常见目标 | 谁通常更新 | 是否会随 clone 直接复制 |
| --- | --- | --- | --- |
| `refs/heads/main` | commit | 本地 commit、merge、reset 等 | 目标提交可传输；源端本地 reflog 不复制 |
| `refs/remotes/origin/main` | commit | fetch、remote update 等 | 每个 clone 独立维护 |
| `refs/tags/v1.4.0` | 任意对象，常为 commit 或 tag object | tag/push/fetch | ref 和所需对象可按 refspec 传输 |
| `refs/notes/review` | notes commit | notes 命令或显式 ref 更新 | 只有 refspec 覆盖时才传输 |
| `refs/recovery/incident-42` | 经过验证的恢复候选 | 人工恢复流程 | 只有显式发布才会离开本地 |

本地分支通常必须指向 commit，标签可以直接指向任意对象。引用只保存当前目标，不把一组提交装进分支；所谓“分支历史”是从分支尖端沿 commit 父边遍历得到的可达集合。

使用引用 API 观察完整名称和值：

~~~bash
git for-each-ref --format='%(refname) %(objecttype) %(objectname)'
git show-ref --heads --tags
git show-ref --verify refs/heads/main
git rev-parse --verify 'refs/heads/main^{commit}'
~~~

`for-each-ref` 和 `show-ref` 会读取当前仓库可见的引用，不依赖调用者知道 backend。`rev-parse ...^{commit}` 还要求目标能剥离为 commit。引用不存在、对象缺失或类型不匹配时命令返回非零；脚本应检查退出码，不能把空输出解释为零值 OID。

## 逻辑引用不能靠遍历 `.git/refs` 盘点

使用 files backend 时，新引用可能先作为 loose ref 出现在 `.git/refs/...`，随后由 `pack-refs` 收进 `packed-refs`。同名 loose ref 可以覆盖已打包值。使用 reftable 等其他 backend 时，物理布局又不同。

因此，下面的文件系统遍历不是完整引用清单：

~~~bash
find .git/refs -type f
~~~

它还会在 linked worktree、分离 Git 目录和 bare 仓库中指向错误位置。需要定位管理文件时，让 Git 解析路径：

~~~bash
git rev-parse --git-dir
git rev-parse --git-common-dir
git rev-parse --git-path packed-refs
git rev-parse --git-path logs/HEAD
~~~

日常工具和自动化通过 `for-each-ref`、`show-ref`、`symbolic-ref`、`update-ref` 等接口操作逻辑引用。直接覆写 ref 文件会绕过锁、旧值校验、reflog 和 backend 抽象，也可能留下部分更新。

`git pack-refs --all` 是写操作。它改变引用的物理表示，可能与其他 writer 竞争锁，但不应改变任何逻辑 ref 的目标 OID。生产仓库不要为了确认“分支是不是文件”临时执行它。

## 符号引用多保存一层名字

直接引用保存对象 OID。符号引用（symbolic ref）保存另一个引用名，`HEAD` 是最常见的例子：

~~~text
HEAD -> refs/heads/main -> C
~~~

观察当前关系：

~~~bash
git symbolic-ref --quiet HEAD
git branch --show-current
git rev-parse --verify 'HEAD^{commit}'
~~~

在附着状态下，第一条输出 `refs/heads/main`，第二条输出 `main`，第三条输出当前 commit 的完整 OID。创建新提交 D 时，Git 创建 commit 对象并把 `refs/heads/main` 从 C 更新到 D；`HEAD` 仍保存分支名。

不要通过 `cat .git/HEAD` 作为通用实现。普通 files 仓库中它便于教学，但 linked worktree 的 `.git` 可能是指向实际 gitdir 的文本文件，其他引用 backend 也不承诺相同物理结构。`symbolic-ref` 和 `rev-parse` 给出的是 Git 解释后的状态。

## unborn HEAD 有名字，但还没有提交

刚初始化、尚未创建首个提交的仓库通常处于 unborn 状态：

~~~text
HEAD -> refs/heads/main -> 尚不存在
~~~

可以用两条不同查询识别：

~~~bash
git symbolic-ref --quiet HEAD
git rev-parse --verify 'HEAD^{commit}'
~~~

第一条成功并输出预设分支名，第二条失败，因为分支还没有目标 commit。此时 `git branch --show-current` 可能显示 `main`，但 `show-ref --verify refs/heads/main` 仍失败。自动化若只读取分支名，会把空仓库误报为已有可构建候选。

首个 `commit` 会创建根 commit 和 `refs/heads/main`。验收至少同时检查：

~~~bash
git show-ref --verify refs/heads/main
git cat-file -e 'refs/heads/main^{commit}'
git rev-list --parents --max-count=1 refs/heads/main
~~~

根提交的 `rev-list --parents` 输出只有自身 OID，没有父 OID。`cat-file -e` 成功时没有正常输出。

## 分离 HEAD 直接保存对象位置

在一次性仓库执行：

~~~bash
git switch --detach <full-commit-oid>
~~~

状态变为：

~~~text
HEAD -> B
refs/heads/main -> C
~~~

此时 `git symbolic-ref --quiet HEAD` 返回非零，`git branch --show-current` 输出空行，`git rev-parse HEAD` 仍返回 B。分离状态不是仓库损坏，它适合检查固定候选、复现构建或在 CI 中检出精确 OID。

如果在分离状态创建提交 D，只有当前 worktree 的 `HEAD` 移到 D，本地分支仍停在原处。离开前应为需要保留的提交创建恢复引用。候选验证和 `refs/recovery/*` 的完整操作流程见[reflog 与 recovery ref](../part-07/12-reflog-and-recovery-refs.md)，本章只解释为何需要这个名字。

切换分支还会尝试更新 index 与工作区。未提交修改会被覆盖时，`switch` 通常拒绝；保存 `status`、未暂存差异和已暂存差异后再处理，不用 `-f` 抹掉保护信号。

## HEAD 之外还有操作状态，不要统称为分支

Git 在特定操作中维护一些特殊名称或状态文件：

| 名称 | 典型含义 | 生命周期 |
| --- | --- | --- |
| `ORIG_HEAD` | 部分高风险操作开始前的位置 | 单一槽位，后续操作可能覆盖 |
| `MERGE_HEAD` | 正在合并的一个或多个对方 commit | merge 完成或中止后移除 |
| `CHERRY_PICK_HEAD` | 当前 cherry-pick 的来源 commit | 序列继续、完成或中止时变化 |
| `REVERT_HEAD` | 当前 revert 的目标 commit | revert 完成或中止后移除 |
| `REBASE_HEAD` | rebase 当前正在处理的 commit | 只在相应阶段存在 |
| `FETCH_HEAD` | 最近一次 fetch 获得的 ref/OID 记录 | 后续 fetch 可重写，不是远端权威状态 |

这些名称不都属于 `refs/` 命名空间，也不都遵守普通引用的 reflog、传输和并发语义。查询实际路径时使用：

~~~bash
git rev-parse --git-path MERGE_HEAD
git rev-parse --git-path rebase-merge
git rev-parse --git-path FETCH_HEAD
~~~

看到 `MERGE_HEAD` 或 rebase 状态目录时，先按正在进行的操作处理冲突、继续或中止。直接创建同名分支不能修复状态机，删除状态文件也可能让 Git 失去安全恢复入口。

## Reflog 是本地引用移动日志

启用日志的引用更新时，reflog 记录旧 OID、新 OID、操作者身份、时间、时区和说明。人类通常从格式化视图读取：

~~~bash
git reflog show --date=iso-strict HEAD
git reflog show --date=iso-strict refs/heads/main
git reflog exists refs/heads/main
~~~

`reflog exists` 只用退出码表示日志是否存在。`HEAD` 日志记录当前工作树看到的提交、切换和 reset 等动作；分支日志记录该分支本身怎样移动。附着状态创建提交时，两者通常都会新增记录。仅切换分支时，`HEAD` 日志变化，两个分支的目标可以都不变。分离状态创建提交时，当前 `HEAD` 日志变化，没有分支自动跟随。

`HEAD@{1}` 表示 `HEAD` 日志中的上一条位置，不等于当前提交的第一父提交。日志序号会随新动作和过期处理变化。恢复记录应保存验证后的完整 OID、仓库稳定身份、对象格式和采集时间，不把 `@{1}` 长期写进事故单。

reflog 是本地状态，不随 clone、fetch 或 push 复制。新 clone 可能为自己的本地分支写一条 `clone: from ...` 记录，但不会继承源仓库的 commit、reset 或 switch 日志。远端托管平台的引用审计、强制推送事件和保留期是另一套证据，必须单独采集。

## Linked worktree 共享分支，不共享 HEAD

同一仓库的 linked worktree 共享对象库和大多数 `refs`，每个 worktree 有自己的 `HEAD`、index、`logs/HEAD` 和进行中操作状态。可以观察解析后的绝对路径：

~~~bash
git rev-parse --path-format=absolute --git-dir
git rev-parse --path-format=absolute --git-common-dir
git rev-parse --path-format=absolute --git-path logs/HEAD
git worktree list --porcelain
~~~

两个 worktree 的 common directory 相同，gitdir 和 `logs/HEAD` 路径不同。`refs/heads/topic` 及其分支日志属于共享状态，因此一个 worktree 提交到 topic 后，另一个 worktree 能读取新的 topic OID；另一个 worktree 的 `HEAD` 日志不会冒充执行了这次提交。

共享 refs 带来真实并发：一个工作树准备把 `main` 从 A 更新到 B 时，另一个工作树可能已经把它更新到 C。操作不能依赖“我刚才看过”的无条件覆盖。

## 条件更新把观察值带回写入

`update-ref` 可以要求引用仍等于预期旧值：

~~~bash
git update-ref -m 'release: promote verified candidate' \
  refs/heads/main "$new_oid" "$expected_old_oid"
~~~

成功表示调用期间该引用从预期旧值更新到新值，并按配置写日志。若实际值已经变化，命令因锁或旧值不匹配返回非零，引用保持为竞争者的新值。处理顺序是重新读取实际 OID、确认更新来源、重算候选和审批，再用新的明确前置条件重试；不能去掉旧值参数把失败变成覆盖。

创建固定恢复引用也应拒绝覆盖同名证据。`update-ref --stdin` 提供 `create` 操作：

~~~bash
printf 'create refs/recovery/incident-42 %s\n' "$candidate_oid" |
  git update-ref --stdin
~~~

目标已存在时创建失败。引用名和 OID 必须来自已经校验的结构化输入，不能把不受信任文本直接拼进 shell。多个相关 ref 需要原子更新时，使用当前 Git 版本支持的 `update-ref --stdin` 事务能力，并在隔离环境验证失败回滚；逐条写文件无法提供同样保证。

本地条件更新只证明本机 ref 的并发前置条件。Push 的远端租约、受保护分支、合并队列和平台审批还需要接收端或平台控制面执行，不能用本地实验替代。

## 名称解析要消除歧义

`main`、路径 `main`、标签 `main` 和远程跟踪分支 `origin/main` 可能同时存在。交互式命令会按 revision 规则解析简写，但审计和自动化应使用完整 ref、类型约束和参数终止符：

~~~bash
git check-ref-format --branch "$branch_name"
git rev-parse --verify --end-of-options "refs/heads/${branch_name}^{commit}"
git show --no-patch --format=fuller --end-of-options "$full_oid"
~~~

路径与 revision 同时出现时用 `--` 分隔。引用名通过本地校验不代表远端允许创建；平台还可能实施保留前缀、大小写、长度、权限和策略限制。自动化记录最终完整 refname 和 OID，不只保留用户输入的短名。

## 观察与写入的副作用不同

| 命令 | 读取 | 可能写入 | 失败后的边界 |
| --- | --- | --- | --- |
| `for-each-ref`、`show-ref` | 当前可见 refs | 无 | 保存完整命令和退出码 |
| `symbolic-ref -q HEAD` | 当前 worktree 的 `HEAD` 关系 | 无 | 非零可能是分离状态，不直接判损坏 |
| `rev-parse --verify` | revision、对象类型和路径 | 无 | 区分 unborn、对象缺失和名称错误 |
| `reflog show` | 本地日志 | 无 | 空日志不证明对象从未存在于别处 |
| `switch` | 目标提交、index、工作区 | `HEAD`、index、工作区、日志 | 被拒绝时保留现场，不强制覆盖 |
| `update-ref` | 当前 ref 与预期旧值 | ref、锁、reflog | 失败后重新读取，不改成无条件写 |
| `pack-refs` | refs 和 backend 状态 | 引用物理存储、锁 | 不作为事故现场观察命令 |
| `reflog expire` | 日志与过期配置 | 可能删除日志记录 | 恢复窗口内只做经审批的 dry-run |

reflog 记录和对象都受过期与维护策略影响。不要在寻找旧提交时运行 `gc`、`prune` 或真正的 `reflog expire`。对象已 missing/corrupt 时转入[对象取证与恢复](../part-11/02-object-forensics-and-recovery.md)；只是引用误移动时按第七篇的恢复流程先建立新名字。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| 有分支名但 `HEAD^{commit}` 失败 | `symbolic-ref HEAD`、`show-ref`、仓库是否刚初始化 | unborn 时创建经过审查的首个提交；其他情况按损坏处理 |
| `symbolic-ref -q HEAD` 返回非零 | `rev-parse HEAD`、`status --branch` | 能解析 commit 时是分离状态，先给需要保留的提交建 ref |
| `.git/refs` 中找不到网页上的分支 | ref backend、packed refs、本地 fetch 范围和时间 | 用引用 API 盘点，再分别核对远端与平台 |
| `cannot lock ref` 或旧值不匹配 | 实际 old/new OID、writer、linked worktree | 停止覆盖，重新生成候选和条件更新 |
| reflog 没有预期提交 | 仓库/工作树是否正确、日志配置、过期与操作来源 | 查其他本地 refs、worktree、clone、备份和平台证据 |
| clone 中没有源仓库 reflog | clone 自己的日志和源端日志 | 回源端采集；不要把传输后的历史当作操作审计 |
| `HEAD@{1}` 与预期不同 | 新增日志动作、日志过期、选择器作用域 | 从保存的完整 reflog 输出验证 OID，不猜序号 |

若引用文件、packed refs 或 reftable 物理数据疑似损坏，先停止 writer 并制作证据副本。不要手工删 lock 或复制未知 ref 文件；并发和损坏的分流见[仓库损坏、锁文件与并发操作](../part-13/08-repository-corruption-locks-concurrency.md)。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-refs-head-reflog.sh
~~~

脚本验证 unborn `HEAD` 只有符号目标、首个提交建立分支、`update-ref` 在 expected-old 正确时成功且在旧值过期时拒绝、`pack-refs` 前后逻辑 OID 不变、分离提交不移动分支、recovery ref 保留候选，以及 linked worktree 共享分支日志但拥有独立 `logs/HEAD`。最后从源仓库 clone，断言源端自定义 reflog 说明不会传入新 clone。

实验只操作临时目录，不连接托管平台，不运行日志过期或对象清理，也不模拟远端租约、审批、分支保护和审计事件。它通过真实 Git 状态和退出码做断言，不把示例文本当成 Git 输出。

## 小结

引用提供可移动的对象名字，`HEAD` 提供当前 worktree 的历史入口，reflog 提供本地移动记录。逻辑引用可能由不同 backend 保存；unborn、附着和分离 `HEAD` 也有不同的成功条件。写入引用时保留 expected-old 前置条件，恢复时尽快把验证过的 OID 挂到新引用，并把本地日志、远端 refs 和平台审计作为三类证据分别核对。

## 资料

- [gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)
- [gitglossary](https://git-scm.com/docs/gitglossary)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-symbolic-ref](https://git-scm.com/docs/git-symbolic-ref)
- [git-update-ref](https://git-scm.com/docs/git-update-ref)
- [git-reflog](https://git-scm.com/docs/git-reflog)
- [git-worktree](https://git-scm.com/docs/git-worktree)
- [git-pack-refs](https://git-scm.com/docs/git-pack-refs)
