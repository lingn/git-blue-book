# 凭据泄漏时先撤销：历史清理不是失效机制

一枚令牌进入 Git 后，最先要做的不是 `git rm`、rebase 或 force push，而是在签发系统撤销它。Git 历史清理只能降低后来者继续发现旧值的概率，不能让已经复制到 clone、日志、缓存、制品或攻击者手中的秘密失效。

这一区分决定事故顺序。若团队先花数小时改写历史，泄漏凭据在这段时间仍可调用生产 API，那么即使最终仓库扫描“干净”，真正的安全目标也失败了。反过来，旧凭据已经撤销后，是否改写历史仍需依据合规、暴露面、下游数量和重新污染风险单独决策。

进入本章前，读者应理解 Git 对象不可变、引用与可达性、reflog、force push、签名、LFS 外部对象和托管平台控制面。读完后，应能分离凭据失效、Git 可达历史清理、物理对象回收和外部副本处置；建立泄漏事故时间线；在专用 clone 评估 `git-filter-repo`；协调远端、隐藏 refs、CI、fork 与旧 clone；并验证仓库不会被旧历史重新污染。

本章 Git 核心实验在 Git 2.49.0 和 macOS 上验证。本机没有安装 `git-filter-repo`，因此没有伪造它的运行结果。生产流程依据 `git-filter-repo` 2.47.0 官方手册核对，核对日期为 2026-08-20；命令使用前必须以本机 `git filter-repo -h` 和组织批准的软件来源复核。平台缓存、管理员清理、审计与隐藏 ref 能力不由本地 bare 仓库验证。

## 一个事故有四种“还存在”

把“删除秘密”拆开，团队才不会用一项成功替代另一项：

| 层 | 问题 | 权威控制面 | 完成证据 |
| --- | --- | --- | --- |
| 凭据有效性 | 旧值还能否认证或授权 | 云平台、身份系统、密钥/证书/令牌签发器 | 撤销状态、轮换记录、拒绝旧值的验证和审计日志 |
| Git 可达历史 | 哪些 refs/reflogs 仍能走到含秘密对象 | 本地与服务端 Git refs、平台评审 refs | 全范围扫描、ref old/new map、first-changed commits |
| 对象物理保留 | 不可达 blob 是否仍在对象库、pack、LFS 或 cache | Git GC、LFS/平台存储与保留系统 | 受控 purge/GC 记录、对象读取失败、恢复边界 |
| 外部副本 | clone、fork、日志、制品、备份或聊天是否留值 | 各系统所有者 | 清单、删除/隔离记录、重新扫描和访问审计 |

`git rm config/production.env && git commit` 只改变新 commit 的 tree。父提交、tag、其他分支、评审 ref 和已经 clone 的对象不变。Force push 可以移动服务端 refs，却不撤销令牌，也不保证服务器立即删除 unreachable objects。即使服务端完成 GC，旧 clone 仍是独立对象库。

机密性结论也不能从 Git hash 推导。Blob OID 是内容地址，不是访问控制；知道或不知道 OID 都不能替代对仓库、对象、日志和备份的权限治理。

## 前三十分钟先控制能力，再整理历史

建议把事故负责人、凭据负责人、仓库负责人和业务负责人分开，避免一个人同时在生产身份系统、远端 refs 和本地历史上并发试错。

### 1. 停止继续暴露

- 暂停会打印、上传或复制该值的 CI job、部署、日志转发和自动同步；
- 对仓库临时冻结写入或限制到事故账号，防止清理期间出现新 refs；
- 隔离发现泄漏的 runner/工作站，保存进程、环境、网络和凭据访问证据；
- 不把完整秘密粘贴到 issue、聊天、命令行、截图或普通工单。

冻结仓库不等于冻结业务。若令牌仍能调用高风险 API，应先在签发系统缩小权限、撤销或禁用，再处理开发流程。

### 2. 撤销旧值并轮换使用者

不同凭据的失效方式不同：

