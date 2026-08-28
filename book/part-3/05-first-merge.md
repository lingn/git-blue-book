# 第一次合并：先确定接收方，再判断能否快进

merge 的方向由当前分支决定。命令参数指定“要合入谁”，当前 HEAD 所在的分支才是“接收变化的一方”。这条规则如果没有先说清，最容易出现的错误就是站在功能分支上，误以为是在把功能合回主线。

## 进入条件与完成标准

准备如下练习状态：

~~~text
main ---------------- C
                       \
feature/quick-start ---- D
~~~

D 的父提交是 C，工作区干净，当前可以从 main 或 feature 分支切换。确认：

~~~bash
git status --short --branch
git rev-parse --verify main^{commit}
git rev-parse --verify feature/quick-start^{commit}
~~~

读完本章后，你应能：

- 解释 merge 参数与当前分支的方向；
- 用祖先关系判断快进条件；
- 观察快进合并只移动 ref、不创建新 commit；
- 使用 ff-only、no-ff 和 no-commit 表达历史策略；
- 处理合并前置条件失败和错误方向；
- 区分本地 Git 合并成功与代码、CI、评审和发布验证。

## 合并前先看两端和共同祖先

在接收变化的分支上执行：

~~~bash
git switch main
git status --short --branch
git merge-base main feature/quick-start
git merge-base --is-ancestor main feature/quick-start
~~~

最后一条退出码为 0，说明 main 是 feature/quick-start 的祖先，存在快进路径。若退出码为 1，两端已经分叉或顺序相反，不能直接把它当作快进；其他非零值表示输入或仓库错误。

当前分支必须干净的原因有两个：合并可能更新 index 和工作区，未提交内容可能被覆盖或让冲突现场难以恢复；其次，提交图证据不能和无关修改混在一起。

## 快进合并改变什么

执行：

~~~bash
old_main="$(git rev-parse main)"
feature_tip="$(git rev-parse feature/quick-start)"
git merge feature/quick-start
new_main="$(git rev-parse main)"
test "$new_main" = "$feature_tip"
test "$old_main" != "$new_main"
git rev-list --parents -n 1 main
~~~

Git 把 main 引用从 C 移动到 D，更新 index 和工作区以匹配 D，但没有创建新的 merge commit。最后一条仍应显示 D 和一个父提交 C。

快进输出通常含有 Fast-forward，但文本可能受语言和版本配置影响。可靠证据是合并前后的 ref OID、父列表和最终状态，不要只匹配一行终端提示。

功能分支的 ref 不会因为这次合并而移动：

~~~bash
git rev-parse feature/quick-start
~~~

main 和 feature/quick-start 此时指向同一提交。删除已合入功能分支是另一个操作，不能把它当成 merge 的隐含步骤。

## 三种历史策略

### 默认策略

~~~bash
git merge feature/quick-start
~~~

当当前分支是目标祖先时默认快进；已经分叉时通常创建合并提交。具体策略还会受配置和参数影响，生产流程应显式写清要求。

### 只允许快进

~~~bash
git merge --ff-only feature/quick-start
~~~

如果当前分支不是目标祖先，命令拒绝且不应移动当前 ref。它适合希望所有主线更新都保持线性的仓库。拒绝后先保存两端 OID，不能通过改名或强推伪造快进。

### 即使可快进也保留合并节点

~~~bash
git merge --no-ff feature/quick-start
~~~

no-ff 要求创建一个 merge commit，即使功能分支包含当前分支。它能保留一次明确的集成边界，也增加历史节点和后续回退复杂度。是否采用属于团队历史策略，不是 Git 正确性的单一答案。

no-commit 不能阻止快进，因为快进没有需要创建的 commit。若必须在可快进场景停下来检查合并结果，使用 no-ff 与 no-commit 的组合，然后在确认 index 和测试后手动提交。不要在不理解参数组合时假设 no-commit 一定留下 MERGE_HEAD。

## 合并的状态边界

快进成功后通常没有 MERGE_HEAD，也没有新的合并提交。非快进合并可能经历：

~~~text
准备 -> 自动合并或冲突 -> index 已解决 -> merge commit -> 完成
~~~

检查进行中状态：

~~~bash
git status
git rev-parse --verify MERGE_HEAD
~~~

在快进场景第二条会失败，这是预期边界。不能把“没有 MERGE_HEAD”解释成合并没有发生。

如果发生冲突，先保留现场，使用 status、diff、ls-files --unmerged 判断状态。merge --abort 只针对进行中的普通 merge，不能用来撤销已经完成的快进或已创建的合并提交。

## 合并成功后要验证什么

至少保存：

~~~bash
git rev-parse HEAD
git rev-parse main
git status --short --branch
git show --no-patch --format='%H%n%P%n%T%n%s' HEAD
git diff --exit-code <expected-tree> HEAD --
~~~

最后一条只有在你有明确 expected tree 或基线时才使用。真实项目还要运行测试、构建和文档检查。Git 的自动合并只说明提交图和文件快照可以组合，不说明业务、性能、数据库和部署结果正确。

## 合并失败和方向错误

| 现象 | 先收集 | 恢复 |
| --- | --- | --- |
| not something we can merge | 参数、refs、对象类型 | 改用已验证的 commit 或分支名 |
| Already up to date | 当前和目标 OID、祖先关系 | 证明目标历史已包含，不重复创建空 merge |
| ff-only 被拒绝 | 两端 OID、merge-base、图形 | 先同步或采用经批准的分叉策略 |
| 工作区有未提交变化 | status、diff、index | 提交、stash 或独立 worktree 后再 merge |
| 合并发生冲突 | MERGE_HEAD、unmerged stages、双方提交 | 按冲突章解决或 abort |
| 当前分支方向错了 | HEAD 分支名、merge 前 OID | 先 abort（若仍在进行），或恢复引用后重新站到接收方 |

命令参数没有“把结果合到自己身上”的自动语义。当前分支是决定写入哪个 ref 的关键上下文。

## 删除已合入分支

确认 main 已经可达功能提交后：

~~~bash
git branch --merged main
git branch -d feature/quick-start
git log --oneline --decorate --all
~~~

小写 -d 只删除分支引用，并在未合入时拒绝。删除后功能提交仍由 main 到达。强制 -D 会跳过检查，只有在备份和责任人确认后才考虑。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-3-basics.sh
~~~

实验验证站在 main 上合入功能分支会产生快进，合并前后 main 的 OID 变化与 feature tip 一致，最终工作区干净，删除已合入分支不会让提交消失。它不验证托管平台的合并请求、保护分支、CI 必需检查或真实代码质量。

## 小结

merge 的方向由当前分支决定。先核对两端 OID、共同祖先和工作区状态，再选择默认、ff-only 或 no-ff。快进只是移动引用，非快进才会创建合并提交；Git 报告成功后，还要用测试和运行证据确认结果。
