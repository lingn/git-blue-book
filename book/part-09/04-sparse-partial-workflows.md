# 稀疏与部分工作流：减少本地负担，不削弱候选证据

“只 checkout 需要的目录”“只下载需要的对象”和“只保留最近几次提交”经常被混成一个优化开关。它们改变的是不同层面的本地状态：refspec 选择引用，shallow 截断历史，partial clone 过滤对象，sparse-checkout 选择工作区路径。任何一层受限，都可能让一个在本地看似成功的命令无法回答完整的工程问题。

本章承接[refspec、浅克隆与部分克隆](../part-4/14-refspec-partial-clone.md)和[性能基线](01-measure-before-optimizing.md)。前一章解释数据面如何传输，本章负责工作流决策：什么时候可以让 CI 或开发者使用受限状态，怎样声明缺失边界，何时必须恢复完整历史、对象或工作区。已有的 `scripts/verify-refspec-partial-clone.sh` 作为机制实验，本章不把它的本地 `file://` 输出当成真实平台能力证明。

本章以 Git 2.49.0、本地 bare 远端和 macOS 为核对基线，日期为 2026-08-23。部分克隆、bundle URI、服务端 filter、sparse-index 兼容、平台缓存和计费会随 Git、服务器、客户端和套餐变化，生产采用前应记录版本、权限、网络、保留和核对日期。

## 进入条件和退出能力

进入本章前，读者应理解 refs、commit/tree/blob、远程跟踪、对象过滤、index、工作区和构建输入闭包。读完后，应能：

- 区分引用范围、历史深度、对象可见性和工作区路径范围；
- 解释 sparse-checkout、sparse-index、partial clone、shallow clone 和负 refspec 的组合与限制；
- 为开发者、CI、代码搜索和发布任务选择完整或受限状态，并记录恢复路径；
- 识别按需对象请求、稀疏路径外修改、浅历史导致的错误版本计算和 ref 漂移；
- 在不覆盖本地修改或误删证据的前提下恢复历史、对象和工作区；
- 说明本地实验只验证 Git 数据面，不能证明服务端 filter、网络、权限和成本。

## 四个旋钮，四类缺口

| 机制 | 主要改变 | 本地看得到什么 | 不能直接证明什么 |
| --- | --- | --- | --- |
| refspec | 哪些 refs 被获取或更新 | 当前可见的本地/远程跟踪 refs | 服务器是否存在未选择的 refs |
| shallow clone | 祖先历史的边界 | `.git/shallow`、边界 commit | 更早提交、merge-base、版本历史一定完整 |
| partial clone/filter | 哪些 Git 对象暂不取得 | promisor 配置、缺失对象标记 | 离线可用、服务端长期保留、payload 已恢复 |
| sparse-checkout | 哪些 tracked paths 展开到工作区 | sparse 规则、index 标志、路径存在性 | 未展开路径不存在于 tree 或构建输入 |

四个机制可以叠加。例如一个 CI runner 只抓 `main`，历史深度为 1，使用 `blob:none`，再只展开 `service-a`。它可能足以运行一个声明了输入闭包的构建，也可能无法计算变更范围、读取版本文件、递归取得子模块或生成完整归档。受限状态不是“更快的完整 clone”，而是另一种需要契约的输入。

## 先声明工作负载，再选择限制

不同任务需要不同完整性：

| 工作负载 | 默认建议 | 允许的限制 | 需要额外门禁 |
| --- | --- | --- | --- |
| 交互式编辑单个服务 | 完整 refs，按目录 sparse | sparse-checkout、必要时 sparse-index | 工具、IDE、生成器不能静默访问未展开路径 |
| 变更影响分析 | 完整目标/基线历史和依赖图 | 可按 refs 过滤，通常不 shallow | 路径策略和构建图缺失时保守扩大检查 |
| 短命单服务 CI | 精确 candidate、声明的输入闭包 | shallow、partial、sparse | 版本计算、测试发现和归档动作有回退路径 |
| 发布构建和来源证明 | 完整候选和构建输入 | 只有经过证明的对象按需获取 | 不能因缺对象、浅边界或 sparse 路径跳过输入 |
| 取证、迁移、灾备 | 完整 refs、对象和历史 | 不建议使用受限状态 | 受限副本只能作为带边界的证据来源 |

不要以“本地工作区能编译”作为受限状态的通用验收。构建系统可能只编译已展开目录，遗漏共享 schema、生成器、许可证、测试夹具或依赖版本。输入闭包应在候选 commit 上计算，路径选择只能作为减少成本的实现，不得改变候选语义。

## Sparse-checkout 管理工作区，不改变 commit tree

