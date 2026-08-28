# 快进、分叉与合并提交：把历史形状讲清楚

快进合并只移动一个引用。两条工作线都向前提交后，目标分支无法直接指向对方，Git 需要创建一个有多个父提交的合并提交，或者按照团队策略拒绝、压平或改写这段历史。

## 进入条件与完成标准

准备一个工作区干净、至少有一条基线提交的练习仓库。所有命令在仓库根目录执行。先确认：

~~~bash
git status --short --branch
git rev-parse --verify HEAD^{commit}
~~~

读完本章后，你应能：

- 从共同祖先画出分叉历史；
- 用 merge-base 和祖先判断解释为什么不能快进；
- 证明合并提交的父顺序和最终 tree；
- 对比默认 merge、ff-only、no-ff 和 squash 的后果；
- 处理合并前置条件、冲突、no-commit 和 hook 失败；
- 把历史形状与评审、发布和回退决策分开。

## 制造真正的分叉

从 main 创建功能分支：

~~~bash
git switch main
git switch --create feature/navigation
printf '# Navigation\n' > NAVIGATION.md
git add -- NAVIGATION.md
git commit -m "docs: add navigation guide"
feature_tip="$(git rev-parse HEAD)"
~~~

再让 main 独立前进：

~~~bash
git switch main
printf '\nVersion notes live here.\n' >> README.md
git add -- README.md
git commit -m "docs: add version note"
main_tip="$(git rev-parse HEAD)"
base="$(git merge-base main feature/navigation)"
~~~

现在图形大致是：

~~~text
             N  feature/navigation
            /
... <- C <- B
            \
             V  main
~~~

base 应等于 C，main 和 feature/navigation 都包含 base，但两端不是彼此的祖先：

~~~bash
git merge-base --is-ancestor feature/navigation main
printf 'feature-in-main exit=%s\n' "$?"
git merge-base --is-ancestor main feature/navigation
printf 'main-in-feature exit=%s\n' "$?"
~~~

两个结果都应为 1。此时在 main 上执行 ff-only 会拒绝，保留两端引用和工作区：

~~~bash
if git merge --ff-only feature/navigation; then
  printf '%s\n' 'Expected ff-only to reject divergent histories.' >&2
  exit 1
fi
test "$(git rev-parse main)" = "$main_tip"
test "$(git rev-parse feature/navigation)" = "$feature_tip"
~~~

拒绝的价值在于它没有替你决定要创建哪种历史。先保存 OID，再选择流程。

## 创建合并提交

在 main 上执行普通合并：

~~~bash
git merge --no-edit feature/navigation
merge_tip="$(git rev-parse HEAD)"
git rev-list --parents -n 1 "$merge_tip"
git show --no-patch --format='%H%n%P%n%T%n%s' "$merge_tip"
~~~

merge_tip 应有两个父提交，第一父通常是合并前的 main_tip，第二父是 feature_tip。最终 tree 同时含有 README.md 和 NAVIGATION.md。

确认父顺序：

~~~bash
parents="$(git show -s --format=%P "$merge_tip")"
test "$(printf '%s\n' "$parents" | wc -w | tr -d ' ')" = 2
test "$(printf '%s\n' "$parents" | awk '{print $1}')" = "$main_tip"
test "$(printf '%s\n' "$parents" | awk '{print $2}')" = "$feature_tip"
~~~

命令输出中的 Merge: 或图形装饰不是权威证据，完整 parent 列表才是。真实合并后还要运行测试、构建和变更审查。

## 选择合并策略

| 策略 | 历史结果 | 适合回答的问题 | 代价 |
| --- | --- | --- | --- |
| 默认 merge | 可快进时移动，分叉时通常创建 merge commit | 是否保留真实集成节点 | 历史图可能更复杂 |
| ff-only | 分叉时拒绝 | 团队是否要求主线线性 | 需要先 rebase 或其他同步 |
| no-ff | 即使可快进也创建 merge commit | 是否保留功能分支边界 | 增加节点，回退需理解父关系 |
| squash | 把变化压成当前分支的一次新提交，不记录完整 merge parent | 是否只需要一条主线提交 | 原分支提交不以父关系进入主线，后续同步语义不同 |

