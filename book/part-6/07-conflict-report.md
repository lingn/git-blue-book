# 冲突解决后如何准确说明：把选择写进证据链

冲突标记会在解决时被删除，Git 提交也不会自动保存一份“当时屏幕上有哪些标记”的报告。合并提交保存了两个父提交和最终 tree，配合冲突现场记录，可以重建双方输入和最终选择。报告的目的不是复述命令，而是让没有参与合并的人能判断结果是否符合业务约束。

## 进入条件与完成标准

准备一个已经完成 merge 或 rebase 的仓库，且能访问合并前的两个提交。开始前执行：

~~~bash
git status --short --branch
merge_commit="$(git rev-parse HEAD)"
git rev-list --parents -n 1 "$merge_commit"
git show --no-patch --format='%H%n%P%n%T%n%s' "$merge_commit"
~~~

如果当前提交不是合并提交，先确认本次操作是普通 merge、squash、rebase 还是 cherry-pick。不同历史形状保存的证据不同，不能套用一个模板。

读完本章后，你应能：

- 从父提交、merge-base 和最终 tree 重建合并输入；
- 区分“Git 结构上完成”与“业务语义已验证”；
- 写出冲突路径、双方意图、最终处理、舍弃内容和测试证据；
- 说明冲突现场哪些信息只能依赖临时日志或协作者记录；
- 处理 merge、rebase、cherry-pick 和 squash 的报告差异；
- 在结果错误时选择追加修正、revert 或私有历史重建。

## 合并提交保存了什么

对普通非快进 merge，合并提交至少保存：

~~~bash
git rev-list --parents -n 1 <merge-commit>
git rev-parse <merge-commit>^{tree}
git show --no-patch --format=fuller <merge-commit>
~~~

它能证明：

- 合并提交的完整 OID；
- 第一父和第二父的 OID；
- 最终根 tree；
- 作者、提交者、说明和时间。

它不能自动证明：

- 哪些路径曾经出现冲突；
- 冲突时采用了谁提出的业务理由；
- 当时执行过哪些测试；
- 某个提交是否经过平台评审、签名或审批；
- 远端接收、CI、制品和部署时间线。

Git 通过最终 tree 和父 tree 计算差异。需要分别查看两侧相对于结果的变化：

~~~bash
git show -m --format=fuller <merge-commit>
git diff <merge-commit>^1 <merge-commit>
git diff <merge-commit>^2 <merge-commit>
~~~

父顺序必须由 parent 字段确认。不要仅凭“ours/theirs”或图形排列推断哪一侧是 main。

## merge-base 和冲突现场

报告中应记录共同祖先：

~~~bash
git merge-base <parent-1> <parent-2>
git merge-base --all <parent-1> <parent-2>
~~~

存在多个共同祖先时，合并策略可能先合成虚拟 base。最终结果不一定能由一个简单的单文件 diff 解释。冲突现场若仍在进行，优先采集：

~~~bash
git status --short --branch
git rev-parse MERGE_HEAD
git ls-files --unmerged
git diff --name-status --diff-filter=U
~~~

这些记录应在解决前保存到受控位置。merge 完成后，MERGE_HEAD 和 unmerged stages 通常消失，只能依赖提交图、reflog、日志、评审讨论和外部证据回溯。

如果现场已经结束，不要为了“重新获得冲突”而再次 merge、reset 或删除分支。重新触发的上下文可能不同，不能当作原始事故重放。

## 一份可转发的冲突报告

建议至少包含：

~~~text
事件标识：<评审、工单或事故编号>
仓库与工作树：<脱敏标识和执行位置>
Git 版本：<版本>
操作类型：merge / rebase / cherry-pick
当前分支：<接收方分支>
合入来源：<来源分支或提交>
共同祖先：<完整 OID>
第一父提交：<完整 OID>
第二父提交：<完整 OID>
最终提交：<完整 OID>
冲突路径：<路径和冲突类型>
当前分支意图：<为什么这样改>
合入分支意图：<为什么那样改>
最终处理：<保留、组合、迁移或重新实现>
舍弃内容：<没有采用什么，为什么>
结构验证：<unmerged stages、父列表、最终 tree>
行为验证：<测试、构建、请求样例和结果>
外部证据：<评审、CI、制品、部署和运行 ID>
限制：<没有验证什么>
~~~

