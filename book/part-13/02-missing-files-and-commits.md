# “不见了”发生在哪一层：文件、路径、提交与恢复边界

开发者切到另一个 worktree 后看不到 `config/schema.yaml`，可能是当前提交没有这条路径、稀疏检出没有展开、文件在 index 中标为删除、大小写重命名尚未被文件系统正确观察，或工作区只剩 LFS pointer。另一类“提交不见了”也可能只是当前分支不再指向它、`log` 的起点/路径过滤没有覆盖、远程跟踪引用过期，或 shallow clone 从未取得更早祖先。

“不见了”描述的是观察者没有在预期入口看到目标，不等于 Git 已经删除对应字节。恢复前必须先确认目标的身份：哪一个路径、哪个 tree、哪个完整 OID、哪个仓库/对象来源，以及最后一次由什么引用保持。

本章以 Git 2.49.0 和受信任的本地仓库为基线。进入本章前，应掌握[最小排障证据集](01-evidence-first.md)、工作区/index/tree/blob、引用、reflog、稀疏检出和共享历史边界。读完后，应能：

- 把“文件不见”分解为工作区路径、index entry、提交 tree、blob 与外部 payload；
- 区分未暂存删除、已暂存删除、当前 tree 不含路径、稀疏未展开、ignore 与大小写问题；
- 在恢复前准确选择来源 tree 和目标区域，不用 `reset --hard` 覆盖无关内容；
- 判断“提交不见”是日志范围、引用移动、reflog 线索、浅边界还是对象缺失；
- 从已验证候选先创建恢复引用，再决定 merge、cherry-pick 或正式 ref 更新；
- 说明未跟踪/未保存字节、过期 reflog、对象回收、LFS 和平台数据的不可恢复边界。

## 文件路径和提交对象不是同一种“存在”

对于路径 `docs/runbook.md`，至少有五个问题：

1. 文件系统工作区里是否有这个路径和字节？
2. index 是否有该路径的 stage 0，或冲突 stages 1/2/3？
3. 当前 `HEAD` 的 tree 是否记录这个路径以及哪个 blob/gitlink？
4. 其他候选提交的 tree 是否记录它？
5. 若路径是 LFS pointer 或 submodule gitlink，外部 payload/仓库是否可取得？

Git commit 保存顶层 tree OID，不保存“某个路径当前在磁盘上”的状态。稀疏检出可以让 tree 中存在的路径不展开到工作区；`git restore` 可以从 index 或指定 tree 把路径写回工作区；LFS 工作区内容又可能由 pointer 指向 Git 之外的 payload。

对于提交 `<OID-C>`，则要问：

1. 当前对象解析环境能否读取该 commit 对象？
2. 它的 tree、父提交和所需对象是否完整？
3. 哪些本地 refs、reflogs、index 或操作状态让它可达？
4. 当前 `log` 的起点、pathspec 和历史简化是否会显示它？
5. 其他 clone、远端、评审、CI、bundle 或备份是否仍持有它？

删除分支首先删除一个名字；它不逐个擦除历史对象。反过来，知道一个 OID 也不保证本地拥有对象：浅仓库、部分克隆、损坏对象库或错误 OID 都可能让解析失败。

## 先固定路径身份，不凭界面名称猜

在[首章的初始快照](01-evidence-first.md)之后，为目标路径追加定向证据。假设路径没有换行等特殊字节，先在报障 worktree 根目录执行：

```bash
target_path='docs/runbook.md'

GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 -- "$target_path"
GIT_OPTIONAL_LOCKS=0 git ls-files --stage -- "$target_path"
GIT_OPTIONAL_LOCKS=0 git ls-tree -r --full-tree HEAD -- "$target_path"
```

`target_path` 必须替换成现场相对路径。三条命令分别观察工作区/index 差异、index entry 和 `HEAD` tree；不主动连接远端。预期输出取决于状态：路径干净时 `status` 可为空，`ls-files` 与 `ls-tree` 仍可各有一行。每条命令都要保存退出码，不能把三条空输出合并成“文件从 Git 消失”。

