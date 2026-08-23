# 从误删分支、错误 reset 和失败 rebase 中恢复

恢复操作的顺序决定还能保留多少证据。事故发生后先停止自动维护、历史改写和重复尝试，确认问题属于正在进行的操作、已经完成的本地引用移动，还是已经更新远端的共享历史。

## 先保存一份只读现场记录

在事故仓库对应的工作区执行：

```bash
git status --short --branch
git rev-parse --show-toplevel
git rev-parse --git-dir
git rev-parse HEAD
git branch --all --verbose --no-abbrev
git log --graph --decorate --oneline --all --max-count=40
git reflog show --date=iso HEAD
```

这些命令不修改引用、index 或工作区。输出可能包含本地路径、分支名、邮箱和内部远程信息，对外发送前要脱敏。若工作区有 Git 从未跟踪的重要文件，用普通文件备份工具复制到仓库之外；Git 恢复流程不能承诺找回从未记录的内容。

不要先运行 `git gc`、`git prune`、`git reflog expire`、`git clean` 或新的 reset/rebase。它们可能清理对象、删除未跟踪文件或覆盖 `ORIG_HEAD` 和新的 reflog 位置。

## 操作仍在进行时使用自身的 abort

`git status` 会说明当前是否正在 merge、rebase、cherry-pick 或 revert。优先使用对应操作的中止命令：

```bash
git merge --abort
git rebase --abort
git cherry-pick --abort
git revert --abort
```

只运行与当前状态匹配的一条。abort 的目标是回到该序列开始前；操作前工作区本来就不干净、用户在暂停期间又执行其他命令，仍可能增加恢复复杂度。中止后重新执行现场记录命令，确认分支头、index 和工作区。

`--quit` 通常只移除当前操作的 sequencer 状态，不恢复分支和文件。除非明确要保留暂停现场并手工接管，不要把 quit 当成 abort。

## 误删未合并分支

删除分支移除了 `refs/heads/...` 名字。若提交对象仍在，可从 `HEAD` reflog、其他引用或外部记录寻找最后分支头。

查看分支删除前后的本地动作：

```bash
git reflog show --date=iso HEAD
git log --all --reflog --graph --decorate --oneline --max-count=60
```

找到候选完整 ID 后先验证，不立即切换：

```bash
candidate="replace-with-the-verified-full-object-id"
git cat-file -e "${candidate}^{commit}"
git show --stat --summary "$candidate"
git branch recovery/deleted-feature "$candidate"
```

新分支使候选提交重新由普通引用保持可达，不改变当前工作区。随后比较：

```bash
git log --left-right --graph --oneline main...recovery/deleted-feature
git diff --stat main...recovery/deleted-feature
```

三点范围要求存在共同祖先。若候选来自无关历史或对象损坏，命令会失败，应保留现场并转入取证流程。

## 错误 reset --hard

`reset --hard` 可能同时移动当前分支、重置 index 并覆盖已跟踪工作区。已提交的旧分支头通常可从命名恢复分支、`ORIG_HEAD` 或 reflog 找到：

```bash
git show --no-patch --decorate ORIG_HEAD
git reflog show --date=iso HEAD
```

`ORIG_HEAD` 只有一个值，后续操作可能覆盖。对候选执行 `cat-file` 和 `show` 检查后，先建立：

```bash
original_tip="replace-with-the-original-full-object-id"
git branch recovery/before-hard-reset "$original_tip"
```

这能恢复提交快照，不能恢复 hard reset 覆盖的未提交修改。编辑器本地历史、文件系统快照和备份可能持有这些字节，Git 不提供统一保证。

恢复引用创建后再选择如何把变化带回正式分支：merge 保留原拓扑，cherry-pick 选择部分提交；历史从未分享且确实要恢复原位置时，才考虑 reset 正式分支。任何会覆盖工作区的动作前都再次检查 `status`、`diff` 和 `diff --staged`。

## rebase 结束后才发现结果错误

进行中的 rebase 使用 `git rebase --abort`。已经成功结束后，sequencer 状态通常不存在，`--abort` 无法回到旧历史。改写前建立的恢复分支是最直接来源：

