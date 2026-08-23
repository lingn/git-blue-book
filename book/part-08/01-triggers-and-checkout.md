# 触发与 checkout：CI 首先要证明自己检出了什么

一条 CI 结果只有绑定到精确候选提交才有意义。候选对象、目标基线和结果过期规则见[候选提交](02-candidate-commits.md)；本章只处理触发事件如何保存快照、runner 如何核对实际 checkout，以及路径选择和权限边界如何影响一次运行。

本章把入口定义为三层：触发事件、实际 checkout、检查选择。后续章节再接候选对象、构建、制品和部署证据。每一次运行都要能回答：谁在什么时间启动了它，runner 实际检出了什么，哪些检查被选择或跳过，以及这些事实是否能与候选记录对齐。

本章以 Git 2.49.0、Bash 和本地隔离仓库为基线，核对日期为 2026-08-22。平台的事件名称、临时合并提交、状态 API、队列锁、权限和计费需要按目标产品版本、角色与套餐单独核对；本章的本地实验不模拟这些平台控制面。

## 进入条件和退出能力

进入本章前，读者需要会读取 commit、tree、父提交和远程跟踪引用，理解 `merge-base`、分离 `HEAD`、浅克隆和受保护分支。读完后，应能：

- 保存事件中的仓库标识、old/new OID 和目标 OID，而不是只保存分支名；
- 在 runner 中证明实际 `HEAD` 与调度记录一致，并识别分离 `HEAD` 的正常含义；
- 选择与候选和目标基线相符的 diff，解释路径过滤漏测的条件；
- 把不受信任代码的验证权限与发布凭据隔离；
- 区分 Git 本地可验证事实、平台控制面事实和运行环境事实，并把候选归属交给下一章的契约。

## 三层入口状态模型

一次 CI 运行的入口可以抽象为：

```text
引用/评审状态发生变化
  -> 事件快照：repository + old/new + target
  -> runner checkout：调度记录要求的 candidate HEAD / tree
  -> 检查选择：路径策略、依赖闭包、检查身份与 attempt
```

每一层都可能在下一层开始前发生变化。功能分支可以强推，目标分支可以前进，流水线定义可以更新，权限也可能被撤销。因此，事件入队后不能再次用可移动的分支名解释结果；候选的不可变 OID 和策略版本由[候选提交](02-candidate-commits.md)记录，本章只核对 runner 是否按记录执行。

最低事件证据至少包含：

```text
repository_identity
event_id / event_type / actor_context
updated_ref / old_oid / new_oid
target_ref / target_oid_at_event
feature_oid / merge_base_oid / candidate_oid / candidate_kind
path_policy_version / selected_checks / skipped_checks
pipeline_definition / attempt / status / started_at / finished_at
```

事件载荷可能来自不受信任贡献者。分支名、标签说明、提交说明和路径应作为数据处理，不能未经引用和转义拼入 Shell 命令、日志控制语句或部署参数。

## 触发源决定为什么启动，不决定构建什么

| 触发源 | 起始问题 | 必须固定的对象 | 常见误判 |
| --- | --- | --- | --- |
| 分支 push | 这个 ref 从哪个 old 移到哪个 new | old/new 完整 OID | 作业开始时重新解析分支名 |
| 评审更新 | 这版变化能否进入目标 | feature、target、候选 | 沿用上一版 feature 的结果 |
| 标签创建 | 这个发布 ref 指向什么 | tag object 与剥离后的 target | 只保存标签名 |
| 定时任务 | 调度时要检查哪个快照 | 调度时解析出的 commit/tree | 运行结束时使用最新主线解释结果 |
| 手工重跑 | 重新验证哪个候选 | 原候选、流水线版本和新 attempt | 用重跑成功覆盖原失败 |
| 合并队列 | 当前顺序下哪个组合可以落主线 | 队列基线、前序候选、当前候选 | 复用入队前的绿色结果 |

触发器只授予“开始评估”的理由。是否能读取秘密、写缓存、创建标签或部署生产，要由独立身份和策略决定。验证外部贡献者代码的作业不应因为触发事件名称变化就突然获得发布凭据。

同一功能连续推送 F1、F2 时，F1 可以被取消以节省资源，但取消原因和已产生的外部副作用仍是证据；F2 是新候选，不能继承 F1 的成功。对同一对象重新运行是新 attempt，runner 镜像、依赖解析和平台状态可能已经变化，旧日志不能被覆盖。

## 候选对象只在这里做入口校验

候选对象的完整形状、共同祖先、比较基线和过期条件见[候选提交](02-candidate-commits.md)。本章只要求 runner 接收并核对一个已登记的精确 OID。候选缺失时，按调度记录的精确 refspec 补取或重新调度，不能用最新分支名生成替代对象。

候选比较、共同祖先和双重 diff 的命令在[候选提交](02-candidate-commits.md)集中说明。本章只在 checkout 门禁中核对调度记录要求的对象，并继续检查工作区、历史边界和远程跟踪引用。

