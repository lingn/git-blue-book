# 备份不是 mirror：bundle、恢复点与恢复演练

“仓库已经在 GitHub/GitLab 上”“每个开发者都有 clone”“还有一台服务器在做 mirror”，都不等于已经建立可恢复的备份。Git 对象可以从某个 clone 找回，但默认分支、评审、分支规则、LFS payload、制品、权限和审计记录可能已经丢失；一个持续同步的 mirror 还可能忠实传播误删和强制改写。

备份的工程目标不是拥有另一份目录，而是在明确的恢复点、允许损失和时间预算内，重新建立经过验收的服务。本章把 Git 数据分成逻辑历史、物理对象库、外部 payload、平台控制面和运行依赖，分别说明 bundle、mirror、文件系统快照和平台导出的能力边界。

本章以 Git 2.49.0、Bash 和本地文件传输为验证基线，不模拟托管平台备份接口。真实方案必须按所用 Git 服务、LFS 服务、对象存储、制品库、身份系统和密钥管理系统的当前能力复核，记录版本、权限、地域、套餐与核对日期。

进入本章前，读者应理解 refs、对象可达性、reflog、pack、alternates、partial clone、LFS、submodule、现场保护和对象取证。读完后，应能：

- 用 RPO、RTO、恢复范围和责任人定义备份契约；
- 解释 bundle、mirror 和文件系统快照分别保存什么、遗漏什么；
- 创建并验证完整/增量 bundle，理解 prerequisite commit；
- 在全新隔离仓库恢复全部预期 refs，并核对 tree、tag、notes 和外部对象；
- 识别 mirror 的强制同步与删除传播风险；
- 设计不会修改生产仓库的定期恢复演练。

## 先定义恢复契约

备份计划至少回答四个问题：

| 维度 | 必须写清的内容 |
| --- | --- |
| 恢复范围 | 仅 Git refs/objects，还是还包括 LFS、评审、issue、wiki、制品、权限、审计和密钥 |
| RPO | 最多允许丢失多少时间或多少次引用更新，例如 15 分钟或 0 次受保护分支更新 |
| RTO | 从宣布灾难到恢复读写服务、验证客户端和解除写入冻结的最长时间 |
| 恢复责任 | 谁宣布故障、谁取得备份、谁验证、谁批准切换、谁通知下游重新同步 |

“每天备份一次”只描述频率，没有说明备份是否成功、是否自包含、保留多久、是否能解密、是否跨故障域，也没有说明一天内的提交能否接受丢失。RPO/RTO 还应分别定义 Git 服务、LFS、评审元数据和制品，因为这些系统可能无法在同一时刻快照。

恢复点应是一个清单，而不是文件名：

~~~text
recovery_point = {
  captured_at,
  git_refs_manifest,
  git_object_format,
  git_backup_digest,
  lfs_object_manifest,
  submodule_repository_points,
  platform_export_id,
  artifact_and_package_points,
  policy_and_identity_export,
  encryption_key_version
}
~~~

跨系统无法原子快照时，记录每个组件的时间窗口和一致性策略。例如 Git ref 已到 C，但对应 LFS payload 尚未进入备份，就不能把 C 宣布为完整恢复点。

## 一份 Git 仓库服务实际包含哪些资产

| 资产层 | Git bundle/mirror | 额外备份 |
| --- | --- | --- |
| branches、tags、notes、自定义 refs 的可达对象 | 可以，但必须明确 refs 范围 | refs 清单、HEAD symbolic ref、对象格式 |
| reflog、不可达对象、进行中操作、index、未提交文件 | 默认不包含 | 事故现场或受控文件系统快照 |
| Git LFS payload 与锁 | 不属于普通 Git 对象传输 | LFS 服务/cache/对象存储及锁元数据 |
| submodule 的外部仓库对象 | superproject 只保存 gitlink OID | 每个依赖仓库的独立恢复点 |
| issue、合并请求、评论、审批、wiki、release 元数据 | Git 协议不定义 | 平台导出/API/数据库备份 |
| 分支规则、权限、团队、机器人、webhook、CI 变量 | 不包含 | 控制面配置、身份系统和秘密管理系统 |
| CI log、artifact、package、容器镜像、部署记录 | 不包含 | 各服务的保留与复制策略 |
| hooks、服务端配置、证书、签名信任库 | 不由普通 clone 保存 | 配置管理、密钥管理和基础设施备份 |