```bash
git show --no-patch recovery/before-interactive-rebase
```

没有恢复分支时，从 reflog 查找 `rebase (start)` 附近的原分支头，验证后创建：

```bash
original_tip="replace-with-the-original-full-object-id"
git branch recovery/before-failed-rebase "$original_tip"
```

比较原序列和重建序列：

```bash
base="replace-with-the-verified-common-base-id"
git range-diff \
  "$base"..recovery/before-failed-rebase \
  "$base"..HEAD
git diff \
  'recovery/before-failed-rebase^{tree}' \
  'HEAD^{tree}'
```

若 rebase 只是整理提交，最终 tree 差异通常应为空；若它同时解决冲突或更换基线，差异需要按任务意图逐项审查。原历史已经分享时，不能在本地选定版本后直接强推，先协调依赖者并使用显式租约。

## 错误强推已经更新远端

先暂停目标分支更新，分别记录服务器当前值和本地远程跟踪值：

```bash
target_branch="feature/search"
target_ref="refs/heads/$target_branch"
tracking_ref="refs/remotes/origin/$target_branch"
remote_now="$(
  git ls-remote --exit-code --heads origin "$target_ref" |
    awk '{print $1}'
)"
tracking_before_fetch="$(git rev-parse "$tracking_ref")"
printf 'server=%s\ntracking=%s\n' "$remote_now" "$tracking_before_fetch"
```

把 `target_branch` 改为真实分支名。先记录再 fetch，因为 fetch 会更新远程跟踪引用。旧提交可以从操作者 reflog、其他协作者克隆、CI 检出记录、评审页面或发布清单寻找。

找到操作前远端 ID 后建立本地恢复引用，并确认其对象完整：

```bash
remote_before_force="replace-with-the-previous-remote-full-object-id"
git branch recovery/remote-before-force "$remote_before_force"
git cat-file -e 'recovery/remote-before-force^{commit}'
```

团队确认恢复目标后，以服务器当前 ID 为新的显式租约进行条件更新。完整命令和并发拒绝处理见显式租约章节。若事故期间远端再次变化，恢复租约应拒绝，不能覆盖新提交继续执行。

远端引用恢复后，已经获取错误历史的克隆、评审状态、CI、制品和部署记录不会自动恢复，需要逐项通知和核对。

## 候选对象不存在或 reflog 已过期

本地常规证据找不到对象时，不要用猜测的短哈希创建分支。继续查找仍持有完整对象的来源：

1. 其他开发者克隆和 worktree；
2. 远程仓库的其他分支或标签；
3. 代码评审和 CI 记录的完整提交 ID；
4. Git bundle、镜像和仓库备份；
5. 服务端管理员保留的 reflog、隔离对象或快照。

`git fsck` 可以列出部分不可达对象，但输出需要对象取证知识，运行结果也受对象是否已清理影响。不要在事故现场一边执行 prune，一边尝试 fsck 恢复。v2 的灾难恢复篇会把对象库损坏、bundle 和备份恢复单独展开。

## 恢复验收同时检查四层

| 层次 | 证据 | 不能证明什么 |
| --- | --- | --- |
| Git 对象 | `cat-file` 能读取候选对象 | 候选就是正确业务版本 |
| 引用与提交图 | 恢复分支指向候选，父关系符合预期 | 工作区和 index 已安全 |
| 源码与测试 | tree 差异、构建和测试通过 | 远端、制品或部署已更新 |
| 共享与运行状态 | 远端 ID、CI、制品摘要、部署记录 | 数据副作用已经自动撤销 |

恢复分支至少保留到评审、发布和协作者迁移完成。事故记录应包含原始目标、误操作命令、候选来源、完整对象 ID、恢复命令、测试证据、远端结果和清理时间。

本篇的 `verify-interactive-rebase.sh`、`verify-reset-reflog.sh` 和 `verify-force-with-lease.sh` 分别覆盖 rebase 中止、引用恢复和远端条件恢复。它们使用临时本地仓库，只证明 Git 行为，不模拟平台审计、CI 或生产部署。
