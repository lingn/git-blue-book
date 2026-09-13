# 快进与合并提交：引用移动和新对象是两种历史结果

合并不总会创建新 commit。当前提交是目标提交的祖先时，Git 可以只把当前分支 ref 向前移动，这叫快进。两端已经分叉时，普通 merge 通常需要创建带两个父提交的新对象；团队也可以用 `--ff-only` 拒绝，或在可快进时用 `--no-ff` 强制保留集成节点。

快进、合并提交、squash 与 rebase merge 会留下不同父关系、签名和恢复入口。本章只处理本地 merge 形状；托管平台三种整合方式的评审和证据后果由第六篇负责。

## 进入条件与完成标准

所有合并写操作只在一次性仓库执行。真实项目先固定：

~~~bash
git status --short --branch
receiver_ref="$(git symbolic-ref --quiet HEAD)"
receiver_oid="$(git rev-parse 'HEAD^{commit}')"
incoming_oid="$(git rev-parse 'refs/heads/topic^{commit}')"
git rev-list --left-right --count "$receiver_oid...$incoming_oid"
git merge-base --is-ancestor "$receiver_oid" "$incoming_oid"
~~~

最后一条退出 0 表示存在从 receiver 到 incoming 的快进路径，退出 1 表示不成立，其他非零是查询错误。

读完本章后，应能区分 Already up to date、快进、分叉合并和强制非快进节点，解释 `--no-commit` 为什么挡不住普通快进，验证二父顺序和最终 tree，并为错误合并选择 abort、revert 或未共享历史恢复。

## 三种祖先关系决定默认入口

给定当前 C 和目标 T：

| 关系 | 默认 `git merge T` 常见结果 | 核验 |
| --- | --- | --- |
| C 与 T 相同，或 T 是 C 的祖先 | Already up to date，不移动 ref | `is-ancestor T C` 为 0 |
| C 是 T 的祖先 | 快进，把当前 ref 移到 T | `is-ancestor C T` 为 0 |
| 彼此都不是祖先，有共同历史 | 三方合并，成功时创建 merge commit | 左右独有数均大于 0 |
| 没有可见共同祖先 | 默认拒绝无关历史 | `merge-base` 无结果，排除 shallow 缺口 |

配置、显式选项、标签和策略选择会改变默认行为，因此生产流程应写明允许的形状，不依赖某台机器的 `merge.ff` 或别名。

## 快进只移动当前引用

开始时：

~~~text
A <- B <- C  main
          \
           D <- E  topic
~~~

若 C 是 E 的祖先，在 main 上执行：

~~~bash
old_main="$(git rev-parse refs/heads/main)"
topic_tip="$(git rev-parse refs/heads/topic)"
git merge --ff-only topic
new_main="$(git rev-parse refs/heads/main)"
~~~

`new_main` 等于 `topic_tip`，topic ref 不移动，没有额外 commit。E 原本的父列表、tree、作者和签名保持不变。Index 与工作区更新为新尖端内容。

验收：

~~~bash
test "$new_main" = "$topic_tip"
git rev-list --parents --max-count=1 "$new_main"
git rev-parse --verify MERGE_HEAD
~~~

最后一条在完成的普通快进后应失败，因为没有进行中的 merge 状态。终端出现 `Fast-forward` 只是展示；OID、父列表和状态文件才是结构证据。

快进保留功能 commit，却没有新对象标记“何时被 main 接纳”。平台评审事件、接收日志和发布记录需要独立保留。

## `--no-commit` 不会暂停快进

~~~bash
git merge --no-commit topic
~~~

如果可以普通快进，Git 直接移动 ref，因为没有 merge commit 可供“暂不提交”。命令成功后不能运行 `merge --abort`，也不能假设 index 停在待审状态。

想在可快进场景强制产生提交前检查点，需要：

~~~bash
git merge --no-ff --no-commit topic
git rev-parse HEAD
git rev-parse MERGE_HEAD
git diff --staged --check
~~~

`--no-ff` 要求合并提交，`--no-commit` 才能在写该对象前停住。当前 `HEAD` 仍是旧 receiver，index/工作区是候选结果。验证后 `git commit`，放弃则 `git merge --abort`。

