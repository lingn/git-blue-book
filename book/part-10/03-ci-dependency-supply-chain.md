# 流水线配置也是代码：第三方 CI 依赖与来源证明

项目源码没有变化，昨天通过的构建今天却执行了另一版 Action；workflow 固定到了精确 commit，但 Action 运行时又从 `main` 下载脚本；容器写着 `builder:1.4`，同名 tag 已被替换；一个来自外部贡献者的 job 写入共享 cache，生产发布稍后把它当成可信工具链恢复。此类事故不发生在 Git 提交图内部，却由 Git 仓库中的 CI 配置把外部代码引入高权限执行环境。

“流水线已经版本化”只说明入口文件属于某个 tree，不说明入口解析出的第三方模板、Action、插件、镜像、包、在线脚本、runner 镜像和 cache 具有不可变身份。可靠的供应链控制必须保存两类值：人选择的 selector，以及执行器当时解析得到的精确对象或内容摘要。只记录 `v4`、`latest`、`main` 或下载 URL，无法在复盘时证明实际执行了哪些字节。

进入本章前，读者应理解 Git 引用与对象 ID、CI 候选提交和流水线证据链、最小权限机器身份、对象签名，以及不受信任仓库何时进入执行链。读完后，应能盘点流水线的直接与传递依赖；区分名称、解析结果、实际字节和来源证明；为 Action、复用 workflow、远程模板、镜像和在线工具选择固定策略；建立可审查更新与回退流程；并在依赖失陷时界定受影响的 run、凭据、cache、制品与发布。

本章 Git 实验在 Git 2.49.0 和 macOS 上验证。平台事实按 GitHub.com Actions 与 GitLab CI/CD 当前官方文档核对于 2026-08-20；SLSA 参考版本为 1.2，OCI Image Spec 参考版本为 1.1.1。自托管平台、套餐、策略权限、执行器解析规则和保留期可能不同，实施前必须复核 `docs/FACT-REGISTER.md` 与当前产品文档。本地实验不启动第三方脚本、不访问网络，也不伪造平台 token、runner、cache 或 attestation。

## 一条 `uses` 或 `include` 背后的完整状态链

把“CI 依赖”只理解成 YAML 中的一行，会漏掉解析和执行之间的变化：

```text
候选提交中的配置
  -> selector：仓库 + branch/tag/version/URL
  -> resolver：平台、包管理器、容器运行时或自定义下载器
  -> resolved identity：commit OID / content digest / package version
  -> fetched bytes：实际进入 runner 的脚本、镜像、包或模板
  -> transitive inputs：依赖再次解析或运行时下载的内容
  -> execution context：token、secrets、文件系统、网络、cache 与 runner
  -> outputs：检查结果、cache、artifact、制品和 provenance
```

Selector 表达维护意图，例如“兼容 v4”“使用 1.2 系列”；resolved identity 表达这一次实际选择，例如精确 Git commit 或 OCI digest。前者便于更新，后者用于复现和取证。系统可以允许人在配置中使用版本范围，但必须在执行前生成可验证的解析快照，并确保后续 job 不再重新解析到别的内容。

固定精确 commit 也只覆盖该仓库对象。若脚本随后运行包管理器、`curl | sh`、读取浮动容器 tag 或调用另一个复用 workflow，传递输入仍可漂移。所谓“已固定”必须说明固定到了哪一层。

## 先建立依赖清单，不从某一种 YAML 语法出发

不同平台名称变化很快，工程风险却可以归入稳定类别：

| 依赖类别 | 常见 selector | 可核对的精确身份 | 仍需追踪的边界 |
| --- | --- | --- | --- |
| Git 型 Action/plugin | branch、tag、短/完整 commit | 来源仓库中的完整 commit OID、tree/blob OID | Action 内包裹的运行时与下载 |
| 复用 workflow/远程模板 | branch、tag、版本、URL | 配置 commit、内容 SHA-256、解析后配置摘要 | 嵌套 workflow、secret 与权限传递 |
| 容器镜像 | tag、semver、`latest` | OCI manifest/index digest | 多架构选择、基础层、entrypoint |
| 语言包与工具 | 版本范围、包名、下载 URL | lockfile 版本、registry integrity、制品摘要/签名 | lifecycle script、传递包、registry 来源 |
| Runner 与 bootstrap | 镜像标签、池名称、在线安装器 | runner image digest、初始化脚本摘要、工具链清单 | 宿主机、内核、挂载、预装软件 |
| Cache 与跨 job artifact | cache key、artifact 名称 | 内容摘要、生产 run/job、schema 与保留记录 | 写入者信任级别、fallback 与覆盖策略 |

