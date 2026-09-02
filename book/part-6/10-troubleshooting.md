# 一套可恢复的 Git 排障流程：先固定证据，再改变状态

Git 排障最危险的时刻，是还不知道问题发生在哪一层就连续执行修复命令。一个看似“清理”的 reset、prune、fetch 或 force push，可能改变现场、引用和对象，之后再也无法判断原始症状。

本章提供日常工程入口。发生文件或提交消失、push/认证失败、仓库损坏、签名异常、LFS 或子模块故障时，进入第十三篇的症状分流；发生安全事件或合规调查时，优先进入第十、十一、十二篇。

## 进入条件与完成标准

在报障涉及的实际工作树中执行，只读采集优先。不要把下列命令直接复制到不受信任仓库、生产接收端或包含凭据的终端脚本。

开始前记录：

~~~bash
pwd
git --version
git rev-parse --show-toplevel
git rev-parse --git-dir
git rev-parse --git-common-dir
~~~

如果第一条 Git 查询失败，问题可能只是执行位置；如果路径发现成功但后续命令失败，再进入仓库状态和对象层诊断。

读完本章后，你应能：

- 用统一坐标描述症状，而不是只说“Git 报错”；
- 采集 HEAD、工作区、index、refs、对象和远程配置证据；
- 区分普通排障、安全事件、取证事件和组织级故障；
- 识别每个命令的写入副作用和停止条件；
- 把证据包脱敏后交给协作者；
- 在获得足够证据后选择最小恢复动作并验证结果。

## 一、先描述症状和目标

一份可操作的报障至少包含：

~~~text
发生时间：<带时区的时间>
执行位置：<工作树和仓库标识>
当前分支/HEAD：<分支名、分离状态和完整 OID>
症状：<看到什么，何时开始>
期望：<希望保留和改变什么>
共享边界：<是否已推送、评审、构建、部署或被其他工作树使用>
最近动作：<实际执行的命令，不省略失败命令>
外部系统：<远端、CI、制品、数据库、LFS、子模块>
安全等级：<是否可能含凭据、恶意仓库或客户数据>
~~~

“reset 失败了”无法决定恢复动作；“我在 feature/payments，希望保留工作区修改，取消最近一次未推送提交，并让修改回到未暂存状态”才足以开始分流。

不要在报障中贴令牌、私钥、Authorization header、客户数据或未经脱敏的内部 URL。原始错误文件应保存在受控位置，外发版本另行生成。

## 二、采集本地布局和进行中操作

在仓库根目录优先执行：

~~~bash
git status --short --branch --untracked-files=all
git status --porcelain=v2 -z
git rev-parse --verify HEAD^{commit}
git symbolic-ref --quiet HEAD
git for-each-ref --format='%(refname) %(objectname) %(objecttype)'
git worktree list --porcelain
~~~

status 会显示 merge、rebase、cherry-pick、revert 等进行中状态。porcelain v2 与 NUL 分隔适合机器采集，但解析脚本不能按空格或换行拆路径。

这些命令通常不改变对象和分支，但 status 可能更新 index 的缓存元数据。严格取证时记录这一副作用，不把它称为绝对无写入。不要在采集前运行 gc、prune、reset --hard 或 checkout -f。

检查状态文件时只读查看：

~~~bash
git rev-parse --verify MERGE_HEAD
git rev-parse --verify REBASE_HEAD
git rev-parse --verify CHERRY_PICK_HEAD
git rev-parse --git-path MERGE_MSG
git rev-parse --git-path rebase-merge
git rev-parse --git-path rebase-apply
~~~

其中某些命令失败是正常的，表示当前没有对应操作。不要因为目录为空就删除它，先以 status 和实际路径为准。

## 三、分开观察工作区和 index

提交、文件不见和冲突症状都需要三层差异：

~~~bash
git diff --no-ext-diff --no-textconv
git diff --no-ext-diff --no-textconv --staged
git diff --check
git diff --staged --check
git ls-files --stage
git ls-files --unmerged
~~~