## Checkout 合约：先核对实际 HEAD

许多 CI checkout 处于分离 `HEAD`，`git branch --show-current` 输出空字符串是正常状态。真正的失败是 runner 实际检出对象与调度候选不一致，或工作区在构建前已被缓存/脚本污染。

在 runner 工作树执行：

```bash
expected_commit="${CI_EXPECTED_COMMIT:?CI_EXPECTED_COMMIT is required}"
actual_commit="$(git rev-parse HEAD)"

if test "$actual_commit" != "$expected_commit"; then
  printf 'checkout mismatch: expected %s, got %s\n' \
    "$expected_commit" "$actual_commit" >&2
  exit 1
fi

test -z "$(git status --porcelain=v1 --untracked-files=all)"
git branch --show-current
git rev-parse HEAD^{tree}
git rev-parse --is-shallow-repository
```

命令读取实际 commit、工作区、当前分支和 tree；不会移动 HEAD。干净 checkout 的 `status` 没有输出，分离 HEAD 的 `branch --show-current` 为空，浅克隆状态输出 `true` 或 `false`。如果缓存恢复、生成文件或前置脚本改变工作区，应在构建前停止并保存差异，不要用 `git reset --hard "$expected_commit"` 掩盖 checkout 组件或缓存隔离错误。

若 runner 需要 `merge-base`、标签、变更范围、blame、bisect 或完整归档，浅克隆可能缺少祖先；部分克隆还可能把读取某个 blob 的成本推迟到运行时。工作流应先声明历史和对象需求，再用下面的门禁验证：

```bash
git rev-parse --is-shallow-repository
git rev-parse --show-object-format
git cat-file -e "$expected_commit^{commit}"
```

输出只说明当前仓库的边界和对象格式。它不证明远程跟踪引用是最新，也不证明 LFS payload、submodule commit、外部 Action 或制品缓存存在。需要补对象时，记录 fetch 的远端、refspec、身份和副作用；补齐后仍以原候选 OID 为准。

### 远程跟踪引用是缓存

runner 中的 `origin/main` 表示最近一次 fetch 写入的本地记录。调度事件中的目标 OID、候选的第一父和 `origin/main` 可能不同，必须分别记录：

```bash
git rev-parse HEAD
git show --no-patch --format='%H%n%P%n%T' HEAD
git rev-parse origin/main
```

若必须向服务器确认最新主线，先保存初始证据，再执行 fetch，因为 fetch 会修改远程跟踪引用和 `FETCH_HEAD`。fetch 成功也不能把旧候选变成新候选；目标已经前进时，应让平台重新生成候选并重跑检查。

## 路径过滤必须近似依赖闭包

路径过滤不是性能开关，而是一种风险模型。`services/payment/` 变化时，payment 测试还可能依赖：

- 根目录构建脚本、工具链和依赖锁文件；
- 公共库、接口定义、代码生成器和数据库 schema；
- 基础镜像、部署模板和 feature flag；
- CI 配置、测试夹具、submodule 和 LFS payload；
- 仓库外制品、缓存和环境策略。

共享输入变化应触发所有消费者；路径策略自身变化应触发完整检查；无法证明依赖关系时采用更大的检查集。目标分支已经包含的新共享配置通常不会出现在候选相对目标的 changed paths 中，但它仍参与候选构建，不能因路径列表看起来很小就省略组合测试。

路径清单必须保留字节边界。文件名可包含空格、制表符和换行，使用 `-z`：

```bash
runner_temp="${CI_RUNNER_TEMP:?CI_RUNNER_TEMP is required}"
changed_paths="$runner_temp/changed-paths.zlist"
git diff --name-only -z "$merge_base" "$feature_commit" > "$changed_paths"
```

该命令只读取对象，在 runner 临时目录写 NUL 分隔的证据文件。消费者必须使用支持 NUL 的解析方式，不能把它放入 `for path in $(...)`。需要区分新增、删除、重命名或 submodule gitlink 时，使用 `--name-status -z` 并正确解析重命名的两个路径字段。没有解析测试时，宁可触发完整检查，也不要静默漏测。

每次选择结果应保存比较对象、merge-base、原始路径清单、策略版本、选中检查和跳过理由。只保存“payment-test skipped”无法判断它是没有相关路径、被策略排除、上游失败、平台取消，还是 runner 根本没有启动。

## 结果过期与合并队列

一条可用于保护规则的检查结果至少绑定：

```text
repository
candidate_commit / candidate_tree
check_identity
pipeline_definition
path_policy_version
attempt
result / started_at / finished_at
```

功能头、目标基线、流水线定义、路径策略或检查身份变化后，旧结果是否过期必须是显式规则。`success`、`skipped`、`canceled`、`timeout` 和基础设施失败在不同平台上的名称和保护语义可能不同，不能只按显示颜色判断。