| 类型 | 首要动作 | 还要追踪 |
| --- | --- | --- |
| 短期访问令牌 | 立即撤销 session/token，停止续签 | 签发主体、scope、TTL、最后使用时间、派生令牌 |
| 长期 API key/密码 | 创建替代值、切换合法消费者、撤销旧值 | 所有部署、脚本、第三方集成和备用环境 |
| SSH/签名私钥 | 移除授权或信任、撤销证书/key，生成新 key | 登录、Git 引用更新、历史签名、agent/硬件与副本 |
| 云角色/服务账号 | 禁用 key/session，必要时冻结主体 | 策略变更、assume-role 链、资源访问与持久化动作 |
| 证书 | 吊销/替换证书和私钥 | CRL/OCSP、终端缓存、双向认证和过期窗口 |

“轮换”不是只生成一个新值。完整动作包括把新值安全分发到合法消费者、验证它们工作、撤销旧值、证明旧值被拒绝，并清除不再需要的副本。高可用系统若必须分阶段切换，也要先缩小旧值权限、缩短有效期并强化监控；不能因为发布窗口不便就延迟风险控制而不记录。

### 3. 以签发器日志界定影响

从最早可能进入 commit、CI、评审或日志的时间，到撤销真正生效的时间，查询：

- 谁、从何网络/设备使用了凭据；
- 调用了哪些 API、读取或修改了哪些资源；
- 是否创建了新 key、用户、token、规则、webhook 或持久化入口；
- 是否触发构建、发布、部署或数据导出；
- 审计日志是否完整，时钟和保留策略是否可信。

Git author/committer date 由提交者提供，不能当作可信泄漏时钟。应结合服务端 ref update、CI、secret manager 和签发系统日志建立时间线。若怀疑凭据被使用，事件范围已经超出“仓库清理”，需要对应系统的入侵调查和业务恢复。

## 保存证据，但不要扩散秘密

清理前保存原 refs、对象与平台状态，才能回答发生了什么并在错误改写后恢复；这份副本本身含秘密，应进入受限、加密、带保留期限的事故证据存储，而不是普通备份桶、开发共享盘或另一个可广泛 clone 的 Git 远端。

证据记录宜使用签发器对象 ID、key fingerprint、受控 hash 或掩码前后缀标识凭据，不在文档中复制完整值。对低熵密码，直接存无盐 hash 仍可能被枚举；标识方案由安全团队确定。

在隔离、只读凭据的事故 clone 中先盘点：

```bash
git version
git rev-parse --show-toplevel
git status --short --branch
git remote -v
git for-each-ref --format='%(refname) %(objecttype) %(objectname)'
git reflog list
```

这些命令不改 refs，但 `status` 可能刷新 index stat；高风险现场应在证据副本使用 `--no-optional-locks`。Remote、ref 和 reflog 输出可能暴露内部命名与用户活动，应限制访问。普通 clone 看不到所有平台隐藏 refs、fork 或服务端 reflog，清单必须由平台管理员补齐。

若秘密曾位于一个已知路径，可先调查路径历史：

```bash
git log --all --full-history --name-status -- config/production.env
git rev-list --objects --all
git for-each-ref --contains <first-leaked-commit> \
  --format='%(refname) %(objectname)'
```

在专用 clone 根目录执行。第一条读取当前可见 refs 中该路径的历史；rename 不会被历史过滤工具自动跟随，必须把旧路径、复制路径和大小写变体纳入。第二条列出可达对象及其历史路径提示，可能很大；第三条定位含泄漏 commit 的 refs。Commit OID 每次事故不同，不能把示例占位符直接运行。

不要把真实秘密作为 shell 参数传给 `grep`：它可能进入 shell history、进程列表和遥测。使用组织批准的 secret scanner、受保护 pattern file 或在隔离进程中按凭据类型检测；扫描输出只记录位置和受控 fingerprint。扫描范围还要包含 commit/tag message、文件名、notes、LFS payload、release assets、CI logs/artifacts、容器层和包。

## 是否改写历史是第二个决策

旧值已经可靠撤销后，历史改写的收益是降低偶然发现、满足数据删除/许可证要求、减少扫描噪音或移除不应分发的内容。它的代价是所有后继 commit OID 变化、签名失效、tag/发布/评审链接断裂、协作者重新同步，以及旧历史被重新推回来的风险。

