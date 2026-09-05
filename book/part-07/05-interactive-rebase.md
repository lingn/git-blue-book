# 交互式 rebase：重建一段尚未共享的历史

本章是 v2 第七篇的历史重建章节。它负责 todo 计划、提交拆分、冲突、中止和重建后的验证；共享分支的改写许可与远端租约仍要结合第六篇和后续恢复章节判断。

普通 rebase 更换一段提交的起点，交互式 rebase 还允许修改重放计划。它可以改提交说明、调整顺序、合并、删除、暂停修改或拆分提交。所有被重建的提交及其后续提交都会获得新对象 ID。

本章只处理尚未分享、由当前操作者独占的本地历史。已经推送、被评审引用或被其他分支依赖的提交，先按公开历史章节判断是否允许改写。

## 操作前固定范围和原始分支头

假设最新三条提交需要整理。执行位置是当前功能分支的本地工作区，开始前确认没有正在进行的 merge、rebase、cherry-pick 或 revert：

```bash
git status --short --branch
git branch --show-current
git log --graph --decorate --oneline --all --max-count=20
```

交互式 rebase 会反复更新 index 和工作区。工作区不干净时默认拒绝开始。`--autostash` 可以临时收起修改，但 rebase 成功后重新应用 stash 仍可能冲突，事故恢复也多一层状态；高风险整理先明确处理当前修改，不把 autostash 当作默认方案。

记录范围基点和原分支头：

```bash
rewrite_base="$(git rev-parse HEAD~3)"
original_tip="$(git rev-parse HEAD)"
git branch recovery/before-interactive-rebase "$original_tip"
printf 'base=%s\ntip=%s\n' "$rewrite_base" "$original_tip"
```

`HEAD~3` 表示沿第一父关系向前走三次，只适用于确认要重建最近三条线性提交的场景。范围中含合并提交时，默认 rebase 会把历史线性化并省略原合并提交。先检查：

```bash
git rev-list --merges "$rewrite_base"..HEAD
```

没有合并提交时命令不输出。存在输出时，不要继续套用本章的线性计划；保留合并拓扑需要评估 `--rebase-merges`、原冲突解决和团队历史约定。

## todo 列表按旧到新执行

打开最近三条提交的计划：

```bash
git rebase -i "$rewrite_base"
```

编辑器中的提交按从旧到新排列，与默认 `git log` 的新到旧顺序相反：

```text
pick a1b2c3d feat: add parser
pick d4e5f6a fix: correct parser typo
pick 7a8b9c0 test: cover parser
```

Git 先把当前分支重置到 `rewrite_base`，再从第一行开始重放。每一行依赖前面已经生成的历史，因此调整顺序可能让后续提交失去依赖、产生冲突或使中间提交无法构建。

todo 中的对象 ID 用来识别原提交。保存计划后，Git 会创建新提交，不能把 todo 里的短 ID 当作最终历史坐标。

## 常用动作改变什么

| 动作 | 行为 | 对提交说明的处理 | 主要风险 |
| --- | --- | --- | --- |
| `pick` | 重放提交 | 保留原说明 | 父提交变化时 ID 仍会变化 |
| `reword` | 重放后打开编辑器 | 修改当前说明 | 后续提交 ID 连锁变化 |
| `edit` | 重放后暂停 | 保留，可随后 amend | 暂停期间混入无关内容 |
| `squash` | 合入前一条提交 | 编辑合并后的说明 | 两条意图被错误混合 |
| `fixup` | 合入前一条提交 | 默认丢弃当前说明 | 有价值的因果说明丢失 |
| `drop` | 不重放该提交 | 删除 | 独有文件变化消失 |
| `exec` | 在当前位置执行命令 | 不直接改变 | 命令副作用污染历史 |

移动整行会重排提交。删除提交行通常等同于 `drop`，不是“这条不需要编辑”。编辑器底部的帮助文字会列出当前 Git 版本支持的动作，脚本不要依赖固定行号修改 todo。

