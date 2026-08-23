# 故障转移不是改 DNS：远端丢失、区域故障与安全回切

主仓库不可访问时，把域名指向另一台服务器看似直接，但真正的第一个问题是：另一端到底停在哪个恢复点？如果副本少了最后三次 push、LFS payload 尚未复制、平台数据库比 Git refs 更旧，立刻开放写入会把一次可用性故障变成永久数据分叉。

灾难恢复需要同时处理三个目标：恢复服务、守住已确认数据、保留故障证据。热备可以缩短启动时间，却可能同步误删和损坏；不可变备份能回到过去，却通常有更长 RTO；开发者 clone 可能持有最后提交，却不应未经验证就升级为组织权威。

本章以 Git 2.49.0、Bash 和多个本地 bare 仓库验证 Git 数据面的异步复制、滞后识别、donor 补齐、条件引用提升与旧主围栏。本地实验不模拟真实区域、DNS/TLS、负载均衡、托管平台数据库、LFS、身份系统、CI 或对象存储；这些系统必须按组织架构和厂商能力在专用环境演练。

进入本章前，读者应理解现场保护、对象取证、refs、mirror、bundle prerequisite、RPO/RTO、迁移 cutover、LFS 和平台控制面。读完后，应能：

- 区分不可用、数据损坏、安全事故和控制面丢失；
- 量化副本相对权威 refs 与外部对象的复制滞后；
- 选择热备、不可变备份或可信 donor 作为恢复候选；
- 在旧主已围栏、候选已验证的前提下执行条件提升；
- 用普通客户端和 CI/制品链验收后再开放写入；
- 把旧主回归视为重新建副本，而不是自动切回。

## 先分类故障，避免把错误状态复制得更快

| 故障类型 | 典型现象 | 首要动作 | 不应立即做 |
| --- | --- | --- | --- |
| 入口/网络不可用 | DNS、TLS、代理、负载均衡或网络失败 | 确认数据面是否仍健康，围栏重试写入 | 假定存储也丢失并重建历史 |
| 应用/控制面不可用 | Git 服务进程、数据库、队列异常 | 保存控制面状态，评估一致恢复点 | 只提升裸 Git objects 后开放全部平台功能 |
| Git 对象或 refs 损坏 | missing/corrupt、refs 指向错误对象 | 停止复制与维护，进入取证恢复 | 把当前主站强制同步到所有副本 |
| LFS/附件/制品丢失 | Clone 成功但 checkout、评审附件或部署失败 | 冻结相关发布，恢复外部对象清单 | 用 `git fsck` 通过宣称系统完整 |
| 凭据或供应链事故 | 非授权 push、token 泄漏、依赖被替换 | 撤销凭据、保存审计、固定可信点 | 单纯切换区域并继续使用同一凭据 |
| 整个故障域丢失 | 计算、存储、身份或网络同时不可用 | 启动跨故障域 runbook 与决策权限 | 临时拼装未经演练的“新主站” |

可用性故障可以从最新健康副本继续；完整性故障必须找到损坏前的恢复点；安全事故还要撤销身份和隔离污染来源。三者共用部分工具，但恢复候选和开放条件不同。

## RPO 要按每一种状态分别计算

Git 主分支的 RPO 为 0，不代表平台 RPO 为 0。一次 push 可能同时依赖：

- Git ref 更新和新对象；
- LFS payload/lock；
- 合并请求、审批和审计事件；
- CI workflow、cache、artifact 和 package；
- release/deployment 记录；
- webhook、队列和外部系统副作用。

恢复清单应为每个组件记录最后成功复制的源事件、目标点和验证时间：

~~~text
replication_checkpoint = {
  git_refs_at,
  platform_event_id,
  lfs_manifest_at,
  artifact_replication_at,
  audit_export_at,
  backup_snapshot_id,
  verified_at
}
~~~

时间戳只是线索。两端时钟可能不同，异步任务也可能乱序；Git 层优先比较完整 ref/OID，平台层比较单调事件 ID、事务日志位置或厂商定义的恢复点。不能用“副本最后更新时间是刚刚”代替对象和关系核对。

RTO 也应拆成检测、决策、数据恢复、控制面启动、验收、流量切换和开放写入。只测虚拟机启动时间，无法代表研发服务恢复时间。

## 热备、冷备和开发者 clone 解决不同问题

### 热备/镜像

优点是 refs 和对象通常接近主站，可快速提供只读或提升。缺点是误删、force update、恶意对象和逻辑损坏可能随复制传播；同步删除的 mirror 也没有历史保留窗口。

### 不可变备份