| 情况 | 通常处置 |
| --- | --- |
| 只在未共享、无备份/日志同步的本地 commit | 仍先评估撤销；可在本地重写并检查 reflog/对象，不扩大协作面 |
| 已 push 到受限团队仓库 | 撤销后盘点 refs、clone、CI 和备份；由事故负责人决定是否全局改写 |
| 已进入公开仓库、release 或第三方镜像 | 假定内容已复制；历史改写只能减少继续分发，不能承诺“互联网删除” |
| 只是示例格式、没有真实授权能力 | 先确认确实不可用；修复扫描规则和当前 tree，避免把测试值误报成真实事故 |
| 删除会破坏关键审计/法律证据 | 撤销凭据并限制访问；由法务/安全决定隔离、保留与公开历史策略 |

若组织决定不改写，必须记录风险接受、旧值撤销证据、访问范围、扫描抑制方式和未来公开/迁移限制，不能把“值失效了”写成“仓库从未含敏感信息”。

## 生产改写使用专用工具和 fresh clone

Git 2.49 的 `git filter-branch` 手册明确警告其性能和安全陷阱无法向后兼容修复，并推荐 `git-filter-repo`。后者不是 Git 内置命令；应从批准的软件源取得固定版本，核对摘要/签名、Python/Git 兼容和运行环境，不能在事故仓库临时执行网上复制的脚本。

先确认能力：

```bash
git filter-repo --version
git filter-repo -h
```

本机未安装时，第一条会由 Git 报告 `filter-repo` 不是命令。停止改写并准备受控工具环境，不要回退到 `filter-branch` 只为赶进度。本章以下 `filter-repo` 命令是按 2.47.0 手册核对的操作模板，不是本地执行输出。

### Fresh mirror clone 是可销毁工作副本，不是证据备份

在隔离主机、冻结远端写入并已另存受控证据后：

```bash
cleanup_root="$(mktemp -d "${TMPDIR:-/tmp}/credential-cleanup.XXXXXX")"
source_url=https://example.invalid/team/service.git

git clone --mirror --no-local \
  "$source_url" \
  "$cleanup_root/service-cleanup.git"
```

`source_url` 必须由事故负责人核对，不能从不受信任工单拼入 Shell。Mirror clone 以 `+refs/*:refs/*` 取得服务器愿意广告的 refs，并设置 mirror fetch/push 行为；它仍看不到被平台隐藏或禁止读取的 refs。`--no-local` 对本地路径避免 hardlink/直接复制优化，确保可销毁 clone 与来源对象边界分离。

`git-filter-repo` 会检查 fresh clone；`--force` 可绕过并默认立即过期 reflog、清理旧对象，不应作为常规“修复检查”。若 fresh clone 检查不通过，最安全的恢复通常是丢弃这个 cleanup clone，确认来源后重新 clone，而不是猜测需要关闭哪项保护。

### 删除整个敏感文件

如果该文件所有历史版本都不应保留：

```bash
git -C "$cleanup_root/service-cleanup.git" filter-repo \
  --sensitive-data-removal \
  --invert-paths \
  --path config/production.env \
  --path config/legacy-production.env
```

命令重写所有取得的相关 refs，从第一次路径出现处开始生成新 commits，并移除所列路径；路径选择不跟随 rename，所以必须列出每个历史位置。`--sensitive-data-removal` 还会尝试 fetch 全部 refs，记录 first-changed commits 和可能成为 orphan 的 LFS 对象，并给出其他副本清理提示。Fresh clone 中不应有 local-only work；否则该 fetch 步骤可能覆盖它们。`--no-fetch` 会保留本地内容，却增加漏掉远端 refs 的风险，不应无评审启用。

### 只替换文件中的秘密字符串

若文件其他内容必须保留，可把表达式写在仓库外、权限受限的 pattern file，再使用：

```bash
git -C "$cleanup_root/service-cleanup.git" filter-repo \
  --sensitive-data-removal \
  --replace-text "$restricted_replacement_rules"
```