开发者 clone 可能成为找回某些提交的 donor，却通常没有平台隐藏 refs、其他人的未合入分支、服务端 hooks、LFS 全量 payload 或评审数据。它是恢复来源之一，不是完整备份设计。

## bundle 是带 refs 广告和 pack 的逻辑传输文件

Bundle 把指定 revision 参数形成的可达对象打成一个可验证文件，并在 header 中声明可取得 refs 与可能需要的 prerequisite commits。它适合离线传输、时间点归档和分层增量备份，但不会自动包含工作区、index、reflog、local config、hooks、不可达对象或平台数据。

### 创建完整 bundle 前先固定 refs

在自包含的备份工作仓库中执行，不要直接拿事故现场或 partial clone 当唯一来源：

~~~bash
backup_dir=/srv/backup/git/project/2026-08-20T120000Z
repo=/srv/git/project.git

install -d -m 0700 "$backup_dir"
git --no-optional-locks -C "$repo" version > "$backup_dir/git-version.txt"
git --no-optional-locks -C "$repo" \
  rev-parse --show-object-format --show-ref-format \
  > "$backup_dir/object-format.txt"
git --no-optional-locks -C "$repo" \
  symbolic-ref -q HEAD > "$backup_dir/head.symref"
git --no-optional-locks -C "$repo" \
  for-each-ref \
  --format='%(refname)%00%(objecttype)%00%(objectname)%00%(*objectname)%00' \
  > "$backup_dir/refs.nul"
~~~

前提是 repo 已冻结到本次恢复点，或服务端能提供一致的引用快照。命令只读取 Git 状态，输出应进入受限目录；`symbolic-ref` 在 detached/unborn HEAD 时会非零退出，必须把该状态记录下来，而不是用空文件冒充 main。

然后创建 bundle：

~~~bash
git -C "$repo" bundle create "$backup_dir/repository.bundle" --all
git -C "$repo" bundle verify "$backup_dir/repository.bundle" \
  > "$backup_dir/bundle.verify.txt"
git bundle list-heads "$backup_dir/repository.bundle" \
  > "$backup_dir/bundle-heads.txt"
~~~

`--all` 以当前仓库所有可见 refs 为 revision 输入，适合受控备份 clone；它仍不等于“服务器全部数据”，也不会把只有 reflog 或没有任何 ref 可达的对象变成备份根。组织可以改为显式 namespace 白名单，但必须把 branches、tags、notes、平台导出的评审 refs 和自定义归档 refs 的取舍登记在清单中。

成功时 `bundle verify` 会列出 advertised refs、prerequisites、对象格式并报告 bundle 可用。失败可能来自 revision 为空、对象缺失、读取权限、空间不足或输出文件已存在。不要覆盖上一份已验证备份；创建到新的恢复点目录，验证和计算摘要成功后再更新“latest”索引。

### 验证 bundle 不等于验证恢复完成

`git bundle verify` 检查 bundle 格式、pack 和当前仓库是否满足 prerequisites。它不验证：

- refs 集合是否符合组织预期；
- 默认分支 symbolic HEAD 是否正确；
- LFS payload、submodule commit 和制品是否可取；
- 平台评审、权限和审计导出是否完整；
- 解密 key、跨区域副本和恢复账号是否在灾难时可用。

所以 bundle 文件必须同时保存摘要、refs manifest、外部对象清单、生成日志和恢复演练结果。

## 增量 bundle 依赖前置对象

完整备份后，可以只打包新历史：

~~~bash
base=0123456789abcdef0123456789abcdef01234567
git -C "$repo" bundle create incremental.bundle \
  "$base..refs/heads/main"