SBOM 主要回答产物包含什么；CI 依赖清单要回答构建过程中信任并执行了什么。二者相交但不相同：一个只影响测试编排的 Action 可能不进入产品 SBOM，却能读取源码、修改制品或窃取发布凭据。

### 从精确候选对象读取入口

在已经取得候选对象、且不执行其内容的审计 clone 中，先固定候选：

```bash
candidate_oid="$(git rev-parse --verify "${CI_CANDIDATE_OID:?}^{commit}")"
git show --no-patch --format='commit=%H tree=%T parents=%P' "$candidate_oid"
git grep -n -I -E \
  'uses:|include:|image:|curl[[:space:]]|wget[[:space:]]' \
  "$candidate_oid" -- .github/workflows .gitlab-ci.yml .ci
```

前置条件是 `CI_CANDIDATE_OID` 由调度证据提供，而不是现场重新解析的分支名。第一条只解析已存在 commit；第二条读取 commit/tree/parents；第三条对约定 CI 路径做初筛，不 checkout、不修改 refs、index 或工作区。对象不存在或不是 commit 时立即失败；`git grep` 返回 1 也可能只是没有匹配，不能据此断言“没有外部依赖”。变量插值、生成配置、组织模板、平台应用、容器 entrypoint 和构建脚本中的下载仍需从平台解析结果与实际进程/网络证据补齐。

任意 Git 路径可以包含换行等特殊字节。需要自动生成清单时，应使用 `git ls-tree -rz`、`git grep -z` 等 NUL 接口，并用支持 NUL 的程序解析；上面的逐行输出只用于受控路径的人工作业，不是任意仓库扫描器。

## 名称方便更新，内容身份负责执行

### Git branch 和 tag 都可以移动

`owner/action@v4` 看起来像一个发布版本，但 Git tag 是否可移动取决于服务端权限和治理；branch 本来就用于移动。上游账号被攻陷、维护者误推或服务端允许强制更新时，同一 selector 可以解析到不同 commit。

截至 2026-08-20，GitHub.com 的 secure-use 官方文档把完整 commit SHA 描述为当前唯一能把第三方 Action 当作不可变 release 使用的方式，并要求核实该 SHA 来自目标 Action 仓库而不是 fork；同一文档说明仓库/组织可配置强制完整 SHA 的策略。GitHub 对第三方 reusable workflow 同样允许 SHA、release tag 或 branch，并把 commit SHA 称为稳定性与安全性最好的选择。这是 GitHub Actions 解析与控制面事实，不是所有 CI 产品的通用语法。

精确 OID 解决“同一名字后来指向不同对象”，没有解决：

- 最初选中的 commit 本身包含恶意或脆弱代码；
- Commit 来自同 OID 可见的错误 fork/来源，评审没有核对上游归属；
- 上游删除仓库或对象，平台无法再取得 pinned dependency；
- Action 的传递依赖和运行时网络输入没有固定；
- 执行 job 给了它不必要的 token、secret、Docker socket 或共享目录；
- 更新机器人把新 OID 自动合并，绕过了源码与权限变化评审。

因此固定与更新是一对控制：运行必须使用精确身份，升级必须由自动化提出 old/new identity 和差异，再由所有者评审。不要为了“自动获得安全修复”让生产每次执行都跟随 `main`；应缩短更新延迟，而不是取消变更门禁。

### 解析远端 Git selector 会改变审计仓库

在一次性、无生产凭据的审计目录中，可以取得一个已批准 URL 与 selector：

