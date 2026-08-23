# 候选提交：把一次检查绑定到精确对象

CI 运行经常被描述成“检查某个分支”或“检查某个合并请求”。这两个说法都不够精确。分支和评审都是可移动的控制面对象，运行开始以后它们仍可能变化；真正能让结果可复核的是一次检查所绑定的源码对象、目标基线、生成方法和策略版本。

本章把 **候选** 定义为一次检查或发布流程实际承诺验证的不可变输入。候选通常是一个 commit，也可能是一个没有正式 commit 引用的临时 tree。后一种情况仍要保存它的构造输入，否则一个 tree ID 无法说明它是怎样从目标分支和功能变更组合出来的。

本章以 Git 2.49.0、Bash 和本地隔离仓库为验证基线，核对日期为 2026-08-22。Git 的对象和引用行为可以在本地复现，评审平台如何创建临时提交、报告检查和锁定合并队列则属于控制面事实，必须按目标产品、版本、权限、套餐和核对日期单独确认。

## 进入条件和退出能力

进入本章前，读者应理解 commit、tree、父提交、引用、`merge-base`、分离 `HEAD` 和受保护分支。读完后，应能：

- 区分触发事件、功能头、目标头、临时合并结果和最终主线提交；
- 为每种候选记录足够的 OID、目标基线、构造方法和检查上下文；
- 判断一个检查结果能否用于当前候选，而不是只看分支名或评审编号；
- 解释 merge、squash、rebase 和合并队列为何会产生不同对象；
- 在目标分支、功能分支、流水线或策略变化后使旧结果过期；
- 在候选缺失、对象不一致或条件更新失败时停止并恢复，而不是在现场拼出一个新候选。

## 工作定义：候选包含什么

下面几个名称在全书保持同一含义：

| 名称 | 工作定义 | 不能替代的东西 |
| --- | --- | --- |
| 功能头 | 触发时功能引用解析到的 commit | 与目标分支组合后的结果 |
| 目标基线 | 触发或生成候选时目标引用解析到的 commit | 运行开始时最新的目标分支名 |
| 合并基点 | 目标与功能历史的共同祖先，可能不止一个 | 平台实际采用的合并策略 |
| 候选提交 | 本次检查实际验证的 commit 对象，以及它的构造上下文 | 可移动的分支、标签或评审编号 |
| 候选 tree | 在没有持久 commit 时用于检查的根 tree，加上构造输入和策略 | 一个孤立的 tree ID |
| 候选类型 | 描述对象如何得到，例如 feature、merge、squash、rebase 或 queue | 对最终合并方式的猜测 |
| 检查上下文 | 流水线定义、路径策略、依赖解析、runner 和 attempt 等输入 | 只记录一个 `success` 状态 |

候选对象和候选上下文要同时保存。两个不同目标基线可能生成相同的 tree，但它们对合并冲突、父历史、版本生成和结果是否过期的含义不同；只保存 tree 不能恢复这些信息。

## 五种常见候选形状

### 功能头候选

功能头是贡献者最后一次推送的 commit。它适合回答“这条分支自身能否构建”，但不能回答“它与当前目标分支组合后能否构建”。如果目标分支包含接口、依赖或配置变化，功能头检查可能完全没有覆盖集成问题。

### 临时合并候选

目标头为 `T`，功能头为 `F`，平台按某种合并策略生成候选 `C` 时，常见的提交图是：

```text
      F
     / \
B---+   C
     \ /
      T
```

图中的 `B` 是共同祖先，`C` 可能是一个有两个父提交的临时 merge commit。父顺序、冲突策略和是否把对象写入可见引用都由生成方决定，不能仅凭图形推断平台行为。检查结果至少要绑定 `C`、`T`、`F` 和生成策略。

### Squash 候选

Squash 通常生成一个只有目标头为父提交的新 commit。它的 tree 可以包含功能分支的全部变更，但它不是功能头的同一对象，也不保留功能分支上的每个提交。若检查在 squash 结果上运行，结果不能自动转移到功能头或另一个目标基线。

### Rebase 候选

Rebase 把功能提交重新放到新的目标基线上，产生一组新的 commit ID。即使文件内容看起来相同，提交对象、父关系、签名和提交者时间都可能不同。结果绑定应指向 rebase 后的精确头或最终合并候选，不能使用 rebase 前的旧 OID。

### 合并队列候选

合并队列把目标当前状态和队列前缀一起作为基线。假设目标为 `T0`，队列中先后有 `F1`、`F2`：

```text
T0 + F1 -> Q1
Q1 + F2 -> Q2
```