路径可能含空格、换行、制表符、前导短横线或不可见 Unicode。自动采集使用 `status -z`、`ls-files -z` 和 `ls-tree -z` 保存 NUL 分隔原字节；人类界面显示相同不保证路径字节相同。macOS/Windows 的大小写折叠、Unicode 规范化和 `core.ignoreCase` 会让仅大小写重命名在不同文件系统表现不同，诊断要记录操作系统、文件系统和：

```bash
git config --show-origin --get core.ignoreCase
```

配置没有显式值时命令返回 1，不代表 `false`；仓库初始化时 Git 可能根据文件系统探测写入值。不要为了让文件出现而临时改配置，先在隔离副本验证大小写/规范化行为和目标 tree。

### 直接核对 tree 中的对象

如果已确认简单路径字节，可以验证当前提交是否含对应对象：

```bash
git cat-file -e "HEAD:$target_path"
```

成功通常没有输出，表示 `HEAD` tree 可解析该路径；非零可能是路径不在 tree、`HEAD` 尚未出生、所需对象缺失或表达式无法解析。保存 stderr，不能单凭非零删除工作区文件或运行 fetch。

查看对象类型和内容前先考虑敏感性：

```bash
git cat-file -t "HEAD:$target_path"
git ls-tree HEAD -- "$target_path"
```

普通文件通常解析为 `blob`；submodule 在 tree 中是 mode `160000`、类型 `commit` 的 gitlink。Symlink 的 tree mode 通常为 `120000`，blob 内容是链接目标文本。把这三种都当普通文件复制，会得到错误恢复结果。

## 用四层矩阵解释“文件不见”

| 工作区 | index | `HEAD` tree | 典型解释 | 下一步 |
| --- | --- | --- | --- | --- |
| 有 | 有 stage 0 | 有 | 可能干净或有修改 | 比较 worktree/index/HEAD 三者 OID/差异 |
| 无 | 有 stage 0 | 有 | 未暂存删除，或稀疏路径未展开 | 检查 porcelain 与 sparse 状态 |
| 无 | 无/记录删除 | 有 | 删除已暂存 | 先固定 index diff，再选择来源恢复 |
| 有 | 无 | 无 | 未跟踪或被 ignore 的文件 | 检查 ignore；Git 无提交恢复保证 |
| 无 | 无 | 有于其他提交 | 当前分支/tree 不含路径 | 定位候选提交与 rename，不先硬重置全树 |
| pointer 有 | pointer blob 有 | pointer blob 有 | Git 层正常，LFS payload 未水合 | 独立检查 LFS OID/size/服务/cache |
| 空目录/异常入口 | gitlink 有 | gitlink 有 | submodule 未初始化或固定 commit 不可取 | 检查 `.gitmodules`、URL、固定 OID 与递归协议 |

工作区“无”要以文件系统和 Git 状态共同证明。IDE 搜索范围、构建容器挂载、generated source、忽略视图和 sparse-aware 工具可能隐藏路径而不改变磁盘。

### 未暂存删除与稀疏未展开的区别

若 `HEAD` 和 index 都有路径、工作区没有，先看 porcelain v2。普通删除会报告 worktree 一侧变化；稀疏检出则可能把路径标为 `skip-worktree`，并不把缺少工作区文件视为删除。

检查仓库是否启用稀疏检出：

```bash
git sparse-checkout list
git ls-files -v -- "$target_path"
```

第一条在未启用/不支持的状态可能非零；启用时列出选择规则。`ls-files -v` 的 tag 受 `assume-unchanged` 与 `skip-worktree` 标志影响，不能只凭一个字母直接编辑 index bits；结合 sparse 配置和 `git sparse-checkout reapply`/`set` 的预期范围判断。完整模型见[受限克隆与稀疏检出](../part-4/14-refspec-partial-clone.md)。

若确认路径只因 sparse 未展开，可在受信任 worktree、无冲突且已保护本地修改后扩大范围。例如 cone 模式下目录为 `docs`：

```bash
git sparse-checkout add docs
git status --short --branch
```

命令会更改 sparse 配置、index 标志和工作区；部分克隆中还可能从 promisor remote 按需下载 blob。预期 `docs/runbook.md` 按当前 tree 展开，实际输出依版本和状态变化。网络、磁盘、未跟踪冲突或 required filter 失败时停止，保留原 sparse 列表；不要删除 `.git/info/sparse-checkout` 或手工清空 skip-worktree bits。

