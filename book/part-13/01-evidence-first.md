# 先别急着修：从症状到最小证据集

值班频道里出现一句“Git 切不了分支，我已经 reset、pull、stash 过了”，真正需要诊断的已经不止最初的切换失败。`pull` 可能更新当前分支，`stash` 可能移动工作区与 index，`reset` 的不同模式又可能移动引用或覆盖路径；如果没有保留每一步之前的状态，后续只能从混合现场反推。

排障的第一产物不是一条成功命令，而是一份足以回答“问题发生在哪一层”的状态快照。只有先固定目标、边界和证据，修复动作才有明确输入，失败时也知道回到哪里。

本章以 Git 2.49.0 和受信任的本地实验仓库为基线。进入本章前，应理解工作区、index、对象、引用、`HEAD`、远程跟踪引用和提交图。读完后，应能：

- 把“Git 不工作”改写成包含目标、位置、共享边界和原始症状的问题；
- 判断普通排障、事故现场保护和安全响应之间的分流点；
- 按环境、布局、操作状态、工作区/index、refs/对象、传输和平台逐层定位；
- 采集不主动连接远端的最小证据包，并记录命令退出状态与采集缺口；
- 识别 `status`、`diff`、`fetch`、`fsck --lost-found` 等命令不同的副作用边界；
- 用“一次改变、一个预期、一次验证”控制修复风险；
- 在求助前生成可脱敏、可校验且不把空结果冒充正常的材料。

## 先分流：普通排障不是万能入口

下列情况不要继续运行“常用修复命令”：

- 仓库来源不可信，打开目录后出现未知 filter、hook、submodule URL 或可执行脚本；
- token、私钥、生产配置或客户数据可能泄漏；
- `fsck`、服务监控或多个 clone 同时报告 missing/corrupt，损坏可能仍在复制；
- 共享分支发生无法解释的强制移动、删除或未知主体写入；
- Git 服务、身份、审计、LFS、CI 或制品系统出现组织级影响；
- 现场可能涉及纪律、法律、合规或攻击调查。

不受信任仓库先按[不受信任仓库边界](../part-10/05-untrusted-repositories.md)处理；凭据事件进入[凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md)；需要保全现场时进入[事故现场保护与证据采集](../part-11/01-preserve-and-acquire.md)；对象损坏进入[对象取证与恢复](../part-11/02-object-forensics-and-recovery.md)；多人和平台级事件使用[组织级故障手册](../part-12/06-incident-playbooks-and-drills.md)。

本章的最小证据集服务于正常工程排障。它不是磁盘镜像、平台审计导出或完整保管链，也不能把恶意主机变成可信环境。

## 报障先固定六个坐标

一个可诊断问题至少包含：

| 坐标 | 要回答的问题 | 缺失后的误判 |
| --- | --- | --- |
| 目标 | 想保留什么、改变什么，最终不变量是什么 | 把“命令成功”误当业务恢复 |
| 执行位置 | 哪个路径、worktree、仓库、bare 端或 CI checkout | 在另一个 clone/linked worktree 修错对象 |
| 共享边界 | 提交/ref 是否已推送，谁可能并发写入 | 把本地改写当成无协作者风险 |
| 原始症状 | 完整命令、退出码、stdout/stderr 和首次时间 | 只根据转述错误关键词猜原因 |
| 最近好状态 | 最后确认正常的 OID、ref、时间和数据面 | 无法判断何时、在哪一层发生偏移 |
| 后续动作 | 症状后运行过什么，分别成功还是失败 | 把修复动作造成的状态当原始故障 |

例如，不要只写“reset 后代码没了”，而要写：

```text
目标：保留当前未提交文件，并让 feature/payments 回到已推送提交 <OID-A>
位置：/work/payments，普通 worktree；common Git directory 为 /work/payments/.git
共享边界：feature/payments 已推送；当前 HEAD <OID-B> 尚未推送
原始症状：执行 git switch main 退出 1，stderr 已原样保存
最近好状态：2026-08-21 15:40 +08:00，<OID-A> 已由 CI 检出
后续动作：运行过一次 git stash，成功；未运行 reset/clean/gc
```

`<OID-A>`、路径和时间是现场变量，不应伪造为固定示例输出。目标里还要说明是否允许丢弃构建产物、未跟踪文件、未推送提交或共享历史；“都恢复”通常没有足够精度。