### 改提交说明

把需要修改的行从 `pick` 改成 `reword`：

```text
reword a1b2c3d feat: add parser
pick   d4e5f6a fix: correct parser typo
pick   7a8b9c0 test: cover parser
```

保存后 Git 在重放该提交时打开提交说明编辑器。文件 tree 可以不变，但 commit 内容改变；第一条新提交的 ID 变化后，后面两条即使仍是 `pick`，父提交也不同，因此 ID 一起变化。

### 合并连续提交

修正提交只服务于前一条功能提交时，可以使用：

```text
pick  a1b2c3d feat: add parser
fixup d4e5f6a fix: correct parser typo
pick  7a8b9c0 test: cover parser
```

`fixup` 合入前一条，默认保留前一条说明。`squash` 会打开编辑器整理两条说明。目标行必须位于要合入的提交之后；todo 第一行不能 squash 或 fixup 到不存在的前一条。

## edit 可以修改或拆分提交

把一行标记为 `edit` 后，Git 重放该提交并暂停。查看当前状态和正在处理的原补丁：

```bash
git status
git rebase --show-current-patch
```

只需补充内容时，修改文件、暂存并 amend：

```bash
git add -- path/to/modified-file
git commit --amend
git rebase --continue
```

需要把当前提交拆成多条时，先确认 `HEAD` 正是暂停的那条新提交，再执行 mixed reset：

```bash
git reset HEAD^
```

这会移除刚重放的 commit，把它的 tree 变化保留在工作区并重置 index。随后按意图分别暂存和提交：

```bash
git add -- src/parser.ext
git commit -m "feat: add parser"

git add -- tests/parser-test.ext
git commit -m "test: cover parser"

git rebase --continue
```

示例路径必须替换为仓库中的真实路径。每次提交前检查 `git diff` 和 `git diff --staged`，防止把暂停前就存在的无关文件带入历史。若拆分后遗漏原提交的一部分，最终 tree 比较会暴露差异。

## 冲突时先确认正在重放哪条提交

普通 rebase 章节已经解释逐条重放。交互式计划在 reword、squash、重排或 edit 后同样可能冲突。先收集：

```bash
git status
git rebase --show-current-patch
git diff
```

使用默认 merge 后端时，冲突提示中的 ours 是已经重建的历史及新基线，theirs 是当前正在重放的原提交变化，和普通合并时的直觉可能相反。不要只按 ours/theirs 名称选择整边内容，应根据基线和当前补丁意图编辑最终文件。

解决并暂存所有冲突后继续：

```bash
git add -- path/to/resolved-file
git rebase --continue
```

后续提交可能再次在同一路径冲突，因为每条原提交都要独立重放。`git rebase --skip` 会丢弃当前整条补丁，只有确认其变化已经在新历史中或确实应删除时才使用。

## abort、quit 和 edit-todo 的差异

计划选错、冲突不可控或验证目标不成立时：

```bash
git rebase --abort
```

`--abort` 尝试把 `HEAD`、index 和工作区恢复到本次 rebase 开始前，并重新检出原分支。中止后仍要核对 `original_tip` 和恢复分支。

`git rebase --quit` 只结束 rebase 状态，保留当前 `HEAD`、index 和工作区，不恢复原分支；使用 autostash 时，临时 stash 会保留在 stash 列表。它适合明确要接管当前现场的高级操作，不是 abort 的同义词。

rebase 暂停期间需要修改剩余计划，可以运行：

```bash
git rebase --edit-todo
```

它只编辑尚未执行的 todo，不撤销已经生成的提交。

## 空提交和重复补丁需要明确决定

提交的变化若已经存在于新基线，rebase 可能识别为 clean cherry-pick 并跳过；某条非空提交也可能在重放后变为空。Git 2.49.0 的交互模式对后者默认停下询问，可通过 `--empty=drop|keep|stop` 明确策略。

空提交不一定是垃圾，它可能承担发布标记、流水线触发或审计语义。删除前要确认仓库和外部系统是否依赖提交本身，而不只检查文件 tree。