Bundle、存储快照和平台备份可以回到已验证恢复点，抵抗部分误操作和勒索/删除。缺点是 RPO 受备份频率影响，恢复控制面和外部对象需要更长时间。备份必须在独立故障域和权限边界，且密钥能在灾难账号下取得。

### 开发者/CI clone

可能持有主站尚未复制的 commit，可作为 donor 候选。普通 clone 通常没有全部 branches/tags/notes/隐藏 refs、LFS 全量 payload、reflog 或平台数据；工作区还可能有未提交修改、replace refs、alternates 或不可信配置。先按证据来源隔离和验证，不把某位开发者的 main 直接命名为组织 main。

恢复架构通常同时需要三层：热备缩短 RTO，不可变备份提供历史恢复点，分散 clone 作为最后的对象线索。它们不能互相替代。

## 复制滞后必须由 refs 和对象证明

故障前的健康监控可以分别采集主/备广告：

~~~bash
git ls-remote --symref "$primary_url" > primary.refs
git ls-remote --symref "$standby_url" > standby.refs
~~~

命令只读取当前身份可见的 refs。比较时保留完整 OID、refname、采集时间、服务端身份和退出码；默认 HEAD 相同不等于所有 namespace 相同。隐藏评审 refs、notes、自定义归档 refs 和平台数据库需用对应管理员接口核对。

若有受控 bare 副本，可保存机器清单：

~~~bash
git -C "$repo" for-each-ref \
  --format='%(refname)%00%(objecttype)%00%(objectname)%00%(*objectname)%00' \
  > refs.nul
git -C "$repo" fsck --full --strict --no-progress
~~~

`fsck` 通过说明当前根集合连接完整，不证明副本是最新、无恶意内容或包含 LFS。主站已不可用且没有故障前 manifest 时，不能精确声称“零丢失”；只能列出当前已知副本、donor 和外部事件，给出置信度。

## 故障转移是一条有门禁的状态机

~~~text
NORMAL
  -> SUSPECTED
  -> WRITES_FENCED
  -> RECOVERY_POINT_SELECTED
  -> CANDIDATE_VALIDATED
  -> PROMOTED_READ_ONLY
  -> ACCEPTED
  -> WRITES_OPEN
  -> STABILIZED
  -> OLD_PRIMARY_RESEEDED
~~~

每次状态变化都要有负责人、时间、输入证据、批准和回退点。不能从 `SUSPECTED` 直接跳到 `WRITES_OPEN`。

### 1. 宣布事故并围栏全部写入入口

围栏范围包括 Git push、平台 merge、tag/release、LFS 上传、issue/评论、机器人、CI 写回、webhook 重试和管理员旁路。只把网页设为维护模式而 SSH push 仍可用，不是围栏。

若旧主完全失联，网络隔离提供了临时围栏，但仍要防止它恢复后自动重新加入负载均衡或复制拓扑。记录旧主实例、存储、IP/证书和复制身份，准备显式 quarantine。

### 2. 保存故障前后证据并选择恢复点

使用第一章的现场采集规则保存可用主/备状态、复制检查点、监控、审计、队列和外部对象清单。候选优先级不是简单的“时间最新”：

1. 已验证且与控制面/LFS 一致的健康热备；
2. 已验证不可变恢复点加后续可信增量；
3. 从多个独立 donor 重建的候选；
4. 无法证明的单个开发 clone，只能作为调查线索。

选择较旧恢复点意味着明确接受 RPO 损失；选择更新 donor 意味着增加来源核验和外部一致性工作。两种决定都要记录。

### 3. 在隔离环境验证候选自包含

~~~bash
git -C "$candidate_repo" rev-parse \
  --is-bare-repository --show-object-format --show-ref-format
git -C "$candidate_repo" config --get extensions.partialClone
git -C "$candidate_repo" rev-parse --git-path objects/info/alternates
git -C "$candidate_repo" fsck --full --strict --no-progress
~~~

`config --get` 在未配置 partial clone 时应非零退出；alternates 路径存在不等于文件存在，必须检查文件和环境变量。断开未批准的 donor/网络后再验证一次，避免提升后才发现对象按需来自失联主站。

还要验证 refs 范围、replace refs、默认 HEAD、关键 tree/tag/signature、LFS、submodule 和平台数据库。候选读得出来不等于能承担完整服务。

### 4. 把 donor 对象先放入恢复 namespace

可信 donor 可以生成增量 bundle：

~~~bash
git -C "$donor_repo" bundle create donor.bundle \
  "$standby_tip..refs/heads/main"
git -C "$candidate_repo" bundle verify donor.bundle
git -C "$candidate_repo" fetch donor.bundle \
  '+refs/heads/main:refs/recovery/incident-2026-08/main'
~~~

