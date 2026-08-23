# 二进制与 Git LFS：pointer 不是文件本体

把一个大文件改成 Git LFS 跟踪，并不会让它“离开版本控制”。改变的是版本记录的边界：Git 提交保存一个可审查的 pointer blob，文件本体由 LFS 对象存储按 SHA-256 寻址，工作区再通过 filter 恢复成开发者需要的字节。

这个边界解决的是“大型、需要版本化的文件本体不适合反复进入 Git 对象库”的问题。它不自动解决制品发布、权限治理、备份、锁冲突、容量预算或供应链可信度。Pointer 已经 clone 下来，也不证明它指向的 payload 仍能下载。

进入本章前，读者应理解 blob、tree、commit、Git 对象 ID、`.gitattributes`、clone/fetch、filter driver 和不受信任仓库边界。读完后，应能决定一个二进制应进入 Git、Git LFS、制品库还是其他对象存储；解释 Git blob、LFS pointer、LFS payload 与工作区之间的状态；设计 CI 水合、完整性验证、迁移和灾难恢复流程。

本章 Git 核心实验在 Git 2.49.0 和 macOS 上验证。本地环境没有安装 `git-lfs`，因此没有伪造 `git lfs fetch`、锁 API、配额或托管平台输出。客户端命令语义依据 Git LFS 3.7.1 官方规范和手册核对，核对日期为 2026-08-20；在真实环境执行前，仍须以安装版本的 `git lfs <command> --help`、服务端能力与组织策略复核。

## 先决定这个文件是否应该版本化

“超过多少 MB 就用 LFS”不是完整决策。大小只是成本变量，重建能力、变更频率、访问范围和保留责任同样重要。

| 文件性质 | 首选边界 | 原因 | 需要额外回答 |
| --- | --- | --- | --- |
| 小型、稳定、源码构建必需的二进制输入 | Git blob 可能足够 | clone 后自包含，工具最少 | 历史增长是否可接受；许可证是否允许分发 |
| 大型、需要与源码 commit 一起版本化的美术源文件、模型或数据快照 | Git LFS 候选 | Git 记录 pointer，payload 独立传输 | 服务可用性、容量、锁、备份和离线开发 |
| 每次 CI 可重复生成的包、镜像、安装器 | 制品库/镜像仓库 | 生命周期与发布、晋级、保留策略不同于源码 | 怎样关联候选 commit、构建身份和摘要 |
| 数据集、训练 checkpoint、审计归档 | 专用对象/数据存储，必要时由清单引用 | 访问、区域、生命周期和容量通常超出源码仓库 | 不可变版本、checksum、权限、血缘和删除策略 |
| 密钥、令牌、个人数据 | 不进入 Git 或 LFS | LFS 不是秘密存储，pointer 与历史仍会传播 | 撤销、轮换、清理、法律与审计要求 |

LFS 尤其适合“必须随源码选定一个精确版本，但 diff 和 merge 价值有限”的大文件。若文件只是构建输出，把它放进 LFS 往往只是把重复构建物从 Git 对象库搬到另一张账单里。若团队必须逐行评审可读格式，先考虑稳定序列化、拆分或可重复生成，而不是用锁掩盖格式问题。

不要只按扩展名决定。`.zip` 可能是第三方工具链的不可替代输入，也可能是每次流水线都能生成的发布包；两个场景的保留责任完全不同。评审记录应至少写明：文件所有者、产生方式、单版/年增长、读取者、离线要求、保留期、能否重建、是否允许并行编辑，以及服务失效时的恢复目标。

## 三层对象，两个内容地址

假设 `assets/model.bin` 在候选提交 `C` 中由 LFS 跟踪。至少要区分以下状态：

| 层 | 保存什么 | 怎样寻址 | 谁负责 |
| --- | --- | --- | --- |
| Git tree/blob | 路径、文件模式和 pointer 文本 | 仓库对象格式决定的 Git 对象 ID | Git 仓库与普通 clone/fetch |
| LFS payload | 原始二进制字节 | pointer 中的 `oid sha256:<hex>` | 本地 LFS cache 与 LFS 服务 |
| 工作区 | 已水合 payload，或在显式跳过下载时保留的 pointer | 路径与当前 index/HEAD | filter、checkout 和本机状态 |