路径、OID 和事件 ID 比“已解决”三个字更有用。涉及客户数据、凭据或内部 URL 时，报告应先脱敏，再按权限共享。

## 不同历史形状的报告

### 普通 merge

普通 merge 有多个父提交。报告要说明当前分支和被合入分支，以及每个冲突路径的最终选择。即使使用 no-ff，也要说明为什么保留集成节点。

### squash

squash 通常只在当前分支创建一个新提交，不保存被压缩分支的父关系。报告必须额外保存原功能分支的 tip、评审候选和测试 OID，否则主线提交无法独立解释来源。

### rebase

rebase 逐条生成新提交，冲突可能发生多次。报告要保存原提交序列、新提交序列、当前重放提交和 range-diff。不要把最终线性历史写成“一次合并解决”。

### cherry-pick

cherry-pick 在目标分支生成新提交。报告要区分 source OID 和 picked OID，说明目标版本的依赖和为什么没有直接合并来源分支。

## 结构验证不等于业务验证

完成 merge 后，至少运行：

~~~bash
git status --short --branch
git ls-files --unmerged
git diff --check
git show --no-patch --format='%H%n%P%n%T%n%s' HEAD
git diff HEAD^1 HEAD
~~~

结构上没有 unmerged stages，只能说明 index 已经形成单一结果。业务验证还要覆盖：

- 受影响的测试和构建；
- 配置、schema、消息和共享库兼容；
- 生成文件和二进制输入；
- LFS、submodule 和外部依赖；
- 制品摘要、部署实例和运行指标；
- 回退或向前修复路径。

冲突解决时删除了代码，不代表删除是安全的；增加了代码，也不代表新增路径会被构建和部署使用。

## 何时追加修正，何时回退

结果错误但尚未共享时，可以在私有分支中修正或重建历史。合并已经进入共享主线时，优先追加修正提交或 revert：

~~~bash
git revert <merge-commit>
~~~

revert 合并提交需要选择 mainline，且只能撤销 Git tree 的变化，不能自动回退数据库、消息和外部数据。发布系统应把代码回退、制品回退、schema 回退和数据恢复分别记录。

不要为了再次展示冲突而改写共享历史。冲突报告的价值在于保存当时的判断和证据，不在于制造一个新的冲突现场。

## 常见失败和补救

| 现象 | 先收集 | 补救 |
| --- | --- | --- |
| 合并提交只有一个父 | 提交类型、操作日志、parent 字段 | 判断是否 fast-forward、squash 或普通提交 |
| 不知道原来哪条路径冲突 | 现场日志、评审讨论、reflog | 如实标记未知，不从最终 diff 猜测 |
| 报告只写“选 ours” | 当前分支、来源分支、业务约束 | 改成具体路径和最终语义 |
| 测试只在冲突工作区通过 | 最终 commit、干净检出、构建清单 | 在候选 OID 的干净环境重跑 |
| 合并后发现共享库受影响 | 构建图、调用方、部署清单 | 扩大服务验证和 rollout 范围 |
| 冲突结果已发布但行为错误 | merge OID、制品、实例和数据状态 | 追加修复或按发布流程回退，不直接 reset |

## 隔离实验验证了什么

可结合以下实验验证本地证据：

~~~bash
./scripts/verify-part-3-conflicts.sh
./scripts/verify-history-attribution.sh
~~~

它们验证合并父关系、冲突中止与解决、标签 target、逐父历史查询和调查清单完整性。实验不证明真实平台评审、审批、CI、制品、部署或业务责任。

## 小结

冲突解决后最容易丢的是判断过程，而不是文件内容。用 parent、merge-base、最终 tree 和提交 OID 保存 Git 事实，再补充路径决策、测试、构建、部署和回退证据。结构完成只能说明 Git 能继续，准确报告还要说明为什么这个结果值得被共享。
