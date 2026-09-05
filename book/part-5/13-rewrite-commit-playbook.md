# 提交之后又想改：先判断有没有共享，再决定改写还是追加

提交不是可以原地编辑的文档。补一个文件、改一句提交说明、合并两条提交或删除一条提交，都会创建新的 commit，或者让分支改指向别的 commit。真正决定操作方式的，不是“改动大不大”，而是旧提交是否已经成为别人使用的坐标。

本章把常见需求放进同一套判断流程。`amend`、交互式 rebase、revert 和显式租约的完整模型仍以本篇前面的权威章节为准，这里只解决实际工作中“现在该走哪条路”。

## 先回答三个问题

动手前执行：

```bash
git status --short --branch
git branch -vv
git log --graph --decorate --oneline --all --max-count=30
git diff
git diff --staged
```

然后回答：

1. 要改的是最新一条提交，还是更早的提交？
2. 旧提交是否已经推送、进入评审、被 CI 检查、被别人拉取，或者用于制品和部署？
3. 工作区与 index 是否还混有其他任务的修改？

“已推送”是最容易观察的共享信号，但不是唯一信号。本地提交也可能已经被另一个 worktree、bundle、CI 或同事的临时远端使用。无法确认时，按已共享处理。

| 现场 | 默认动作 | 原因 |
| --- | --- | --- |
| 最新提交未共享，补充内容属于同一意图 | `git commit --amend --no-edit` | 用新的完整提交替换旧提交 |
| 最新提交未共享，只改说明 | `git commit --amend` | 说明属于 commit 内容，修改后 OID 会变化 |
| 更早的未共享提交要改名、合并、拆分或删除 | `git rebase -i` | 从目标提交起重建后续序列 |
| 个人远程分支允许改写 | 本地改写后使用显式 `--force-with-lease` | 条件更新远端，避免覆盖查询后出现的新提交 |
| 主线、发布分支或多人共享分支 | 追加修正或 `git revert` | 保留已经公开的提交坐标 |

## 刚提交但还没推送，又补了一段代码

假设最新提交刚完成，后来发现漏了同一功能的一份测试。先只暂存这份补充：

```bash
git status --short
git diff -- tests/search_test.java
git add -- tests/search_test.java
git diff --staged --check
git diff --staged
```

确认 index 里只有应当并入原提交的内容后，保存旧位置并改写：

```bash
old_tip="$(git rev-parse HEAD)"
git branch recovery/before-amend "$old_tip"
git commit --amend --no-edit
new_tip="$(git rev-parse HEAD)"

test "$new_tip" != "$old_tip"
git show --stat --format=fuller HEAD
git status --short
```

`--no-edit` 只表示沿用原说明，不表示修改旧对象。Git 使用当前 index 生成新 tree，再创建一个新 commit。旧 OID 仍由恢复分支指向，新 OID 成为当前分支头。

如果补充内容是另一个需求，不要为了“一条提交看起来整齐”而 amend。直接创建下一条提交，意图边界比提交数量更重要。

## 已经推送，又要补代码并保持一条提交

这只适合明确允许改写的个人评审分支。主线、发布分支和多人共同开发分支默认不走这条路。

先获取远端事实并保存预期旧值：

```bash
branch_name="feature/search"
remote_ref="refs/heads/$branch_name"

git fetch origin
expected_remote="$(git rev-parse "refs/remotes/origin/$branch_name")"
server_remote="$(
  git ls-remote --exit-code --heads origin "$remote_ref" |
    awk 'NR == 1 {print $1}'
)"
test -n "$server_remote"
test "$server_remote" = "$expected_remote"
git branch recovery/remote-before-amend "$expected_remote"
```

再暂存、改写和验证：

```bash
git add -- src/search.java tests/search_test.java
git diff --staged --check
git diff --staged
git commit --amend --no-edit
git show --stat --format=fuller HEAD
git status --short
```

最后把远端从刚才确认的旧 OID 条件更新到新提交：

```bash
git push \
  --force-with-lease="$remote_ref:$expected_remote" \
  origin "HEAD:$remote_ref"
```

如果租约被拒绝，说明远端不再位于 `expected_remote`。停止推送，重新获取远端提交并确认是谁的工作、是否要保留。不要改成 `--force`，否则会把并发保护一并去掉。

## 修改提交说明

### 最新提交尚未共享

```bash
git branch recovery/before-message-amend HEAD
git commit --amend -m "fix: handle empty matcher id"
git show --no-patch --format=fuller HEAD
```

即使 tree 完全相同，说明变化也会生成新 OID，因为提交说明是 commit 对象内容的一部分。

### 更早的提交尚未共享

先确定要重建的范围，再进入交互式 rebase：

```bash
git log --oneline --decorate -10
git branch recovery/before-reword HEAD
git rebase -i HEAD~4
```

在 todo 中把目标行的 `pick` 改为 `reword`。Git 从最早被修改的提交开始重建，目标提交之后的提交也会因为父 OID 变化而获得新 OID。完成后比较：

```bash
git range-diff recovery/before-reword~4..recovery/before-reword HEAD~4..HEAD
git diff 'recovery/before-reword^{tree}' 'HEAD^{tree}'
```

### 提交已经共享

个人评审分支只有在协作者和平台规则允许时，才能 reword 后走显式租约流程。共享主线通常不为文字美化重写历史。提交说明造成真实审计歧义时，追加一条说明清楚的修正提交，并在评审或事故记录中关联原 OID。

## 合并、拆分或删除未共享提交