一个典型 v1 pointer 是：

```text
version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345
```

规范要求 pointer 是小于 1024 字节的规范 UTF-8 文本，使用 Unix 换行；`version` 固定在首行，当前 payload OID 只支持小写十六进制 SHA-256，`size` 是原始 payload 的字节数。扩展行使合法 pointer 不一定永远只有三行，所以生产解析器应使用 Git LFS 自身能力或完整规范，不能把本章实验的三行断言复制成通用服务端解析器。

这里同时存在两个不同的内容地址：

- Git 对 pointer blob 计算 Git 对象 ID；SHA-1 仓库和 SHA-256 仓库的算法可能不同。
- Pointer 的 `oid sha256:` 对原始 payload 字节计算 SHA-256，不因 Git 仓库对象格式改变。

因此，`git rev-parse HEAD:assets/model.bin` 得到的是 pointer blob 的 Git 对象 ID，不是大文件本体的 LFS OID。把两者混进同一个“文件 SHA”字段，会让 CI、备份和事故取证产生歧义。

### Pointer 存在只证明提交引用过一个 payload

只要 pointer blob 和 commit 都在 Git 对象库里，普通 `git fsck --full` 就可以认为 Git 对象图完整，即使 LFS 服务、本地 cache 和所有 payload 备份都已经丢失。这不是 `git fsck` 的缺陷；payload 本来就不在 Git 对象图中。

完整性问题至少分四级：

1. Pointer blob 是否是可解析的规范格式；
2. 当前本地 LFS cache 是否存在 OID 对应的对象，hash 与 size 是否一致；
3. 远端 LFS 服务是否能向目标身份返回该对象；
4. 备份是否能在主服务不可用时恢复所需对象和元数据。

`git lfs fsck --pointers`、`git lfs fsck --objects` 可帮助检查前两级的指定 revision/当前状态，但不能凭一次本地成功证明第三、第四级。远端与灾备必须从一个没有旧 cache 的受控客户端真实下载并核对字节。

## `.gitattributes` 选择路径，本机配置执行程序

典型属性规则如下：

```gitattributes
*.psd filter=lfs diff=lfs merge=lfs -text
*.blend filter=lfs diff=lfs merge=lfs -text
```

`.gitattributes` 会进入提交，告诉 Git 哪些路径选择名为 `lfs` 的 driver。真正的 `clean`、`smudge` 或长运行 `process` 命令来自本机 Git 配置；clone 不会把源仓库的 `.git/config` 复制给新仓库。Git LFS 客户端通常还安装 `pre-push` hook，在 Git 引用更新前上传需要的 payload。

这形成一条重要的安全边界：tracked 文件可以选择一个 filter 名称，但不能单独让 Git 凭空执行同名程序；客户端或组织工具必须先安装本地配置。不过，一旦本机预先配置了某个 driver，打开不受信任仓库并执行 checkout/add 仍可能触发程序。应把 LFS 客户端、hook 管理和[不受信任仓库](../part-10/05-untrusted-repositories.md)策略一起治理。

在准备采用 LFS 的测试 clone 根目录，先观察而不修改：

```bash
git --version
git lfs version
git lfs env
git check-attr -a -- assets/model.psd
git config --show-origin --get-regexp '^(filter\.lfs\.|lfs\.)'
```

前置条件是路径已经存在于候选 tree，且当前身份有读取仓库配置的权限。`git lfs env` 和 config 输出可能包含内部 endpoint、本机路径和代理线索，应限制日志访问并脱敏。`check-attr` 显示该路径实际命中的属性；config 查询没有匹配时退出 1，不表示 Git 本身损坏。

若第二条出现类似 `git: 'lfs' is not a git command`，停止水合、迁移和 push 演练。按组织批准的渠道安装受支持客户端，再在一次性 clone 中检查版本和签名。`git lfs install --local` 会修改当前仓库配置并处理 hook，不应在未知 hook 管理方案的生产仓库盲目执行；先检查 `core.hooksPath`、现有 `pre-push` 和团队的 hook 组合方式。

