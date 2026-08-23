# 秘密扫描、恶意对象与归档导出：发现不等于净化

把一个文件从当前工作区删掉，并不能回答“秘密是否仍然存在”。它可能还在旧提交、另一个分支、附注、reflog、LFS payload、CI 日志、构建制品、镜像或同事的旧 clone 中。反过来，git fsck 报告对象库结构完整，也不能回答“内容是否适合执行或发布”。

本章建立一条不依赖具体托管平台的判断链：先定义扫描输入，再区分发现结果与凭据有效性；然后检查对象和路径的语义风险，最后把特定提交导出为可核验的归档。归档是一个新副本，不是历史清理；扫描通过是一个观察结果，不是授权或安全证明。

本章以 Git 2.49.0、Bash 和 macOS 为验证基线。Git 版本、文件系统、归档工具、LFS 客户端、CI 平台及套餐权限都会影响实际结果。正文中的 GitHub/GitLab 事实以 2026-08-20 的官方文档为准，部署时必须重新核对。实验只使用 EXAMPLE-... 形式的无效合成字符串。

进入本章前，读者应理解提交图、引用、reflog、LFS pointer、受保护引用和 CI 制品证据链。读完后，你应能：

- 画出一次秘密扫描实际覆盖的输入集合，并指出遗漏的副本；
- 区分工作区扫描、增量扫描、可达历史扫描和取证扫描的发现能力；
- 解释 git fsck 能证明对象结构什么、不能证明内容什么；
- 识别 symlink、超大 blob、压缩包和特殊路径带来的对象语义风险；
- 生成带内容清单、字节摘要和扫描记录的源码归档，并说明它仍不等于历史净化。

## 先定义扫描对象，而不是先选扫描器

“扫描仓库”不是一个单一动作。一个可审计的扫描记录至少要保存四个字段：

1. 输入范围：哪些对象、引用、文件系统副本和外部服务结果被纳入；
2. 检测器：provider-specific pattern、通用规则、熵规则、文件类型规则或人工复核；
3. 发现结果：位置、摘要、置信度、误报状态和访问权限；
4. 处置状态：凭据是否撤销、哪些引用已重写、哪些副本仍未处理。

下面的表把常见输入放在同一张地图上。当前 tree 与完整历史不是可以随意互换的两个叫法：前者回答“现在将被 checkout 或导出的内容有什么”，后者回答“指定 refs 能到达的对象里有什么”。

| 输入 | 典型获取方式 | 能发现什么 | 常见遗漏 |
| --- | --- | --- | --- |
| 工作区与未跟踪文件 | 扫描文件系统；同时检查 git diff、index | 尚未提交的密钥、构建生成物 | 被 .gitignore 忽略的文件、另一个工作树、外部缓存 |
| index 与暂存差异 | git diff --cached，按路径读取 blob | 即将提交的内容 | 工作区未暂存改动、旧提交和其他引用 |
| 当前 commit/tree | 固定 tree-ish 后遍历 git ls-tree/blob | 当前版本将被导出的内容 | reflog、不可达对象、LFS 外部本体 |
| 一次提交的增量 | 比较 base 与 candidate 的 changed paths | 本次变更引入或修改的秘密 | 未变化但已存在的秘密、路径过滤和超时跳过 |
| 所有可达 refs | git rev-list --objects --all | 分支、标签和本地可见引用中的历史对象 | 隐藏服务端 refs、reflog、外部 clone |
| reflog 与取证对象 | git reflog --all、git fsck --unreachable | 本地引用移动记录、暂时不可达对象 | 已过期日志、另一台机器的 reflog |
| notes 与附注 tag | 显式遍历 notes refs、tag 对象和 message | 不在普通文件快照中的说明或签名 payload | 只扫描 commit tree 的脚本 |
| LFS payload | LFS cache、LFS API、备份清单 | pointer 指向的真实二进制 | 只跑 Git fsck；只扫 pointer 文本 |
| CI 日志、artifact、cache | 构建平台 API 或归档清单 | 运行时打印的 token、生成的配置 | 只扫描源码仓库；过期或跨项目副本 |
| bundle、mirror 与旧 clone | 逐个收集并扫描副本 | 仍可重新推送的旧历史 | 只清理当前主仓库的 refs |