## 把观察、假设和改变分开

排障记录至少分三栏：

1. **观察**：命令实际返回的字节、退出状态和已确认的仓库事实；
2. **假设**：对原因的可证伪解释，以及什么证据能支持或否定它；
3. **改变**：经批准执行的状态更新、预期不变量和验证结果。

“远端分支被删了”若只来自 `git branch -r`，仍是一个假设：本地远程跟踪引用可能过期；远端也可能因权限只返回部分 refs。只有查询目标远端、记录认证身份/权限与响应后，才能提高结论置信度。

同样，空输出不是自动的 `pass`。可能确实没有差异，也可能命令在错误仓库执行、pathspec 为空、权限隐藏数据或采集失败。每份证据都保存命令、位置、时间、退出码、输出文件和缺口；结论使用：

- `pass`：该项不变量由当前证据证明满足；
- `fail`：证据证明不变量不满足；
- `inconclusive`：权限、可见性、前提、工具或采集失败使结论无法成立。

`inconclusive` 不是中间人为了推进工单可以改成 `pass` 的措辞。

## “只读命令”也要说明边界

Git 命令不能只按是否看起来像查询来分类：

| 命令/动作 | 主要读取 | 可能的改变或执行边界 |
| --- | --- | --- |
| `git --version`、`rev-parse`、`for-each-ref` | 程序版本、布局、refs | 不预期改变仓库；仍会读取配置和仓库格式 |
| `git status` | `HEAD`、index、工作区、操作状态 | 可能做可选 index refresh、调用 fsmonitor；`GIT_OPTIONAL_LOCKS=0` 可抑制部分可选写入 |
| `git diff` | tree、index、工作区 | attributes、textconv 或 external diff 可能影响解释/执行；诊断采集关闭 external diff 与 textconv |
| `git log --all` | 当前本地 refs 可达历史 | 不连接远端；`--all` 不代表平台隐藏 refs 或已删除远端 refs |
| `git fetch` | 远端 advertised refs 与对象 | 连接远端、使用凭据、写对象、远程跟踪 refs 和 `FETCH_HEAD`，可能触发后台竞态 |
| `git fsck --full --strict` | 当前对象来源和根集合 | 默认用于检查；结果受 refs、reflog、index、alternates/promisor 影响 |
| `git fsck --lost-found` | 同上 | 还会写 `.git/lost-found/`，不能用于原始现场的第一轮观察 |
| `gc`、`repack`、`prune`、`maintenance` | 对象库与辅助索引 | 会重写物理布局或删除对象，不是“修一下再检查”的诊断命令 |

在受信任仓库里，初始采集可为 Git 命令设置：

```bash
GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 --branch
```

前置条件是当前目录属于已确认可信的仓库。命令读取本地 `HEAD`、index 与工作区，预期输出是零到多条 porcelain v2 记录；提交 OID、分支名和路径均随现场变化。它不主动连接远端，且环境变量只抑制 Git 的部分可选锁/刷新，不会把写命令变成只读，不会禁用本地配置、filter、fsmonitor 或其他程序，也不是安全沙盒。

若命令退出非零，保存 stderr 和退出码，将本项标记 `inconclusive`，先检查仓库发现、权限、index 锁与配置来源；不要用 `reset --hard` 让 `status` “恢复正常”。

## 八层诊断地图

从最靠近当前进程的边界向外找第一处失败：

| 层 | 关键问题 | 第一批证据 |
| --- | --- | --- |
| 环境与仓库发现 | 运行的是哪个 Git，当前路径是否属于预期仓库 | 版本、`pwd`、toplevel、Git/common directory、bare/worktree |
| 运行中操作 | merge、rebase、cherry-pick、revert、bisect 是否未完成 | `status` 与 Git path 中的状态标记 |
| 工作区与 index | 路径是未跟踪、忽略、暂存、冲突还是稀疏排除 | porcelain v2、index stages、工作区/暂存差异 |
| refs 与提交图 | `HEAD`、本地/远程跟踪 refs 指向哪里，是否分叉 | symbolic HEAD、OID、refs snapshot、有限提交图 |
| 对象来源 | 所需对象是否可读、自包含，是否受 shallow/promisor/alternate 约束 | 仓库格式、对象读取错误；必要时升级到取证流程 |
| 传输与认证 | DNS/TLS/SSH 主机、凭据、身份和授权哪一层失败 | 原始 stderr、脱敏 URL 结构、显式只读探针 |
| 平台控制面 | 默认分支、保护规则、审批、配额或服务状态是否拒绝动作 | 带产品版本、权限、时间的 API/UI/审计证据 |
| 外部数据面 | LFS、submodule、CI、制品或依赖是否与 Git OID 对齐 | pointer/gitlink/OID、外部服务响应和独立完整性检查 |