~~~

状态变化只发生在新 bundle 文件；源 refs 不移动。Header 会把 base 等边界提交登记为 prerequisite，而不重复打包其祖先。目标仓库缺少 prerequisite 时：

~~~bash
git -C "$empty_repo" bundle verify incremental.bundle
~~~

应非零退出，并列出缺失提交。恢复端先导入包含 base 的完整 bundle，再验证和获取增量：

~~~bash
git -C "$restore_repo" bundle verify incremental.bundle
git -C "$restore_repo" fetch incremental.bundle \
  '+refs/heads/main:refs/heads/main'
~~~

第二条会写对象并移动目标 ref，只能在隔离恢复仓库、确认 old/new OID 和更新策略后执行。增量链中任一层缺失、损坏或加密 key 丢失，后续层都可能无法使用；生产方案需要定期重新生成完整基线、限制链长并验证从最老保留点恢复。

## 恢复到全新仓库，而不是覆盖生产仓库

下列流程只适用于新建的空 bare 仓库：

~~~bash
restore_repo=/srv/restore/project.git
git init --bare --initial-branch=main "$restore_repo"
git -C "$restore_repo" fetch /backup/repository.bundle \
  '+refs/*:refs/*'
git -C "$restore_repo" symbolic-ref HEAD refs/heads/main
git -C "$restore_repo" fsck --full --strict --no-progress
~~~

`+refs/*:refs/*` 会强制写入所有 bundle 广告的 refs。在非空仓库执行可能覆盖同名引用，在工作仓库还可能碰到当前分支保护；因此恢复前必须确认目标路径是新建隔离仓库。普通 `git clone repository.bundle` 会按默认 clone/fetch 规则组织 heads、remote-tracking refs 和 tags，不应假设 notes 或自定义 namespace 已按原名恢复。

恢复后比较源清单与目标清单，并抽查 commit/tree/tag：

~~~bash
git -C "$restore_repo" for-each-ref \
  --format='%(refname)%00%(objecttype)%00%(objectname)%00%(*objectname)%00' \
  > restored-refs.nul
git -C "$restore_repo" rev-parse refs/heads/main^{tree}
git -C "$restore_repo" cat-file -p refs/tags/v1.0
git -C "$restore_repo" notes show "$candidate"
~~~

预期 refs 的缺失、多出、OID 不同或 annotated tag peeled target 不同都应阻止切换。恢复动作失败时保留输出，销毁并从同一只读备份重新建立恢复仓库；不要在半恢复仓库反复手工补 ref，除非每个偏差已进入变更记录。

## mirror 是同步拓扑，不是保留策略

~~~bash
git clone --mirror --no-local /srv/git/project.git project-mirror.git
git -C project-mirror.git remote update --prune
~~~

`clone --mirror` 创建 bare 仓库，并把远端 refs namespace 直接映射到本地对应 refs；后续更新允许强制移动并按 prune 删除源端不存在的引用。它适合迁移中继、只读副本或备份采集输入，但具有三个关键边界：

1. 源端误删、强制改写或污染可能在下一次同步传播；
2. 通过 Git 传输只取得 refs 可达对象，不取得源 reflog、不可达对象、hook、任意 local config、未提交文件或平台数据库；
3. 单个持续变动的 mirror 没有历史保留窗口，不能回答“回到三天前”。

因此可靠方案通常把 mirror 当采集层，再从一致的 mirror 状态生成不可变、带日期和摘要的 bundle/存储快照。同步前后保存 refs diff，异常大规模删除、默认分支变化或 force update 应触发门禁，而不是自动覆盖最后一份好副本。

`git push --mirror` 同样会强制更新并删除目标端多出的 refs。它只能用于已经确认是空的新恢复目标或经过审批的迁移切换；不能把生产仓库当作“试一下”的目标。

## 文件系统快照保存更多，也更容易取得不一致状态