`Q2` 的绿色结果不代表 `F2` 单独在 `T0` 上绿色，也不代表 `F2` 可以复用没有 `F1` 的结果。队列中的每个位置都要保存自己的目标、前序候选和生成时间；目标在条件更新时发生变化，候选就必须重建。

## 候选的生成过程

生成候选不是把一个字符串写进环境变量，而是一次需要审计的状态转换。推荐保存以下五个阶段：

| 阶段 | 要固定的输入 | 结果 | 失败时的处理 |
| --- | --- | --- | --- |
| 事件快照 | 仓库稳定 ID、事件 ID、old/new OID、目标引用 | 不可变事件记录 | 事件字段缺失时不调度构建 |
| 解析引用 | 功能头、目标头、标签对象及剥离目标 | 完整对象 ID | 重新解析可移动引用不能覆盖原记录 |
| 选择策略 | merge、squash、rebase、queue 顺序、冲突策略 | 候选类型和生成参数 | 策略版本未知时暂停 |
| 生成对象 | 所需 commit/tree、父关系和 tree | candidate OID 或 candidate tree | 对象缺失或冲突不在 runner 内私自补齐 |
| 绑定检查 | pipeline、路径规则、依赖、runner、attempt | 可复核的运行记录 | 绑定字段不完整时结果不可用于保护规则 |

事件到候选之间可能经过平台控制面。Git 仓库可以证明某个 OID 是否存在、父关系是什么、tree 是否一致，但不能证明平台是否真的按页面上显示的策略生成了这个对象。平台证据要保存生成请求、策略版本、控制面返回值和审计事件，并与本地对象核对。

## 候选记录的最小契约

下面的字段不是要求采用某个 JSON 格式，而是要求保留这些语义。字段缺少时，应该把结果标成不可复用，而不是填入 `latest` 或空字符串：

```text
schema_version
repository_identity
event_id / change_id
event_type / actor_context / trust_domain
updated_ref / old_oid / new_oid
target_ref / target_oid
feature_oid / merge_base_oids
candidate_kind
candidate_commit_or_tree
candidate_parent_oids
merge_strategy / strategy_version
pipeline_definition_identity
path_policy_version / selected_checks / skipped_checks
dependency_resolution_identity
runner_identity / attempt
created_at / started_at / finished_at
result / expiry_reason
```

`candidate_parent_oids` 可以为空，因为临时 tree 没有父提交；此时必须保存目标和功能输入、策略、比较基线以及 tree 的计算证据。`merge_base_oids` 也可能有多个，不能把一个任意祖先写成唯一事实。提交 ID 和 tree ID 使用仓库实际对象格式，不能在 SHA-1 和 SHA-256 仓库之间截断后比较。

最低不变量如下：

1. `candidate_commit_or_tree` 在运行仓库中可读取，或者有可信的外部存储证明其字节和摘要。
2. 实际 checkout 的 `HEAD` 或根 tree 与记录中的候选一致。
3. 构造候选时使用的目标 OID 与检查记录中的目标 OID 一致。
4. 检查身份、流水线定义、路径策略和依赖解析版本没有被重跑过程静默替换。
5. 候选通过后，最终更新引用仍以生成时的目标 OID 为 expected old 条件。

这些不变量分别覆盖对象、调度、执行和写入四个边界。只核对 `HEAD` 不能证明路径策略或发布权限没有变化，只核对平台绿灯也不能证明 runner 没有检出另一个对象。

## 在 runner 中核对候选对象

下面的命令在已经完成 checkout 的 CI 工作树中执行。前置条件是调度系统提供完整的小写 OID，仓库包含候选、目标和功能对象，`CI_RUNNER_TEMP` 是当前作业专用且权限受限的临时目录。命令只读 Git 对象，并把头信息写入临时证据文件，不移动 `HEAD`、不更新 refs，也不修改 index。