### Clean、smudge 与 process 改变哪一层

- `clean` 在 `git add` 等 Git 收集路径内容时，把工作区 payload 写入本地 LFS cache，并向 Git 输出 pointer；它本身不等于 payload 已上传远端。
- `smudge` 在 checkout 等写工作区时，读取 pointer，必要时从 LFS 服务取得 payload，再向工作区输出原始字节。
- `filter-process` 是 Git 的长运行过滤协议，可在一个进程中处理多个路径和延迟 checkout；它优化交互方式，不改变 pointer/payload 的责任边界。
- `filter.lfs.required=true` 要求 driver 失败时 Git 操作失败，避免把本应转换的内容悄悄当作普通 blob 继续。不要为了让 CI 变绿而全局改成非 required；应显式选择是否跳过 smudge，并在使用 payload 前设置水合门禁。

不要手抄一组 `filter.lfs.*` 命令冒充完整安装。不同 Git LFS 版本可能选择 process、clean/smudge 和 hook 的不同组合；以客户端的 `install`、`env` 与当前手册为准。

## 开始跟踪只影响之后进入 index 的内容

在干净的测试分支根目录，确认 pattern 与目标文件后可执行：

```bash
git lfs track --lockable '*.psd'
git diff -- .gitattributes
git check-attr filter diff merge lockable -- assets/model.psd
git add .gitattributes
git diff --cached -- .gitattributes
```

第一条修改或创建 `.gitattributes`，这里还给匹配路径增加 `lockable` 属性；它不会上传文件、不会自动提交，也不会重写过去的 blob。预期 diff 是一条明确的属性规则，`check-attr` 应显示目标路径命中 `filter: lfs` 等属性。Pattern 由 attributes 规则解释，包含 `*`、`?` 或 `[]` 的字面文件名应使用 `git lfs track --filename`，不能依赖 shell 和 attributes 的双重猜测。

对已经被 Git 跟踪、但只需要从“下一次提交”开始转换的当前文件，可在确认选择范围后重新规范化：

```bash
git add --renormalize -- 'assets/*.psd'
git diff --cached --stat
git diff --cached -- .gitattributes 'assets/*.psd'
git lfs status
```

命令会改变 index：匹配文件的 staged blob 应从原始字节变为 pointer。路径很多时，先在副本缩小 pathspec；错误 pattern 可能一次转换数千个文件。中止提交前可用 `git restore --staged -- <paths>` 让 index 回到 HEAD，但工作区和新产生的本地 LFS cache 可能仍存在；不要用 `git clean` 或 `git lfs prune` 作为第一反应。

即使当前版本已经转换，历史里的旧 Git blob 仍然存在，仓库也不会立即缩小。若目标是重写过去的版本，必须进入单独的迁移项目，而不是继续扩大本次普通提交。

## Git 传输与 LFS 传输是两条路径

把命令按状态变化拆开，故障会清楚得多：

| 操作 | Git objects/refs | LFS cache | 工作区 |
| --- | --- | --- | --- |
| `git fetch` | 取得 commit/tree/pointer blob，更新选定远程跟踪引用 | 通常不等价于取得所有 payload | 不改工作区 |
| `git lfs fetch <remote> <ref>` | 不移动 Git refs | 下载 ref 所需 payload | 不改工作区 |
| `git lfs checkout` | 不移动 refs/index | 只使用本地已有 payload | 用可用 payload 替换缺失文件或同 OID pointer，不覆盖已修改文件 |
| `git lfs pull` | 以当前 ref 为范围组合 LFS fetch 与 checkout | 下载 | 水合可安全更新的路径 |
| `git push` + 正常 LFS pre-push | 尝试更新远端 Git refs | 先上传相应 payload | 不改工作区 |

普通 clone 在客户端已安装 LFS 且允许 smudge 时，checkout 可能边检出边下载；显式设置 `GIT_LFS_SKIP_SMUDGE=1` 时，工作区可以暂时保留 pointer。这是合法的受限工作流，但任何真正读取二进制的构建步骤之前必须水合。