交互式 rebase 的 todo 是一份重放计划：

| 动作 | 用途 | 结果 |
| --- | --- | --- |
| `reword` | 修改说明 | tree 可不变，commit OID 变化 |
| `edit` | 暂停后补内容或拆分 | 当前及后续提交重建 |
| `fixup` | 合入前一条并丢弃当前说明 | 两条意图合为一条 |
| `squash` | 合入前一条并整理两条说明 | 两条意图合为一条 |
| `drop` | 不再重放该提交 | 该提交独有的变化离开新历史 |

### 把几条临时提交合成一条

```bash
git branch recovery/before-squash HEAD
git rebase -i HEAD~4
```

保留第一行为 `pick`，把要并入它的后续行改成 `fixup` 或 `squash`。不要把互不相关的需求仅为减少数量而合并。

### 把一条混合提交拆开

在 todo 中把目标行改为 `edit`。rebase 暂停后：

```bash
git reset HEAD^
git add -p
git commit -m "feat: add matcher validation"
git add -p
git commit -m "test: cover missing matcher id"
git rebase --continue
```

`git reset HEAD^` 在这里移动当前临时分支头并保留工作区内容。执行前必须确认 rebase 正停在预期提交，工作区没有其他任务修改。

### 删除一条未共享提交

对中间提交使用 `drop`。删除 todo 行通常也等价于不重放，但显式写 `drop` 更容易审查。操作后验证最终 tree，避免把目标提交中仍需要的内容一起丢掉。

## “删除远端的一条提交”实际是什么意思

Git 不能进入远端 commit 对象里按删除键。通常所谓“删除远端提交”有两种完全不同的目标：

1. 保留历史，但撤销这条提交带来的变化。
2. 改写远端分支，使该提交不再位于分支可达历史中。

第一种用于共享历史：

```bash
git fetch origin
git switch main
git pull --ff-only
git revert <bad-commit-oid>
git push origin main
```

原提交仍存在，revert 新增反向变化，别人已有的历史坐标不失效。

第二种只能用于明确允许改写的分支。删除最新一条远端提交时，先保存本地与远端 OID，并确认工作区干净：

```bash
git status --short
git fetch origin
expected_remote="$(git rev-parse origin/feature/search)"
server_remote="$(
  git ls-remote --exit-code --heads origin refs/heads/feature/search |
    awk 'NR == 1 {print $1}'
)"
test -n "$server_remote"
test "$server_remote" = "$expected_remote"
test "$(git rev-parse HEAD)" = "$expected_remote"
git branch recovery/before-drop "$expected_remote"
git reset --hard HEAD^
git push \
  --force-with-lease=refs/heads/feature/search:"$expected_remote" \
  origin HEAD:refs/heads/feature/search
```

删除中间提交则使用 `git rebase -i <bad-commit-oid>^`，把目标行改成 `drop`，验证后再用同样的显式租约。上面的远端查询没有返回分支、两次 OID 不一致或本地 HEAD 不在远端旧位置时，都必须停止并重新判断提交图。`reset --hard` 会覆盖已跟踪工作区和 index，只有在两者干净且恢复引用已建立时才能采用。

远端引用改写后，旧对象仍可能存在于 reflog、其他 clone、标签、评审引用、CI、bundle、制品或服务端保留区。它不是清除秘密的可靠方法。凭据误提交时先撤销和轮换凭据，再进入安全篇的历史清理流程。

## 其他高频现场怎样选入口

| 现场 | 先做什么 | 后续入口 |
| --- | --- | --- |
| 提交到了错误分支 | 给错误提交建立恢复分支，切到正确基线后 cherry-pick | 错误分支未共享可 reset，已共享则 revert |
| 一次提交混入两个需求 | 建恢复分支，交互式 rebase 中 `edit`，再 `reset HEAD^` 和 `add -p` | 分成可独立审查的提交 |
| 多个 `fix typo` 临时提交 | 核对是否同一意图，再用 fixup/squash | 用 range-diff 和最终 tree 验证 |
| 作者或邮箱错误 | 先判断身份事实与共享范围 | 最新私有提交 amend，更早私有提交 rebase，公开历史按治理处理 |
| 在 detached HEAD 完成了提交 | 立即用 `git branch recovery/detached-work HEAD` 命名 | 再切到目标分支 merge 或 cherry-pick |
| 远端分支改名或删除 | 用 `git ls-remote` 区分远端事实与本地缓存 | 进入远程引用漂移章节 |
| 强推租约被拒绝 | 保存当前远端 OID，不升级为无条件 force | 获取、协调、重建或放弃改写 |
| 提交中含有凭据 | 先撤销凭据和限制影响 | 历史清理不能替代凭据失效 |

## 完成一次改写后的验收

至少检查：

```bash
git status --short --branch
git log --graph --decorate --oneline --all --max-count=30
git show --stat --format=fuller HEAD
git diff 'recovery/before-rewrite^{tree}' 'HEAD^{tree}'
git reflog --date=iso -20
```

根据实际任务替换恢复分支名。还要运行项目测试，并核对评审、CI、标签、制品和部署是否仍指向有效 OID。Git 只能证明对象和引用变化，不能替你证明业务行为正确。

## 小结

提交一旦创建就不可原地修改。未共享历史可以在保存恢复入口后用 amend 或交互式 rebase 重建；允许改写的个人远程分支还需要显式租约；共享主线优先追加修正或 revert。所谓删除远端提交，本质是撤销变化或重写引用，必须先说清是哪一个目标。