```bash
audit_root="$(mktemp -d "${TMPDIR:-/tmp}/ci-dependency-audit.XXXXXX")"
dependency_url=https://example.invalid/owner/dependency.git
dependency_selector=refs/tags/v4

git init --bare "$audit_root/dependency.git"
git --git-dir="$audit_root/dependency.git" fetch \
  --no-tags "$dependency_url" "$dependency_selector"
resolved_commit="$(git --git-dir="$audit_root/dependency.git" \
  rev-parse 'FETCH_HEAD^{commit}')"
printf 'resolved_commit=%s\n' "$resolved_commit"
```

示例 URL 不可访问，执行前必须从批准清单替换，不能直接使用候选提交提供的任意 URL。`fetch` 会连接远端，把可达对象写入一次性 object database，并更新 `FETCH_HEAD`；`rev-parse` 把 branch、轻量 tag 或附注 tag 剥离为 commit。输出 OID 随上游状态变化，正是要写入依赖锁和审计记录的值。

DNS、TLS/SSH、认证、权限、selector 不存在或对象类型错误都会失败。失败时保留 URL、selector、时间和错误阶段，不切换到“最新可用”版本。若解析结果不等于已批准 OID，停止执行并调查引用变化；恢复方式是使用仍可取得的已知良好 OID/内部镜像，或通过独立更新评审批准新对象，而不是强推上游 tag 迎合本地锁。

审计目录含未信任对象，结束后应销毁；若需要长期可用性，将审核过的对象或归档同步到只允许受控写入的内部镜像，并记录来源映射。镜像能降低上游删除风险，也会产生补丁同步、漏洞响应和保留责任。

## 镜像 tag、远程模板与包下载需要各自的 digest

### 容器 tag 不是镜像身份

OCI Image Spec 1.1.1 的 descriptor 使用 digest 和字节数描述目标内容，并要求从不受信任来源取得内容时按 digest 验证。`registry.example/builder:1.4` 是便于发现的名字，`@sha256:...` 才把消费指向内容标识。多架构 image index 与所选平台 manifest 可能有不同 digest，证据要记录执行器实际拉取的 digest 和平台架构，不能只保存 YAML 字符串。

截至 2026-08-20，GitLab 当前 pipeline security 文档也明确建议按 SHA digest 使用 Docker image，而不是 `latest` 等 tag。实现时仍要核对所用 runner 是否确实按 digest 拉取、是否允许本地同名缓存覆盖、镜像签名策略验证哪个 registry identity，以及基础层是否进入来源清单。

Digest 证明“取得的字节等于预期内容”，不证明内容安全、维护者可信或没有漏洞。预期 digest 的来源若可由候选自行修改，校验会变成“攻击者同时提交恶意文件和它的正确摘要”。高权限发布依赖的锁与允许列表要经过独立所有权评审。

### Remote include 必须有内容校验或内部副本

一个裸 HTTPS URL 只固定位置，不固定响应内容。TLS 保护这次连接并验证服务器身份，不能保证该 URL 明天仍返回同样字节。优先把模板放入受控 Git 仓库，以精确 commit 引用；必须使用远程内容时，保存长度、SHA-256、媒体类型和来源，并在解析前校验。

截至 2026-08-20，GitLab 当前 YAML 文档的 `include:integrity` 可为 `include:remote` 指定 Base64 编码的 SHA-256；内容不匹配时不处理远程文件并让 pipeline 失败。这个关键字的可用版本、自托管部署和缓存行为需要在目标实例复核。其他平台即使没有相同语法，也应在下载与 YAML/脚本解析之间设置等价的 fail-closed 校验。

### Lockfile 不是传递依赖完整性的自动证明

Lockfile 可以固定解析结果，但覆盖范围取决于包管理器：是否记录 registry、包摘要、平台可选依赖、Git dependency commit、安装脚本与工具版本都可能不同。禁止在发布流程中无记录删除 lockfile、重新求解或使用 `--no-lock` 一类绕过；也不要因为 lockfile 已提交就跳过 registry 访问、摘要验证和依赖来源审计。