合并队列至少遵守：读取目标 T，生成候选 Q1，验证 Q1，以 T 为 expected old 条件更新；主线进入 Q1 后，再以 Q1 为基线生成下一项 Q2。一个本地实验可以演示条件更新：

```bash
expected_old_commit="${QUEUE_EXPECTED_OLD:?QUEUE_EXPECTED_OLD is required}"
candidate_commit="${QUEUE_CANDIDATE:?QUEUE_CANDIDATE is required}"
git update-ref refs/heads/main "$candidate_commit" "$expected_old_commit"
```

前置条件是临时仓库、已验证候选和当前没有共享写入者。成功通常无输出并移动本地 ref；expected old 不匹配时返回非零且保留旧 ref。命令不能模拟平台评审、分布式锁、权限、绕过和最终合并方法，生产主线必须使用平台等价的条件更新和审计控制。

## 不受信任代码与发布凭据分域

外部贡献者可以修改测试脚本、构建工具和依赖。若验证作业同时注入发布 token、生产密钥或长期缓存写权限，代码本身就可能读取或滥用它们。

至少分成两个信任域：

1. **验证域**：只读源码权限、隔离 runner 和缓存，接受不受信任代码；
2. **发布域**：只接受已批准候选的不可变制品与证据，不重新执行贡献者任意脚本。

平台是否向某种事件暴露 secrets 是易变事实，必须按版本、权限和组织设置测试登记。不能用“这个事件通常没有权限”替代运行时证据。

## 故障分流

| 症状 | 先固定 | 默认动作 | 停止条件 |
| --- | --- | --- | --- |
| 修改代码没有触发 CI | event ID、old/new OID、路径清单、策略版本 | 修复触发/依赖规则，对遗漏候选补跑 | 事件范围或权限不可见 |
| checkout 成功但候选不一致 | expected/actual OID、checkout 日志、远端 URL | 停止作业，修复调度或 checkout 组件 | 用 reset 掩盖不一致 |
| 必需检查永久等待 | candidate、check identity、状态映射、报告者 | 恢复正确报告或规则映射 | 为通过而关闭全部保护 |
| 旧提交结果显示在新提交上 | candidate 绑定、复用键、attempt | 使旧结果过期，重建新候选 | 无法证明状态归属 |
| 路径过滤漏跑检查 | merge-base、NUL 路径、策略版本、共享输入 | 扩大检查集，修复依赖图 | 继续依赖未验证的跳过规则 |
| 队列不断重建 | 目标外部更新、功能头变化、策略变化、flaky 记录 | 固定候选，按原因分类重建 | 无法区分代码失败与基础设施失败 |

## 隔离实验与真实边界

本篇当前章节复用两组已验证的本地实验。它们都在仓库根目录执行，使用 `mktemp` 临时目录、虚构身份和本地 Git，不连接真实平台：

```bash
bash scripts/verify-ci-evidence-chain.sh
bash scripts/verify-ci-trigger-queue.sh
```

`verify-ci-evidence-chain.sh` 验证分离 HEAD 的 candidate checkout、候选 tree、流水线 blob、可重复源码归档、制品摘要、部署副本篡改检测，以及主线前进后 runner 仍保持原候选。成功输出为：

```text
Detached CI checkout, reproducible archive, manifest, and deployment verification passed.
```

`verify-ci-trigger-queue.sh` 验证 NUL 路径、共享配置变化、旧候选与队列重建候选的差异，以及带 expected old 的条件引用更新。成功输出为：

```text
CI path selection, stale candidate, queue order, and conditional ref updates passed.
```

实验只证明 Git 对象、tree、路径字节和本地 ref 条件更新。它不证明托管平台如何投递事件、创建临时 commit、报告检查、提供 secrets、实现队列锁、处理权限/绕过或收取 CI/制品费用。平台结论必须保留产品、版本、权限、套餐、测试仓库、事件 ID 和核对日期。

## 小结

CI 的第一责任不是“尽快跑完”，而是证明自己运行在正确候选上。触发事件说明为什么启动，候选 OID 说明测试什么，checkout 合约说明实际检出了什么，路径策略说明运行了哪些检查；四层都要保存对象和策略证据。

分支名、标签名、远程跟踪引用和路径列表都可能漂移或不完整。目标前进、功能强推、流水线变化、路径规则变化或队列顺序变化后，旧结果默认不能继承。验证不受信任代码与发布制品还要分隔权限。下一章将把候选、构建输入、制品摘要和部署记录接成完整证据链。

## 资料

- [git-cat-file](https://git-scm.com/docs/git-cat-file)
- [git-diff](https://git-scm.com/docs/git-diff)
- [git-merge-base](https://git-scm.com/docs/git-merge-base)
- [git-rev-parse](https://git-scm.com/docs/git-rev-parse)
- [git-show](https://git-scm.com/docs/git-show)
- [git-update-ref](https://git-scm.com/docs/git-update-ref)
- [git-fetch](https://git-scm.com/docs/git-fetch)