### “status 看不到”可能只是被忽略

对于磁盘上存在、Git 未跟踪但默认 status 不显示的路径：

```bash
git check-ignore -v -- "$target_path"
```

匹配时输出规则来源、行号、pattern 与路径；没有匹配通常输出空并返回 1。Ignore 只影响未跟踪路径的候选显示，不删除文件，也不会让已经跟踪的路径退出历史。需要完整解释时同时检查仓库 `.gitignore`、`.git/info/exclude` 和 `core.excludesFile` 的来源，外发前脱敏本机路径。

`assume-unchanged` 与 `skip-worktree` 也不是通用“本地忽略修改”功能。错误使用会让状态观察变得反直觉；清除之前记录 index flag，并确认它不是 sparse-checkout 正常管理的一部分。

## 恢复文件前先选来源和目标区域

`git restore` 的问题不是“恢复哪个文件”，而是“从哪个 tree/index，把内容写到工作区、index 或两者”。

### 仅工作区删除，index 仍是正确来源

前置条件：`ls-files --stage` 证明 index stage 0 是希望恢复的 blob；目标路径没有要保留的未保存字节；不在未解决冲突中。先保存定向状态与差异，然后：

```bash
git restore --worktree -- "$target_path"
git status --porcelain=v2 -- "$target_path"
```

默认来源是 index。命令会把路径写回工作区，不改当前 `HEAD` 或其他路径，成功通常无输出；验证时目标删除应消失。若 index 也是错误版本，这条命令会恢复错误字节。路径被未跟踪文件/目录占用、filter 失败、文件权限或缺失对象都可能导致失败，保留 stderr，不升级成 `reset --hard`。

该动作覆盖目标工作区路径。删除前若存在从未进入 index/tree 的新内容，Git 不能从旧 index 推导出来；先查编辑器历史、文件系统快照或备份。

### 删除已经暂存，选择明确提交来源

前置条件：已验证 `<SOURCE-OID>` 的 tree 中包含目标路径，且它就是要恢复的版本。若希望同时恢复 index 与工作区：

```bash
source_oid='<SOURCE-OID>'
git cat-file -e "$source_oid^{commit}"
git ls-tree "$source_oid" -- "$target_path"
git restore --source="$source_oid" --staged --worktree -- "$target_path"
git diff --staged -- "$target_path"
git diff -- "$target_path"
```

占位符必须换成已核对完整 OID。命令把来源 tree 的路径写入 index 与工作区，不移动分支；相对当前 `HEAD` 是否仍有 staged diff 取决于来源是否等于 `HEAD`。若只想取出内容审查，不应先覆盖原路径，可在隔离目录读取：

```bash
git show "$source_oid:$target_path" > /absolute/restricted/review/runbook.md
```

重定向写入目标文件，需确保目录受限、目标不存在或允许覆盖，并检查命令退出码；文件可能含秘密，symlink/submodule/LFS pointer 又需要按类型处理。不要用这条命令伪造文件权限、扩展属性或 LFS payload 恢复。

### 路径在旧提交中，但可能发生重命名

先固定候选范围：

```bash
git log --follow --name-status -- "$target_path"
```

`--follow` 对单一路径执行重命名启发式追踪，不是提交保存的 rename 事实；目录重命名、拆分/合并、低相似度修改和历史简化可能漏掉。必要时比较相邻 tree 并记录 `-M`/`-C` 阈值。找到候选后验证完整 tree/OID，再恢复精确旧路径或把内容放到新路径，不根据一行 `R100` 直接改正式历史。

## 未跟踪文件：Git 可能从未拥有它

文件只在工作区出现、从未 `add`、stash 或 commit 时，Git 通常没有它的对象和路径关系。`reflog` 记录 refs 移动，不记录每次保存；`git restore` 也不会生成未知字节。

有些编辑器/IDE、本地历史、Time Machine/文件系统快照、云端工作区或构建缓存可能保留副本，但它们属于各自系统。恢复时记录来源、时间和内容摘要，不能把外部副本称为“从 Git 找回”。

