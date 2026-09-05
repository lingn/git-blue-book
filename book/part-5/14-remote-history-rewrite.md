# 远端历史被重写后为什么同时 ahead 和 behind

本地分支突然显示 `ahead 3, behind 9`，并不表示 Git 算错了，也不等于“本地还有 3 条新工作、远端比我多 9 条业务需求”。它只说明：以当前本地分支和远程跟踪分支的共同祖先为界，本地一侧有 3 个只在本地可达的 commit，远端一侧有 9 个只在远端可达的 commit。

当远端历史被 rebase、reset 或其他非快进方式改写时，同一批业务变化可能以新 OID 再出现。旧提交于是被计入 ahead，新提交被计入 behind。判断它们是不是同一批变化，需要继续比较补丁和最终 tree，不能只看数量或提交说明。

## 一个正好得到 ahead 3、behind 9 的提交图

假设本地仍停在旧历史：

```text
                 L1---L2---L3  local feature
                /
C--------------+
                \
                 R1---R2---R3---R4---R5---R6---L1'---L2'---L3'  origin/feature
```

`C` 是共同祖先。远端在新的六条基线提交后，重新应用了原来三条提交的变化。`L1'`、`L2'`、`L3'` 的说明和补丁可能分别与 `L1`、`L2`、`L3` 相似，甚至最终文件完全一致，但它们的父提交不同。

commit 对象包含 tree、父提交、作者、提交者、时间和说明。父 OID 一变，commit 内容就变，OID 也会变化。因此 Git 按对象可达性得到：

```text
local-only:  3
remote-only: 9
```

这就是 `ahead 3, behind 9`。ahead/behind 统计 commit 身份，不判断两边的业务意图是否等价。

## 第一轮先固定现场

在出现问题的仓库根目录执行，不要先 pull、reset 或继续 rebase：

```bash
git status --short --branch
git branch -vv
git rev-parse HEAD
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
git log --graph --decorate --oneline --all --max-count=40
git reflog --date=iso -30
```

如果工作区有修改，再保存：

```bash
git diff --binary
git diff --staged --binary
git status --porcelain=v2 --untracked-files=all
```

未跟踪文件不在普通 diff 中。重要且从未进入 Git 的文件，要先用普通文件备份工具保存到仓库之外。

## 获取远端之后重新计算两边

`origin/feature` 是本地远程跟踪引用，不是服务器上的实时指针。只有通信后，它才表示这次 fetch 观察到的远端位置。

```bash
git fetch origin
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
git rev-list --left-right --count "HEAD...$upstream"
git log --left-right --graph --decorate --oneline "HEAD...$upstream"
```

若输出是：

```text
3       9
```

左边对应 `HEAD` 独有的 3 条，右边对应 `$upstream` 独有的 9 条。分别查看：

```bash
git log --oneline "$upstream..HEAD"
git log --oneline "HEAD..$upstream"
git merge-base HEAD "$upstream"
```

三点范围 `A...B` 以共同祖先为边界，双点范围 `A..B` 表示从 B 可达但从 A 不可达。这里没有“谁更新、谁过时”的价值判断，只是在数两组可达对象。

## 怎样知道远端发生过强制更新

### fetch 输出是第一条线索

当 fetch 发现远端分支从旧 OID 移到一个不以旧 OID 为祖先的新 OID，通常会显示 `forced update`。这表示本次引用更新不是快进，不表示一定有人直接运行了 `git push --force`。平台管理员操作、镜像同步、API 更新或其他历史改写也可能产生同样结果。

### 远程跟踪引用的 reflog 是本地证据

查看本地 `origin/feature` 近期怎样移动：

```bash
git reflog show --date=iso "$upstream"
```

典型记录类似：

```text
new_remote_oid origin/feature@{2026-09-01 10:20:30 +0800}: fetch origin: forced-update
old_remote_oid origin/feature@{2026-08-30 18:02:11 +0800}: fetch origin: fast-forward
```