squash 不是普通 merge 的“更干净显示”。它生成的提交通常只有当前 HEAD 作为父提交，功能分支的提交图不会被主线引用直接包含。使用时应保留候选分支 OID 和评审证据，不能只留下一个无法追溯来源的标题。

## no-commit 和 fast-forward

若需要在写入合并提交前检查 index：

~~~bash
git merge --no-ff --no-commit feature/navigation
git status --short --branch
git diff --staged --check
git diff --staged
git commit -m "merge: integrate navigation guide"
~~~

对于可快进的情况，单独使用 no-commit 不会停下，因为 Git 没有创建 commit。需要保留检查点时必须同时使用 no-ff。若 merge 已停止在冲突状态，先解决所有 unmerged stages，再继续；不要直接提交半完成的 index。

## 合并提交的差异视角

合并提交有多个父节点。普通 show 可能使用 combined diff，只显示对多个父节点都有独特意义的变化。分别查看每个父：

~~~bash
git show -m --format=fuller "$merge_tip"
git diff "$merge_tip^1" "$merge_tip"
git diff "$merge_tip^2" "$merge_tip"
~~~

第一父视角常用于主线发布，第二父视角用于查看被合入分支相对结果。两者都不是“合并引入的唯一补丁”，因为共同祖先和双方各自已有修改也会影响结果。

## 合并失败时状态怎么保留

非快进 merge 可能写入 MERGE_HEAD 并改变 index、工作区。发生冲突后先保存：

~~~bash
git status --short --branch
git rev-parse HEAD
git rev-parse MERGE_HEAD
git ls-files --unmerged
git diff --name-status --diff-filter=U
~~~

正确的选择只有两类：

- 继续：根据共同祖先、两侧提交和业务约束形成最终文件，逐路径 add 或 rm，检查没有 unmerged stages，再 continue 或 commit；
- 中止：确认不应继续时执行 merge --abort，回到合并前状态并核对 HEAD。

不要在进行中的 merge 上执行 reset --hard，也不要删除 MERGE_HEAD 伪造“已完成”。复杂冲突的 index stage 与 rerere 在后续章节展开。

## 与团队流程的关系

历史形状是 Git 数据面事实，平台控制面另有状态：

- 有 merge commit 不等于评审通过；
- squash 后只有一个主线 commit 不等于构建输入不可追溯；
- ff-only 通过不等于远程没有并发更新；
- 合并成功不等于部署实例已经运行同一 OID；
- 删除功能分支不等于删除平台评审、CI 或制品记录。

团队规则应同时记录候选 OID、评审事件、CI 运行、发布制品和部署结果。Git 只能证明提交图和 tree 的一部分。

## 失败路径和恢复

| 现象 | 先收集 | 恢复 |
| --- | --- | --- |
| ff-only 被拒绝 | 两端 OID、merge-base、工作区状态 | 选择 rebase、merge 或保留分叉，不强推 |
| Already up to date | 当前与目标 OID、祖先关系 | 记录目标已包含，不创建空 merge |
| no-commit 后看不到暂停 | 是否可快进、是否使用 no-ff | 说明快进已完成，按 OID 核对，不执行 abort |
| 合并提交父顺序不符预期 | rev-list --parents、当前分支 | 先保留提交，再按团队策略评估修正 |
| hook 拒绝合并提交 | hook stderr、HEAD、index stages | 修复门禁后继续，保留失败证据 |
| 合并结果错误 | merge tip、父提交、最终 tree、测试 | 共享历史追加 revert，私有历史再评估改写 |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-3-conflicts.sh
~~~

该实验先制造无文本重叠的分叉并验证合并提交拥有两个父提交，再制造内容冲突、执行 abort、形成解决提交并创建附注标签。它验证本地提交图和 index 状态，不模拟平台评审、保护分支、合并队列、CI 或发布控制面。

## 小结

分叉历史要求先找到共同祖先，再决定快进、合并提交、squash 或拒绝。合并提交的父顺序、最终 tree 和 index 状态是可复核事实；输出文字和图形只是辅助。历史形状确定后，业务测试和外部平台证据仍然必须单独完成。