若第一层就在错误目录，不必讨论 rebase；若本地对象和 refs 正常而 `push` 的 SSH 主机校验失败，不要改写提交图；若 Git `fsck` 通过而 LFS payload 缺失，修复对象库也不会水合工作区。

## 最小本地证据集

以下采集顺序只适用于已确认可信的普通本地仓库。默认不连接远端、不运行项目代码、不执行 clean/reset/gc，也不把输出直接发布到聊天工具。

### 1. 环境与布局

在报障发生的同一终端环境和仓库目录运行：

```bash
git --version
pwd -P
GIT_OPTIONAL_LOCKS=0 git rev-parse --show-toplevel
GIT_OPTIONAL_LOCKS=0 git rev-parse --path-format=absolute --git-dir
GIT_OPTIONAL_LOCKS=0 git rev-parse --path-format=absolute --git-common-dir
GIT_OPTIONAL_LOCKS=0 git rev-parse --is-bare-repository --is-inside-work-tree
```

`--show-toplevel` 在 bare 仓库或仓库外会退出非零，不能因此断言仓库损坏。保存各命令自己的退出码；bare 仓库改用绝对 Git directory 和 refs 观察，linked worktree 则必须同时记录 per-worktree Git directory 与 common directory。发现路径和预期项目不一致时停止，不要 `cd` 到另一个目录后假装复现了同一现场。

### 2. `HEAD`、状态和 index

```bash
GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 --branch
GIT_OPTIONAL_LOCKS=0 git symbolic-ref -q HEAD
GIT_OPTIONAL_LOCKS=0 git rev-parse --verify HEAD^{commit}
GIT_OPTIONAL_LOCKS=0 git ls-files --stage
```

`symbolic-ref -q` 在 detached `HEAD` 时退出 1，这是有效状态，不是采集失败；此时 `rev-parse` 给出实际提交。未出生分支可能没有可解析的 `HEAD^{commit}`。`ls-files --stage` 的第一列是 mode，第二列是 OID，第三列是 stage：正常条目为 0，未合并路径可同时出现 1/2/3。输出可能包含敏感路径，分享前在派生副本脱敏。

### 3. 运行中操作

不要根据 `.git/` 字面路径猜状态；linked worktree 的操作目录可能不在那里。先用 `git rev-parse --git-path <name>` 取得实际位置，再记录是否存在：

```text
MERGE_HEAD
CHERRY_PICK_HEAD
REVERT_HEAD
rebase-merge
rebase-apply
BISECT_LOG
sequencer
```

`status` 的人类可读说明适合当场判断，状态标记适合结构化采集；二者不一致时标记 `inconclusive` 并保留全部路径证据，不手工删除 lock 或状态目录。

### 4. 本地 refs 与有限提交图

```bash
GIT_OPTIONAL_LOCKS=0 git for-each-ref \
  --format='%(refname) %(objecttype) %(objectname) %(*objectname)'
GIT_OPTIONAL_LOCKS=0 git log --graph --decorate --oneline --all -30
```

这些命令只观察本地已存在的 refs。远程跟踪引用可能过期，`--all` 也不会联系托管平台。`for-each-ref` 为空时先区分新仓库、权限/格式错误与命令失败；`log` 因 missing object 失败时停止普通排障，转入对象取证，不先 fetch、gc 或删除损坏对象。

### 5. 工作区与暂存差异

```bash
GIT_OPTIONAL_LOCKS=0 git diff --no-ext-diff --no-textconv --binary
GIT_OPTIONAL_LOCKS=0 git diff --staged --no-ext-diff --no-textconv --binary
```

