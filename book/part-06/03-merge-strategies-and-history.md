# Merge、squash 与 rebase merge 留下不同证据

托管平台上的几种“合并”都会让目标分支包含某项变化，但它们写入的 commit 对象和父关系不同。后续用 OID 查发布、用 `revert` 回滚、用 `bisect` 定位问题或用签名验证来源时，这些差异会直接影响可用证据。

## 进入条件与完成标准

本章假设已经理解快进、合并提交、rebase 和 cherry-pick。示例应在临时仓库或本书实验脚本中运行，不要在真实共享分支上试合并方式。

开始观察真实评审结果前，在开发者 clone 中记录：

~~~bash
git status --short --branch
git fetch origin
target="$(git rev-parse --verify origin/main^{commit})"
feature="$(git rev-parse --verify HEAD^{commit})"
base="$(git merge-base "$target" "$feature")"
printf 'target=%s\nfeature=%s\nbase=%s\n' "$target" "$feature" "$base"
~~~

fetch 会更新本地远程跟踪引用和对象库，输出中的 OID 随仓库状态变化。读完本章后，应能预测三种方式的最终父关系、OID、可达性、回滚入口和评审映射，并知道哪些结论必须从平台或发布系统补证。

## 先固定五个对象

比较合并方式前，至少保存目标基线 `T`、功能头 `F`、共同祖先 `B`、评审候选 `C` 和最终主线提交 `M`。`C` 可能等于 `F`，也可能是平台创建的临时合并提交；`M` 可能等于 `F`、等于 `C`，或是合并时新生成的对象。

只记录评审编号和分支名，过一段时间就无法回答以下问题：

- 检查验证的是功能头还是组合候选；
- 最终主线是否复用了被验证对象；
- 目标分支在合并前是否前进；
- squash 或 rebase 后，原提交怎样映射到新对象；
- 发布使用的是最终主线提交还是另一个标签目标。

## Fast-forward 复用功能头

目标提交是功能头的祖先时，fast-forward 可以直接把目标引用移动到 `F`。不会创建额外合并提交，功能分支上的 commit OID 保持不变。

~~~text
B---T---f1---F
        main -> F
~~~

它保留原提交签名和父关系，发布与评审可以直接引用 `F`。代价是主线图中没有一个单独对象标记“这组提交通过某次评审进入主线”。平台评审事件仍然需要保留，不能从线性 Git 图重建。

目标在审批后前进时，原来的 fast-forward 前提可能消失。此时要重新生成候选或明确选择其他合并方式，不能把旧绿色结果直接用于新基线。

## Merge commit 保存两条父链接

目标和功能分支已经分叉时，普通 merge 通常创建新 commit `M`：

~~~text
      f1---F
     /      \
B---T--------M
~~~

`M` 的第一父通常是执行合并时所在的目标分支，第二父是被合入的功能头。最终 tree 由合并策略和冲突解决共同决定，不保证等于任一父的 tree。

核对一个候选是否真是两父提交：

~~~bash
merge_commit="<完整 OID>"
git show --no-patch --format='%H%n%P%n%T%n%s' "$merge_commit"
git diff "$merge_commit^1" "$merge_commit"
git diff "$merge_commit^2" "$merge_commit"
~~~

命令在包含该对象的本地仓库中执行，只读。父不存在通常说明对象缺失、浅边界或输入并非 merge commit。不要把 `^1`、`^2` 的方向称为固定的 ours/theirs；冲突过程中的视角还取决于当时正在执行的操作。

`git revert -m 1 "$merge_commit"` 会以第一父为主线计算反向变化。它不删除被合并对象，也不保证以后重新 merge 会恢复原变化。执行前必须在临时分支验证 mainline 选择、冲突和业务结果，详见[revert 共享历史](../part-5/07-revert.md)。

## Squash 只保存最终差异

Squash 以目标分支为父创建一个新 commit `S`，把功能分支相对基线的最终变化压成一个 tree 差异：

~~~text
      f1---F
     /
B---T---S
~~~

原功能提交通常不是 `S` 的祖先。下面的检查返回非零，不代表功能没有合入：

~~~bash
git merge-base --is-ancestor "$feature" "$squash_commit"
~~~

Squash 之后要从评审记录、目标/功能 OID、生成策略、最终 tree 或补丁映射证明来源。提交说明相同、tree 相同或 patch-id 相同都只是部分证据，不能替代构造上下文。