### 结果不能自动成为秘密

扫描器发现一个高熵字符串，只能说明它匹配了规则。处置者还要在不把值扩散到聊天、日志或 issue 的前提下核对：

- 这是凭据、测试 fixture、哈希、证书公钥，还是普通随机数据？
- 它的签发器、受众、权限和到期时间是什么？
- 能否在签发器或服务端以 key ID、指纹或时间窗口验证它，而无需再次打印秘密值？
- 是否已有使用记录、访问日志和下游复制品？

验证真实凭据的首要动作是撤销或冻结，不是把它复制到另一个扫描器。结果存储也要最小化：保存位置、规则 ID、摘要、状态和责任人；原始片段仅在受限事故系统中保存，不能写进公开 CI 日志。

## 四种扫描模式，各自回答不同问题

### 工作区与暂存区扫描：提交前门禁

开发者在仓库根目录执行以下检查时，扫描的是当前磁盘状态和即将写入 index 的内容：

~~~bash
git status --short
git diff --cached --name-status -z
git diff --name-only -z
~~~

前提是当前目录属于目标仓库，且输出不会直接进入公开日志。--name-only -z 使用 NUL 分隔路径，调用脚本必须逐项解析，不能按换行拆分。命令只观察，不改变工作树或 index。扫描器失败时先保存差异和路径清单，再区分“无法读取”“规则超时”和“确认发现”；不要用 git reset --hard 清理扫描失败。

### 增量 diff 扫描：快速反馈，不是历史审计

合并请求给扫描器一个 base 与 candidate 时，先固定对象 ID：

~~~bash
base_commit="$(git rev-parse --verify origin/main^{commit})"
candidate_commit="$(git rev-parse --verify HEAD^{commit})"
git diff --name-status -z "$base_commit" "$candidate_commit"
git diff --binary "$base_commit" "$candidate_commit" --
~~~

这里的 origin/main 只是本地最近一次 fetch 的远程跟踪引用；CI 应使用事件 payload 或合并队列产生的精确候选。增量扫描有两个盲点：秘密可能早已存在于 base、这次 diff 没有变化；路径过滤、二进制上限和超时也会使结果不完整。把“本次 diff 未发现”写成“仓库没有秘密”是错误的安全结论。

### 可达历史扫描：回答“指定 refs 里有什么”

在审计 clone 中先列出要纳入的 refs，再固定它们：

~~~bash
git for-each-ref --format='%(refname) %(objectname)' > refs.snapshot
git rev-list --objects --all > reachable-objects.snapshot
git fsck --full --no-progress
~~~

前两条保存引用和可达对象清单，第三条验证对象数据库结构。对实际内容，扫描器应按对象清单取 blob，也应单独处理 commit message、tag message、notes 和路径名。--all 来自本地 refs 集合；隐藏服务端 refs、已删除 review refs、reflog 和平台 artifact 不会自动进入扫描。报告必须记录 ref 快照时间以及 clone 是否为 mirror。

### 取证扫描：reflog、不可达对象和外部副本

发现泄漏后不要立即过期 reflog 或运行激进清理。先在证据副本中收集：

~~~bash
git reflog --all --date=iso > reflog.snapshot
git fsck --full --unreachable --no-progress > unreachable.snapshot
git count-objects -vH > object-count.snapshot
~~~

这些命令保存本地引用移动、当前可发现的不可达对象和对象库统计。结果受 reflog、替代对象库、最近 GC 和配置影响；它不是服务端全量对象清单。取证副本应只读或写保护，输出权限要限制，因为 reflog message、路径和对象内容本身可能含敏感数据。