前一条比较工作区与 index，后一条比较 index 与 `HEAD`。`--binary` 让可表达的二进制变化进入补丁，但不包含未跟踪文件，也不保证能安全公开。命令关闭 external diff 与 textconv，仍要求仓库已被信任。未出生分支、冲突 index、submodule、LFS pointer 和稀疏工作区要按各自模型解释，空补丁不能单独证明“没有需要保留的内容”。

### 6. 远程只记录名字，不先取值

```bash
GIT_OPTIONAL_LOCKS=0 git remote
GIT_OPTIONAL_LOCKS=0 git branch -vv
```

第一轮不默认运行 `git remote -v`，因为 URL 可能嵌入用户名、token、内部主机和路径；不默认运行 `git config --list --show-origin`，因为配置可能含凭据或敏感目录。需要诊断传输时，把 URL scheme、host、path、proxy、credential helper 来源和 branch upstream 保存到受限原件，再生成脱敏副本。

`branch -vv` 展示的是本地 upstream 配置和本地远程跟踪引用，不证明远端当前存在、最新或对当前身份可见。

## 原始错误必须连同退出状态保存

最有价值的往往是第一次失败的 stderr，而不是搜索引擎里的同名错误。若动作可安全重放，应先完成初始快照，然后在相同目录捕获两个输出流：

```bash
set +e
git switch topic >command.stdout 2>command.stderr
command_status=$?
set -e
printf 'exit=%s\n' "$command_status"
```

这里的 `topic` 是待替换分支名。`git switch` 不是只读命令：成功会改变 `HEAD`、index 和工作区；因此该示例只用于已经判断切换可重放、并准备比较前后状态的场景。若原动作是 `push --force`、`reset --hard`、`clean`、`gc`、凭据撤销或平台规则变更，不为获取错误而在原现场重演。

保存原始字节、退出状态、Git 版本、执行位置和时间。终端截图可以补充上下文，但不可搜索、丢失退出码，也可能截断前因；它不能替代文本原件。

## `fetch` 是受控诊断动作，不是初始观察

要判断远端当前状态，最终可能需要 `ls-remote` 或 `fetch`。两者都涉及网络、服务器身份、凭据和授权；`fetch` 还会写对象、远程跟踪 refs 与 `FETCH_HEAD`。执行前至少记录：

- remote 名称与脱敏 endpoint；
- 当前远程跟踪 refs/OID 和 upstream；
- `FETCH_HEAD` 是否存在及其摘要；
- 将使用的主体/凭据来源和允许读取的资源；
- 后台 IDE、定时任务或其他 worktree 是否也会 fetch；
- 预期 refspec、prune/tag 策略和失败停止条件。

执行后把变化当作新证据，不覆盖“fetch 前”的快照。`fetch` 成功只证明当前身份按本次 refspec 取得了服务端公开的数据；它不证明没有隐藏 refs、平台评审数据或权限过滤。

如果只是确认一个已知 ref 是否可见，可在获得网络授权后使用：

```bash
git ls-remote --exit-code origin refs/heads/main
```

在本地 worktree 或仓库中执行。成功输出 `<OID><TAB>refs/heads/main`，OID 随远端变化；退出 2 表示没有匹配 ref，其他非零可能来自 URL、DNS/TLS/SSH、认证或服务错误。即使没有匹配，也不能在未确认 API 可见性和权限前断言 ref 被删除。`ls-remote` 不更新本地 refs，但仍会连接远端和使用认证上下文。

## 找“第一处破坏的不变量”

症状只说明用户在哪里看见问题；根因常在更早边界：

| 症状 | 先验证 | 暂时不要做 |
| --- | --- | --- |
| 文件“不见了” | 是否在正确 worktree/tree，路径是未跟踪、忽略、删除、稀疏排除还是 LFS pointer | `reset --hard`、`clean -fd` |
| 不能 switch/merge/rebase | 运行中操作、index stages、本地修改和 lock owner | 手删 lock/状态目录、连续 abort |
| “提交不见了” | `HEAD`/refs/reflog、可见 refs、对象是否仍可读 | gc/prune、创建大量新历史 |
| push 被拒 | 原始 stderr、本地与远端 OID、祖先关系、认证主体和规则 | `--force` 或扩大 token 权限 |
| clone/fetch 失败 | URL/协议、服务器身份、凭据 helper、授权、对象过滤和磁盘 | 关闭 TLS/SSH 主机校验 |
| 仓库很慢/很大 | workload、冷/热状态、Trace2、对象/refs/index/worktree/网络维度 | 直接 repack/gc 或删除大文件 |
| LFS/submodule 失败 | pointer/gitlink OID、外部 endpoint、递归协议和固定提交可达性 | 把 pointer 当 payload 提交、移动依赖分支 |
| 签名验证失败 | 对象是否含签名、密码学验证、key-principal 映射、信任策略时间 | 因绿色徽章直接授权发布 |
| missing/corrupt/pack 错误 | 根集合、alternate/promisor、磁盘/副本、损坏是否扩散 | `prune`、用不可信 donor 覆盖 |