```bash
candidate_commit="${CI_CANDIDATE_COMMIT:?CI_CANDIDATE_COMMIT is required}"
target_commit="${CI_TARGET_COMMIT:?CI_TARGET_COMMIT is required}"
feature_commit="${CI_FEATURE_COMMIT:?CI_FEATURE_COMMIT is required}"
runner_temp="${CI_RUNNER_TEMP:?CI_RUNNER_TEMP is required}"
test -d "$runner_temp"

is_hex_oid() {
  case "$1" in
    ''|*[!0-9a-f]*) return 1 ;;
  esac
  test "${#1}" = 40 || test "${#1}" = 64
}

for object_id in "$candidate_commit" "$target_commit" "$feature_commit"; do
  if ! is_hex_oid "$object_id"; then
    printf 'expected a full lowercase SHA-1 or SHA-256 object ID\n' >&2
    exit 1
  fi
  git cat-file -e "$object_id^{commit}"
done

candidate_header="$runner_temp/candidate-header.txt"
git show --no-patch --format='%H%n%P%n%T' "$candidate_commit" \
  > "$candidate_header"

actual_commit="$(git rev-parse HEAD)"
if test "$actual_commit" != "$candidate_commit"; then
  printf 'candidate checkout mismatch: expected %s, got %s\n' \
    "$candidate_commit" "$actual_commit" >&2
  exit 1
fi

git rev-parse HEAD^{tree}
git rev-parse --show-object-format=storage
git status --porcelain=v1 --untracked-files=all
```

成功时，`candidate-header.txt` 的三行分别是候选 commit、父提交列表和根 tree；`HEAD^{tree}` 应与记录中的候选 tree 相同；干净工作区的 `status` 没有输出。`git cat-file -e` 失败说明对象在当前仓库不可用，不能据此判断远端没有该对象。应保留失败证据，让调度系统按原始 OID 补取对象或重新生成候选。

如果输入来自外部事件，不能把分支名、评审标题或未经验证的字符串替换到对象参数中。调度器应先把它们解析为完整 OID，再由门禁校验长度、字符集和对象类型。验证失败时停止作业，不能用 `git fetch origin main` 后重新解析一个移动分支来“修好”记录。

## 正确比较候选与变更

一次集成检查通常需要回答两个不同问题：功能分支相对共同起点改变了什么，以及候选相对目标基线最终增加了什么。下面的命令在对象已取得的临时 runner 仓库中执行：

```bash
merge_bases_file="$CI_RUNNER_TEMP/merge-bases.txt"
git merge-base --all "$target_commit" "$feature_commit" > "$merge_bases_file"

merge_base_count="$(wc -l < "$merge_bases_file" | tr -d ' ')"
if test "$merge_base_count" != 1; then
  printf 'cannot choose one merge-base; found %s\n' "$merge_base_count" >&2
  exit 1
fi

merge_base="$(sed -n '1p' "$merge_bases_file")"
printf '%s\n' 'feature changes from merge-base:'
git diff --name-status "$merge_base" "$feature_commit"

printf '%s\n' 'candidate changes from target:'
git diff --name-status "$target_commit" "$candidate_commit"
```

第一组差异用于路径策略或评审解释，第二组差异用于判断候选最终带入目标的变化。它们在简单历史中可能相同，但目标分支从共同祖先到 `target_commit` 的改动可能改变第二组结果。`--name-status` 默认以行分隔，文件名若可能包含换行，应改用 `--name-status -z` 并使用支持 NUL 的解析器。

`git merge-base --all` 返回多个祖先时，历史可能是 criss-cross，平台的递归合并策略需要明确决定如何组合虚拟基点。不能从多个输出中随意取第一行。常见恢复办法是停止路径筛选、调用平台的实际合并器生成候选，再把生成策略和所有基点写入记录。

候选对象缺失时，补取也有边界。可以在专用 runner 中按调度记录的精确 OID 和允许的 refspec 取得对象，但要保存远端、身份、fetch 前后的 refs 与 `FETCH_HEAD`；不能把补取最新目标分支当成候选重建，也不能用补取结果覆盖原始事件。

## 合并方法改变对象身份

| 方法 | 典型结果 | 结果绑定 | 主要风险 |
| --- | --- | --- | --- |
| fast-forward | 功能头直接成为目标头的新值 | 功能头 OID 和目标 old OID | 目标再次前进后旧结果过期 |
| merge commit | 新 commit，父关系通常包含目标和功能头 | 新 commit、两个输入和策略 | 冲突解决和父顺序不能猜 |
| squash | 新 commit，通常以目标头为父 | squash commit、功能变更 ID 和目标 OID | 不能把结果转给功能头 |
| rebase | 一组新 commit | rebase 后头、旧头映射和目标 OID | 签名、时间和每个 OID 都可能变化 |
| queue | 每个队列位置重建一个组合 | 队列序号、前序候选和目标 OID | 不能复用入队前或相邻位置结果 |

最终写入主线的对象可能又不同于检查候选。例如平台先在临时 merge commit 上检查，合并时采用 squash；这时必须重新运行或明确平台等价地证明 squash 结果，而不能把临时 merge commit 的状态名称复制过去。发布记录要保存最终主线 OID 和实际构建制品的来源关系。

