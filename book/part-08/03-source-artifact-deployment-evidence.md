# 从源码到运行版本：制品与部署证据链

Git 提交能精确标识源码对象，却不知道 runner 使用了哪一版流水线、依赖从哪里取得、生成了哪些字节，也不知道线上实例最后加载了什么版本。把“主线是绿色的”直接写成“已经发布”，会把源码、制品、配置、数据库和运行状态混成一个无法复盘的结论。

本章承接[触发与 checkout](01-triggers-and-checkout.md)和[候选提交](02-candidate-commits.md)：它假定候选 OID 和实际 `HEAD` 已经核对，继续处理 checkout 之后的构建输入、制品摘要、发布引用、部署请求和运行实例。候选选择、路径过滤和合并队列的定义以候选章为准，本章只补充它们如何进入发布证据。

本章以 Git 2.49.0、Bash 和本地隔离仓库为验证基线，核对日期为 2026-08-22。制品仓库、部署平台、签名服务、数据库工具和运行编排器属于外部系统，正文使用厂商无关抽象；任何产品、版本、权限、套餐或计费事实都必须另行登记。

## 进入条件和退出能力

进入本章前，读者应理解候选 commit、tree、分离 `HEAD`、附注 tag、受保护引用和路径过滤。读完后，应能：

- 记录源码提交、源码 tree、流水线定义、runner、依赖和构建参数；
- 为制品计算并核对不可变摘要，区分文件名、版本标签和内容身份；
- 把发布 tag、制品摘要、部署请求和运行实例绑定到同一条记录；
- 判断控制面“部署成功”是否已被实际实例和流量证据证实；
- 区分制品回退、配置回退、源码 revert、数据库向前修复和数据恢复；
- 识别证据链断点，并在断点处停止继续提升，而不是修改 Git 标签迁就错误制品。

## 一次发布跨越九类状态

```text
候选 checkout
  -> 流水线定义与 runner
  -> 依赖、工具链和构建参数
  -> 源码构建与制品字节
  -> 制品摘要与来源记录
  -> 发布引用/审批
  -> 部署请求与环境配置
  -> 运行实例实际加载的制品
  -> 流量、健康和回退状态
```

每个箭头都要保留输入、输出、主体和时间。Git 只覆盖 commit 对象中的 tree、父提交、作者/提交者和说明；它不覆盖未提交文件、runner 镜像、环境变量、密钥、数据库状态、部署参数、网络依赖或运行流量。

建议把每次构建或发布表示为一个不可变证据记录：

```text
schema_version
repository_identity
source_commit / source_tree
candidate_kind / target_commit / change_id
pipeline_definition / runner_image_digest
dependency_lock_digest / external_input_digests
build_command_identity / build_identity
artifact_name / artifact_digest
release_ref / release_approval
environment / configuration_version / database_version
deployment_id / deployer / started_at / finished_at
runtime_observed_digest / health_and_traffic_result
```

字段名可以按组织格式调整，但语义不能只剩一个 `version=latest`。`source_commit` 关联历史和评审，`source_tree` 固定源码快照；不同 commit 可能拥有相同 tree，不能只保留其中一个。

## 流水线定义和构建输入也要固定

仓库中的 CI 文件、构建脚本和依赖锁文件通常随源码版本化，但平台还可能拼接组织模板、引用外部 action、注入 runner 镜像或从缓存恢复依赖。记录源代码提交不等于记录实际执行过程。

如果约定入口是 `.ci/pipeline.sh`，在已经通过 checkout 合约的 runner 中读取它的 blob ID：

```bash
actual_commit="$(git rev-parse HEAD)"
pipeline_blob="$(git rev-parse "$actual_commit:.ci/pipeline.sh")"
printf 'pipeline_blob=%s\n' "$pipeline_blob"
```

前置条件是当前目录为候选 runner 工作树，入口路径属于该 commit tree；命令只读取对象。路径不存在、对象缺失或仓库是受限浅/部分克隆时应失败并停止，不能写入空值继续发布。这个 OID 只证明提交 tree 中的文件内容，不证明平台最终执行了同一内容；平台模板、外部 action 和 runner 镜像需要从调度和执行日志取证。

构建证据至少应记录：

- 流水线配置或入口脚本的 commit/blob 身份；
- runner 操作系统、容器/虚拟机镜像 digest 和工具版本；
- 依赖锁文件、内部制品源、外部 action/plugin 和缓存身份；
- 实际命令、退出状态、开始/结束时间和日志位置；
- 读取/写入凭据的主体、权限范围和有效期；
- 网络访问、缓存命中、降级路径和未取得输入。

环境变量可能含有秘密，不能把完整环境转储当作证据。使用字段白名单，并在写日志前验证脱敏结果。若构建依赖网络动态解析，记录解析后的精确 commit、digest 或包版本；顶层锁文件不自动固定传递依赖。