团队若只是要求 CI 在 ref 移动前验证候选，应在独立候选 ref/工作树或合并队列中构造并检查，而不是在开发者主线工作区暂停合并。

## `--ff-only` 把分叉变成拒绝

两端独立前进：

~~~text
      L  topic
     /
B <-
     \
      R  main
~~~

在 main 上执行：

~~~bash
before_main="$(git rev-parse main)"
before_tree="$(git write-tree)"

if git merge --ff-only topic 2>ff-only.err; then
  printf 'unexpected fast-forward\n' >&2
  exit 1
fi

test "$(git rev-parse main)" = "$before_main"
test "$(git write-tree)" = "$before_tree"
~~~

拒绝表示当前历史不满足线性更新前置条件，不表示哪一侧代码正确。可选动作是合并、在未共享功能历史上 rebase、重建候选，或保留分叉；不能强推目标分支伪造快进。

`pull --ff-only` 也会在本地分支不能快进到取得的远程跟踪尖端时拒绝。Fetch 部分已经可能写入对象与远程跟踪 refs，不能把 pull 失败称为完全无状态变化。

## 分叉合并创建新 commit

两侧变更可自动组合时：

~~~bash
main_before="$(git rev-parse main)"
topic_tip="$(git rev-parse topic)"
git merge --no-edit topic
merge_oid="$(git rev-parse HEAD)"
git show --no-patch --format='%H%n%P%n%T%n%s' "$merge_oid"
~~~

典型二父结果：

~~~text
      L -----\
     /        M  main
B <-         /
     \-- R --
~~~

M 的第一父是 `main_before`，第二父是 `topic_tip`。Topic ref 仍指向原尖端。确认：

~~~bash
parents="$(git show -s --format=%P "$merge_oid")"
test "$(printf '%s\n' "$parents" | awk '{print $1}')" = "$main_before"
test "$(printf '%s\n' "$parents" | awk '{print $2}')" = "$topic_tip"
git merge-base --is-ancestor "$topic_tip" "$merge_oid"
~~~

最终 tree 由策略与冲突解决产生，可能不同于两个父。分别审查：

~~~bash
git diff "$merge_oid^1" "$merge_oid"
git diff "$merge_oid^2" "$merge_oid"
git show -m --format=fuller "$merge_oid"
~~~

Combined diff 是另一种投影视图，不自动等于“此次合并带来的全部变化”。审计保留父 OID、base、结果 tree 和两父比较。

## `--no-ff` 在可快进时保留集成节点

即使 main 是 topic 的祖先：

~~~bash
git merge --no-ff --no-edit topic
~~~

也会创建二父 commit。第一父是旧 main，第二父是 topic tip，结果 tree 常与 topic tree 相同。这个节点可以作为一次集成边界，但 Git 对象本身不保存平台评审、审批者、CI 或发布状态。

代价包括：主线增加 merge 节点，`first-parent` 与完整历史呈现不同，revert 需要选择 mainline，bisect 可能先命中合并结果。团队应根据归因、签名、回滚和候选绑定选择，不用“整洁”这种无法验收的形容词决定。

## Squash 不是合并提交

~~~bash
git merge --squash topic
git diff --staged --check
git commit -m "feat: integrate topic"
~~~

Squash 把 topic 相对基线的最终变化准备到 index，再由普通 commit 以当前 main 为单一父提交。通常不会写 `MERGE_HEAD`，原 topic tip 也不会成为 squash commit 的祖先。

Tree 可以与某次普通 merge 结果相同，拓扑却不同。删除 topic 前保存评审候选、原始 OID、最终 squash OID 和映射。更完整的 merge/squash/rebase merge 工程后果见[共享历史合并策略](../part-06/03-merge-strategies-and-history.md)。

## 多父合并需要更明确的约束

`git merge A B C` 可能使用 octopus 等策略创建三个以上父的 commit，适合能自动合并的多个独立头。发生复杂冲突时通常拒绝。父顺序、回滚 mainline、评审范围和故障归因都更难解释。

不要用八爪鱼合并减少“合并提交数量”。只有多个输入已分别验证、组合结果也有独立候选和测试、组织明确接受多父语义时才采用。一般功能评审使用一项变化对应一个可追踪整合决策。