在线安装器尤其危险：`curl URL | sh` 在验证前执行网络响应，无法为这次运行留下可靠的预期内容。若工具必须从 URL 取得，应先下载到隔离文件，校验来自受保护清单的 size/digest/签名，再执行；下载器、CA、重定向目标和解压路径也属于边界。关键工具更适合由受控镜像或制品仓库分发。

## 直接依赖固定后，传递依赖仍会漂移

第三方 Action 可以在自己的 commit 中写死 `nested_selector=main`；容器 entrypoint 可以在线安装最新包；复用 workflow 可以继续调用另一个浮动 workflow。顶层 OID 没变，实际执行闭包仍变化。

依赖清单至少区分：

- **declared dependency**：候选配置直接声明的 selector；
- **resolved dependency**：解析器实际选择的 commit/digest；
- **runtime dependency**：执行期间通过网络、插件发现、动态 import 或包脚本取得的内容；
- **builder dependency**：runner、编排器、镜像、初始化和平台控制面本身依赖的组件。

完全禁止网络是最强但并非总可行。可采用分阶段模型：解析 job 只从允许源取得并校验依赖，输出带摘要的只读依赖集合；构建 job 禁止任意外网，只读取该集合；发布 job 不重新下载或构建，只消费已验证制品。无法隔离时，至少记录 DNS/URL、最终 digest、缓存命中和失败回退，并把未知网络输入视为不可复现因素。

## 第三方代码获得的是整个 job 的能力

Action、plugin 和构建脚本通常在 runner 进程、容器或共享宿主机上运行。平台的“一个 step”不是通用安全边界：它可能读取当前 job 环境、工作区、Git 配置、已注入 secret、token、网络和前序 step 文件，也可能修改后续 step 会消费的输出。

GitHub 当前 secure-use 文档明确警告，单个 Action 被攻陷可能接触仓库 secrets 和使用 `GITHUB_TOKEN`，具体暴露取决于该 job 可见的 secret 与 token permissions；同一 runner 上的 job/容器还可能通过共享目录、环境或 Docker socket 相互影响。因此：

- 不受信任候选的测试 job 不注入发布/生产 secret，源码和 API token 默认只读；
- 第三方依赖只获得当前动作需要的最小文件、网络和 token，不使用宽泛 `secrets: inherit`；
- 签发、发布和部署在独立 job/runner 中进行，不重新执行候选或测试 artifact 中的脚本；
- 自托管 runner 必须按信任域分池，清除持久状态；容器不是宿主机 Docker socket 的安全替代；
- 对外部 Action 的新增与权限扩大，由 workflow/CODEOWNERS 类独立所有者评审。

机器身份和短期 token 的设计见[最小权限机器身份](02-machine-identities.md)。短 TTL 只能缩小有效窗口；若恶意 Action 在窗口内已经取得 token，它仍可完成授权动作。

## Cache 是不可信优化，不是构建输入的权威来源

Cache key 常含 branch、依赖名或版本前缀，并使用 fallback restore。若低信任 job 能写入一个高信任发布 job 会恢复的 namespace，攻击者可以植入编译器缓存、依赖目录、生成脚本或对象文件；即使源代码和 lockfile 没变，构建字节也可能改变。

安全策略包括：

- 不受信任与受信任 job 的 cache namespace、写权限和存储账号分离；
- key 包含精确候选、lock/blob digest、工具链与平台身份，不只包含 branch/tag；
- fallback 命中被视为新输入并记录，不能静默冒充精确命中；
- 从 cache 恢复的可执行内容重新校验，关键发布可选择完全不用外部可写 cache；
- cache 失效只降低性能，不得迫使流程跳过摘要、签名或来源验证；
- 事故中可以按 writer/run/key 隔离和删除，但保留受控证据与访问审计。

跨 job artifact 也不是自动可信。高权限 job 应把低信任 artifact 当数据，核对 producer run、candidate OID、schema、文件清单与摘要，拒绝路径穿越、symlink、额外可执行文件和解压炸弹；不要下载后直接 `source` 或执行其中脚本。

## 来源证明记录事实，验证策略决定是否接受

Provenance 不是一枚“安全”徽章。它应把产物 digest 与 builder、构建定义、外部参数、解析依赖和具体 invocation 连接起来；消费者还要验证签名者、builder identity、仓库/workflow、候选 OID、依赖约束和环境是否符合策略。