`git add` 曾把内容写成 blob 但未形成 commit 的特殊情况，可能在清理前留下不可达对象；没有 tree/path 关系和已知 OID 时属于对象取证，不是可靠日常恢复方案。停止 gc/prune，在证据副本按[对象取证与恢复](../part-11/02-object-forensics-and-recovery.md)处理。

## “提交不见了”先检查观察范围

`git log` 从给定起点沿父关系遍历。下面这些命令回答不同问题：

```bash
git log --oneline -20
git log --oneline --all -20
git log --oneline --all --reflog -40
git log --oneline main -- docs/runbook.md
```

- 第一条从当前 `HEAD` 开始；
- `--all` 加入本地 refs 作为起点，不联系远端；
- `--reflog` 让 reflog 条目也参与起点集合，但仍只属于当前仓库；
- 带 pathspec 的历史只显示对路径有相关差异的提交，并受 rename/history simplification 影响。

“前 20 条没看到”不能证明对象不存在。Graph 顺序、merge、first-parent、日期/作者过滤、浅边界、replace refs 和 pathspec 都可能改变视图。报障必须保存原始完整命令，而不只保存 GUI 搜索词。

若知道候选完整 OID，直接分三步验证：

```bash
candidate='<FULL-OID>'
git cat-file -e "$candidate^{commit}"
git show --no-patch --format='%H%n%P%n%T%n%aI%n%cI%n%s' "$candidate"
git for-each-ref --contains "$candidate" \
  --format='%(refname) %(objectname)'
```

第一条只证明当前解析环境能把它剥离为 commit；第二条查看身份、父与 tree；第三条列出哪些本地 refs 的可达历史包含它。没有 ref 输出仍可能由 reflog、index/操作状态或已知 OID 暂时找到；也可能候选属于无关历史。短 OID 可能歧义，事故记录使用完整 OID。

## 按证据强度找候选提交

优先级通常是：

1. 当前本地 refs、tag 和操作状态；
2. `HEAD` 与相关分支的 reflog；
3. 其他受控 worktree/clone 的 refs 与 reflog；
4. 远端 refs、评审、CI checkout、发布清单中的完整 OID；
5. bundle、mirror、备份和平台管理员保留；
6. 最后才在证据副本枚举 unreachable/dangling 对象。

### Ref 移动或删除：reflog 是线索，不是备份

```bash
git reflog show --date=iso-strict HEAD
git reflog show --date=iso-strict refs/heads/main
```

Reflog 保存本仓库曾经的引用移动；分支删除时其分支日志可能一起删除，`HEAD` 日志可能仍有线索。日志有过期和清理窗口，不随 clone/fetch/push 传输。完整模型、默认过期边界和 `ORIG_HEAD` 见[reflog 章节](../part-5/11-reflog.md)。

找到候选后，不把正式分支立即 reset 到它。先验证 commit、父、tree、差异、签名与业务内容，然后创建恢复引用：

```bash
candidate='<VERIFIED-FULL-OID>'
git branch recovery/missing-work "$candidate"
git log --oneline --decorate --max-count=5 recovery/missing-work
git diff --stat main...recovery/missing-work
```

`git branch` 新增本地 `refs/heads/recovery/missing-work`，不切换 `HEAD`、index 或工作区；若名字已存在会失败而不覆盖。三点比较需要共同祖先，不存在时分别比较 tree。恢复引用创建后，再根据共享边界选择 merge、cherry-pick 或经协调的条件 ref 更新。详细案例见[误删分支与错误 reset 恢复](../part-5/12-recovery-cases.md)。

### Shallow clone：更早提交可能从未到达本地

```bash
git rev-parse --is-shallow-repository
git rev-list --boundary --oneline HEAD
```

输出 `true` 说明存在显式浅边界；`boundary` 只能展示当前本地历史边界，不证明源端仍有全部祖先。经授权、确认 remote 身份且有足够网络/磁盘后，可在浅仓库中：

```bash
git fetch --unshallow origin
git rev-parse --is-shallow-repository
```