文件系统层备份可以保存 refs、reflog、对象库、hooks、配置和服务端附属文件，但复制正在写入的仓库目录可能跨越 ref 更新、pack 重写和锁文件生命周期，得到一个从未真实存在过的组合状态。

生产方案应使用 Git 服务厂商支持的备份机制、应用一致性快照或明确的停写/冻结协议。快照前后记录：

- 仓库和 common directory 的真实路径；
- alternates、对象池、partial clone promisor 和 LFS 外部存储；
- linked worktree、submodule 和服务端 quarantine/临时目录的取舍；
- 数据库、对象存储与 refs 的一致性点；
- 恢复所需软件版本、配置、证书和密钥。

直接复制单个 `.git/objects` 目录不能恢复引用、默认分支和服务控制面；只复制 refs 又可能缺少 pack 中的对象。物理快照完成后仍应在隔离环境启动或用 Git plumbing 验证逻辑闭包。

## 平台与外部对象要有独立恢复路径

### Git LFS

Git bundle 和 mirror 保存 pointer blob，不保证 payload 已备份。恢复演练必须对每个恢复 ref 枚举 LFS OID/size，确认备份存储可读，再在无生产网络依赖的环境执行 LFS fetch/checkout/fsck。锁、配额、访问策略和 LFS 服务元数据也不在 pointer 中。

### Submodule

Superproject 只恢复 mode 160000 与外部 commit OID。清单需要列出每个 `.gitmodules` URL、gitlink OID、目标仓库备份和恢复顺序。仅恢复 superproject 后 `git submodule update` 失败，通常是依赖仓库或固定 commit 不可用，不是 superproject tree 损坏。

### 托管平台控制面

Issue、合并请求、评论、审批、分支规则、团队权限、webhook、CI 变量、审计日志和 release/package 元数据由平台定义。应使用厂商支持的导出、API 或服务备份，并记录：产品版本/套餐、管理员权限、分页与速率限制、隐藏对象范围、导出格式、附件和删除保留期。平台 API 导出脚本通过不等于附件、审计或密钥已被恢复。

Secrets 通常不能以明文导出；恢复设计应从密钥管理系统重新绑定或轮换，而不是试图把 CI secret 塞进 Git bundle。

## 用恢复演练证明备份可用

恢复演练不能只运行 `bundle verify`。一个最小演练应在与生产隔离的网络、账号和存储命名空间中执行：

1. 选择明确恢复点，冻结备份集合和摘要；
2. 从空目录/空服务实例开始，不复用管理员日常缓存；
3. 恢复 Git refs、symbolic HEAD 和对象，运行 `fsck --full --strict`；
4. 比较完整 refs manifest、关键 tag peeled target、notes 和候选 tree；
5. 恢复 LFS 和所有 submodule 固定 commit；
6. 恢复评审/issue/权限/规则等平台数据，记录无法自动恢复项；
7. 用普通只读客户端 clone/fetch，构建固定候选并核对制品摘要；
8. 测量实际 RPO/RTO，记录人工步骤、权限缺口和失败注入；
9. 销毁演练环境或按审计要求归档证据，不让测试端点成为影子生产。

切换生产前还要处理写入围栏、DNS/入口、旧主站隔离、客户端 stale refs、CI/webhook 重放和凭据轮换。恢复出一棵 Git tree 只是数据面的一部分。

## 备份验收清单

| 检查 | 通过条件 |
| --- | --- |
| 恢复点身份 | 时间、源实例、对象格式、refs 和外部系统点位可追溯 |
| 完整性 | 文件摘要、bundle verify、Git fsck 和外部对象检查通过 |
| 完整性范围 | branches/tags/notes/自定义/隐藏 refs 的包含或排除均有记录 |
| 自包含性 | 恢复环境不依赖未知 alternates、promisor、开发机 cache 或在线源站 |
| 语义一致性 | 默认分支、关键 tree、tag、LFS、submodule 和制品互相对应 |
| 安全性 | 备份加密、访问最小化、读取审计、密钥轮换和删除策略有效 |
| 保留性 | 误删/强推不能立即覆盖所有历史恢复点，跨故障域副本可用 |
| 可操作性 | 值班人员按 runbook 在 RTO 内完成，未知项和审批路径明确 |