## exec 逐条验证重建后的提交

`--exec` 在每个重放结果上执行一条 shell 命令：

```bash
git rebase -i "$rewrite_base" --exec './scripts/test.sh'
```

测试脚本必须来自当前仓库并能在每个中间提交上运行。命令返回非零状态时 rebase 暂停，检查失败原因后使用 `--continue` 或 `--abort`。不要用会发布制品、写远程数据库或修改外部服务的命令作为 exec；rebase 可能重复执行它。

对于大型仓库，逐条构建每个提交可能成本很高。可以用快速静态检查逐条验证，完成后再对最终分支运行完整测试，但要在评审说明中记录实际覆盖范围。

## 验证提交序列和最终 tree

完成后先保存新分支头：

```bash
rewritten_tip="$(git rev-parse HEAD)"
git status --short --branch
git log --graph --decorate --oneline --all --max-count=30
```

比较原序列与新序列：

```bash
git range-diff \
  "$rewrite_base".."$original_tip" \
  "$rewrite_base".."$rewritten_tip"
```

`range-diff` 尝试按补丁相似性对应两组提交，适合检查重排、reword、squash 和 fixup。它不是安全证明，复杂拆分或大幅修改可能无法一一对应。

若此次操作只整理历史表达，不应改变最终文件状态，执行严格 tree 检查：

```bash
git diff --exit-code "${original_tip}^{tree}" "${rewritten_tip}^{tree}"
```

成功时没有输出；有差异时返回非零状态并显示变化。若 edit 本来就要修正内容，差异应与任务范围一致。无论哪种情况，都要运行项目测试并检查未跟踪文件。

commit 签名不会自动迁移到新对象。需要签名历史时，按团队签名策略为新提交重新签名并验证；旧签名只能验证旧提交对象，不能证明新提交已经过同一审批。

## 包含根提交和整条作者改写

`HEAD~N` 要求范围前还有父提交。要包含根提交可以使用：

```bash
git rebase -i --root
```

它会重建根提交及所有后续提交，影响范围远大于修改最近几条。一个特殊场景是私有沙盒中整条历史作者配置错误，确认历史从未分享后，可以先建立恢复分支，再逐条 amend：

```bash
git branch recovery/before-author-rewrite
git rebase --root --exec 'git commit --amend --no-edit --reset-author'
```

author 是 commit 内容的一部分，根提交变化后，后续提交的父 ID 全部变化。完成后核对身份和最终 tree：

```bash
git log --format='%H %an <%ae> %s'
git diff --exit-code \
  'recovery/before-author-rewrite^{tree}' \
  'HEAD^{tree}'
```

这条流程不适用于已经发布、签名或被外部系统引用的历史。

## 隔离实验覆盖成功与中止

**前置条件**：Git 2.28 或更高版本、Bash、`mktemp`、`sed` 和本书工作区。在仓库根目录执行：

```bash
./scripts/verify-interactive-rebase.sh
```

脚本在临时仓库中自动生成 todo：reword 第一条、fixup 第二条，并在第三条暂停拆分；完成后验证最终 tree 与原分支一致。另一个临时仓库制造 rebase 冲突，验证 `--show-current-patch` 后执行 `--abort` 能恢复原分支头和干净工作区。

成功时输出：

```text
Interactive rebase rewrite, split, conflict, and abort passed.
```

脚本用环境变量指定临时编辑器，不修改用户的 Git 编辑器配置。对象 ID 和临时路径每次不同，任一断言失败时返回非零状态并删除实验目录。它只验证本地私有历史，不连接远程或模拟代码评审。

## 共享边界

reword 一条早期提交也会改变其全部后代。已经有同事依赖的功能分支、带发布标签的历史和平台已批准的提交不能未经协调重建。确需更新允许改写的远程评审分支时，先完成本地验证，再使用下一章定义的显式租约流程，并通知评审者旧提交 ID 已失效。