前提是 donor 的 main 以 standby_tip 为祖先，且身份、对象和来源已经登记。Bundle verify 失败可能表示 prerequisite 缺失或 donor 历史不是预期后继；此时停止，不要使用 `--force` 把候选 ref 直接覆盖 main。

恢复 namespace 让调查者先比较 parent、tree、diff、签名和外部评审，再决定是否提升。Donor author 字段不是来源信任证明；应结合多个 clone、CI checkout、制品 digest 和审计事件交叉验证。

### 5. 用期望旧值条件更新恢复候选

在组织批准管理的本地 bare 恢复仓库中：

~~~bash
git -C "$candidate_repo" update-ref \
  refs/heads/main "$recovered_tip" "$standby_tip"
~~~

命令仅当 main 仍等于 standby_tip 时移动引用；若另一名操作员或复制进程已改变 main，会非零拒绝。它写 refs/reflog（若启用），不修改 commit 对象。失败后重新读取状态和审批，不删除期望旧值重试。

托管平台不应绕过受支持控制面直接修改服务器磁盘。使用平台提供的条件 API、事务或维护流程，并记录厂商、版本、权限和核对日期；本地 `update-ref` 实验只证明 Git 引用的比较并交换语义。

### 6. 先以只读状态启动，再做端到端验收

提升后的验收至少覆盖：

- 普通身份从空缓存 clone/fetch，默认分支和全 refs 符合 manifest；
- Git `fsck`、关键 tree/tag/notes/signature 通过；
- LFS payload、submodule 和附件可取；
- issue/评审/权限/保护规则/审计可用；
- CI 检出精确候选，构建制品 digest 与恢复点对应；
- 受控 canary ref 可以写入、读取和删除（按平台流程），非授权写入被拒绝；
- webhook、队列、通知和部署不会重放旧副作用。

只读验收失败时保持旧主围栏，修复候选或选择另一恢复点。不要为了满足 RTO 指标跳过 LFS、权限或制品验证。

### 7. 开放写入并固定新权威

开放顺序应有明确协调者：先更新入口与服务发现，再逐步开放普通客户端、机器人、CI 和管理员路径；持续监控失败率、复制滞后、refs 异常和外部对象缺失。

客户端 DNS、SSH ControlMaster、HTTP 连接池和代理可能仍指向旧端，不能只依靠低 TTL。旧主网络/凭据围栏应保持，直到确认所有入口和自动化已迁移。

## 旧主恢复后不能自动回切

新主开放写入后会产生旧主没有的 refs、平台事件、LFS 和制品。此时旧主即使“磁盘看起来正常”，也只是陈旧副本。安全顺序是：

1. 旧主继续隔离和只读取证；
2. 从当前新权威生成经过验证的全量基线；
3. 清空或新建旧主恢复环境，按副本流程重新播种；
4. 验证 Git、LFS、平台数据库和策略追平；
5. 让它以 standby 身份运行完整观察窗口；
6. 只有新的故障转移审批才允许再次提升。

不要把旧主的 mirror 任务恢复为向新主 `--mirror` push；它可能删除灾后新 refs。Failback 是另一次迁移/切换，不是撤销 DNS。

## 数据损坏和区域不可用走不同恢复路径

### 主站不可达，但数据被证明健康

如果热备 checkpoint 满足 RPO，控制面和外部对象一致，可以直接进入候选验证和只读提升。仍需围栏旧主，避免恢复后双写。

### 主站损坏，复制可能已受污染

立即暂停复制、GC、repack 和自动修复。比较多个时间点备份和副本，找到污染前恢复点；再按对象取证章节验证 donor。最新副本未必最可信。

### 主站存储丢失，但客户端持有新提交

冻结所有 donor，先保存 refs/objects/工作区差异和来源。按 commit DAG、评审、CI/制品和多个 clone 交叉确认，把候选放到 `refs/recovery/`。Git 提交可恢复不代表 issue、LFS 或部署记录已经恢复。

### 区域级基础设施丢失

恢复顺序受依赖图约束：身份/密钥与网络入口、数据库/对象存储、Git/LFS、平台应用、队列/webhook、CI/制品和外部集成必须使用相容恢复点。顺序可以按架构调整，但不能让上层先产生写入，再回滚下层状态。

### 安全事故伴随故障转移

在恢复服务前撤销被盗 token/key/session，隔离污染 refs/制品，重建机器身份和信任策略。把同一管理员凭据复制到灾备区会把攻击路径一起恢复。

## 故障恢复运行手册要能由值班人员执行

Runbook 至少包含：

