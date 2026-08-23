# 发布引用与制品提升：把版本名、摘要和审批连起来

发布时经常同时出现版本号、Git 标签、候选提交、制品文件名和部署环境。它们解决的是不同问题：Git 标签为源码对象命名，制品摘要标识实际字节，发布记录描述谁批准了什么，环境记录说明哪里正在运行。把这些名称压缩成一个 `v1.4.2`，会让标签移动、制品覆盖和部署漂移都失去可追溯性。

本章承接[候选提交](02-candidate-commits.md)、[可重复构建](04-reproducible-builds.md)和[制品与部署证据链](03-source-artifact-deployment-evidence.md)，专门处理发布引用、审批记录和同一制品跨环境提升。滚动发布、实例回退、数据库迁移和长任务兼容会在后续章节展开；本章只定义它们必须消费的发布事实。

本章以 Git 2.49.0、Bash 和本地隔离 bare 仓库为验证基线，核对日期为 2026-08-22。真实托管平台的 protected tag、release 页面、审批、制品库权限、保留和计费属于控制面事实，必须按产品、版本、角色、套餐和核对日期单独验证。本章的本地实验只证明 Git 数据面和文件摘要行为。

## 进入条件和退出能力

进入本章前，读者应理解 commit/tree、附注 tag、候选上下文、制品摘要和构建清单。读完后，应能：

- 区分分支、候选引用、发布 tag、版本别名和制品 digest 的职责；
- 为发布记录保存 tag object、剥离目标、候选、制品和审批之间的映射；
- 在隔离环境中创建并显式推送附注 tag，核对远端对象而不强推覆盖；
- 设计构建一次、多环境提升同一制品的门禁；
- 处理同名 tag 竞态、制品摘要失配、审批过期和候选重建；
- 判断哪些发布事实能由 Git 验证，哪些必须由制品库、审批系统和运行环境补证。

## 五种身份不要混用

| 身份 | 解决的问题 | 是否可移动 | 典型保存方式 |
| --- | --- | --- | --- |
| 分支 ref | 后续开发从哪里继续 | 是 | `refs/heads/...` |
| 候选身份 | 哪个对象接受了这次检查 | 候选 OID 不可移动，外部入口可变 | candidate commit/tree 加上下文 |
| 发布 tag | 哪个源码对象被命名为某个版本 | 共享后应视为不可移动 | 附注 tag object 和 peeled commit |
| 制品 digest | 哪些字节将被提升或部署 | 否 | 制品仓库的内容摘要 |
| 发布记录 | 谁在什么条件下批准了哪组映射 | 追加，不覆盖历史 | 受保护的清单、审批和审计事件 |

版本号是人和流程使用的标签，不是内容身份。`main`、`release/1.x` 和 `latest` 都可能移动；`v1.4.2` 如果允许删除再创建，也会移动。发布记录必须同时保存名称和它在当时解析出的 OID、digest 与环境。

## 从候选到发布要经过独立状态

推荐把发布流程写成状态机，而不是一个可以重复点击的“发布”按钮：

```text
候选固定
  -> 构建清单与制品摘要通过
  -> 发布候选登记
  -> 审批和策略核对
  -> 创建不可移动的发布引用
  -> 验证 tag、制品和清单映射
  -> 把同一制品提升到目标环境
  -> 记录环境和运行版本
```

每个状态都要保存输入、输出、主体、时间和策略版本。状态转换不能靠页面上的版本字符串推断。候选在审批期间可能过期，制品在存储期间可能被覆盖，标签在其他写入者手中可能已经存在；任一映射不一致都应停止提升。

最小发布记录可以表示为：

```text
schema_version
repository_identity
release_name / release_tag_ref
tag_object_oid / peeled_commit_oid / source_tree_oid
candidate_commit_or_tree / candidate_context_digest
pipeline_definition / build_manifest_digest
artifact_name / artifact_digest / artifact_size
checks / policy_version / approval_id
approved_by / approved_at / expires_at
allowed_environments / configuration_version / schema_version
promotion_attempt / actor / started_at / finished_at
status / rejection_or_expiry_reason
```

清单字段不能包含 token、私钥、完整环境变量和未经脱敏的内部地址。发布记录本身也要进入不可被普通发布者覆盖的存储，并与审计事件、构建日志和制品位置建立链接。

## 附注 tag 是源码引用，不是制品容器

附注 tag 是一个独立的 Git tag 对象，它保存目标对象、标签者、时间、说明和可选签名。它不包含制品字节，也不自动证明签名主体有发布权限。创建前应先核对候选和制品清单，再创建一个尚不存在的 tag：