## 扫描器会漏什么

provider pattern、通用 token pattern、熵规则和上下文启发式各有边界：

- provider pattern 可能只识别已知前缀，无法识别自建系统或新版本 token；
- 熵规则会把压缩数据、哈希、随机测试值报成误报；
- 短 token、密码、编码、分片和运行时拼接可能绕过静态匹配；
- 二进制、超大 diff、超长路径和扫描超时可能被跳过或只生成事后告警；
- 规则通常不会执行每个 secret 的在线验证，扫描器也不应为了验证而泄漏值。

策略要把“阻止”“告警”“人工复核”“跳过且留痕”分别定义。绕过 push protection 的理由、操作者、候选提交和后续处置都必须进入审计。

### GitHub 与 GitLab 的平台边界（核对日：2026-08-20）

GitHub 的 secret scanning/push protection 是托管平台控制面：目标是在秘密进入仓库前阻止或告警，但支持的 provider/generic 模式、组织/企业配置、权限和套餐不同。超大 push、超时、路径数量和 bypass 情形不能被本地 Git 语义替代；push protection 不是完整历史扫描，也不自动清理 artifact、日志或旧 clone。

GitLab 的 pipeline secret detection 默认围绕当前状态和未来提交工作；首次启用完整历史需要单独 historic scan，浅克隆可能需要取得完整历史。secret push protection 在 pre-receive 阶段拦截支持的高置信模式，但二进制、超大 diff、超时和“旧文件未在本次 diff 变化”等情况仍是边界。JSON report artifact 又会形成新的副本，必须纳入访问控制和保留治理。

平台事实的版本、权限和套餐必须按实际部署登记。平台绿色状态只说明某个平台检查返回了某种结果，不等于 Git 对象库、LFS 服务、CI cache、镜像和发布制品都已扫描。

## 恶意对象是内容安全问题，不是完整性问题

Git 的对象 ID 可以发现对象字节被替换；git fsck --full 可以检查对象格式、连接关系和引用可达性。两者都不理解“这个文件打开是否安全”“这个 symlink 是否越出导出目录”“这个压缩包解开会占满磁盘”。

### git fsck 能证明什么

~~~bash
git fsck --full --no-progress
git fsck --full --connectivity-only --no-progress
~~~

--full 会验证对象内容和连通性；--connectivity-only 重点验证对象之间的引用关系，不做完整 blob 内容检查。命令成功表示当前检查范围内没有被检测到的对象格式或连接错误，不表示没有秘密、恶意脚本、路径穿越、恶意压缩内容或可利用的依赖。

发现 missing、dangling 或损坏对象时，先停止 prune、repack 和发布，保存 Git 版本、refs、替代对象库配置和完整输出。不要把 fsck 输出直接贴到公开 issue；OID、路径和 commit message 可能泄漏调查信息。

### 路径、symlink、超大 blob 和压缩内容

扫描 tree 时至少记录 mode、路径、对象类型和字节数：

~~~bash
candidate="$(git rev-parse --verify HEAD^{commit})"
git ls-tree -r -z --full-tree "$candidate" > tree.snapshot
git ls-tree -r --full-tree "$candidate" | awk '$1 == "120000" || $1 == "160000" {print}'
git cat-file --batch-all-objects --batch-check='%(objectname) %(objecttype) %(objectsize)' > objects.snapshot
~~~

120000 通常表示 symlink，160000 是 submodule gitlink；它们不是普通文件。自动化解析 tree.snapshot 必须使用 NUL 分隔格式。对象大小检查用于发现异常大 blob 和资源耗尽输入，但不能单凭阈值判断恶意。解压、转换和编译必须在临时文件系统、CPU/内存/文件数限制和无生产凭据环境中完成，并拒绝绝对路径、.. 路径和不安全 symlink。