工作区文件存在而 index 没有条目，通常是未跟踪或被 sparse/ignore 规则影响。index 有 stage 1/2/3，说明冲突尚未完成。当前 tree 中不存在，不代表 blob 对象、其他提交或外部 payload 不存在。

需要精确判断一个路径：

~~~bash
path=path/to/file
git status --short -- "$path"
git ls-files --stage -- "$path"
git ls-tree HEAD -- "$path"
git cat-file -e HEAD:"$path"
git check-ignore -v -- "$path" || true
~~~

恢复时必须明确来源和目标。例如只从 HEAD 恢复工作区：

~~~bash
git restore --worktree --source=HEAD -- "$path"
~~~

只取消暂存并保留工作区：

~~~bash
git restore --staged -- "$path"
~~~

这两个动作会改变不同区域。执行前保存当前文件字节、index 和 diff；不要用全仓库 hard reset 替代窄范围恢复。

## 四、读取 refs 和对象，不先改写

固定本地 refs：

~~~bash
git show-ref
git for-each-ref --format='%(refname) %(objectname) %(objecttype)'
git reflog --all --date=iso-strict
git count-objects -v
git fsck --connectivity-only
~~~

对象查询：

~~~bash
candidate=<完整 OID 或已验证 ref>
git cat-file -t "$candidate"
git cat-file -p "$candidate"
git rev-parse "$candidate^{commit}"
git rev-parse "$candidate^{tree}"
git rev-list --parents -n 1 "$candidate"
~~~

fsck 的检查根、选项和输出范围必须写进记录。unreachable 或 dangling 只说明对象不在当前根的可达图中；它可能因维护而过期。调查期间不要运行 gc、prune 或自动维护。

发现引用误移动时，先建立恢复引用：

~~~bash
git branch recovery/incident <full-commit-id>
git show --no-patch --format=fuller recovery/incident
~~~

恢复引用改变本地 refs，是有副作用动作，但比继续重写或清理更容易回退。执行后再次固定新 refs 和 OID。

## 五、需要远程证据时再通信

本地证据不足时，先查看配置：

~~~bash
git remote -v
git remote get-url origin
git remote get-url --push origin
git config --show-origin --show-scope --get-regexp '^remote\.|^branch\.'
~~~

fetch 会写对象、FETCH_HEAD 和远程跟踪 refs。必须记录 fetch 前后的 OID 和时间：

~~~bash
before="$(git rev-parse --verify origin/main^{commit})"
git fetch origin
after="$(git rev-parse --verify origin/main^{commit})"
printf 'before=%s after=%s\n' "$before" "$after"
~~~

如果只需要查询远端 ref，可使用：

~~~bash
git ls-remote --exit-code origin refs/heads/main
~~~

ls-remote 不更新本地 refs，但需要网络、认证和远端可见性。它不能证明平台控制面、评审、CI 或部署状态。

不要把 fetch 的本地写入描述成“只读排障”，也不要在没有保存本地候选和远端 old OID 时强制推送。

## 六、按故障类别分流

| 类别 | 典型问题 | 首要证据 | 默认停止条件 |
| --- | --- | --- | --- |
| 普通工作流 | 文件、提交、冲突、切换 | status、diff、HEAD、index stages | 不确定来源时停止恢复 |
| 传输与权限 | push、认证、授权、保护 ref | remote URL、原始 stderr、old/new OID | 不换凭据反复重试 |
| 性能与容量 | status/log/clone 变慢、磁盘告急 | workload、规模、Trace2、对象统计 | 不在高负载时无计划 maintenance |
| 安全事件 | 凭据泄漏、恶意 hook/filter、可疑对象 | 现场冻结、refs、对象、副本 | 先撤销/隔离，不先清理历史 |
| 取证事件 | 需要保全时间线和责任证据 | 原始采集、hash manifest、保管链 | 不运行会改写或过期对象的命令 |
| 组织级故障 | 主备切换、权限回收、平台不可用 | 控制面、RPO/RTO、恢复点、审批 | 未通过门禁不提升新权威 |

一个本地 Git 命令只能证明它所属的数据面。不要用本地 fsck、status 或 push 成功替代安全、平台、制品、数据库和运行系统证据。