## 制品身份来自内容摘要，不来自文件名

`application.tar`、`latest`、`v1.4.2` 或对象存储路径都可能被覆盖。发布记录应使用制品仓库提供的不可变 digest，或在制品字节完成写入后计算 SHA-256：

```bash
artifact_file="${ARTIFACT_FILE:?ARTIFACT_FILE is required}"
test -f "$artifact_file"

if command -v sha256sum >/dev/null 2>&1; then
  artifact_sha256="$(sha256sum "$artifact_file" | awk '{print $1}')"
else
  artifact_sha256="$(shasum -a 256 "$artifact_file" | awk '{print $1}')"
fi

printf 'artifact_sha256=%s\n' "$artifact_sha256"
```

命令在构建输出目录执行，只读取已完成的文件。文件不存在、摘要工具不可用或计算期间仍有进程写入文件时，结果不能作为发布证据；应使用原子完成标记或只读制品存储后重试。跨系统传输后必须重新计算并与原摘要比较。

不要把 Git 对象 ID 当成任意制品的 SHA-256。Git 对象 ID 对象类型和长度编码，且仓库可能使用不同对象格式；它与文件内容摘要属于不同协议。源码归档可以同时记录 commit/tree 和文件摘要，但两者不能互相替代。

## 构建一次，再提升同一制品

构建的完整输入闭包、逐字节比较、非确定性来源和失败分类见[可重复构建](04-reproducible-builds.md)。本章只消费已经通过构建门禁的制品摘要，并把它接入发布引用、部署请求和运行观测。

测试、预发布和生产通常应提升同一个不可变 digest，只改变经过审计的环境配置。若每个环境重新构建，即使源码 commit 相同，也会产生新的制品和来源记录，不能继续使用原构建的发布结论。

## 发布引用只命名源码，不包含制品

附注 tag 可以为候选或正式发布提交提供稳定名称，并保存说明和可选签名。验证时同时读取 tag 对象和剥离后的目标：

```bash
release_tag="${RELEASE_TAG:?RELEASE_TAG is required}"
tag_object="$(git rev-parse --verify "$release_tag^{tag}")"
tag_target="$(git rev-parse --verify "$release_tag^{}")"
git cat-file -t "$tag_object"
printf 'tag_object=%s\ntag_target=%s\n' "$tag_object" "$tag_target"
```

前置条件是附注 tag 已在当前仓库取得；`^{tag}` 会拒绝轻量 tag，避免把没有 tag 对象误当作签名发布。命令只读取对象。它不能证明服务器仍保存同一 ref、制品存在、签名主体获授权或部署完成。

发布记录要同时保存：

- 服务器在发布时观察到的 tag ref OID、tag object OID 和剥离目标 commit；
- 制品仓库、不可变摘要和构建证据位置；
- 发布审批、允许环境、配置版本和数据库兼容范围；
- 已知良好的回退制品及其摘要；
- 发布主体、时间、策略版本和审计事件。

已经共享的发布标签不应为了适配错误制品而移动。发现制品和源码不一致时，隔离制品，保留原始记录，重新生成候选或新版本；签名、评审和部署证据不能通过改 tag 名称补齐。

## 部署记录必须连接到运行实例

一次部署至少记录环境/集群/区域稳定标识、制品 digest、构建证据、配置和 secret 版本、数据库迁移版本、发起者/批准者、部署工具身份、批次和健康门槛。控制面接受请求只证明请求被接受，不证明实例已经使用该制品。

部署完成后要从运行实例、任务定义、镜像运行时或等价可信观测中读取实际 digest，并记录：

- 新旧版本实例数量、部署批次和流量比例；
- 健康检查、错误率、关键业务指标和观察窗口；
- 是否仍存在旧版本实例，何时终止；
- 实际运行的配置/secret/schema 版本；
- 部署失败、暂停、回退和重试的原因。

应用版本端点应只返回非敏感的 build identity 或 artifact digest，不能输出 token、完整环境变量或内部凭据。主线在部署期间可以继续前进，平台页面上的 `main` 不能反推生产当前版本；部署记录必须锁定构建时的 `source_commit` 和 `artifact_digest`。

## 数据库和外部副作用决定回退边界

“回滚”至少有五种含义：

| 动作 | 改变的状态 | 常见前提 | Git 中的动作 |
| --- | --- | --- | --- |
| 重新部署旧制品 | 运行实例制品选择 | 旧制品兼容当前配置、schema、消息和外部协议 | 可以不改 Git |
| 回退环境配置 | 配置控制面 | 旧配置和 secret 仍可取且兼容 | 可以不改 Git |
| revert 源码再构建 | 共享历史与新制品 | 反向变化可构建、可评审、可部署 | 新增 revert commit |
| 数据库向前修复 | 数据和 schema | 已演练、可观测、可审计 | Git 保存脚本，不自动回退数据 |
| 从备份恢复数据 | 数据库/消息状态 | 明确 RPO/RTO、跨服务一致性和恢复点 | Git 只保存恢复流程 |