### 一个可审计的 CI 水合门禁

以下流程是模板，不是本地已运行的真实 LFS 输出。前置条件是 CI 使用一次性目录、安装了经批准的 Git LFS 3.7.1 或组织支持版本、Git 候选 commit 已由上游事件固定、凭据只有读取 LFS 所需权限，并且 job 不复用未知来源的 `.git/lfs` cache。

```bash
candidate_oid="$CI_CANDIDATE_OID"
test -n "$candidate_oid"
git rev-parse --verify "$candidate_oid^{commit}"

GIT_LFS_SKIP_SMUDGE=1 git checkout --detach "$candidate_oid"
git lfs fetch origin "$candidate_oid"
git lfs checkout
git lfs fsck --objects "$candidate_oid"
git status --porcelain=v1
```

在仓库根目录执行。Checkout 会把 HEAD 移到精确候选；fetch 只填充 LFS cache；checkout 再把本地已有 payload 写入工作区；fsck 检查目标 revision 的本地 LFS 对象。最后一条应无输出，但“干净”只表示 filter 规范化后的工作区与 index 一致，不证明远端备份完整。

对构建真正使用的每个关键文件，还应把以下证据写入制品清单：候选 commit OID、仓库路径、pointer blob 的 Git OID、pointer 中的 payload SHA-256/size、实际水合字节的 SHA-256/size、Git/Git LFS 版本和 LFS endpoint 身份。若实际摘要或长度与 pointer 不符，立即停止构建并隔离 cache；不要重新上传当前工作区字节“修复”一个来源不明的对象。

失败要按层分流：

- `git rev-parse` 失败：Git 候选未取得或事件传入错误，不是 LFS 故障；
- `git lfs fetch` 返回未授权、对象不存在或传输错误：保留 endpoint、OID、HTTP/SSH 错误和 request ID，检查凭据、对象保留与服务状态；
- `git lfs checkout` 后仍是 pointer：检查 fetch include/exclude、`.gitattributes`、本地 cache 和文件是否被修改；
- `git lfs fsck` 失败：隔离损坏 cache，从可信远端重新取相同 OID；远端也缺失时转入恢复流程；
- `git status` 有修改：不要直接 `git add` 掩盖差异，先比较 pointer OID、工作区摘要和 filter 配置来源。

CI cache 只能加速，不能成为唯一副本。Cache key 至少包含仓库/服务边界和可信输入，来自 fork 或不受信任分支的 cache 不应覆盖受信发布任务使用的 LFS 对象。

## 锁是协调记录，不是二进制合并算法

`git lfs track --lockable` 可把路径标为需要锁定，`git lfs lock <path>` 在 LFS 服务创建锁记录，`git lfs unlock <path>` 删除记录。官方锁 API 按仓库路径创建、列出、验证和删除锁；客户端 pre-push 可以查询“ours/theirs”并拒绝修改他人锁定路径的 push。

这不等于 Git commit 不能在本地产生，也不保证所有入口都执行相同检查。强制程度取决于客户端 hook、`lfs.<url>.locksverify`、服务端实现、权限和管理员绕过能力。自动化账号、镜像工具、Web 上传和旧客户端都应纳入测试矩阵。

适合锁的对象通常不可有意义合并且编辑成本很高，例如场景文件或设计源文件。治理流程还要定义：锁的所有者身份、时限、交接、离职清理、管理员强制解锁、网络中断和紧急修复。把所有大文件都设成 lockable 会把并行开发转化为排队系统。

在真实服务验证锁时，使用一次性项目和两个测试身份：身份 A 锁定路径，身份 B 分别测试列锁、编辑和 push，A 解锁后再重试。记录客户端版本、endpoint、权限、返回状态和服务端审计事件。本地 bare 仓库不能证明这套 API、身份映射或强制策略成立。

锁 API 支持情况、强制语义、配额、带宽、单文件限制、保留和计费都属于厂商易变事实。本书不固化数字；采用前必须在[事实登记表](../../docs/FACT-REGISTER.md)按产品、版本/套餐、权限和核对日期登记。

## 历史迁移是一项协作事故级变更