`restricted_replacement_rules` 必须由安全流程创建并在运行前验证绝对路径，文件本身可能含真实秘密，不能进入 Git、CI artifact 或普通 shell trace。2.47.0 的每行默认按 literal 替换，也支持显式 `glob:`/`regex:` 与 `==>` replacement；错误 regex 可能删改无关源码。先在同源的另一可销毁 clone 做 dry run/抽样，但 `--dry-run` 保存的原始 export 也可能含秘密，仍属于受限证据。

Commit/tag message 中的值使用 `--replace-message` 等对应能力，不能期待 `--replace-text` 自动处理。文件名本身若敏感，还要清理路径；LFS pointer 被删除不等于 payload 从 LFS 服务消失。

## 验证的是范围和语义，不是一行成功输出

`git-filter-repo` 会在 `$GIT_DIR/filter-repo/` 生成 `commit-map`、`ref-map`、`changed-refs`，敏感数据模式还提供 `first-changed-commits`、原始/孤立 LFS 对象清单。它默认删除 `origin` remote，避免操作者不经意把旧、新历史混回原服务；这是安全机制，不是故障。

改写后至少完成：

1. 用独立扫描器覆盖所有本地 refs、tree/blob、commit/tag message 和历史路径变体；
2. 检查 `ref-map` 是否包含每个 branches、tags、notes 和平台导出的特殊 ref；
3. 比较候选 tree、构建、测试、依赖、许可证和发布内容，确认只发生批准变化；
4. 保存 old-to-new commit/ref map 和 first-changed commits 到受控事故记录；
5. 验证改写后的签名、tag、CI cache key、submodule gitlink、发布清单与外部链接处置；
6. 在没有旧对象/cache的环境 clone 清理结果并重新扫描。

每个被改写 commit 的 OID 都会变化，其后代即使 tree 内容没变，也因 parent OID 变化而重建。Commit/tag 对象签名不能继续为新对象背书；需要按新 OID 重新评审、签名或发布，旧签名保留在受限证据中。不要批量伪造原签名者的新签名。

若验证发现范围或内容错误，停止，不要在同一 cleanup clone 反向修改。销毁该工作副本，从未改写的受控证据/远端重新 fresh clone，修正规则后完整演练。这比依赖 `refs/original` 或复杂 reset 更容易审计。

## 更新服务端是一次冻结窗口内的引用迁移

重新添加任何 remote 前，平台管理员应给出：当前所有 refs/OID、冻结起点、允许强制更新的 namespace、不可客户端修改的评审 refs、fork/镜像列表、GC/缓存清理流程和回退负责人。

`git-filter-repo` 默认移除 `origin`。确认目标后才重新添加：

```bash
git -C "$cleanup_root/service-cleanup.git" remote add origin "$source_url"
git -C "$cleanup_root/service-cleanup.git" remote -v
```

第一条只恢复 URL，不发布。Mirror clone 原本可能带 `remote.origin.mirror=true`；删除/重加后的实际配置仍须用 `git config --show-origin --get-regexp '^remote\.origin\.'` 检查。不要看到 `--mirror` 就直接执行 `git push --force --mirror`：它会强制创建、更新或删除整个可见 refs namespace，可能覆盖冻结后提交、平台 refs 或事故证据。

更可审计的发布方式是从 `ref-map` 生成经人工批准的 old/new/ref 表，对每个可写 ref 执行带预期旧 OID 的条件更新；平台不支持原子多 ref 或显式 lease 时，在维护窗口逐项记录成功/失败并保持写入冻结。任何 ref 拒绝都要归入“尚未清理”，不能因为 main 和 tags 成功就继续解冻。

托管平台常把评审历史放在客户端不能 force 更新的 namespaces，例如 `refs/pull/*`、`refs/merge-requests/*` 或 `refs/changes/*`。清理方法、所需管理员角色、保留和 GC 是厂商易变事实，应按产品/版本/权限/核对日期登记并由平台支持流程执行。本地 bare 仓库接受自定义 ref，不代表真实平台允许修改。

