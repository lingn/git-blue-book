# 冲突不是报错：三方合并为什么需要人做决定

Git 能判断对象和文本的关系，但它不知道业务意图。两条分支从同一个提交出发，各自改动同一语义位置时，Git 可以发现“双方意见不同”，却无法替团队决定保留哪一种行为。这种状态叫合并冲突，是一次尚未完成的 merge，不等于仓库损坏。

## 进入条件与完成标准

准备一个一次性练习仓库，至少有一个共同祖先和两条已分叉的分支。当前工作区必须干净，当前分支应是准备接收变化的一方。开始前保存：

~~~bash
git status --short --branch
git rev-parse HEAD
git rev-parse feature/title
git merge-base HEAD feature/title
~~~

读完本章后，你应能：

- 说出三方合并的 base、ours 和 theirs；
- 解释为什么最终文件可能既不是上半段也不是下半段；
- 使用 status、diff 和 ls-files --unmerged 观察冲突状态；
- 区分内容冲突、删除/修改冲突、重命名冲突和无标记冲突；
- 选择继续解决或 merge --abort，并说明各自改变的区域；
- 写出“双方意图、最终选择、验证证据”，而不是只报告命令不再报错。

## 三个输入和一个结果

三方合并使用：

~~~text
共同祖先 C
  ├── 当前分支 V（ours）
  └── 被合入分支 N（theirs）
~~~

Git 分别计算 C 到 V 和 C 到 N 的变化，再尝试把两组变化组合成结果 tree。只有一边修改、两边以相同方式修改或修改不重叠时，通常可以自动合并；两边对同一位置作不同修改时，Git 停下来。

ours 和 theirs 是命令视角，不是人员标签。在普通 `git merge feature/title` 中，ours 是执行命令时所在分支，theirs 是参数指定的分支。换一个当前分支执行同一命令，两个名字就会互换。处理冲突时使用分支名、提交 ID 和业务目标，避免把“我的代码”当作稳定定义。

共同祖先可以先用命令确认：

~~~bash
git merge-base HEAD feature/title
git rev-list --parents -n 1 HEAD
git rev-list --parents -n 1 feature/title
~~~

merge-base 只是合并算法的输入之一。存在多个共同祖先、重命名或目录迁移时，合并策略还会进行额外处理，不能把一个 OID 当成完整解释。

## 工作区标记只是一个视图

文本冲突常见的工作区片段：

~~~text
&lt;&lt;&lt;&lt;&lt;&lt;&lt; HEAD
当前分支的内容
&#61;&#61;&#61;&#61;&#61;&#61;&#61;
被合入分支的内容
&gt;&gt;&gt;&gt;&gt;&gt;&gt; feature/title
~~~

它们表示冲突区域的两侧候选。标记行不是最终文件内容，完成解决前不能提交。默认样式可能只显示两侧；diff3 或 zdiff3 会加入共同祖先段，帮助理解双方从哪一版出发。

设置冲突样式时只在隔离仓库操作：

~~~bash
git config --local merge.conflictStyle zdiff3
git config --local --get merge.conflictStyle
~~~

配置只影响之后生成的冲突文本，不会自动重写现有标记，也不会解决二进制或路径级冲突。真实项目应按版本和团队规则统一设置，不要为了某个冲突全局修改用户配置。

冲突标记并不覆盖所有冲突。修改/删除、重命名/删除、文件/目录、模式、符号链接、submodule 和二进制文件可能只在 status、index stages 或命令错误中体现。搜索标记不能作为“没有冲突”的唯一检查。

## 先取证，再编辑

merge 停止后，先在仓库根目录执行：

~~~bash
git status --short --branch
git rev-parse HEAD
git rev-parse MERGE_HEAD
git diff --name-status --diff-filter=U
git ls-files --unmerged
~~~

这些命令分别回答：

- 当前分支的 HEAD 有没有移动；
- 哪个提交正在被合入；
- 哪些路径仍未合并；
- index 是否保存了不同候选版本。

ls-files --unmerged 的输出包含 mode、对象 ID、stage 和路径。stage 的详细含义和 rename/delete 处理在复杂冲突章说明；本章至少要知道“有 unmerged 条目就不能完成普通 merge”。

如果第三条 rev-parse MERGE_HEAD 失败，当前可能不是普通 merge，可能正在 rebase、cherry-pick，或者根本没有进行中的操作。不要套用 merge --abort；先读 status 的状态提示和对应操作文件。

## 状态矩阵