`git lfs migrate import` 默认会把匹配 Git blobs 改成 pointer，并重写 commit OID；tag、签名、评审引用、CI cache、发布清单、fork 和开发者本地分支都可能失去原对应关系。`--everything` 扩大扫描范围，但不会替团队定义哪些隐藏 refs、平台 refs 或外部镜像属于迁移范围。

迁移应在专用普通 clone 中分阶段进行：

1. 冻结写入或建立明确 cutover，记录所有远端、refs、tags、隐藏 refs 获取方式和当前 OID；
2. 备份 Git 对象与已知 LFS payload，并完成一次独立恢复测试；
3. 在只读盘点阶段运行 `git lfs migrate info --everything --pointers=follow`，记录扫描范围、文件类型、数量和体积；
4. 用明确 `--include`/`--exclude` 和 refs 范围在可销毁 clone 演练，输出 old-to-new object map；
5. 验证新 refs、tree 内容、`.gitattributes`、pointer、所有所需 payload、构建与发布证据；
6. 让仓库所有者、安全、制品/备份负责人共同批准；
7. 在维护窗口按每个 ref 的预期旧 OID 条件更新远端，上传 LFS payload，再重建平台索引、CI cache 和开发者 clone；
8. 保留旧映射和只读恢复副本到既定期限，监控缺失 OID 与旧历史继续写入。

盘点命令会扫描大量历史，通常还会刷新远端 ref 列表；应在副本或低峰运行。`info` 不重写 refs，但它的默认范围不等于 `--everything`，报告必须保存完整命令。

正式演练可类似：

```bash
git lfs migrate import --everything \
  --include='*.psd,*.blend' \
  --object-map="$migration_evidence_dir/object-map.csv"
```

前置条件是工作区干净、变量指向仓库外受控证据目录、所有相关 refs 已盘点且 payload 服务可用。命令修改本地 refs、提交、tree、`.gitattributes` 和工作区，不修改远端；成功输出中的进度和 OID 随仓库而变，不能硬编码成测试断言。

如果范围、磁盘、对象或属性规则不符合预期，停止并丢弃整个演练 clone，从保存的原始 refs 重新开始。不要在同一 clone 上用一连串反向迁移猜测恢复。未推送前，权威恢复来源应是迁移前不可变备份；推送后则按已批准 cutover 方案恢复 refs 和 payload，不能只把主分支 force-push 回去。

`git lfs migrate import --no-rewrite` 只在当前分支创建新的转换提交，适合从某一点开始采用 LFS；旧 Git blobs 仍在历史里，所以它不是“缩小全部历史”的替代品。

## 镜像 Git 仓库不是 LFS 灾难恢复

`git clone --mirror` 复制 Git refs 和 Git 对象，pointer 会随之进入镜像；它不会因此自动拥有所有 LFS payload、锁记录、配额配置、身份映射或服务端审计日志。普通开发 clone 也可能因 fetch include/exclude、最近窗口、浅历史或 cache prune 只持有一部分 payload。

一套可恢复备份至少定义：

- 哪些 Git refs、隐藏 refs、reflog 或平台对象属于恢复范围；
- 每个范围内 pointer 引用的 LFS OID/size 清单；
- Payload 字节、checksum、存储位置、加密和保留策略；
- LFS endpoint、访问策略、锁记录与管理员恢复流程；
- `.gitattributes`、Git/LFS 客户端兼容矩阵和 hook 配置；
- 恢复到新 endpoint 后如何重写配置、验证权限并从空 cache clone；
- RPO、RTO、所有者、演练日期和缺失对象告警。

`git lfs fetch --all <remote>` 会取得所给 refs 可达的全部 LFS 对象，官方将其定位为备份/迁移用途；但它只是一项采集动作。可见 refs 不一定覆盖服务端全部保留对象，本地目录也没有天然持久性，命令不会备份锁和平台元数据。必须把采集结果复制到受控备份介质，并用清单与恢复演练证明范围。