```bash
release_tag="${RELEASE_TAG:?RELEASE_TAG is required}"
release_commit="${RELEASE_COMMIT:?RELEASE_COMMIT is required}"

git cat-file -e "$release_commit^{commit}"
if git show-ref --verify --quiet "refs/tags/$release_tag"; then
  printf 'release tag already exists: %s\n' "$release_tag" >&2
  exit 1
fi

git tag -a "$release_tag" "$release_commit" \
  -m "Release $release_tag"

tag_object="$(git rev-parse --verify "$release_tag^{tag}")"
tag_target="$(git rev-parse --verify "$release_tag^{}")"
test "$tag_target" = "$release_commit"
printf 'tag_object=%s\ntag_target=%s\n' "$tag_object" "$tag_target"
```

前置条件是当前目录为发布工作树，`release_commit` 来自已批准的候选或最终发布对象，版本名已经通过组织的命名规则校验。命令会创建 tag object 并移动本地 `refs/tags/<name>`，不会构建制品、连接远端或部署。成功输出中的 OID 随仓库和时间变化，不能写成固定示例。

如果本地 tag 指向错误且尚未共享，可以保存错误 OID 后执行 `git tag -d "$release_tag"`，再从正确候选重建。删除只影响本地引用，tag 对象可能暂时仍在对象库中；一旦 tag 已推送或进入发布记录，不能把删除和重建当作普通修正，必须走事故和消费者影响评估。

附注 tag 与轻量 tag 的对象类型不同。发布流程若需要签名、标签说明或稳定审计对象，应明确要求附注 tag，并在验证时拒绝轻量 tag：

```bash
git cat-file -t "$release_tag"
git rev-parse --verify "$release_tag^{tag}"
git rev-parse --verify "$release_tag^{}"
```

第一条应为 `tag`，第二条是 tag object 的 OID，第三条是剥离后的目标对象。命令只读取本地对象，不能证明远端仍公布同一个 ref，也不能证明制品、审批或部署已经存在。

## 显式推送并核对远端引用

本地 tag 通过发布门禁后，使用完整 refspec 推送同一个名字，避免把其他本地标签一并发送：

```bash
git push origin \
  "refs/tags/$release_tag:refs/tags/$release_tag"
```

前置条件是远端地址、认证主体、标签写权限和保护策略已核对，构建清单中的 `release_commit` 与本地 tag 目标相同。成功会向远端发送缺少的 tag object 和祖先对象，并创建同名远端 ref；失败时本地 tag 不会消失。不要为了“让发布继续”追加 `--force`，先按 endpoint、认证、授权、同名 ref 和服务器规则分流。

推送后在保存初始证据的客户端或受信任查询环境中核对：

```bash
git ls-remote --tags origin \
  "refs/tags/$release_tag" \
  "refs/tags/$release_tag^{}"
```

附注 tag 通常返回 tag object 和剥离目标两行，具体行数和格式以 Git 版本为准。剥离目标必须等于发布记录中的 `release_commit`，tag object 也要与推送前的本地对象一致。`ls-remote` 只证明服务器公布了 Git 引用，不证明平台 release 页面、制品库、签名信任或部署实例状态。

## 发布引用和制品提升必须原子地对账

发布前至少对账以下关系：

```text
release record.release_tag_ref -> tag object -> peeled commit
release record.peeled_commit -> build manifest.source_commit
build manifest.artifact_digest -> artifact bytes in registry
promotion record.artifact_digest -> environment deployment target
runtime observation.digest -> promotion record.artifact_digest
```

其中任一箭头没有证据，发布状态应为 `inconclusive` 或 `blocked`，不能用相邻字段推断。比如 tag 目标正确但制品摘要不同，说明源码命名正确、输出不可信；制品摘要正确但实例 digest 不同，说明提升或 rollout 失败；审批正确但候选已经过期，说明审批对象需要重新生成。

制品提升是复制同一不可变字节的过程，不是每个环境重新解析分支并构建：

1. 在构建环境生成制品和构建清单，计算内容摘要；
2. 将制品写入受保护的制品存储，完成后才允许读取；
3. 在 staging 读取并重新计算摘要，核对清单和环境兼容性；
4. 审批记录锁定候选、清单 digest、制品 digest 和目标环境；
5. 提升相同制品到下一环境，禁止使用 `latest` 或重新构建替代；
6. 保存每次提升的主体、时间、策略版本、状态和失败原因。

下面的片段展示如何在制品目录中核对摘要和构建来源。它不调用特定制品库 API，也不把文件复制成功当作授权成功：