对象到达不等于程序执行，但构建、checkout、归档解析或递归依赖一旦启动，内容安全就超出 fsck 的职责。上一章的不受信任仓库边界、filter、hook、submodule 和 CI 权限必须一并审计。

## git archive 只导出一个 tree

源码发布常常需要把某个精确提交的文件打成 tar/zip。git archive 读取指定 tree，不把 .git 目录写进归档；它不会重写历史，也不会访问 LFS 服务取得 pointer 对应的 payload。

### export-ignore 的工作定义

~~~gitattributes
private/ export-ignore
*.local export-ignore
docs/INTERNAL-NOTE.txt export-ignore
~~~

export-ignore 只影响 git archive 是否把匹配路径放入当前导出。默认属性来自被归档 tree 中的 .gitattributes；--worktree-attributes 才读取工作树版本，$GIT_DIR/info/attributes 也能提供本地规则。用 git check-attr --source=<tree-ish> 可以检查指定提交的属性：

~~~bash
git check-attr --source="$candidate" export-ignore -- \
  private/ docs/INTERNAL-NOTE.txt
git archive --format=tar --output=source.tar "$candidate"
~~~

第一条只读取属性，第二条生成新归档；归档输出应放在仓库外的临时目录，避免把它再次纳入扫描输入。--worktree-attributes 适合一次性试验，却会让未提交属性改变影响产物。发布系统应固定提交中的属性，并把工作树属性差异记录为阻断条件。

### 归档不是净化

即使归档扫描没有发现秘密，也只能得出“该提交 tree 生成的这一个字节副本未匹配当前规则”。旧 commit、tag、review ref、bundle、LFS payload、CI 日志、artifact、镜像层和旧 clone 仍可能含有相同内容；归档中的合法脚本、symlink 或压缩包也仍可能有下游风险。

对外发布前至少保存：源 commit OID、归档文件 SHA-256、归档路径清单、export-ignore 检查、秘密扫描版本/规则集、symlink 与路径安全检查、发布者和时间。消费者应能据此确认“下载的字节就是扫描过的那一份”。

## 副本治理：archive、bundle、mirror 和 artifact 不同

| 副本 | 保留内容 | 是否可能保留旧历史 | 处置重点 |
| --- | --- | --- | --- |
| source archive | 某个 tree 的文件字节 | 通常不含 .git 历史 | 固定 tree、属性、清单、摘要和内容扫描 |
| bundle | refs 可达的 Git 对象 | 是，取决于创建的 refs | 清理 refs 后重新生成 |
| mirror clone | refs、对象和远程映射 | 是，可能含额外 refs | 按 ref 快照和对象库扫描 |
| CI artifact/log/cache | 构建输入、输出或运行日志 | 经常是 | API 清点、最小权限、删除/过期、重新构建 |

force push 只更新指定服务端引用；旧 bundle、镜像、artifact 和开发者 clone 仍能重新引入旧对象。历史清理、凭据撤销和副本销毁必须分别登记负责人和完成证据。

## 一次可审计的导出流程

### 1. 固定候选并保存环境

~~~bash
candidate="$(git rev-parse --verify 'refs/tags/vX.Y.Z^{commit}')"
git --version
git show --no-patch --format='%H%n%T%n%P%n%s' "$candidate"
git check-attr --source="$candidate" export-ignore -- .
~~~

标签名、提交 OID 和属性结果要写入构建证据。若标签可移动，先从可信事件取得 OID，再比较服务端当前值；不要把“名字相同”当成候选相同。

### 2. 生成归档、清单和摘要

~~~bash
export_root="$(mktemp -d "${TMPDIR:-/tmp}/git-export.XXXXXX")"
archive_path="$export_root/source.tar"
git archive --format=tar --output="$archive_path" "$candidate"
tar -tf "$archive_path" > "$export_root/archive.paths"
case "$(uname -s)" in
  Darwin) shasum -a 256 "$archive_path" ;;
  *) sha256sum "$archive_path" ;;
esac
~~~