SLSA 1.2 build provenance 模型把 `buildDefinition` 与 `runDetails` 分开：`externalParameters` 记录外部可控输入，`resolvedDependencies` 记录构建实际取得的依赖，`builder.id` 表示受信任构建平台边界，顶层 `subject` 标识输出。它还明确指出，运行时取得的 `foo.sh` 与其再取得的 `bar.tar.gz` 在可知时都应进入 resolved dependencies。这个模型适合检验“顶层固定、传递漂移”的缺口。

一份面向本书模型的最小依赖证据可以包含：

```text
candidate_commit
pipeline_config_commit_or_digest
dependency_kind
declared_origin
declared_selector
resolved_identity
content_size_and_digest
transitive_lock_or_manifest_digest
resolver_and_runner_identity
permissions_and_network_policy
review_record
invocation_id
output_subject_digest
attestation_location
```

这些字段必须由可信控制面采集或交叉验证。若候选脚本可以任意填写 provenance，再用同一 job 的密钥签名，格式完整也不能证明记录真实。Attestation 验证成功只证明某个 signer 对 statement bytes 背书；是否接受该 signer-builder pair 和 statement 内容仍由组织策略决定。

## 更新依赖是一项代码与权限变更

成熟更新流程不把“版本机器人提交了一个 SHA”直接等同于安全升级：

1. 解析当前 selector，记录 old exact identity、来源与可用性；
2. 从批准来源解析候选版本，核对 new identity 属于预期仓库/registry；
3. 阅读 old..new 代码、元数据、入口、依赖、权限和网络目标差异；
4. 校验上游签名/attestation、维护者变更、发布说明和已知漏洞，但不把任何单一信号当授权；
5. 在无生产 secret、只读 token、隔离 cache/网络的测试环境运行；
6. 由 CI 依赖所有者批准 lock/pin、允许列表和必要权限的变化；
7. 合并后保存解析快照，观察失败与异常网络，再逐级用于高权限流程；
8. 保留上一已知良好 identity 与内部副本，验证可以只回退依赖而不移动上游名字。

在已取得 old/new 对象的一次性 Git 审计仓库中，可先观察变化范围：

```bash
git --git-dir="$audit_root/dependency.git" diff \
  --stat "$old_commit" "$new_commit"
git --git-dir="$audit_root/dependency.git" diff \
  --name-status "$old_commit" "$new_commit"
git --git-dir="$audit_root/dependency.git" log \
  --format='%H %P %an <%ae> %s' "$old_commit..$new_commit"
```

命令只读已有对象，输出的 OID、作者和路径随上游变化。对象缺失、两者不是 commit 或历史不相连时不能得出“正常升级”结论；先取得完整对象并调查来源。Diff 只展示 Git tree/历史，不覆盖 release asset、registry 包、构建产物或被重写的外部下载。发现异常时继续使用旧精确 identity、停止高权限运行并隔离新依赖；不要删除审计记录或移动本地 tag 掩盖差异。

## 事故处置从停止新解析开始

当上游 Action、模板、镜像或包被报告失陷时：

1. 禁止新的 selector 解析和相关 workflow 运行，必要时在组织策略中 block 精确依赖；
2. 保存候选 OID、解析后配置、direct/transitive identities、runner、cache key、网络、token 与输出摘要；
3. 按第一次可能受影响的依赖 identity 和使用时间枚举所有 pipeline attempts；
4. 撤销这些 job 可见的凭据，调查仓库写入、release、package、部署和外部 API；
5. 隔离由相关 run 写入的 cache、artifact、制品和 attestation，不因摘要存在就继续发布；
6. 选择已知良好 pin 或经过评审的修复对象，在干净 runner、空 cache 和受限网络重建；
7. 比较新旧制品摘要、来源证据和运行结果，逐环境恢复；
8. 复盘允许列表、更新延迟、传递依赖、runner 隔离和凭据范围。

