# 解决、中止与验收：冲突消失只是结构条件

合并冲突发生后，Git 保留三方对象和未完成状态，让操作者选择继续、恢复到合并前，或保留当前文件后退出状态机。`git add` 把某条冲突路径收束为 stage 0，`merge --continue` 创建合并提交，`merge --abort` 尝试恢复合并前状态，`merge --quit` 只忘记操作元数据。四个动作不能互换。

一个可交付的冲突结果还要证明最终 tree 符合双方业务意图、目标测试通过、评审和 CI 绑定当前候选。`ls-files -u` 为空只说明 index 不再含未合并 entries。

## 进入条件与完成标准

本章写操作只在临时仓库演练。真实现场先确认是普通 merge：

~~~bash
git status --short --branch
git rev-parse 'HEAD^{commit}'
git rev-parse 'MERGE_HEAD^{commit}'
git merge-base --all HEAD MERGE_HEAD
git ls-files --unmerged
~~~

没有 `MERGE_HEAD` 时，可能处于 rebase、cherry-pick、revert 或普通脏状态，应使用对应 continue/abort，不套用 merge 命令。

读完本章后，应能在编辑前保存现场，按路径形成 stage 0，区分 continue/abort/quit 和 autostash，处理 hook/编辑器失败，并从结构、内容、测试与外部证据四层验收合并结果。

## 先决定继续还是中止

冲突不是必须完成的任务。开始编辑前先问：接收分支是否正确、incoming OID 是否是预期候选、共同祖先和策略是否可信、当前是否具备业务决策人和测试环境。

保存最小现场：

~~~bash
evidence_dir="/restricted/evidence/merge-incident"
git status --porcelain=v2 --branch -z > "$evidence_dir/status.z"
git ls-files --stage -z > "$evidence_dir/index.z"
git diff --binary > "$evidence_dir/worktree.patch"
git diff --staged --binary > "$evidence_dir/index.patch"
git show --no-patch --format='%H%n%P%n%T%n%s' \
  HEAD MERGE_HEAD > "$evidence_dir/heads.txt"
~~~

前置条件是目录已经由授权人员创建并限制访问。Patch 可能含秘密，NUL 文件不能按行解析。命令会读取仓库配置与 filters；不受信任仓库按安全篇隔离。

目标或方向错误、证据不足、业务 owner 不在场时优先 abort。只有确认继续，才编辑工作区。

## Stage 对象比冲突标记可靠

对普通 content/content：

~~~bash
git show :1:path/to/file > "$evidence_dir/base.bin"
git show :2:path/to/file > "$evidence_dir/ours.bin"
git show :3:path/to/file > "$evidence_dir/theirs.bin"
~~~

Stage 可能因 add/delete/rename 而缺失，不能假定三条总存在。复杂类型见[复杂路径冲突](06-complex-path-conflicts.md)，index 数据结构见第三篇的[Index 内部结构](../part-03/05-index-internals.md)。

工作区里的 `<<<<<<<` 是编辑视图。二进制、submodule、mode 和路径冲突可能没有标记；合法测试夹具也可能故意包含标记字符串。搜索标记不能代替 `ls-files --unmerged`。

## 最终结果可以是第三种内容

Base、ours 和 theirs 都是输入，不是只能三选一的答案。比如两侧分别新增超时与重试配置，正确结果可能需要同时保留并增加总时限；一侧删除旧 API、另一侧修补旧 API 时，结果可能把修补迁到新实现。

每条冲突记录至少回答：

| 字段 | 内容 |
| --- | --- |
| base | 原有接口、数据或路径约束 |
| ours | 当前接收分支的变化和理由 |
| theirs | 被合入提交的变化和理由 |
| decision | 最终内容、路径、mode 与舍弃项 |
| validation | 测试、构建、schema、运行或人工核对 |
| owner | 作出业务判断和复核的人/系统身份 |

不要把“选择 ours”当作报告。它没有说明丢弃了哪些 incoming 变化，也无法指导后续回归。

## `add` 和 `rm` 只完成路径选择

编辑或移动完成后，对明确路径执行：

~~~bash
git add -- path/to/resolved-file
git rm -- path/to/obsolete-file
git ls-files --unmerged
git diff --staged --check
git diff --staged
~~~

`add` 会用工作区最终内容写 stage 0，并删除该路径的非零 stages；`rm` 记录最终删除。其他冲突仍保留。`git add -A` 会纳入无关修改和未跟踪文件，真实现场默认逐路径操作。

解决期间工作区可能又出现未暂存修改：

~~~bash
git status --short
git diff
git diff --staged
~~~

Staged diff 是下一次 merge commit 的 tree 相对 `HEAD` 的变化；它不展示所有 incoming 相对结果，完成后还要分别比较两父。

## `merge --continue` 仍可能失败

所有 unmerged entries 消失后：

~~~bash
GIT_EDITOR=true git merge --continue
~~~

`GIT_EDITOR=true` 只适合已经审查并接受现有合并说明的非交互环境。普通使用让编辑器打开并写明整合意图。

Continue 会运行 commit 流程，可能因 identity、签名、pre-commit、prepare-commit-msg、commit-msg、编辑器或磁盘失败。失败后不要删除 `MERGE_HEAD`：

~~~bash
git status --short --branch
git rev-parse HEAD
git rev-parse MERGE_HEAD
git ls-files --unmerged
~~~