Squash 的回滚入口清晰，一个普通 `git revert "$squash_commit"` 可以生成反向提交。但一项变更包含数据库、消息、配置和多个发布单元时，单个 Git 提交仍不等于可以一步回退所有运行状态。

## Rebase merge 重建每个功能提交

Rebase merge 把功能分支上的提交逐个复制到当前目标之后，再快进目标引用：

~~~text
      f1---F
     /
B---T---f1'---F'
~~~

`f1'` 和 `F'` 有新的父提交，因此 OID 会改变。tree 或补丁可能等价，author 信息通常保留，committer、时间、签名和对象身份可能变化。原功能提交不是新主线的祖先。

评审和 CI 若只绑定旧 `F`，不能自动声明新 `F'` 已验证。平台可能在服务端重建后重新检查，也可能按产品规则转移状态；具体行为必须按当前平台版本和配置核对。厂商无关证据至少保存旧到新 OID 映射、目标基线、rebase 策略和最终检查绑定。

本地比较两段提交可以使用：

~~~bash
rebased_feature="<重建后的完整 OID>"
git range-diff "$base".."$feature" "$target".."$rebased_feature"
~~~

`range-diff` 用补丁序列帮助评审重建前后关系，输出不是永久对象，也不证明运行行为相同。依赖变化、冲突解决和提交顺序仍要单独审查。

## 三种方式的工程后果

| 维度 | Merge commit | Squash | Rebase merge |
| --- | --- | --- | --- |
| 原功能 OID 在主线父历史中 | 通常保留 | 通常不保留 | 不保留 |
| 主线新增对象 | 一个 merge commit | 一个 squash commit | 每个功能提交的副本 |
| 分支拓扑 | 保留 | 压平 | 压平 |
| 单次 Git 回滚入口 | merge commit，需要 mainline | squash commit | 一个或多个重建提交 |
| 原签名 | 原提交仍可达时保留；新 merge 另算 | 不转移到新对象 | 不转移到新对象 |
| 评审映射 | 候选、merge OID 和平台事件 | 必须保存来源与新 OID | 必须保存旧新提交映射 |
| `bisect` 粒度 | 可进入功能提交，也可能先命中 merge | 整项变化一个提交 | 保留重建后的逐提交粒度 |

“历史整洁”无法决定选哪一种。需要看变更规模、是否要求逐提交归因、发布回滚单位、签名策略、评审系统能否保存映射，以及团队是否愿意长期维护 merge commit 的双亲语义。

## 选定默认方式后还要定义例外

团队约定至少回答：

- 默认方式和适用仓库；
- 大型或堆叠变更是否允许例外；
- 谁能改变合并方式；
- 检查验证的候选与最终对象怎样关联；
- 提交签名或发布签名在哪个对象上重新生成；
- 回滚手册怎样按历史形状选择入口；
- 原分支何时删除，旧 OID 映射保存多久。

已经被评审或被其他分支依赖的功能分支，服务端 rebase 或 squash 会改变坐标。例外不能只由合并者临时点击，应该在评审决定和审计事件里留下理由。

## 隔离实验

运行：

~~~bash
./scripts/verify-part-6-collaboration.sh
~~~

实验在临时仓库中构造同一项功能的 merge、squash 和 rebase 结果，断言父数量、祖先关系、tree 和 OID 变化。它不会连接托管平台，也不证明审批、状态转移、服务端签名、队列或审计行为。

## 失败方式和恢复

| 现象 | 先固定 | 恢复与边界 |
| --- | --- | --- |
| 合并后找不到原提交 | merge 方法、原/最终 OID、评审记录 | squash/rebase 场景按映射调查，不用祖先查询下定论 |
| 绿色候选与最终对象不同 | 候选、目标 old、最终 new、构造方式 | 停止发布，重新绑定或重新检查最终对象 |
| revert merge 方向错误 | merge 父列表、目标主线、反向 diff | 中止未完成 revert；已共享则追加恢复提交并重新验证 |
| rebase merge 后签名消失 | 旧新 OID、签名和组织授权 | 对最终对象按策略重新签名或授权，不能转借旧对象签名 |
| squash 后无法逐提交定位 | 原分支、评审记录、patch 映射 | 从保留 refs 或证据库调查；没有映射时如实标记粒度丢失 |

## 小结

Merge、squash 和 rebase merge 处理的是同一份变更，却生成不同对象和父关系。选定方式前，要把评审绑定、签名、回滚、归因和发布证据放在一起判断。最终主线 OID 及其构造上下文必须保留，不能用平台上的一个合并标记代替。