```bash
artifact_file="${ARTIFACT_FILE:?ARTIFACT_FILE is required}"
manifest_file="${MANIFEST_FILE:?MANIFEST_FILE is required}"
expected_digest="${EXPECTED_ARTIFACT_DIGEST:?EXPECTED_ARTIFACT_DIGEST is required}"
expected_commit="${EXPECTED_SOURCE_COMMIT:?EXPECTED_SOURCE_COMMIT is required}"

test -f "$artifact_file"
test -f "$manifest_file"

if command -v sha256sum >/dev/null 2>&1; then
  actual_digest="$(sha256sum "$artifact_file" | awk '{print $1}')"
else
  actual_digest="$(shasum -a 256 "$artifact_file" | awk '{print $1}')"
fi
test "$actual_digest" = "$expected_digest"

manifest_commit="$(awk -F= \
  '$1 == "source_commit" {print substr($0, index($0, "=") + 1)}' \
  "$manifest_file")"
manifest_digest="$(awk -F= \
  '$1 == "artifact_digest" {print substr($0, index($0, "=") + 1)}' \
  "$manifest_file")"
test "$manifest_commit" = "$expected_commit"
test "$manifest_digest" = "$actual_digest"

printf 'promotion_source_commit=%s\npromotion_artifact_digest=%s\n' \
  "$manifest_commit" "$actual_digest"
```

前置条件是制品已经完成写入，清单来自受保护的构建记录，期望值由审批或发布控制面提供。命令只读取文件和清单，不移动 Git ref；文件缺失、摘要失配、清单重复键或来源提交不符时应停止提升。不要用 `source "$manifest_file"` 读取外部清单，因为清单内容可能包含命令替换或未预期的环境变量。

## 版本命名和发布分支

版本名应让人知道它是候选、正式版本还是维护线，但不要承担对象完整性。可以采用以下分层：

| 层次 | 例子 | 规则 |
| --- | --- | --- |
| 开发线 | `main`、`release/1.x` | 可移动，不能作为已部署版本身份 |
| 候选 | `v1.4.2-rc.1` | 绑定精确候选和制品，失败后增加序号或废弃 |
| 正式版本 | `v1.4.2` | 共享后默认不可移动，重做用新版本或补丁版本 |
| 人类别名 | `stable`、`latest` | 允许移动，但不能作为审计唯一身份 |
| 内容身份 | SHA-256 digest | 不可变，跨环境提升必须保持不变 |

发布分支只在需要多版本维护、长期安全修复或客户定制线时使用。分支上的每次构建仍需要自己的候选、制品 digest 和发布记录；不能因为分支名称稳定，就跳过候选和清单核对。

## 审批、签名和权限是不同证据

审批回答“组织是否允许把这次构建提升到某环境”，签名回答“某个 key 是否对特定字节作出密码学承诺”，权限回答“当前主体能否执行动作”。三者不能互相替代：

- tag 签名有效，不代表签名主体有生产发布权限；
- 审批记录存在，不代表审批对象仍是当前候选；
- 制品 digest 正确，不代表下载或部署主体被授权；
- 平台页面显示可发布，不代表实例已加载该 digest。

发布主体、构建主体、审批主体和部署主体应按最小权限分开，并在记录中保存主体稳定 ID、委托关系、权限范围和时间。密钥生命周期、信任根和供应链来源证明见第十篇；本章只规定发布记录必须引用这些证据，不能在候选代码中自带一份信任策略来批准自己。

## 同名发布的竞态

两个候选可能同时认为自己可以发布 `v1.4.2`。安全规则是第一个成功创建受保护引用的候选获胜，其他候选收到明确拒绝并重新选择版本，不能覆盖已有 tag：

```text
候选 A 通过 -> 尝试创建 v1.4.2 -> 成功
候选 B 通过 -> 发现 v1.4.2 已存在 -> 拒绝并保留证据
```

如果要在本地验证“只允许创建、不允许覆盖”，可以使用 expected old 为空的条件 ref 更新。该命令只能在临时仓库中执行：

```bash
tag_ref="refs/tags/$release_tag"
tag_object="${TAG_OBJECT_OID:?TAG_OBJECT_OID is required}"
git cat-file -e "$tag_object^{tag}"
git update-ref "$tag_ref" "$tag_object" ""
```

成功时创建 ref；当前 ref 已存在或 expected old 不匹配时返回非零并保持旧值。命令会修改当前仓库的 refs，必须在专用临时仓库中运行，生产发布应使用服务端的等价原子创建、保护规则和审计事件。`git push` 对同名已存在 tag 的拒绝不能被本地强推绕过。

