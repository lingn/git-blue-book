# reflog 保存引用移动的本地证据

分支从 C 被 reset 到 B 后，普通 `git log main` 只能沿 B 的父关系向前查找，C 看起来像消失了。Git 通常还在本地 reflog 中记录这次引用移动。只要对象尚在，就可以根据记录重新给 C 创建名字。

```text
A <- B  main
      \
       C  没有普通分支指向，但可能仍被 reflog 引用
```

reflog 是恢复线索，不是备份系统。它记录本地引用曾经指向哪里，不保存工作区的每次编辑，也不会随 push 复制到其他仓库。

## 一条 reflog 记录包含什么

引用更新时，reflog 记录旧对象 ID、新对象 ID、操作者身份、时间和说明。`HEAD` 日志还会记录分支切换，因此它通常比单个分支日志覆盖更多本地动作。

查看 `HEAD` 日志：

```bash
git reflog show --date=iso HEAD
```

典型输出形状如下，哈希、身份、时间和序号都以本机实际结果为准：

```text
b2b2b2b HEAD@{2026-08-20 10:00:00 +0800}: reset: moving to HEAD~1
c3c3c3 HEAD@{2026-08-20 09:58:00 +0800}: commit: add payment validation
```

`HEAD@{1}` 表示 HEAD 日志中前一条位置，不等于“上一个提交”。每次切换、提交或 reset 都可能新增记录并改变序号。事故记录应保存核对后的完整对象 ID，不要长期保存 `HEAD@{1}` 这种相对选择器。

查看特定分支日志：

```bash
git reflog show --date=iso refs/heads/main
```

分支删除后，对应日志可能一起删除，`HEAD` 日志仍可能保留曾经检出和提交的线索。可以先检查某个引用是否有日志：

```bash
git reflog exists refs/heads/main
```

存在时退出状态为 0，不存在时为非零，没有成功文本可匹配。

## ORIG_HEAD 只有一个位置

reset、merge、pull 等操作会在部分场景把操作前的分支头写入 `ORIG_HEAD`。它适合立即撤回刚完成的一次操作：

```bash
git show --no-patch --decorate ORIG_HEAD
```

`ORIG_HEAD` 不是按时间追加的日志，后续操作可以覆盖它。reflog 可以保留多次引用更新，两者应分别核对。任何候选对象都要检查内容和父关系，不能因为名字叫 ORIG_HEAD 就直接 hard reset。

## 从候选到恢复引用

事故现场先减少写操作，不运行 `git gc`、`git prune`、`git reflog expire` 或会继续改写历史的命令。查看日志后，把候选完整 ID 保存到变量：

```bash
candidate="replace-with-the-full-object-id-from-reflog"
```

不要输入尖括号占位符。依次验证对象类型、提交内容和附近历史：

```bash
git cat-file -e "${candidate}^{commit}"
git show --stat --summary "$candidate"
git log --graph --decorate --oneline --all --boundary "$candidate"~3.."$candidate"
```

第一条成功时没有输出；对象缺失或不能剥离为 commit 时返回非零状态。根提交没有 `~3`，最后一条可能报错，此时直接使用：

```bash
git log --graph --decorate --oneline --all --max-count=20 "$candidate"
```

确认候选后创建新分支：

```bash
git branch recovery/payment-work "$candidate"
git log --decorate --oneline --max-count=5 recovery/payment-work
```

创建分支只新增引用，不移动当前 `HEAD`，也不覆盖 index 和工作区。之后再比较恢复分支与正式分支的差异，决定 merge、cherry-pick 或在未共享历史中移动正式分支。

## reflog 能恢复哪些状态

reflog 适合寻找曾经成为引用目标的对象，例如 reset 前的提交、amend 前的提交、变基前的分支头和删除分支前曾检出的提交。它不能直接恢复以下内容：

- 从未提交且从未写入对象数据库的编辑器内容；
- `reset --hard` 覆盖的未提交已跟踪修改；
- 只存在于另一台电脑、从未进入当前仓库的提交；
- 已经过期且对象已被清理的历史；
- 平台评审、CI 日志、发布制品和权限状态。

`git add` 可能把文件内容写成 blob，但 reflog 不记录这个 blob。没有 tree、commit 或已知对象 ID 时，从对象库取证属于后面的历史取证主题，不能把它当作常规恢复保证。

## 日志和对象都有保留期限

Git 2.49.0 文档给出的默认配置是：可达 reflog 条目通常 90 天过期，不可达条目通常 30 天过期。实际值可由系统、全局或仓库配置覆盖：

```bash
git config --show-origin --get gc.reflogExpire
git config --show-origin --get gc.reflogExpireUnreachable
```

配置未显式设置时，这两条命令可能没有输出并返回非零状态，Git 仍使用默认值。过期时间不等于对象必定存活到那一天，也不等于到期立刻删除；清理还取决于维护任务、对象可达性、prune 配置和仓库实现。

只想评估哪些记录会过期时，可以使用 dry-run：

```bash
git reflog expire --dry-run --verbose --all
```

它不删除记录，但会按当前配置计算候选。事故恢复期间不要去掉 `--dry-run`，也不要运行 `git gc --prune=now` 之类会缩短恢复窗口的命令。

## reflog 属于当前仓库

本地 reflog 不会随 fetch、push 或 clone 传输。Alice 的 reflog 不会自动包含 Bob 的 reset，新的 clone 也不会带上服务器或旧克隆的 reflog。裸仓库是否记录 reflog 取决于其配置和服务实现。

使用多个 worktree 时，各工作树有自己的 `HEAD` 等每工作树引用日志，普通分支引用由仓库共享。事故报告要记录命令在哪个 worktree 执行，不能只写仓库名称。

本地日志找不到候选时，按证据强度继续查找：其他克隆中的分支和 reflog、远程引用、评审页面记录的完整提交 ID、CI 检出记录、发布清单和管理员备份。找到 ID 后仍需验证对象是否在当前仓库；必要时从仍持有对象的仓库建立临时引用并获取。

## 恢复完成后的验证

恢复分支创建后，至少确认：

```bash
git cat-file -e 'recovery/payment-work^{commit}'
git diff --stat main...recovery/payment-work
git log --left-right --graph --oneline main...recovery/payment-work
git status --short --branch
```

三点 diff 需要两边存在共同祖先；没有共同祖先时会失败，应改为分别检查两个 tree 或使用适合该事故的比较方式。测试通过、协作者确认并完成发布后，再按保留策略清理恢复分支。

上一章的 `verify-reset-reflog.sh` 同时验证 reset 产生的 `ORIG_HEAD`、HEAD reflog 记录和恢复引用。实验只在临时仓库中运行，不模拟日志过期、对象清理或远程服务端保留策略。