## 结果绑定与过期规则

检查结果的复用键至少应由以下字段组成：

```text
repository_identity
candidate_commit_or_tree
candidate_context_digest
check_identity
pipeline_definition_identity
path_policy_version
dependency_resolution_identity
```

`attempt` 是同一候选的重跑序号，不应替代候选 ID。重跑可以得到不同日志、runner 和外部依赖结果，第一次失败仍要保留。若平台支持缓存，缓存键也必须包含会影响结果的输入，不能只用分支名或路径目录。

候选至少在以下情况之一发生时过期：

- 功能头或目标基线 OID 改变；
- 合并策略、冲突解决、队列前缀或候选 tree 改变；
- 流水线定义、runner 镜像、依赖锁或外部依赖解析改变；
- 路径策略、必需检查集合或检查身份改变；
- 候选以外的签名信任根、发布权限或安全策略改变；
- 检查结果与最终写入的主线 OID 之间没有可验证映射。

“结果仍然显示绿色”不是“不曾过期”的证据。过期原因应进入记录，例如 `target-advanced`、`candidate-rebuilt`、`policy-changed` 或 `reporter-unknown`。没有原因时，保护规则应按未通过处理。

## 合并队列的条件更新

合并队列的核心不是排队界面，而是候选生成和目标引用更新之间的条件关系。对目标 `T0` 和首个功能 `F1`，一个安全的状态机是：

```text
读取 T0
  -> 生成 Q1(T0, F1)
  -> 在 Q1 上运行检查
  -> 重新读取目标，要求仍为 T0
  -> 条件更新 T0 -> Q1
  -> 读取 Q1，再生成 Q2(Q1, F2)
```

如果其他写入者先把目标从 `T0` 更新为 `X`，`T0 -> Q1` 必须失败并保留 `X`。失败不是让 runner 再次强推 `Q1` 的信号，而是让调度器重新取得新目标、生成新候选、重新检查。

在本地临时仓库中，`git update-ref` 可以验证这一点：

```bash
expected_old_commit="${QUEUE_EXPECTED_OLD:?QUEUE_EXPECTED_OLD is required}"
candidate_commit="${QUEUE_CANDIDATE:?QUEUE_CANDIDATE is required}"
git update-ref refs/heads/main "$candidate_commit" "$expected_old_commit"
```

前置条件是测试仓库中没有其他共享写入者，两个 OID 都已通过对象类型和策略检查。成功通常没有输出并移动本地 `main`；expected old 不匹配时命令返回非零，旧值保持不变。这个命令只证明本地 ref 的条件更新，不模拟平台权限、评审批准、队列锁、绕过和审计。生产系统必须使用控制面提供的等价条件写入，并保存实际事件 ID。

## 候选与信任边界

候选的提交内容可能由不受信任贡献者控制，候选记录却必须由受信任的调度器和验证器共同保护。至少分开以下职责：

| 职责 | 可以读取 | 不应默认拥有 |
| --- | --- | --- |
| 事件接收 | 事件快照和公开对象 | 发布、生产密钥和长期写入凭据 |
| 候选生成 | 目标和功能对象、合并策略 | 修改受保护主线 |
| 不受信任代码验证 | 候选源码和隔离缓存 | 读取生产 secrets 或写入可信制品 |
| 候选验收 | 候选记录、检查和来源证据 | 重新执行任意贡献者脚本来“补证明” |
| 发布提升 | 已批准候选的不可变制品和证据 | 以分支名重新构建未知对象 |

候选代码可以修改测试、构建脚本、Git attributes 和依赖声明。把验证和发布放在同一作业只会把候选输入提升为发布权限。具体平台是否对某种事件暴露 secrets、是否允许来自 fork 的写缓存或批准后重用结果，是版本和权限相关事实，必须在专用测试仓库中记录，不能靠事件名称推断。

## 故障分流与恢复边界