`fetch` 下载对象、调整 `.git/shallow`，并可能更新远程跟踪 refs 与 `FETCH_HEAD`；成功后第二条通常输出 `false`。源端本身浅、网络中断、权限/过滤或容量不足时不能完成，保留当前边界，不手工删除 `.git/shallow`。若只需有限祖先可用 `--deepen=<n>`，仍要把深度作为证据限制。

### Partial clone、alternate 与对象缺失

若 `cat-file` 因缺失对象失败，先记录：

```bash
git rev-parse --is-shallow-repository
git config --show-origin --get-regexp \
  '^extensions\.partialClone$|^remote\..*\.promisor$|^remote\..*\.partialclonefilter$'
git rev-parse --path-format=absolute --git-path objects/info/alternates
```

Partial clone 可能按需联网获取 promisor 对象，alternate 可能让当前仓库依赖外部 object directory。不要为验证存在性在原现场触发未知网络或移除 alternate；转入受控副本。Missing/corrupt、pack 错误或多个副本异常时，按[对象取证与恢复](../part-11/02-object-forensics-and-recovery.md)保全根集合和对象来源。

## 远端“提交/分支不见了”不是本地结论

本地 `origin/main` 是上次 fetch 留下的远程跟踪引用。它可能落后，也可能已被本地 prune；服务器响应又可能因当前身份和隐藏规则只暴露部分 refs。

在初始本地 refs 快照后，经授权查询精确 ref：

```bash
git ls-remote --exit-code origin refs/heads/main
```

成功输出服务器当前向此会话 advertised 的 OID/ref；退出 2 表示无匹配，其他非零需区分传输、服务器身份、认证和服务错误。无匹配也只证明当前 endpoint/身份/时刻的可见性，不自动证明 ref 从平台物理删除。

需要取得对象时，把 fetch 写成单独动作，记录 refspec 和 fetch 前追踪 OID。不要先 `fetch --prune`：prune 可能删除本地映射引用，使最后一个易读名字消失；虽然对象可能仍受 reflog 保持，恢复难度已经增加。

错误强推或远端删除涉及并发协作者、平台审计和服务端保留，进入[显式租约](../part-5/09-force-with-lease.md)与[综合恢复案例](../part-5/12-recovery-cases.md)，不由个人根据本地 reflog直接覆盖服务器。

## 恢复验收按对象、路径、引用和外部状态分层

| 层 | 验收 | 仍不能证明 |
| --- | --- | --- |
| 对象 | candidate commit/tree/blob 可按 OID 读取 | 候选就是正确业务版本或来源可信 |
| 路径 | 目标 tree/index/worktree 的 mode、OID、内容符合目标 | 其他路径未被误覆盖，LFS payload 已存在 |
| 引用 | recovery ref 指向候选，提交图/共同祖先符合预期 | 远端和协作者已经切换 |
| 项目 | 构建、测试、配置检查基于精确候选通过 | 制品/部署/数据库已恢复 |
| 外部数据面 | LFS、submodule、评审、CI、制品与部署关联同一 OID | 事故证据和权限问题已经关闭 |

文件恢复后至少重新运行定向 `status`、两类 diff、对象/tree 查询和项目测试。提交恢复后保留 recovery ref 到评审、远端协调、制品/部署核对和保留窗口结束。不要为了“保持干净”立刻删除唯一恢复 ref 或运行 gc。

## 常见失败与安全动作