Force update 后旧对象通常仍物理保留一段时间。平台 cache、搜索索引、diff 页面、raw URL、fork、release asset、CI log/artifact、包/镜像和备份必须分别处置。若产生 orphaned LFS OID，由 LFS 管理员按服务端流程 purge；普通 Git GC 看不到 payload。

## 旧 clone 是最容易漏掉的重新污染源

推荐让所有协作者重新 clone，而不是在旧 clone 上普通 pull。旧历史和新历史从 first-changed commit 后分叉；旧 clone 可以把两条历史 merge，生成同时包含 clean tip 和旧泄漏 ancestry 的新 commit。因为 clean tip 是它的父提交，这个 merge 对服务端甚至可能是一次普通 fast-forward push，不需要 force。

切换期间应：

- 暂停普通账号写权限，直到主要 clone、机器人、镜像和部署工作区完成处置；
- 发布 old/new OID map 和 first-changed commits，但不发布秘密本体；
- 要求从受控 URL fresh clone，并验证 tags、submodule、LFS 与本地工具；
- 对确有未发布工作的协作者，在隔离环境导出仅包含合法变化的 patch，扫描后应用到新 clone；不要把整个旧 bundle/branch 直接合回；
- 在服务端能够实施时，拒绝包含 first-changed old commits 的 push，并监控旧 OID 重新出现；
- 让 CI runner、代码索引、镜像、发布机器人和长期工作区重新建立，不复用旧 Git object cache。

强制删除旧 tag 后，仅运行普通 `git fetch --tags` 也可能保留本地同名旧 tag；reclone 更可靠。无法重建 clone 时必须由专家逐一删除旧 tags/refs、fetch prune、把合法本地提交 rebase/cherry-pick 到新历史并扫描，不能发布一段通用“修复所有 clone”脚本。

## Ref 不可达与对象被删除不是同一时刻

远端 refs 全部指向 clean history 后，旧 blob 可能仍在 pack、reflog、quarantine、备份或缓存中。`git cat-file -e <old-blob>` 成功只证明当前对象库仍能读取；失败也不证明其他副本不存在。

生产仓库不要在调查期间运行：

```bash
git reflog expire --expire=now --all
git gc --prune=now
```

这两条分别让 reflog 不再保护旧对象并立即清理 unreachable objects，显著缩短恢复和取证窗口。只有证据保全、refs 验证、平台流程和回退批准完成后，才由对象库管理员在明确目标执行。托管平台通常需要后台 GC 或支持工单，本地命令不能控制其存储。

对象物理删除也不是凭据撤销证据。反过来，为法务取证保留一份受限旧对象库，也不表示必须让生产仓库继续公开它。生产可用历史与事故证据应分开存储、分开授权和分开保留。

## 常见失败与恢复

| 失败 | 证据 | 恢复 |
| --- | --- | --- |
| 先改写、旧令牌仍有效 | 签发器状态和使用日志 | 立即撤销/缩权，扩展影响调查；Git 清理不能补偿风险窗口 |
| 只改 main，tag/评审 ref 仍含秘密 | ref inventory、`--contains`、scanner | 保持冻结，从 fresh clone 按完整 refs 重跑；平台 ref 走管理员流程 |
| 路径曾 rename/copy，部分版本残留 | path reports、blob scan、旧树 | 补齐所有路径或用内容规则重跑，独立扫描验证 |
| Filter 误删正常内容 | tree/build diff、commit/ref map | 丢弃 cleanup clone，从受限原始副本重跑；不在错误历史上补提交掩盖 |
| Force push 覆盖并发工作 | 冻结起点 OID、ref update audit | 保持冻结，从证据恢复合法提交并重新映射；明确责任人批准 |
| Tag/签名/发布引用失效 | 新旧 OID、签名和 release records | 按新对象重新评审/签名，保留映射，不把旧签名复制到新对象 |
| LFS pointer 清了但 payload 仍在 | orphaned OID、LFS 服务/备份 | 由 LFS 管理员 purge 并验证；同时保留合规要求的受限证据 |
| 旧 clone 重新污染 | 新 refs 再次包含 old first-changed commit | 再冻结、恢复 clean refs、处理该 clone/账号并复扫所有 refs |
| 服务端 objects 仍可按 OID 读取 | refs、reflog、GC/保留/缓存状态 | 由平台执行 purge/GC；不要用未批准的生产 `prune=now` |