后续症状章会沿此表展开。首章的职责是保住初始坐标和证据，不提前用一个万能命令掩盖分层差异。

## 一次改变只对应一个可验证假设

准备修复时写一张动作卡：

```text
hypothesis：切换失败由未完成 merge 和 stage 1/2/3 导致
precondition：MERGE_HEAD 存在；初始 refs/index/patch 已固定
action：按 merge 章节选择 resolve 或 merge --abort
expected changes：操作状态结束；index 不再有未合并 stages
must not change：共享远端 refs；已固定的 pre-merge commit OID
failure stop：abort 报无法重建本地修改，或 refs/OID 与快照不符
verification：status、ls-files --stage、HEAD/ref、项目测试
recovery：停止；从原始补丁/恢复副本重建，不连续尝试 reset/clean
```

修复动作一次只验证一个假设。动作失败后先比较预期与实际变化，再决定是否升级；不要把第二、第三条补救命令追加到同一终端，最后只留下“好了”或“更乱了”。

“命令退出 0”只是命令级结果。最终验证还要覆盖用户目标、工作区/index、提交图、共享 ref、项目测试以及 LFS/CI/制品等相关外部数据面。

## 证据包要能证明完整，也要能表达缺口

最小证据包可包含：

```text
manifest.tsv
environment.tsv
layout.tsv
command-results.tsv
status.porcelain-v2
index-stages.tsv
operation-state.tsv
refs.tsv
graph.txt
worktree.patch
staged.patch
SHA256SUMS
gaps-and-redactions.md
```

`manifest.tsv` 为每个文件记录来源命令、执行位置、时间、退出码、敏感级别、摘要和状态。摘要能发现保存后的字节变化，不能证明采集命令正确、来源完整或主机可信。缺文件、命令失败和权限不可见进入 `gaps-and-redactions.md`，不能用空文件占位后声明采集完整。

### 原件与分享副本分开

可能需要脱敏的内容包括：

- remote URL 中的 userinfo、内部 host、组织和仓库路径；
- 配置中的 credential helper、header、代理、证书与本地路径；
- 文件名、diff、commit message、作者邮箱、branch/tag 名；
- CI/LFS/submodule endpoint、工单、客户和业务数据；
- token、cookie、私钥和任何真实 secret——这类内容先撤销/隔离，不只是打码。

保留受限原件，从它生成派生副本，并分别计算摘要；不要直接编辑原件后声称“只是脱敏”。分享时说明删除/替换了哪些字段，这些处理是否让某项诊断变成 `inconclusive`。

## 求助模板

```text
目标与必须保留：
执行位置与仓库布局：
Git/OS/客户端版本：
共享边界与并发参与者：
原始命令、退出码、stdout/stderr：
最近确认正常的 OID/ref/时间：
症状后已经执行的动作：
当前 HEAD/status/operation state：
本地 refs 与最小提交图：
远端是否查询过、使用何种主体（不提供 secret）：
已确认事实：
待验证假设：
采集失败、脱敏和未知项：
```

这个模板不是要求把仓库内容公开。组织内应定义受限支持渠道、保留期和最小访问；外部求助只提供完成脱敏且得到授权的派生材料。

## 常见失败与恢复