仅把 `@v4` 改成另一个 tag 不是止损证据。必须证明平台解析到了哪一个精确对象、该对象在哪些 run 中执行，以及这些 run 持有什么能力。若攻击可能修改 Git refs 或发布制品，还应转入凭据泄漏、历史取证与发布恢复流程。

## 按证据诊断失败

| 现象 | 优先证据 | 恢复与安全边界 |
| --- | --- | --- |
| 同一候选重跑却执行不同依赖 | selector、每次 resolved identity、解析时间和平台重跑语义 | 固定精确 identity，旧新 attempt 分开保留；不覆盖第一次结果 |
| Tag/branch 与 lock 不一致 | 远端 ref OID、批准 OID、更新审计 | 停止执行；使用已知良好对象或走更新评审，不追随移动引用 |
| 精确 pin 无法取得 | 上游可达性、对象保留、镜像和下载日志 | 从受控镜像恢复；不能改成 `latest` 只为通过 |
| 顶层 Action OID 未变但行为变化 | 运行时网络、传递包、容器/工具 digest、cache | 固定/隔离传递输入，在空 cache/受限网络重建 |
| Remote include integrity 失败 | 实际 bytes、预期 digest、URL/重定向和更新时间 | 保持 fail-closed；评审内容后更新 digest，不关闭校验 |
| 镜像 tag 相同但 digest 改变 | registry manifest/index、平台架构和拉取日志 | 隔离新 digest，回退已知良好 digest；调查 tag 写权限 |
| 高权限 job 恢复了低信任 cache | cache writer/run/key、命中类型和内容清单 | 隔离 cache 与产物，撤销凭据并用空 cache 重建 |
| Attestation 验证通过但策略拒绝 | signer、builder.id、subject、candidate、resolved dependencies | 修复来源或策略映射；不因密码学有效放宽 builder 信任 |

## 隔离实验验证了什么

在本书仓库根目录运行：

```bash
./scripts/verify-ci-dependency-pinning.sh
```

前置条件是 Bash、Git 2.49 或兼容实现、`sed`、`grep`、`mktemp` 和可写临时目录。脚本隔离 system/global Git config，在自己的临时目录创建 Action、传递工具、consumer 和本地 bare 仓库；不访问网络、不读取凭据、不执行 fixture 中的脚本，退出时删除实验目录。

实验先为 Action 创建附注 `v1` tag，并让其配置把传递工具选择为 `refs/heads/main`。Consumer 锁记录 Action 与工具的精确 commit，runner mirror 初次解析与锁一致。随后上游把 `v1` force 更新到新的 Action commit；runner fetch 后相同 selector 解析为新对象，而旧 exact commit 的 tree 仍可区分，锁验证按预期失败。

接着实验只移动传递工具的 `main`，断言顶层 Action commit 和其中的 selector 没变，但实际工具对象已经变化，证明直接 pin 不等于传递闭包固定。最后 consumer 经过显式更新生成新的 lock blob，记录两个新 OID，验证才重新通过。这个 lock 是实验用的简单 key/value 文件，不冒充任何平台 lockfile 或 SLSA attestation。

成功时只输出：

```text
Mutable CI dependency refs, exact pins, and transitive drift boundaries passed.
```

实验没有验证 GitHub Actions、GitLab include、OCI registry、包管理器、签名、attestation、真实 runner、cache、权限或网络沙箱。它只证明 Git branch/tag 的可变性、精确 commit 的内容边界，以及顶层对象固定时传递 selector 仍可解析到新对象。

## 小结

流水线依赖不能只保存“引用了谁”，还要保存“这次解析成什么、实际取得什么、又传递取得什么、带着哪些权限执行、产生了什么”。Branch、tag、semver、URL 和镜像 tag 适合表达升级意图，不适合独自承担运行证据；commit OID、内容 digest 和经验证的 provenance 才能把一次执行固定下来。

固定不是结束。安全系统还要核对来源、审查更新、限制 job 能力、隔离 cache/runner、记录传递依赖，并为上游删除或失陷保留已知良好副本。Provenance 负责陈述构建事实，签名负责把陈述关联到 signer，组织策略负责决定这个 builder 和这些输入是否可接受；三者不能互相替代。