## 七、执行一个动作，立刻复核一个不变量

每次改变状态后，保存动作前后的：

~~~bash
git rev-parse HEAD
git status --short --branch
git for-each-ref --format='%(refname) %(objectname)'
git diff --stat
git count-objects -v
~~~

根据动作选择不变量：

- restore 后，指定来源与目标路径字节一致，其他路径不变；
- merge/rebase/cherry-pick 后，没有未解决 stages，最终 tree 和测试符合意图；
- fetch 后，远程跟踪 OID 与 fetch 结果一致，本地工作分支未被意外移动；
- push 后，远端目标 ref 等于预期 new OID，且旧 OID 与并发检查已记录；
- recovery ref 建立后，候选 commit 可解析，原始对象未被清理；
- maintenance 后，对象完整性、refs、index 和工作区不变量仍成立。

不要连续运行多条“补救命令”后才查看结果。每一步都应能说清改变了什么、失败如何回退。

## 八、最小动作卡

### 文件或提交不见

先查 worktree、index、tree、reflog、浅克隆和对象来源，再按明确来源执行窄范围 restore 或建立 recovery ref。不要先 reset --hard、gc 或删除分支。第十三篇第二章给出完整分流。

### push 被拒绝

保存原始错误、远端目标、old/new OID 和共同祖先，fetch 后比较两侧提交。选择 merge、rebase、review ref 或显式租约，不能用换邮箱解决 non-fast-forward。第十三篇第三章处理认证和授权分层。

### 仓库变慢或容量不足

先固定 workload、时间分位、对象和磁盘指标，再评估索引和 maintenance。维护需 scratch、互斥、备份和停止条件；不在事故现场直接 prune。第十三篇第四章处理性能与容量边界。

### LFS、子模块或 CI clone 异常

分别验证 pointer/payload、gitlink/嵌套仓库和 candidate/checkout 输入，记录外部服务与缓存来源。Git 对象可读不代表 LFS payload、子模块 commit 或构建输入可用。第十三篇第五章处理。

### 签名或密钥异常

分开检查签名存在、密码学验证、key/principal、有效期/撤销和组织授权。不要因本地 verify 成功就提升发布。第十三篇第六章处理。

## 九、求助模板

把以下内容脱敏后提供给协作者：

~~~text
symptom: <单一可观察症状>
time: <带时区时间>
worktree: <仓库根和 git-dir 的脱敏路径>
head: <完整 OID>
branch: <分支或 detached>
operation: <merge/rebase/fetch/push 等>
status: <porcelain 输出摘要>
refs: <相关 local/remote refs 与 OID>
objects: <count-objects/fsck 范围和结果>
command: <实际命令>
stderr: <原始错误的脱敏版本>
shared: <是否已共享、评审、构建或部署>
external: <平台、CI、制品、数据库、LFS、子模块>
desired: <希望保留和改变什么>
actions_taken: <已执行动作及前后 OID>
limitations: <没有验证什么>
~~~

如果可能是安全或取证事件，不要继续执行修复命令，先通知安全和现场负责人。现场采集、对象恢复、迁移和组织演练分别使用第十、十一、十二篇的流程。

## 隔离实验验证了什么

结合以下实验验证本地排障动作：

~~~bash
./scripts/verify-troubleshooting-snapshot.sh
./scripts/verify-missing-files-and-commits.sh
./scripts/verify-push-auth-permission-boundaries.sh
./scripts/verify-part-6-engineering.sh
~~~

这些实验验证合成仓库的证据采集、路径恢复、push 拒绝分流、stash、worktree 和 bisect 状态。它们不证明真实平台权限、恶意仓库安全、文件系统取证、LFS 服务、组织审计或生产 RPO/RTO。

## 小结

可恢复的排障顺序是：描述症状，固定位置和 OID，采集工作区/index/refs/对象证据，按故障类别分流，执行一个最小动作并立即验证。fetch、restore、reset、prune、force push 和维护命令都有副作用，使用前必须知道恢复来源。无法区分普通工作流、安全事件、取证事件和组织级故障时，先停止改变状态，把问题交给对应流程。