若 `HEAD` 仍是合并前提交且 `MERGE_HEAD` 存在，修复具体门禁后可重试；也可在保留证据后 abort。不要用 `--no-verify` 绕过组织要求，只为让状态消失。

## `merge --abort` 尝试回到合并前

~~~bash
pre_merge_oid="$(git rev-parse HEAD)"
git merge --abort
test "$(git rev-parse HEAD)" = "$pre_merge_oid"
git status --short --branch
~~~

合并前工作区/index 干净时，abort 最容易完整恢复。它删除进行中 merge 状态、还原 index 和受影响工作区，不删除双方 commit。

合并前已有修改时，Git 可能无法重建全部现场。`git merge --autostash` 会先创建临时 stash；abort 时尝试重新应用，应用本身可能冲突。检查：

~~~bash
git rev-parse --verify MERGE_AUTOSTASH
git stash list
git status --short
~~~

`MERGE_AUTOSTASH` 是否存在取决于实际路径和 Git 版本。不要把 autostash 当作备份，未跟踪/忽略文件和外部状态仍可能不在其中。Abort 后比较预先保存的工作区 hash、diff 和 stash OID。

快进已经完成时没有 merge 状态可 abort。按 reflog 与旧 OID 恢复引用，并先判断是否共享。

## `merge --quit` 保留当前文件和 index

~~~bash
git merge --quit
~~~

Quit 移除 `MERGE_HEAD` 等操作元数据，不把 `HEAD`、index 和工作区恢复到合并前。Unmerged stages 和冲突文件可以继续存在，但 `merge --continue`/`--abort` 不再知道原状态机。若有 autostash，quit 会把它保存进 stash 列表而不是应用。

只有明确要接管当前 index/工作区、已经保存三方 OID 和 stages、并有后续恢复方案时才使用 quit。日常“取消合并”使用 abort。Quit 后不能靠重新创建一个 `MERGE_HEAD` 文件恢复完整状态；在临时副本重建合并，或根据保存的 pre-merge OID 受控重置。

## 完成后验证提交对象和 tree

~~~bash
merge_oid="$(git rev-parse 'HEAD^{commit}')"
git show --no-patch --format='%H%n%P%n%T%n%s' "$merge_oid"
git diff "$merge_oid^1" "$merge_oid"
git diff "$merge_oid^2" "$merge_oid"
git status --short --branch
git ls-files --unmerged
~~~

普通二父 merge 的第一父应为合并前 receiver，第二父为 incoming。最终 tree 同时按两父视角审查。还要运行目标测试、构建、生成器、schema/配置兼容和安全检查。

Merge commit 不保存冲突清单、人工选择或测试记录。平台评论、冲突报告和 CI 证据必须绑定最终 merge OID；若目标在解决期间前进，旧结果可能过期。

## 冲突报告记录决策，不复制整段 diff

建议字段：

~~~text
receiver_ref / receiver_oid
incoming_ref / incoming_oid
merge_bases / strategy / options / Git_version
conflict_paths_and_types
per_path_base_ours_theirs_decision
discarded_constraints
final_merge_oid / parents / tree
tests_and_external_evidence
reviewer / timestamp / unresolved_risks
~~~

报告中的内部路径、身份、日志和配置先脱敏。只写“冲突已解决、测试通过”无法复现候选，也无法判断测试属于哪个 OID。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| 标记删完仍不能 continue | `ls-files -u`、其他路径和 mode | 逐条处理 index，不用 `add -A` 猜测 |
| `add` 后测试失败 | stage 0、两侧意图、构建与运行证据 | 保留 merge 状态并修正，或 abort 重来 |
| Continue 被 hook/签名拒绝 | stderr、hook 来源、identity、`MERGE_HEAD` | 修复门禁后重试，不删状态文件 |
| Abort 后本地修改异常 | pre-merge diff/hash、autostash 和 stash list | 停止覆盖，从保存副本恢复 |
| Quit 后无法 continue | 保存的三方 OID、index 和工作区 | 在副本重建状态或受控恢复，不伪造元数据 |
| 已提交结果父顺序错误 | `%P`、receiver 和 incoming | 阻止发布，按共享边界修正 |
| 本地通过但平台候选不同 | merge OID、目标基线、平台 candidate | 重新绑定评审与检查，不转借绿色结果 |

对象缺失、index 损坏或锁异常时转入取证/排障章节，不能把重新 clone 当成保留本地冲突现场。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-merge-resolution-control.sh
~~~

实验验证 `--autostash` 冲突后 abort 恢复合并前未提交修改，普通冲突中 quit 删除操作元数据但保留 stages/工作区，失败的 pre-commit hook 让 continue 保持可重试状态，移除合成 hook 后完成二父 merge 并验收 tree。

已有 `scripts/verify-part-3-conflicts.sh` 继续验证基础 resolve/abort 流程。实验不模拟真实签名服务、IDE、平台候选、业务测试或外部数据库。

## 小结

解决冲突先固定三方对象，再按路径形成最终 stage 0。Continue 进入提交工作流，abort 尝试恢复合并前，quit 只移除状态机。结构干净、最终 tree、两父差异、业务测试和外部候选绑定都通过后，才能把结果交给共享或发布流程。

## 资料

- [git-merge](https://git-scm.com/docs/git-merge)
- [git-status](https://git-scm.com/docs/git-status)
- [git-ls-files](https://git-scm.com/docs/git-ls-files)
- [githooks](https://git-scm.com/docs/githooks)
- [git-stash](https://git-scm.com/docs/git-stash)