## 故障分流与恢复

| 症状 | 先固定 | 安全动作 | 不要做的事 |
| --- | --- | --- | --- |
| 本地 tag 指向错误且未共享 | tag object、peeled commit、候选和清单摘要 | 保存错误 OID，删除本地 tag，修正候选后重建 | 直接改 tag 目标后继续审批 |
| 远端同名 tag 已存在 | `ls-remote`、服务器返回、已有发布记录 | 停止并确认所有者，使用新版本或事故流程 | `push --force` 覆盖 |
| tag 目标与清单 source commit 不同 | tag object、剥离目标、manifest | 隔离发布，重新走候选和构建 | 移动 tag 迁就制品 |
| 制品摘要与清单不符 | 原摘要、重算摘要、存储审计、写入时间 | 阻止提升，恢复已知摘要版本并调查篡改 | 修改清单或文件名 |
| staging 摘要正确，生产摘要不同 | 提升记录、存储对象、实例观测 | 暂停 rollout，重新从不可变制品提升 | 重新在生产构建 |
| 审批完成后候选过期 | 目标/功能 OID、策略版本、审批时间 | 使审批失效，重建候选并重新审批 | 复制旧审批到新候选 |
| 发布标签已删除但消费者仍使用 | 平台审计、镜像、clone、部署和包索引 | 保留事故记录，通知消费者，按组织流程发布修正版 | 认为删除 ref 就删除了所有对象 |

恢复顺序是保留原始记录、隔离错误制品、确认当前环境实际版本，再决定创建新候选、新版本还是回退已验证制品。不要先用版本号或 tag 名称覆盖现场，因为那会同时破坏审计和消费者的定位线索。

## 隔离实验与真实边界

在本书仓库根目录运行：

```bash
bash scripts/verify-release-promotion.sh
```

实验使用 `mktemp`、虚构身份和本地 bare 仓库，完成以下断言：

1. 为候选 commit 创建附注 tag，核对 tag object 和剥离目标；
2. 用显式 refspec 推送 tag，并从 bare 远端读取两个 OID；
3. 生成带 source commit 和 artifact digest 的清单，把同一制品复制到 staging 并重新计算摘要；
4. 故意修改 staging 副本，确认摘要失配后恢复已知制品；
5. 另一个候选尝试创建同名 tag 时被拒绝，远端仍保持第一个候选。

成功输出为：

```text
Release tag, immutable promotion, artifact digest, and tag-race protection passed.
```

实验只证明 Git tag、bare 接收端、文件摘要和本地竞态边界。它不模拟 GitHub/GitLab release 控制面、protected tags、真实制品仓库权限、审批服务、签名验证、计费、数据库、滚动发布或运行实例。生产发布必须在目标平台专用环境中验证这些控制面证据。

## 综合练习：判断一个版本是否真的可发布

某团队提交了以下材料：分支 `release/1.x`、标签 `v1.4.2`、制品 `application.tar`、审批记录和 staging 部署截图。请写出发布前核对表，至少回答：

1. 标签是轻量还是附注 tag，tag object 和剥离目标是什么；
2. 候选 commit、构建清单 source commit 和 tag target 是否一致；
3. 制品摘要是否在写入完成后计算，并在提升前重新计算；
4. 审批主体批准的是哪个候选、哪个 digest 和哪个环境，审批是否已经过期；
5. 生产是否会重新构建，运行实例如何证明实际加载了相同 digest；
6. 若另一个候选先创建了同名 tag，应如何处理当前发布。

合理答案不会把截图、分支名和版本号当作内容身份，而会要求 tag object、peeled commit、候选上下文、构建清单、artifact digest、审批和环境观测形成可验证映射。

## 小结

发布 tag 只为源码对象命名，制品 digest 才标识要部署的字节，发布记录把它们与候选、清单、审批和环境绑定。共享 tag 默认不可移动，同名竞态应由原子创建和保护策略处理，不能用强推覆盖。

发布采用构建一次、提升同一制品的路径，环境变化只通过经过审计的配置进入。摘要、来源或审批任一失配都应阻止提升；恢复时先保留证据，再创建新候选、新版本或使用已验证的回退制品。下一章将把部署策略、运行观测和回退动作展开为环境状态机。

## 资料

- [git-cat-file](https://git-scm.com/docs/git-cat-file)
- [git-ls-remote](https://git-scm.com/docs/git-ls-remote)
- [git-push](https://git-scm.com/docs/git-push)
- [git-tag](https://git-scm.com/docs/git-tag)
- [git-update-ref](https://git-scm.com/docs/git-update-ref)