命令在审计 clone 执行，归档写到临时目录。tar -tf 只列条目，不解压。路径检查至少拒绝绝对路径、../、NUL、意外 symlink 和超过组织上限的单项/总大小。扫描器失败、超时或无法识别格式时，状态应是 inconclusive，而不是 clean。

### 3. 不通过时从源对象重新生成

若归档含不应发布的路径，修正源提交中的 .gitattributes、发布 tree 或构建输入，然后从原始候选重新生成。不要在已生成 tar 上删除文件后继续沿用原摘要，也不要把临时 --worktree-attributes 修改当作历史修复。发现秘密时先撤销，再按本篇第一章的全 refs 清理和副本治理流程处置。

## 合成实验：扫描范围与导出边界

本书提供 scripts/verify-secret-scanning-and-exports.sh。实验只在 mktemp 目录创建本地仓库和文件，不连接网络、不调用托管平台、不使用真实 token。运行前提是 Bash、Git 2.28+、tar、awk、grep 和 shasum 或 sha256sum。

在仓库根目录执行：

~~~bash
bash scripts/verify-secret-scanning-and-exports.sh
~~~

脚本验证：合成标记在旧提交、tag、branch、notes、reflog、文件名和外部副本中仍可发现；当前 tree 初筛与全 refs 扫描不同；git fsck 通过但语义扫描仍发现标记、symlink 和大 blob；默认 archive 遵守提交中的 export-ignore，--worktree-attributes 反映未提交属性；bundle clone 仍带旧历史；最后保存归档清单、摘要和扫描结果。任一检查失败都从候选 tree 重新生成，而不是修改旧输出。

脚本结束自动删除临时目录。中途失败时它会停止；要调查应把整个临时目录复制到权限受限的证据位置，不能上传公开日志。实验不模拟 GitHub/GitLab push protection、historic scan、LFS API、CI artifact 保留或真正压缩炸弹防护，这些能力必须在对应平台和隔离安全环境中另行验收。

## 小结：五个不能混淆的结论

1. 发现范围决定扫描结果能说什么；当前 diff 未发现，不等于历史、reflog 或副本没有。
2. 秘密有效性由签发器和服务端状态决定；扫描器不应打印或滥试秘密。
3. 对象完整性由 OID、fsck 和连接性检查帮助判断；它不替代恶意内容和资源耗尽防护。
4. 归档导出只产生指定 tree 的新副本；export-ignore 不删除 Git 历史，不清理 LFS payload，也不处理 CI artifact。
5. 净化完成必须有凭据撤销、全 refs/副本清点、重新生成的输出、内容扫描和可复核摘要共同证明。

下一章将把这些证据接入取证与灾难恢复：当对象已不可达、远端不可用或历史清理需要迁移时，先保护现场，再决定哪些对象可以恢复、哪些副本必须销毁。

## 资料与核对日期

- Git 官方：[git-fsck](https://git-scm.com/docs/git-fsck)、[git-archive](https://git-scm.com/docs/git-archive)、[gitattributes](https://git-scm.com/docs/gitattributes)、[git-check-attr](https://git-scm.com/docs/git-check-attr)、[git-prune](https://git-scm.com/docs/git-prune)，核对日期 2026-08-20。
- GitHub 官方：[Push protection](https://docs.github.com/en/code-security/concepts/secret-security/push-protection)、[Supported secret scanning patterns](https://docs.github.com/en/code-security/reference/secret-security/supported-secret-scanning-patterns)，核对日期 2026-08-20；权限、套餐和限制以实际版本为准。
- GitLab 官方：[Pipeline secret detection](https://docs.gitlab.com/user/application_security/secret_detection/pipeline/)、[Secret push protection](https://docs.gitlab.com/user/application_security/secret_detection/secret_push_protection/)、[Secret detection overview](https://docs.gitlab.com/user/application_security/secret_detection/)，核对日期 2026-08-20；具体版别和报告保留策略以实际部署为准。