| 症状 | 原因 | 安全动作 |
| --- | --- | --- |
| 一上来运行 reset/pull/clean | 把动作名当诊断，未固定目标和状态 | 停止写操作，记录后续动作；从仍可见 refs、reflog、补丁和其他副本重建时间线 |
| `git status` 在另一个目录正常 | 多 clone、linked worktree 或 IDE cwd 不一致 | 记录绝对 toplevel、Git/common directory，回到原执行环境重新采集 |
| `branch -r` 没有目标就断言远端删除 | 远程跟踪引用陈旧、被 prune 或权限不可见 | 保留本地快照；经授权使用 `ls-remote`/平台证据，空响应标记可见性边界 |
| 为“刷新状态”先 fetch | fetch 改写追踪 refs/FETCH_HEAD，初始对比丢失 | 保存 fetch 前 OID/refspec/FETCH_HEAD；把 fetch 作为单独动作记录 |
| 截图里只有最后一行 fatal | 前置 warning、命令、退出码和环境缺失 | 保存 stdout/stderr 原文、退出状态和位置；截图只作补充 |
| 分享完整 config/diff | URL、header、路径或业务内容泄漏 | 限制原件访问，生成有字段清单和独立摘要的脱敏副本；必要时撤销凭据 |
| 摘要通过就称证据完整 | 摘要只覆盖已采集文件 | 检查 manifest、命令退出码、来源覆盖和 gaps；缺口保持 inconclusive |
| 一条修复命令退出 0 就关闭问题 | 只验证命令，没有验证目标和外部数据面 | 重跑状态/图/测试并核对共享 ref、LFS、CI、制品或平台状态 |

## 隔离实验：冲突现场、无变异快照与 fetch 副作用

本书提供 `scripts/verify-troubleshooting-snapshot.sh`。在仓库根目录执行：

```bash
bash scripts/verify-troubleshooting-snapshot.sh
```

脚本在 `mktemp` 下使用虚构身份创建：一个处于真实 merge 冲突、含 index stage 1/2/3 和未跟踪文件的本地仓库；一个用于证明 fetch 会移动远程跟踪 ref 与写入 `FETCH_HEAD` 的独立仓库。它验证：

1. 采集包固定 Git 版本、绝对布局、porcelain v2、index stages、操作标记、refs、图和两类 diff；
2. 采集前后 `HEAD`、refs、index、工作区内容和未跟踪文件摘要不变；
3. `MERGE_HEAD` 与 stage 1/2/3 被真实观察，不用伪造状态输出；
4. URL 中的无效合成 secret 不进入分享证据包；
5. 完整包为 `pass`，缺失必需文件为 `inconclusive`，摘要被改写为 `fail`；
6. 失败的 `switch` 保存非零退出码和 stderr，且没有改变冲突现场；
7. `merge --abort` 在隔离仓库实际结束操作、恢复 pre-merge tree 并保留未跟踪文件；
8. 单独的 fetch 实验真实更新远程跟踪 ref 和 `FETCH_HEAD`，证明它不是初始只读观察。

实验不连接真实远端、平台、身份或 LFS，也不证明恶意仓库安全、磁盘证据完整、平台日志覆盖或命令适合生产现场。所有路径、OID 和时间均为临时 fixture；真实事故按第十一、十二篇处理。

## 小结

可靠排障从六个坐标开始：目标、位置、共享边界、原始症状、最近好状态和后续动作。先把观察、假设与改变分开，再沿八层地图找到第一处破坏的不变量。`fetch`、`fsck --lost-found` 和维护命令都有状态或外部副作用，不能因为常用于诊断就当作无痕查询。

最小证据集不仅保存输出，还保存退出码、执行位置、摘要、敏感级别和缺口；`inconclusive` 必须保持为未知。修复阶段一次只改变一个假设相关状态，并同时验证“应改变”和“不得改变”的不变量。后续章节将在此协议之上，分别处理文件/提交消失、运行中操作、push/认证、性能、LFS/submodule、签名和对象损坏等症状。

## 资料

- [git-status](https://git-scm.com/docs/git-status)
- [git-rev-parse](https://git-scm.com/docs/git-rev-parse)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-ls-files](https://git-scm.com/docs/git-ls-files)
- [git-diff](https://git-scm.com/docs/git-diff)
- [git-fetch](https://git-scm.com/docs/git-fetch)
- [git-ls-remote](https://git-scm.com/docs/git-ls-remote)
- [git-fsck](https://git-scm.com/docs/git-fsck)
- [Git environment variables](https://git-scm.com/book/en/v2/Git-Internals-Environment-Variables)