这能证明当前 clone 的远程跟踪引用在那次 fetch 中发生了非快进移动。它不能证明：

- 是谁更新了服务器；
- 使用了 `--force`、`--force-with-lease`、平台 API 还是管理员工具；
- 服务器动作发生的精确时间，因为 reflog 时间是本地引用被更新的时间；
- 其他 clone 当时看到了什么。

要追究操作者和服务端动作，需要 GitLab、GitHub 或其他平台的审计事件、push 日志、保护规则例外记录和身份信息。仅凭本地 Git 数据不能可靠归因。

如果旧远端 OID 仍可读取，也可以验证新位置不是它的后代：

```bash
old_remote="<从 reflog 核实的完整旧 OID>"
new_remote="$(git rev-parse "$upstream")"
git merge-base --is-ancestor "$old_remote" "$new_remote"
```

退出码为 1 表示旧位置不是新位置的祖先，更新不可能是普通快进。退出码为 128 等错误表示对象或参数不可用，不能解释成非快进证据。

## 为什么 rebase --abort 后又回到旧状态

rebase 的目标是把本地提交放到新基线上重新创建。开始时，Git 会记录原分支和原分支头，然后检出新基线，逐条重放本地提交。发生冲突后执行：

```bash
git rebase --abort
```

abort 的职责不是“接受远端版本”，而是尽量恢复 rebase 开始前的分支、HEAD、index 和工作区。因此分支重新指回旧的本地提交链，`ahead 3, behind 9` 再次出现，正是预期结果。

不是通过界面现象猜到这一点，而是可以从 HEAD reflog 重建：

```bash
git reflog show --date=iso HEAD
```

典型顺序如下：

```text
old_local_tip HEAD@{...}: checkout: moving from main to feature
new_remote_tip HEAD@{...}: rebase (start): checkout origin/feature
old_local_tip HEAD@{...}: rebase (abort): returning to refs/heads/feature
```

最后一行同时写出了动作和返回目标。再核对：

```bash
git branch --show-current
git rev-parse HEAD
git status --short --branch
```

进行中的 rebase 才能 abort。rebase 已经成功完成后，sequencer 状态通常已经删除，应从恢复分支或 reflog 找旧位置，而不是再次运行 `git rebase --abort`。

## 区分旧副本和真正未发布的本地工作

这是处理前最关键的一步。提交说明相同只是一条线索，不是证明。

### 先按补丁等价性筛查

```bash
git cherry -v "$upstream" HEAD
```

输出前缀的含义：

- `-` 表示上游存在补丁等价的变化，这条本地提交很可能是改写前的旧副本；
- `+` 表示没有找到补丁等价项，它可能是真正未发布的工作，也可能是在改写时被调整过；
- 没有输出表示 HEAD 没有上游之外的提交。

`git cherry` 比较补丁，不比较业务语义。重命名、冲突解决、格式化、提交拆分或合并都可能让本质相近的变化显示为 `+`。

### 再比较两段提交序列

从提交图中核实旧序列和新序列的基线后：

```bash
old_base="<旧三条提交之前的完整 OID>"
new_base="<远端重建三条提交之前的完整 OID>"
git range-diff "$old_base..HEAD" "$new_base..$upstream"
```

`range-diff` 会尝试按补丁相似性配对，适合发现“同一变化换了父提交”“某条被拆分”“冲突解决改变了结果”。它不是安全证明，最终还要检查 tree 和项目测试：

```bash
git diff --stat "HEAD^{tree}" "$upstream^{tree}"
git diff "HEAD^{tree}" "$upstream^{tree}"
```

远端多出的六条基线变化会让最终 tree 不同，这不等于本地三条提交未被迁移。要把基线变化和三条任务变化分开审查。

### 给每条本地提交分类

处理记录至少列出：