| 观察 | 说明 | 下一步 |
| --- | --- | --- |
| UU path | 双方都修改了同一路径，尚未形成 stage 0 | 阅读 base、ours、theirs，决定最终内容 |
| UD、DU | 一侧删除，另一侧修改 | 判断删除理由和修改价值，必要时迁移内容 |
| AA | 双方新增同名路径 | 比较两个新增文件的用途和来源 |
| DD | 双方都删除同一路径 | 确认没有仍需保留的引用或生成规则 |
| status 显示冲突但没有标记 | 路径或对象层冲突 | 查看 ls-files、tree 和 mode，不要只搜文本 |
| 没有 unmerged 条目 | 结构上已经为所有冲突路径选择结果 | 仍要审查暂存差异和业务测试 |

status 的短码适合定位，不负责判断结果是否正确。一个路径被 add 只表示它已经从 unmerged stages 变成了 stage 0，不能证明代码行为正确。

## 冲突解决的业务问题

对每个冲突路径写下五项：

1. 共同祖先中原来的约束是什么；
2. 当前分支为什么改动；
3. 被合入分支为什么改动；
4. 最终结果要满足哪些接口、数据、配置和部署约束；
5. 哪个测试、检查或运行证据能证明选择成立。

例如两个分支分别把配置项改成不同值，机械选择一边可能让另一个服务失去兼容性。正确结果可能是保留一边、合并字段、迁移到新路径，甚至撤回两边并新增第三种实现。冲突解决不是在两个文本片段里投票。

## 继续还是中止

### 继续解决

形成最终文件后，只对明确路径执行：

~~~bash
git add -- path/to/conflict-file
git status --short
git ls-files --unmerged
git diff --staged --check
git diff --staged
~~~

当所有冲突路径都没有 unmerged 条目时，才能：

~~~bash
git merge --continue
~~~

有些版本或配置会直接打开编辑器；也可以确认说明后用 git commit。无论哪种方式，都先验证 index 的完整内容和测试结果。

### 中止合并

如果目标错误、证据不足或需要重新协调：

~~~bash
git merge --abort
git status --short --branch
git rev-parse HEAD
~~~

abort 尝试恢复 merge 开始前的 HEAD、index、工作区和状态文件。合并前已经有未提交修改时，恢复可能不完整，尤其是这些修改与冲突路径重叠。开始 merge 前保持干净、提交临时节点、stash 或使用独立 worktree，都会让恢复更可靠。

merge --quit 只清除进行中 merge 的元数据，保留当前 index 和工作区；它不是 abort 的同义词。只有明确接管当前状态时才使用 quit，并先保存 stages 和差异。

## 解决后的验收

至少验证：

~~~bash
git status --short --branch
git ls-files --unmerged
git diff --staged --check
git diff --staged
git show --no-patch --format='%H%n%P%n%T%n%s' HEAD
~~~

ls-files --unmerged 没有输出是结构条件。最终 tree、测试、构建、生成文件和运行验证是业务条件。被跟踪文件中没有冲突标记可以作为辅助检查：

~~~bash
git grep -n -e '<<<<<<<' -e '=======' -e '>>>>>>>'
~~~

这个命令可能命中合法文档示例或测试数据。没有输出不能证明二进制、未跟踪文件、submodule、LFS payload 或外部配置没有冲突。

## 失败路径和恢复

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| merge 提示冲突 | HEAD、MERGE_HEAD、merge-base、status | 取证后逐路径解决或 abort |
| 编辑后仍无法提交 | ls-files --unmerged、暂存差异 | 找出未标记为 stage 0 的路径 |
| 冲突标记消失但行为错误 | 双方提交、最终 tree、测试 | 追加修正提交或按共享边界回退，不把“可提交”当作正确 |
| abort 后工作区不一样 | merge 前状态、是否有未提交工作、autostash | 从保存副本恢复，避免继续覆盖现场 |
| 误使用 ours/theirs | 当前分支和 MERGE_HEAD | 按分支名重新解释，必要时 abort 后重做 |
| merge --continue 失败 | hooks、说明、index、剩余状态 | 修复具体门禁后继续，保留失败输出 |

不要删除 .git/MERGE_HEAD、index 或整个仓库来结束冲突。那会破坏恢复线索。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-3-conflicts.sh
~~~

实验验证无冲突分叉会形成两个父提交，内容冲突会进入 UU 和 MERGE_HEAD 状态，abort 能回到合并前，人工编辑后能形成合并提交，附注标签能指向精确提交。它不验证业务语义、平台评审、CI、保护分支或真实二进制/LFS 冲突。

## 小结

三方合并把共同祖先和两侧尖端作为输入，Git 只能决定机械组合，业务选择必须由人负责。冲突现场先保存 HEAD、MERGE_HEAD、index 和双方提交，再逐路径形成最终 tree；继续与 abort 是不同状态机，验收必须同时覆盖结构、内容和业务测试。