## 预防重点是减少秘密寿命和传播面

- 源码只提交 secret 名称和安全模板，真实值来自 secret manager、workload identity 或短期签发；
- `.gitignore` 只能减少误 add，不保护已跟踪文件，也不是安全控制；
- 开发端 pre-commit scanner 用于早反馈，服务端 push/评审扫描用于统一门禁，两者都要管理误报和绕过审计；
- CI 不向不受信任候选注入生产 secrets，日志默认 mask，但不能依赖字符串替换覆盖所有编码；
- 令牌使用最小 scope、短 TTL、可归属主体和快速撤销，机器人/环境之间不共享长期 key；
- 定期演练 ref 冻结、filter 工具环境、平台隐藏 refs、reclone 和重新污染检测；
- 对 secret scanner 发现结果设置访问限制，避免安全工具生成第二份泄漏数据库。

预防扫描不能证明“没有秘密”，正如历史清理不能证明“没人复制”。安全结论来自身份生命周期、最小权限、检测、审计和可演练处置的组合。

## 隔离实验验证了什么

在本书仓库根目录运行：

```bash
./scripts/verify-sensitive-history-boundaries.sh
```

前置条件是 Bash、Git 2.49 或兼容实现、`grep`、`mktemp` 和可写临时目录。脚本只使用形如 `EXAMPLE-LEAK-DO-NOT-USE-*` 的无效合成字符串，隔离 system/global config，创建自己的临时 local/bare 仓库，不访问网络或真实签发器，退出时删除实验目录。

实验建立安全 root、泄漏 commit 和“从当前 tree 删除文件”的后继 commit，同时让 branch、annotated tag 与自定义评审 ref 指向旧历史。它先只重写 main，删除 `refs/original`、过期 reflog 并 GC，断言其他 refs 仍让合成秘密可达。

随后实验对全部本地 refs 重写，验证新 main/archive/tag/review OID 变化且安全 root 保持不变。改写后 `refs/original` 仍使秘密可达；删除该 namespace、过期实验 reflog 并在可销毁 clone 运行 `gc --prune=now` 后，旧 blob 才不可读取。这里使用的 `filter-branch` 仅为了在没有 `git-filter-repo` 的环境制造可验证 fixture；Git 官方明确不推荐它，脚本不是生产清理方案。

实验逐项 force 更新临时 bare 服务 refs 后，旧 blob 仍物理存在。一个清理前 clone fetch 新主线、把旧历史 merge 进去，再普通 push，就能让远端重新出现泄漏 ancestry；把 main 恢复到 clean OID 并对一次性服务执行 GC 后，fresh clone 不再取得旧 blob，但旧 clone 仍持有它。

成功时只输出：

```text
Sensitive path rewrite, ref coverage, object retention, and stale-clone recontamination passed.
```

实验没有验证真实凭据撤销、入侵调查、`git-filter-repo`、托管平台隐藏 refs、fork/cache/GC、LFS purge、备份删除或法律保留。它只证明 Git refs、对象可达性和独立 clone 的核心边界。

## 小结

凭据事故的第一完成条件是旧能力已经撤销、合法消费者完成轮换、风险窗口得到调查；仓库扫描变绿不是替代证据。历史改写是后续暴露面治理：必须覆盖所有 refs、对象存储、平台副本和下游 clone，并接受 OID、签名、评审和发布关系全部变化。

最危险的误解有两个：删除当前文件就认为历史干净，以及 force push 后就认为旧历史消失。Git 为恢复而尽量保留对象，分布式 clone 也天然保留独立副本。可靠处置依赖冻结、fresh clone、完整 ref map、受控清理、reclone 与重新污染监控，而不是一条看似强力的删除命令。