| 本地提交 | patch 对应 | 是否有独有业务变化 | 处理 |
| --- | --- | --- | --- |
| `L1` | `L1'` | 否 | 旧副本，不再迁移 |
| `L2` | `L2'` | 否 | 旧副本，不再迁移 |
| `L3` | 无或不确定 | 是或待确认 | cherry-pick、重做或继续调查 |

只有当每条 `ahead` 提交都有结论，才能决定 reset 或 rebase。

## 四种处理路线

### 路线一：本地三条全是旧副本，没有未提交修改

这是最简单的情况。先确认工作区和 index 干净，再建立恢复分支：

```bash
git status --short
old_tip="$(git rev-parse HEAD)"
git branch recovery/before-remote-sync "$old_tip"
git reset --hard "$upstream"
```

验证：

```bash
test "$(git rev-parse HEAD)" = "$(git rev-parse "$upstream")"
git status --short --branch
git log --graph --decorate --oneline --all --max-count=30
git show --no-patch recovery/before-remote-sync
```

`reset --hard` 会覆盖已跟踪工作区和 index。只在两者确实干净、旧分支头已经被恢复引用保护、三条本地提交已确认没有独有工作时使用。

### 路线二：本地仍有少量真正未发布的提交

不要把整条旧历史再次 rebase。先从远端新位置创建干净分支，再只迁移已经确认的提交：

```bash
git branch recovery/before-remote-sync HEAD
git switch --create feature/recovered "$upstream"
git cherry-pick <genuine-local-oid-1> <genuine-local-oid-2>
```

发生冲突时判断每条变化在新基线上的业务意图，解决后运行测试。完成后用 `range-diff`、tree diff 和提交列表验收。

### 路线三：本地有大量独有工作，必须保留提交序列

先建立恢复分支，再根据已经核实的旧基线、新基线和待迁移范围设计 `rebase --onto`。不要仅凭 `ahead 3` 猜边界。任何一个边界 OID 不确定，就停止并改用逐条 cherry-pick 或让熟悉该需求的人确认。

### 路线四：远端改写本身是错误

不要让所有客户端各自 reset。暂停目标分支更新，保存服务器当前 OID、旧远端 OID 和依赖者清单，由分支负责人决定恢复哪个提交。若批准恢复远端引用，也要以服务器当前 OID 为显式租约，防止事故处理中覆盖新的更新。

## 一张可执行的事故检查表

1. 停止 pull、reset、rebase 和自动 prune，保存 status、refs、图和 reflog。
2. 备份未提交文件，确认未跟踪内容是否重要。
3. fetch 一次并记录输出，核对远程跟踪引用是否出现 `forced-update`。
4. 用 `rev-list --left-right --count` 解释数量，不把 ahead 当成新工作。
5. 用 `cherry`、`range-diff`、tree diff 和业务测试给每条本地提交分类。
6. 建立 `recovery/...` 分支后，再选择 reset、cherry-pick、rebase 或远端恢复。
7. 处理后核对本地 HEAD、远端 OID、评审、CI、制品和部署引用。
8. 需要追责时查平台审计，不从本地 reflog 猜操作者。

## 隔离实验

运行：

```bash
./scripts/verify-remote-history-rewrite.sh
```

实验会在临时目录中创建旧三条提交，随后在远端的新六条基线上重建这三条变化并强制更新。脚本验证 `ahead 3, behind 9`、补丁等价、远程跟踪 reflog 的 `forced-update`、rebase abort 返回旧分支头，以及建立恢复分支后同步到新远端。它不模拟托管平台审计、分支保护、真实网络、评审、CI 或业务测试。

## 小结

`ahead 3, behind 9` 是提交图的左右可达数量，不是业务变化数量。远端改写后，旧三条和重建后的三条即使内容相似，也因为父关系变化而成为不同 commit。强制更新由 fetch 输出和远程跟踪 reflog 证明，rebase abort 回到旧状态由 HEAD reflog 证明。真正的处理依据，是每条本地提交是否仍含远端没有的工作，而不是哪边数字更大。