| 阶段 | 必备内容 |
| --- | --- |
| 宣告 | 严重度、决策人、通信频道、写入围栏权限 |
| 发现 | 服务、refs、对象、LFS、数据库、身份、CI 的观测与退出码 |
| 恢复点 | checkpoint、RPO 损失、donor、备份摘要和批准 |
| 提升 | 基础设施顺序、条件更新、默认分支、凭据与旧主隔离 |
| 验收 | 普通 clone、canary write、CI/artifact、权限、审计与业务检查 |
| 开放 | 流量/写入分批、监控阈值、停止条件和回退方向 |
| 稳定 | 复制重建、客户端清理、事件复盘和备份补齐 |

每次演练记录实际 RPO/RTO、人工步骤、需要临时权限的环节、未覆盖平台能力和失败注入结果。演练环境不得复用生产写入端点，测试数据和临时凭据按保留策略销毁。

## 常见失败与恢复

| 症状 | 原因 | 安全动作 |
| --- | --- | --- |
| Standby `fsck` 通过但 main 落后 | 对象闭包完整，不代表复制最新 | 比较 refs/checkpoint，选择接受 RPO 或验证 donor |
| Failover 后最后提交“消失” | 异步复制尚未包含该 ref/object | 冻结写入，从备份/CI/clone 找候选，先写 recovery ref |
| Donor bundle verify 缺 prerequisite | Standby 太旧、历史分叉或 donor 不完整 | 获取正确基线，核对 parent；不强制覆盖 main |
| 提升引用时 expected old 不匹配 | 并发复制/操作员已移动 ref | 重新采集状态和审批，保留拒绝证据 |
| Clone 成功但 LFS/附件/CI 失败 | 只恢复 Git 数据面 | 保持只读，恢复外部对象和控制面再开放 |
| 旧主恢复后出现新写入 | 网络/凭据/自动化围栏不完整 | 冻结两端，盘点独有事件，重新选择单一权威 |
| 自动 failback 删除灾后 refs | 陈旧 mirror 以 `--mirror` 覆盖新权威 | 停止任务，从新主重建旧端副本 |
| 区域切换后认证全部失败 | 身份、证书、密钥或时钟依赖未恢复 | 使用批准 break-glass，恢复/轮换信任链并审计 |
| RTO 达标但恢复点错误 | 只计启动时间，未验证数据和外部关系 | 回到只读，按 manifest 做端到端验收 |

## 合成实验：复制滞后、donor 恢复与旧主围栏

本书提供 `scripts/verify-disaster-failover-recovery.sh`。实验只在 `mktemp` 下使用本地 Git 仓库和虚构身份，不修改网络、DNS 或真实服务。

在仓库根目录执行：

~~~bash
bash scripts/verify-disaster-failover-recovery.sh
~~~

脚本验证：

1. 异步 standby 停在 checkpoint，而 primary 后续多一个 commit；`fsck` 通过不能发现复制滞后；
2. Primary 路径隔离后旧 endpoint 读取失败，donor clone 仍持有晚到 commit；
3. Donor 增量 bundle 必须以 standby commit 为 prerequisite，并先导入 `refs/recovery/`；
4. 候选 parent/tree 验证后，带期望旧值的 `update-ref` 完成提升；陈旧期望值会被拒绝；
5. 新建 recovered primary 只导入批准 namespace，refs manifest、notes 和 `fsck` 与故障点一致；
6. Acceptance client 能在新主继续 push，而恢复在线的旧主通过 receive hook 拒写并保持陈旧状态。

实验不能验证真实区域、同步复制、托管平台数据库、DNS/TLS、身份、LFS、对象存储、CI、负载均衡、hook 管理或实际 RPO/RTO。生产故障转移必须使用平台支持的围栏和提升机制，不能把本地文件路径实验当作服务级证明。

## 小结

灾难恢复的核心不是最快找到一个能接受 push 的仓库，而是在单一写入权威下选择可解释的恢复点，验证 Git 与外部系统一致，再受控开放服务。热备解决时间，不可变备份解决回到过去，donor 解决缺失线索；三者都需要 refs、对象、平台事件和外部 payload 证据。

旧主恢复在线后仍必须围栏，并从新权威重新建副本。Failback 是新的切换，不是把 DNS 改回去。至此第十一篇完成了从现场保护、对象取证、历史归因、备份、迁移到故障转移的主链；后续组织治理篇将把这些动作变成仓库生命周期、权限回收、审计留存和定期演练制度。

## 资料

- [git-ls-remote](https://git-scm.com/docs/git-ls-remote)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-fsck](https://git-scm.com/docs/git-fsck)
- [git-bundle](https://git-scm.com/docs/git-bundle)
- [git-fetch](https://git-scm.com/docs/git-fetch)
- [git-update-ref](https://git-scm.com/docs/git-update-ref)
- [git-clone](https://git-scm.com/docs/git-clone)