| 症状 | 先固定的证据 | 安全动作 | 不要做的事 |
| --- | --- | --- | --- |
| 候选 OID 在 runner 中不存在 | 事件 ID、候选记录、对象格式、fetch 范围 | 按原 OID 补取或重新生成候选 | 解析最新分支代替原候选 |
| `HEAD` 与候选不一致 | 预期/实际 OID、checkout 日志、缓存摘要 | 停止作业，修复 checkout 或调度绑定 | 现场 `reset --hard` 后继续发布 |
| 功能头绿色，集成候选失败 | 功能头、目标头、候选头及各自 diff | 针对精确候选分析冲突和兼容性 | 把功能头结果复制到候选 |
| 候选成功但目标已前进 | 生成时目标、当前目标、条件更新返回值 | 使候选过期并从新目标重建 | 强推旧候选进入主线 |
| squash/rebase 后状态找不到 | 旧头、新头、映射、检查绑定策略 | 按最终对象重新检查或依据平台规则核验 | 用相似提交说明匹配结果 |
| 队列第二项复用了第一项结果 | 队列位置、前序候选、缓存键 | 清除错误复用，按新前缀重建 | 只改检查显示名称 |
| tree 相同但结果无法复核 | tree、目标、功能、策略和依赖记录 | 标记证据不完整，补齐构造上下文 | 把 tree 当成完整候选身份 |

恢复的第一步是保护原始记录和工作目录。候选 OID、策略版本或信任根不明时，继续运行可能产生新的不可归因制品；这时宁可丢弃一次构建，也不要用一个“看起来接近”的对象填补证据缺口。

## 隔离实验与真实边界

本章复用仓库根目录的两组隔离实验。它们都使用 `mktemp` 临时目录、虚构身份和本地 Git，不连接 GitHub、GitLab、制品库或真实 CI：

```bash
bash scripts/verify-ci-evidence-chain.sh
bash scripts/verify-ci-trigger-queue.sh
```

运行前置条件是 Bash、Git 2.28 或更高版本、`awk`、`sed`、`sha256sum` 或 `shasum`。脚本在临时目录创建功能头、目标前进和临时 merge candidate，验证分离 `HEAD` 与候选一致，比较目标和功能差异，检查候选 tree、NUL 路径、旧候选过期，以及带 expected old 的条件 ref 更新。成功时分别输出：

```text
Detached CI checkout, reproducible archive, manifest, and deployment verification passed.
CI path selection, stale candidate, queue order, and conditional ref updates passed.
```

脚本失败时应阅读它保留的断言和退出位置，不能在真实项目中手工执行其中的历史改写或强制更新。脚本只证明本地 Git 对象、tree、路径字节和 ref 条件更新；它不证明平台创建临时提交的规则、检查状态 API、队列分布式锁、身份和权限、秘密暴露、制品服务、计费或真实发布流程。

## 综合练习：为一条绿色结果写出边界

给定以下事实：功能分支 `F1` 在 10:00 通过，目标在 10:05 从 `T0` 前进到 `T1`，平台在 10:06 生成临时候选 `C1`，`C1` 在 10:10 通过，但 10:11 的最终合并采用 squash 生成 `S1`。请写出一份最小证据记录，至少包含：

1. `F1`、`T0`、`T1`、`C1` 和 `S1` 的对象身份及生成时间；
2. `C1` 的合并策略、父关系、根 tree 和检查 attempt；
3. `S1` 是否重新检查，若没有，平台采用了什么可核对的等价规则；
4. 10:05 后 `F1` 的绿色结果为何不能直接保护 `T1`；
5. 制品、发布 tag 和部署实例应绑定 `C1` 还是 `S1`，缺少哪个对象时应停止提升。

合理答案不会只写一个版本号。它会指出 `F1`、`C1` 和 `S1` 是三种不同候选，`T1` 的前进使基于 `T0` 的结果至少需要重新判断，最终发布应以实际构建并部署的对象和制品摘要为准。

## 小结

候选是一次 CI 结果的对象级身份。它可能是功能头、临时 merge commit、squash/rebase 结果、合并队列组合，或者带完整构造上下文的临时 tree。分支名、评审编号和标签名只能帮助找到候选，不能替代候选。

候选记录要同时固定源码对象、目标基线、生成策略、检查上下文和 attempt。目标、功能、策略、依赖、信任根或最终写入对象变化后，旧结果应显式过期。合并队列再以 expected old 条件更新目标引用，失败就重建候选，而不是把旧对象强行推进。

下一章讨论候选通过后如何把流水线、依赖、制品摘要、发布引用、部署请求和运行实例绑定起来。[触发与 checkout](01-triggers-and-checkout.md) 负责事件和 runner 的入口门禁，本章负责候选对象和结果归属。

## 资料

- [git-cat-file](https://git-scm.com/docs/git-cat-file)
- [git-diff](https://git-scm.com/docs/git-diff)
- [git-merge-base](https://git-scm.com/docs/git-merge-base)
- [git-rev-parse](https://git-scm.com/docs/git-rev-parse)
- [git-show](https://git-scm.com/docs/git-show)
- [git-update-ref](https://git-scm.com/docs/git-update-ref)