## 配置不能隐藏在个人环境里

影响形状的常见配置包括：

~~~bash
git config --show-origin --get merge.ff
git config --show-origin --get pull.ff
git config --show-origin --get branch.main.mergeOptions
~~~

未设置时命令返回 1，Git 使用内置或其他层规则。个人 `merge.ff=false` 可能让同一命令在另一台机器产生不同历史；别名也可能附加参数。受保护主线应由服务端/平台合并方式和接收规则约束，本地配置只作为开发体验。

脚本显式传 `--ff-only`、`--ff` 或 `--no-ff`，并记录 Git 版本与实际命令。仍需处理标签、特殊策略和版本差异，不把一个选项当成跨平台政策证明。

## 完成、中止和已共享恢复是三个时点

| 时点 | 可用动作 | 边界 |
| --- | --- | --- |
| Merge 进行中，有 `MERGE_HEAD` | `merge --continue` 或 `merge --abort` | 先保护合并前本地修改和 unmerged stages |
| Merge commit 已创建但未共享 | 建 recovery ref 后评估 reset/rebase/revert | 不能因“本地”忽略签名、CI 与依赖分支 |
| Merge commit 已推送或发布 | 通常追加 revert/修复 | 不重写协作者已用坐标，运行状态另行回退 |
| 快进已完成 | 没有 merge 状态可 abort | 从 reflog/旧 OID 恢复引用，先确认共享边界 |

`git revert -m 1 <merge>` 选择第一父作为主线计算反向变化，不删除原合并，也不保证以后重新 merge 会恢复同样改动。必须在临时分支验证父选择、冲突和业务结果。数据库、制品和部署回退不由 Git revert 自动完成。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| Already up to date 与预期不符 | 两端完整 OID、祖先关系、ref 新鲜度 | 修正输入或 fetch，不造空 merge |
| `--ff-only` 被拒绝 | 左右独有数、base、目标政策 | 选择批准的整合方式，不强推目标 |
| `--no-commit` 后没有 `MERGE_HEAD` | 是否发生快进、是否使用 `--no-ff` | 按新 OID 验收；需要恢复则查 reflog，不执行 abort |
| Merge commit 父顺序异常 | 当前分支、参数顺序和 `%P` | 阻止发布，按共享边界重建或追加修复 |
| 自动合并通过但测试失败 | base、两父 diff、结果 tree 和测试 | 未提交时 abort；已共享时走恢复流程 |
| Hook 拒绝 merge commit | hook 来源、stderr、index 和状态文件 | 修复门禁或候选，保留现场后 continue/abort |
| Squash 后祖先查询失败 | 原/最终 OID、tree、patch 和平台映射 | 按 squash 语义调查，不误报“未合入” |

任何恢复前固定 merge 前后 refs、reflog、父列表和工作区证据。删除功能分支、运行 GC 或强制更新只会缩短调查窗口。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-merge-shapes.sh
~~~

实验验证普通快进只移动 ref、没有 `MERGE_HEAD`，并证明单独 `--no-commit` 不暂停快进。它在另一条可快进历史上用 `--no-ff --no-commit` 停住、验证二父候选后 abort。

分叉场景先断言 `--ff-only` 拒绝且 ref/index/工作区不变，再自动组合两侧不同路径，验证进行中状态、abort 恢复、最终 merge commit 父顺序和 tree。脚本还制造内容冲突并检查 stage 1/2/3。它不模拟 squash/rebase merge 的平台映射、多父合并、hooks、签名或业务测试。

## 小结

快进只移动当前引用，分叉 merge 创建多父 commit，`--no-ff` 可以在可快进时保留集成节点，`--ff-only` 则拒绝分叉。`--no-commit` 只影响需要创建 merge commit 的路径。每种形状都用 old/new OID、父列表、结果 tree 和状态文件验收，外部评审与发布证据另行绑定。

## 资料

- [git-merge](https://git-scm.com/docs/git-merge)
- [git-merge-base](https://git-scm.com/docs/git-merge-base)
- [git-rev-list](https://git-scm.com/docs/git-rev-list)
- [git-show](https://git-scm.com/docs/git-show)
- [git-revert](https://git-scm.com/docs/git-revert)