| 症状 | 常见误判 | 安全动作 |
| --- | --- | --- |
| 工作区无路径就认为提交删了文件 | 稀疏检出、另一个 worktree、当前分支不同 | 核对绝对布局、`HEAD` tree、index 与 sparse 规则 |
| `status` 不显示本地文件 | 文件被 ignore，或只在 IDE 过滤视图隐藏 | 检查文件系统与 `check-ignore -v`；ignore 不等于删除 |
| `restore` 后不是预期版本 | 默认来源是 index，不一定是 `HEAD` | 比较 tree/index/worktree，使用已验证显式 `--source` |
| 为找一条路径运行 `reset --hard` | 把全树/引用动作当路径恢复 | 停止；从 reflog/ORIG_HEAD 找提交，未提交覆盖部分查外部备份 |
| 未跟踪文件删除后反复搜 reflog | Git 从未记录内容或路径关系 | 转向编辑器/文件系统/备份；曾 add 的特殊情况升级对象取证 |
| `log -20` 看不到就认为提交被删 | 起点、数量、pathspec、merge 简化或 shallow 边界 | 保存完整 log 命令，扩展已知 refs/reflog/边界而非制造新提交 |
| 找到 reflog OID 就 reset 正式分支 | 候选尚未验证，工作区和共享边界未知 | 先 `cat-file`/show/tree/diff，再创建 recovery ref |
| 浅仓库手删 `.git/shallow` | 把边界声明删除当作祖先恢复 | 从可信远端 deepen/unshallow；失败保留边界 |
| `fsck`/cat-file 报 missing 后先 gc | 维护可能改变不可达窗口和物理证据 | 冻结维护，记录对象来源，进入取证/恢复副本 |
| 远端 ref 无响应就立即重建同名分支 | URL/身份/权限/隐藏规则尚未确认 | 保存探测上下文，查平台审计和其他副本，协调后条件恢复 |

## 隔离实验：四种文件状态与三种提交可见性

本书提供 `scripts/verify-missing-files-and-commits.sh`。在仓库根目录执行：

```bash
bash scripts/verify-missing-files-and-commits.sh
```

脚本只在 `mktemp` 中使用虚构身份和本地 `file://` 远端，验证：

1. 未暂存删除时 `HEAD`/index 仍含同一 blob，`restore --worktree` 只恢复目标工作区路径；
2. 删除已暂存时 index 不再含路径，显式 `--source=<OID> --staged --worktree` 同时恢复 index 与工作区；
3. 稀疏检出使 tree 中路径不在工作区，扩大 sparse 范围后重新展开而不产生删除提交；
4. ignore 让未跟踪路径不进入默认 status，但文件字节仍在磁盘；
5. 从未写入对象库的未跟踪内容删除后，按计算 OID读取失败，只能从实验外部副本恢复；
6. 分支经 hard reset 移走后，旧 commit 仍由 reflog 提供线索；创建 recovery ref 不改变当前 HEAD/index/worktree；
7. depth=1 的浅克隆无法读取源端更早 commit，`fetch --unshallow` 后才取得对象且保留当前工作区版本；
8. 所有恢复都核对目标 blob/tree/ref 与不得改变的旁路文件，不用一条成功输出冒充验收。

实验会真实执行 `restore`、`reset --hard`、sparse-checkout 和 unshallow，但对象仅属于可销毁临时仓库。它不验证编辑器历史、磁盘恢复、真实托管平台、LFS、submodule、恶意仓库、服务端 reflog 或对象过期/GC。不要在日常仓库照抄破坏性步骤来“复现”。

## 小结

文件存在要分别检查工作区、index、tree、blob 和外部 payload；提交存在要分别检查对象可读性、refs/reflog 可达性、日志观察范围和外部来源。工作区没有路径可能只是 sparse 未展开，当前 log 看不到提交可能只是引用移动或浅边界。只有对象缺失/损坏时，问题才真正进入对象来源与取证层。

路径恢复使用明确来源和目标区域，提交恢复先建经过验证的 recovery ref。未跟踪且从未记录的字节不在 Git 恢复承诺内；reflog 有本地范围和过期窗口；远端无匹配受 endpoint、身份和可见性约束。恢复完成还要验证其他路径、共享 refs、项目测试和 LFS/CI/制品等外部状态。

## 资料

- [git-restore](https://git-scm.com/docs/git-restore)
- [git-status](https://git-scm.com/docs/git-status)
- [git-ls-files](https://git-scm.com/docs/git-ls-files)
- [git-ls-tree](https://git-scm.com/docs/git-ls-tree)
- [git-cat-file](https://git-scm.com/docs/git-cat-file)
- [git-check-ignore](https://git-scm.com/docs/git-check-ignore)
- [git-sparse-checkout](https://git-scm.com/docs/git-sparse-checkout)
- [git-log](https://git-scm.com/docs/git-log)
- [git-reflog](https://git-scm.com/docs/git-reflog)
- [git-fetch](https://git-scm.com/docs/git-fetch)