## 常见失败与恢复

| 症状 | 原因 | 安全动作 |
| --- | --- | --- |
| bundle 创建失败或为空 | revision 没有可广告 ref、对象缺失、空间/权限不足 | 保留 stderr；重新固定 refs 和容量，不覆盖上一恢复点 |
| 增量 bundle 在空仓库 verify 失败 | 缺少 header 声明的 prerequisite | 先恢复匹配的完整基线和前序增量；不要跳层 |
| fsck 通过但大文件 checkout 失败 | 只恢复了 LFS pointer，没有 payload | 按 OID/size 恢复 LFS 存储并再次验证 |
| notes、自定义 ref 或评审 ref 缺失 | 使用了默认 clone/fetch refspec，或备份源不可见 | 对照 refs manifest，在空仓库显式恢复批准 namespace |
| mirror 中分支随源端消失 | `--prune` 传播删除，且没有不可变历史恢复点 | 冻结 mirror，从上一份保留快照恢复到隔离 namespace |
| 文件系统副本偶发 corrupt/missing | 复制时 refs 与 pack 正在变化，或遗漏共享对象池 | 使用应用一致性快照；盘点 common dir/alternates 后重做 |
| 备份存在但无法在灾难账号解密 | key 与备份同故障域、权限过期或 runbook 未演练 | 使用批准的密钥托管和 break-glass 流程，定期无缓存演练 |
| 恢复后旧 clone 再次推回错误历史 | 没有写入围栏、旧端点仍在线或用户未重新同步 | 隔离旧服务，条件开放写入，发布 old/new refs 映射 |

## 合成实验：从完整 bundle 到镜像删除传播

本书提供 `scripts/verify-bundle-mirror-recovery.sh`。实验在 `mktemp` 下创建合成仓库，不连接网络、LFS 或托管平台。

在仓库根目录执行：

~~~bash
bash scripts/verify-bundle-mirror-recovery.sh
~~~

脚本验证：

1. branches、annotated tag、notes 和自定义 refs 能进入显式完整 bundle；
2. 空 bare 仓库通过全 refs refspec 恢复后，refs manifest、tree、tag、notes 和 `fsck` 一致；
3. 未被任何 ref 引用的 blob 不会因逻辑 bundle 自动成为恢复对象；
4. 增量 bundle 在空仓库因缺少 prerequisite 失败，在已恢复完整基线后可验证和导入；
5. `clone --mirror` 取得 refs，却不复制任意 source local config、hook、未跟踪文件和不可达 blob；
6. `remote update --prune` 会同步新增 tag，并删除源端已删除或 mirror 独有的 refs。

实验不验证真实 Git 服务备份、数据库一致性、平台隐藏 refs、LFS、对象存储、加密、跨区域复制、访问控制或实际 RPO/RTO。这些项目必须在组织拥有的专用环境演练。

## 小结

Bundle 是指定 refs 的逻辑时间点，mirror 是持续同步拓扑，文件系统快照是物理状态副本；三者都不是完整研发平台的同义词。可靠备份把 Git refs/objects、LFS、submodule、平台控制面、制品和身份配置分别纳入恢复点，并用摘要和清单把它们关联起来。

备份是否成立，只能由从空环境开始的恢复演练证明。验证应覆盖引用集合、对象闭包、默认分支、外部 payload、客户端访问和平台流程，并测量真实 RPO/RTO。下一章将进入跨版本控制系统和托管平台迁移，继续处理身份、标签、评审和权限的映射问题。

## 资料

- [git-bundle](https://git-scm.com/docs/git-bundle)
- [git-clone](https://git-scm.com/docs/git-clone)
- [git-fetch](https://git-scm.com/docs/git-fetch)
- [git-push](https://git-scm.com/docs/git-push)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-fsck](https://git-scm.com/docs/git-fsck)
- [gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)