在一个已固定候选、工作区修改已经保存的非裸仓库中，可以查看当前稀疏规则：

```bash
git sparse-checkout list
git config --show-origin --get-regexp '^core\.sparseCheckout|^index\.sparse$'
git ls-files -t | sed -n '1,20p'
```

第一条在未启用 sparse-checkout 时可能非零，第二条没有匹配也可能非零；这些状态要原样记录。`ls-files -t` 的标志受 Git 版本和 index 状态影响，不应把单个字母当成完整诊断。命令只读配置和 index，通常不改变工作区。

设置目录范围会更新 sparse 规则、index 和工作区：

```bash
git sparse-checkout set --cone services/payments shared
git sparse-checkout reapply
git status --short --branch
```

前置条件是当前工作区没有要覆盖的未提交 tracked 修改，规则已经过代码所有者和构建图审查，路径不存在冲突。`set` 可能删除不在范围内的已跟踪工作区文件，并展开新范围；它不删除候选 tree 中的对象和历史。路径拼写、cone 模式限制、未跟踪冲突、filter/LFS 水合和平台文件系统都可能导致失败。失败后保存原规则和工作区差异，不要手工删除 `.git/info/sparse-checkout`。

如果必须让一个工具暂时读取范围外路径，优先在一次性 worktree 使用 `git sparse-checkout add` 或 `disable`，完成后恢复并核对工作区。`disable` 会展开所有 tracked paths，可能带来大量磁盘和 LFS 请求；不要在低容量 runner 里把它当无成本诊断。

### Sparse-index 是 index 的表示优化

Sparse-index 可以用 sparse-directory entry 表示未展开的目录，减少 index 大小和部分命令工作量。它不改变 commit tree，也不授予范围外路径读取权限。启用前要确认 Git、IDE、格式化器、构建器和脚本都能处理 sparse-directory entry；一些工具会要求扩展 index 或直接遍历工作区。

启用和关闭都应在可恢复副本测试：

```bash
git sparse-checkout reapply --sparse-index
git config --get index.sparse
git sparse-checkout reapply --no-sparse-index
```

具体选项和支持版本以 `git sparse-checkout -h` 为准。前两条可能写入 index，第三条会重新展开 index 表示；不要在有未解决冲突或未保存路径的现场直接切换。验证重点是 `git ls-tree -r <candidate>`、路径级 diff、构建输入和工作区状态保持一致，而不是 index 字节必须相同。

## Partial clone 把缺失对象变成运行时依赖

部分克隆通常使用 promisor remote 和 object filter，例如：

```bash
git clone --filter=blob:none --no-checkout <REMOTE> <DIRECTORY>
git config --show-origin --get-regexp \
  '^remote\..*\.(promisor|partialclonefilter)$'
git rev-list --objects --all --missing=print | sed -n '1,20p'
```

前置条件是服务器允许过滤协商、远端身份和权限已核对，目标目录可销毁，网络和磁盘预算足够。`clone` 取得 commit/tree 等基础对象并把缺失对象交给 promisor，后两条只读配置和可见对象。缺失对象标记并不表示损坏，表示它可能在需要时由 promisor 提供。

读取缺失 blob 可能触发按需网络请求：

```bash
git show <CANDIDATE>:services/payments/schema.sql > /restricted/review/schema.sql
git cat-file -e '<BLOB-OID>'
```

前置条件是允许当前身份访问 promisor，目标路径和输出文件已审查，目标目录不是生产工作树。成功表示本次对象可取得并写入审查文件，不表示所有历史对象或后续离线构建输入完整。认证、超时、服务端过滤不支持、对象被清理或本地容量不足时停止，保存原始 stderr 和缺失对象 OID。

发布、取证和灾备任务通常应先从完整 clone 或完整 bundle 建立基线。若必须使用 partial clone，构建清单要列出 filter、promisor identity、实际请求对象、网络状态和离线恢复路径。不得把“第一次构建没有触发缺失对象”写成完整来源证明。

## Shallow clone 影响祖先关系，不只是少下载几次提交

浅克隆的边界会影响 `merge-base`、变更范围、版本生成、签名链、`git describe`、cherry-pick 上下文和发布候选。先记录：

```bash
git rev-parse --is-shallow-repository
git rev-list --boundary --oneline <CANDIDATE>
cat .git/shallow
```

`true` 说明本地存在 shallow boundary；边界 commit 不是错误，也不证明远端没有祖先。需要完整历史时，在受控 clone 中执行：

```bash
git fetch --deepen=100 origin <BRANCH>
git fetch --unshallow origin
```