旧应用不会因为重新部署就自动获得旧 schema。删除列、收紧约束、重写数据、改变消息语义或产生不可逆外部副作用，都可能让旧制品无法启动或读错数据。发布前采用 expand/contract 等兼容窗口，把 schema 变化与应用切换分阶段，并明确每阶段可以回退到哪个版本。

若新旧版本会同时运行，API、消息和数据格式必须覆盖混合版本窗口。无法回退的迁移要在审批前标记，准备停止发布、向前修复和数据校验方案；事故中不能临时执行未经验证的 SQL 或直接用旧制品覆盖运行实例。

## 证据链断点的处理顺序

| 断点 | 先固定 | 安全动作 | 停止条件 |
| --- | --- | --- | --- |
| 实际 checkout 与候选不一致 | 调度 OID、实际 `HEAD`、checkout 日志 | 停止作业，修复事件/checkout | 用 reset 掩盖差异 |
| 流水线/runner/依赖版本未知 | pipeline blob、镜像 digest、锁文件和外部解析记录 | 使制品不可发布，补齐输入或重建 | 以“同一 commit”代替构建输入 |
| 制品摘要与清单不符 | 原摘要、重算摘要、存储审计和写入时间 | 隔离制品，阻止提升，恢复已知摘要 | 移动 tag 或改清单迁就字节 |
| 发布 tag 与制品来源不一致 | tag object、target OID、来源清单和审批 | 生成新候选/新版本，保留原证据 | 覆盖公开 tag |
| 控制面成功但实例仍是旧 digest | 部署批次、实例观测、流量和健康 | 暂停继续发布，修复 rollout | 只改 Git 分支或标签 |
| 旧制品无法启动 | schema、配置、消息和外部协议兼容矩阵 | 恢复兼容配置或执行已演练的向前修复 | 未经审批的数据破坏动作 |

重新运行成功不能覆盖第一次失败的候选、日志和制品。保留原始时间顺序，记录每次 attempt 的输入、身份、退出状态和外部副作用，才能判断是代码变化、环境变化还是偶发依赖导致恢复。

## 隔离实验：候选、制品和部署副本

本章复用 `scripts/verify-ci-evidence-chain.sh`，在仓库根目录执行：

```bash
bash scripts/verify-ci-evidence-chain.sh
```

前置条件是 Bash、Git 2.28 或更高版本、`awk`，以及 `sha256sum` 或 `shasum`。脚本使用 `mktemp` 临时目录、虚构身份和本地 `file://` 裸仓库，不读取用户级 Git 配置、不连接网络，也不修改蓝皮书仓库。

实验验证：

1. 生成带两个父提交的合并候选，runner 在分离 HEAD 上精确检出候选并核对 commit、tree、流水线 blob 和附注 tag；
2. 对同一候选生成两份源码归档并核对摘要，对功能分支头生成另一份归档，证明“同一候选”是制品输入的一部分；
3. 把摘要清单和制品复制到模拟 staging 目录，故意篡改副本后检测失配，再从已知构建制品恢复；
4. 让服务器 `main` 前进，验证 runner 的 `origin/main` 可以变化，而分离 `HEAD` 和部署记录仍锁定原候选。

成功输出为：

```text
Detached CI checkout, reproducible archive, manifest, and deployment verification passed.
```

`git archive` 的可重复性只证明当前隔离环境中的源码归档字节一致，不代表任意语言编译、容器镜像、外部依赖或跨平台构建已经可重复。模拟 staging 是普通目录，不能证明真实制品权限、签名、审计、滚动发布或运行实例状态；这些证据必须在专用测试环境采集。

## 小结

源码提交回答“构建输入中的 Git 快照是什么”，制品摘要回答“生成了哪些字节”，部署记录回答“哪个环境被要求使用什么制品”，运行观测回答“实例实际加载了什么”。四者必须显式关联，不能用分支名、tag 名或平台绿色状态替代。

证据链断开时先停止提升，保留原始候选、清单、制品和运行状态，再决定重跑、恢复制品、回退配置、revert 源码、向前修复还是恢复数据。Git 可以保存过程和脚本，但不会自动替你回滚数据库、消息和外部副作用。

## 资料

- [git-archive](https://git-scm.com/docs/git-archive)
- [git-cat-file](https://git-scm.com/docs/git-cat-file)
- [git-rev-parse](https://git-scm.com/docs/git-rev-parse)
- [git-show](https://git-scm.com/docs/git-show)
- [git-tag](https://git-scm.com/docs/git-tag)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