谨慎对待 `git lfs prune`。官方行为不考虑 reflog，只考虑 commit 和配置的近期/未推送等保留集合；仅由 orphaned commits 引用的 payload 可能被删除。先执行 `git lfs prune --dry-run --verbose`，确认唯一副本和远端，再决定是否用 `--verify-remote`。共享自定义 `lfs.storage` 的多个仓库不应运行 prune。事故取证期和迁移保留期内应暂停自动清理。

## 常见故障的证据顺序

| 症状 | 先收集什么 | 不要先做什么 | 恢复方向 |
| --- | --- | --- | --- |
| 工作区显示三行 pointer | HEAD 中 pointer、attributes、`git lfs env`、skip-smudge、cache | 把 pointer 当真实文件提交回去 | 安装/修复客户端，fetch 后 checkout |
| Checkout 报 smudge/filter 失败 | OID、endpoint、认证错误、`git lfs logs last`、磁盘 | 设置全局非 required 隐藏错误 | 恢复凭据/服务/空间，从可信端重取 |
| Push 缺失 LFS 对象 | pre-push hook、skip-push、目标 endpoint、payload cache | 只 force-push Git ref | 取得正确 payload，先验证再按目标上传 |
| `git fsck` 通过但构建缺文件 | pointer 与 LFS cache/远端清单 | 宣称仓库完整 | 运行 LFS 对象检查和空 cache 下载演练 |
| 两人覆盖同一二进制 | 锁列表、客户端/hook、服务端审计、提交图 | 假设锁会合并内容 | 协调保留版本，修强制入口和锁生命周期 |
| 迁移后旧 clone 继续 push | 旧/新 OID map、保护规则、服务器 refs | 接受混合历史后再整理 | 冻结旧入口，重新 clone/rebase 或明确桥接 |
| 本地 cache 损坏 | pointer OID/size、本地实际摘要、远端可用性 | 用损坏字节覆盖远端 | 隔离 cache，从独立可信副本恢复同一 OID |

诊断日志可能含内部 URL、用户名、令牌获取路径和 request ID，采集后按安全证据处理。若文件涉嫌恶意内容、秘密或个人数据，不要为了验证 hash 把它复制到普通 CI artifact。

## 隔离实验验证了什么

在本书仓库根目录运行：

```bash
./scripts/verify-lfs-pointer-model.sh
```

前置条件是 Bash、Git 2.49 或兼容实现、`awk`、`cmp`、`find`、`grep`、`sed`、`sha256sum` 或 `shasum`、`mktemp` 和可写临时目录。脚本隔离 system/global Git 配置，创建自己的仓库和外部对象目录，退出时只删除该临时目录，不连接网络。

实验用短小 clean/smudge helper 模拟规范的核心边界：两版二进制分别按 SHA-256 存入 Git 之外，commit 只保存三行 pointer；旧外部对象在新提交后仍存在。无 filter 配置的 clone 只得到 pointer；配置 required filter 后，工作区可以恢复原始字节，重新 clean 后仍对应同一个 pointer blob。

随后脚本隔离移走当前 payload，断言 required smudge 的 restore 失败，而 `git fsck --full` 仍通过；把 SHA-256 正确的对象放回后，工作区可恢复并保持逻辑干净。成功时只输出：

```text
LFS pointer model, external object integrity, missing-object failure, and recovery passed.
```

这个 helper 不是 Git LFS 客户端或服务器。实验没有验证 Batch API、认证、pre-push、并发 transfer、锁、平台配额、`git lfs migrate`、远端完整性或性能；这些项目必须在安装真实客户端的专用环境和一次性服务端项目中验证。

## 小结

Git LFS 把“大文件属于哪个版本”和“大文件字节存在哪里”拆成两条证据链。Git commit 保存路径与 pointer，pointer 的 SHA-256/size 约束 payload，filter 再决定工作区是否水合。任何一层存在都不能替另一层背书。

采用 LFS 的完成标准不是仓库里出现 `.gitattributes`，而是选择边界合理、客户端与服务端兼容、CI 在使用前验证 payload、锁有明确强制和回收路径、迁移可协调回退，并且备份能从空 cache 恢复全部承诺范围。做不到这些时，LFS 只会把 Git 仓库的容量问题变成另一个更隐蔽的可用性问题。