两条命令都会写对象、远程跟踪 refs、`FETCH_HEAD` 或 `.git/shallow`；执行前保存快照，执行后重新保存并比较。远端也可能浅、权限不足、网络中断或容量不足。不要手工删除 `.git/shallow`，否则可能把缺失祖先误判为完整历史。

## 受限工作流的输入契约

CI 或开发工具采用受限状态时，输入清单至少保存：

```text
candidate_commit / candidate_tree
refspecs / excluded_refs
shallow_boundary / depth
object_filter / promisor_identity
sparse_mode / sparse_rules / sparse_index
required_paths / generated_paths / dependency_closure
Git_version / checkout_tool_version
objects_fetched_on_demand
offline_behavior / fallback_to_full_clone
```

候选、tree 和依赖闭包决定“应该有什么”；受限配置决定“现在取得了什么”。两者不能只用一个 `HEAD` 字段代替。路径过滤如果无法证明共享依赖，应扩大到保守检查集；无法取得必要对象时状态为 `inconclusive`，不应跳过测试或发布。

## 组合故障与恢复

| 症状 | 先固定 | 恢复动作 | 不要做的事 |
| --- | --- | --- | --- |
| sparse 工作区缺少构建输入 | candidate tree、规则、构建图、index | 在一次性 worktree 扩大范围并复跑输入核对 | 手工复制范围外文件冒充 checkout |
| partial clone 读取 blob 失败 | OID、promisor config、网络/权限和原始错误 | 恢复 promisor 或用可信完整 clone 取得同一对象 | 把新生成文件写回旧路径当恢复 |
| shallow clone 无法计算 merge-base | boundary、目标/功能 OID、任务要求 | deepen/unshallow 或换完整 clone | 把 boundary 当共同祖先 |
| sparse-index 工具报未知 entry | Git/工具版本、index 模式、规则 | 关闭 sparse-index 或扩展 index，验证 tree 不变 | 直接删除 index 重新 add 全仓库 |
| 受限 checkout 显示绿色但发布缺少文件 | 输入清单、构建日志、实际请求对象 | 阻止发布，完整取得候选输入后重建 | 用当前分支重新构建覆盖记录 |
| 远程跟踪 ref 不见 | refspec、服务器可见性和本地缓存 | 重新固定候选，必要时按权限查询远端 | 通过创建本地 ref 隐藏来源缺口 |

恢复后要重新计算候选 tree、输入清单和制品摘要。把受限 clone 原地“补全”可能改变测量和证据上下文；关键发布或事故调查应保留原副本，另建完整副本执行恢复。

## 隔离实验与真实边界

在仓库根目录运行：

```bash
bash scripts/verify-refspec-partial-clone.sh
```

前置条件是 Bash、Git 2.49 或兼容实现、`awk`、`grep`、`sed`、`mktemp` 和可写临时目录。实验使用本地 bare 远端和虚构身份，创建负 refspec、浅克隆、部分克隆和 sparse-checkout，退出时清理临时目录，不连接网络，也不修改本书仓库。

实验验证：

1. 负 refspec 不创建被排除的远程跟踪 ref，也不取得其分支尖端；
2. shallow clone 的边界和 deepen/unshallow 会改变本地历史可见性；
3. `blob:none` 部分克隆在读取指定对象时按需取得 blob；
4. sparse-checkout 只改变工作区展开范围，关闭后候选文件仍可恢复；
5. 受限机制恢复后，引用、对象和路径结果可以重新核对。

实验不验证真实服务端 filter、SSH/TLS、凭据、平台隐藏 refs、冷/热缓存、费用、LFS、子模块、CI runner 或生产构建完整性。它也不提供性能收益结论，目标环境必须按[性能基线](01-measure-before-optimizing.md)重新测量。

## 小结

受限工作流不是一个开关，而是 ref、历史、对象和工作区四层状态的组合。Sparse-checkout 让工作区更小，partial clone 让对象按需取得，shallow clone 截断祖先，refspec 减少引用范围；每一层都可能改变命令能证明的事实。

先按工作负载声明候选、依赖和离线要求，再选择限制；构建、发布、取证和灾备默认要求更完整的输入。遇到缺失或边界不明确时保留 OID、原始错误和受限副本，恢复到完整状态后重新核对，不要用“本地目录里能跑”代替来源证明。

## 资料

- [git-sparse-checkout](https://git-scm.com/docs/git-sparse-checkout)
- [git-clone](https://git-scm.com/docs/git-clone)
- [git-fetch](https://git-scm.com/docs/git-fetch)
- [git-rev-list](https://git-scm.com/docs/git-rev-list)
- [git-ls-files](https://git-scm.com/docs/git-ls-files)
- [partial clone](https://git-scm.com/docs/partial-clone)
