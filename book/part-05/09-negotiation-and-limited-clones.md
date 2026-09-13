# 协商与受限克隆：少传数据会改变本地证据边界

一次 fetch 并不是把远端目录复制到本地。客户端先选择 refs，再与服务端判断哪些对象已经拥有，服务端据此生成 pack。浅克隆、部分克隆和稀疏检出又分别限制祖先、对象和工作区路径。它们都能减少某类成本，但留下的缺口不同。

“代码已经 checkout”只证明当前工作区所需的一部分数据可用。版本计算可能缺 tag 或祖先，离线构建可能缺 blob，取证与备份还可能缺隐藏 refs、LFS 和平台数据。

## 进入条件与完成标准

开始前应理解[提交图与可达性](../part-03/04-commit-graph-and-reachability.md)、[remotes/refspec](03-remotes-and-refspecs.md)和 [fetch 状态变化](04-fetch-and-fetch-head.md)。本章以 Git 2.49.0 验证；对象过滤要求服务端支持，托管平台允许哪些过滤器要按产品、版本、权限与核对日期确认。

在现有 clone 中先只读盘点：

~~~bash
git config --show-origin --get-all remote.origin.fetch
git rev-parse --is-shallow-repository
git config --get remote.origin.promisor
git config --get remote.origin.partialclonefilter
git sparse-checkout list
git count-objects -vH
~~~

未启用某项能力时，对应配置或 `sparse-checkout list` 可以返回非零。不要把“没有输出”统一解释为损坏。上述命令不改变 refs、index 或工作区；`count-objects` 读取本地对象统计，不测量远端大小。

读完本章后，应能解释 fetch/push 协商的输入与产物，区分窄 refspec、shallow、partial clone 和 sparse-checkout，识别每种受限状态会让哪些命令证据不足，并为加深历史、恢复对象或重新完整克隆制定边界。

## Fetch 把引用选择和对象选择连起来

一次典型 fetch 可以按四段理解：

1. 客户端连接 upload-pack，双方交换协议能力；
2. 服务端提供当前身份可见的引用信息，客户端按命令和 refspec 选择目标；
3. 客户端声明想取得的对象，并提供自己已有历史的线索；
4. 服务端计算缺口、生成 pack，客户端接收对象后再更新本地 refs 与 `FETCH_HEAD`。

具体 packet 顺序、是否使用 bitmap、怎样选取已有提交线索，都取决于协议版本、Git 实现、仓库图和配置。上面的分段用于判断状态，不是可逐行匹配的网络规范。

对象协商解决的是“为所选结果少传哪些对象”。它不决定客户端能看到哪些私有 refs，也不授予对象权限。多个 refs 可达同一对象，排除一个分支不能保证其提交或 blob 不会经另一条可达路径到达本地。

Fetch 接收 pack 后才进入本地引用事务。对象已经写入而 ref 更新失败时，不能用 pack 字节数证明 `origin/main` 已前进；反过来，本地 ref 未变化也不证明对象库毫无新增。状态验收仍要分别核对对象、remote-tracking refs 与 `FETCH_HEAD`。

## 协商观测本身也有边界

在获批测试仓库中，可以只运行协商而不取得 pack：

~~~bash
git fetch --negotiate-only \
  --negotiation-tip=refs/heads/main \
  origin
~~~

命令会连接远端并输出双方共同祖先，要求至少一个 `--negotiation-tip`。它不执行普通 fetch 的对象传输和本地 ref 更新，但会产生网络、认证、服务端日志与限流影响。真实仓库执行前要确认 URL 和数据暴露范围。

`--negotiation-tip` 限制客户端用哪些本地 tips 告知已有历史，可能减少协商开销，也可能让服务端不知道客户端其实拥有某些对象，进而多传数据。它是性能提示，不改变目标 refs 的语义，不能用来隐藏本地对象。

Packet trace 可用于协议诊断：

~~~bash
GIT_TRACE_PACKET=1 git fetch --dry-run origin
~~~

`--dry-run` 不应更新本地 refs，但仍可能连接、认证和交换协议数据。Trace 可能暴露 refs、OID、能力与内部主机信息；保存前设定访问权限，分享前脱敏。服务端版本、协议与仓库状态变化都会改变输出，书稿不提供伪造的固定 trace。

## Push 的对象计算与 fetch 不完全对称

Push 先读取服务端接收端公开的 refs 与能力，再为目标更新准备对端缺少的对象，并发送 ref 更新命令。服务端是否接受 ref，仍由 non-fast-forward、hooks、授权和平台策略决定。

某些 Git 配置可让 push 额外进行协商，以减少发送的 pack：

~~~bash
git config --show-origin --get push.negotiate
~~~

这是性能选择，不是数据完整性开关。启用前在代表性仓库测量总时延、往返次数、CPU 与 pack 大小；高延迟网络上，少传字节不一定更快。无论怎样优化，成功证据仍是服务端目标 ref 的 old/new OID，详见[Push 与远端引用更新](06-push-upstream-and-ref-updates.md)。

## 四种“少一点”限制不同状态

| 机制 | 限制对象 | 本地提交图 | 本地对象 | 工作区 | 主要风险 |
| --- | --- | --- | --- | --- | --- |
| `--single-branch` 或窄 refspec | 引用范围 | 所选 refs 的历史可完整 | 所选历史所需对象可完整 | 正常检出 | 看不到未映射 refs |
| 浅克隆 | 祖先深度或时间边界 | 边界外祖先不在本地图中 | 边界外对象通常缺失 | 当前版本可完整 | merge-base、describe、blame、bisect 证据不足 |
| 部分克隆 | 对象过滤 | `blob:none` 下提交/tree 常可完整 | 某些对象由 promisor 远端按需提供 | 检出会水合所需 blob | 离线失败、按需请求尾延迟 |
| 稀疏检出 | 展开路径 | 不改变提交图 | 单独使用通常不减少下载 | 只展开所选路径 | 工具把未展开误判为不存在 |

`--depth` 默认还会限制到单分支，除非显式使用 `--no-single-branch`。部分克隆与 sparse-checkout 经常组合，但前者控制对象传输，后者控制工作区和 index 表示。只开 sparse-checkout 不会让已有对象库自动变小；只开 `blob:none`，默认 checkout 仍会立刻取回当前 tree 需要的 blob。

窄 refspec 只限制引用选择。它不是路径权限或秘密隔离，因为同一对象可能由所选历史可达，拥有读取权限的客户端也可能用其他允许的 refspec 再取。

## 浅克隆把边界提交当作本地根

在目标目录不存在时执行：

~~~bash
source_url=https://host.example/team/repository.git
target_dir=/absolute/path/to/shallow-repository

git clone --depth=50 --branch=main "$source_url" "$target_dir"
git -C "$target_dir" rev-parse --is-shallow-repository
git -C "$target_dir" rev-list --count main
git -C "$target_dir" rev-list --boundary main
~~~

示例 URL 不可连接，必须换成获批来源和新目录。Clone 创建仓库、对象、refs、index 与工作区，并用 `.git/shallow` 记录边界。预期 shallow 查询输出 `true`；提交数不保证恰好为 50，历史不足、合并图和服务端行为都会影响结果。

直接用本地路径 clone 可能采用本地复制优化并忽略 `--depth`。要验证传输语义，应使用 `file://` 或真实传输，并检查 shallow 状态，不能只看命令参数。

需要增加现有边界之前的历史：

~~~bash
git fetch --deepen=50 origin main
git rev-parse --is-shallow-repository
git rev-list --count main
~~~

`--deepen=50` 从当前浅边界再增加 50 层，与把总深度设为 50 不同。Fetch 会传入对象、调整 `.git/shallow`，并可能更新 `origin/main` 与 `FETCH_HEAD`，不会自动把当前本地分支整合到新远端 tip。

源端拥有完整历史且容量允许时：

~~~bash
git fetch --unshallow origin
git rev-parse --is-shallow-repository
~~~

成功后应输出 `false`。传输可能很大，执行前评估磁盘、时间和 CI 超时。源端本身也是浅仓库时，客户端只能得到源端拥有的祖先。不要手工删除 `.git/shallow` 伪造完整历史。

## 部分克隆把缺失对象交给 promisor

常见的 blobless 克隆：

~~~bash
source_url=https://host.example/team/repository.git
target_dir=/absolute/path/to/partial-repository

git clone --filter=blob:none "$source_url" "$target_dir"
git -C "$target_dir" config --get remote.origin.promisor
git -C "$target_dir" config --get remote.origin.partialclonefilter
git -C "$target_dir" rev-parse --is-shallow-repository
~~~

服务端接受过滤时，常见输出是 `true`、`blob:none` 和 `false`。这说明 origin 承诺提供缺失对象，且祖先未被 shallow 边界截断，不代表本地一个 blob 都没有。默认 checkout 会水合当前工作区文件。

服务端不支持过滤时，clone 可能失败，也可能警告后取得更多对象。目标目录存在不等于过滤生效。要检查标准错误、promisor 配置、过滤器和本地对象统计；托管平台能力按当前文档核对。

按需读取尚未取得的历史 blob 会连接 promisor 远端：

~~~bash
git show <commit>:path/to/file
~~~

命令可能写入新对象，不能当作纯本地只读操作。离线、凭据过期或远端删除对象时会失败。恢复方向是修复 promisor 读取路径后重试；若任务要求离线完整性、取证或备份，应新建普通完整 clone 并独立验收，不要仅删除 promisor 配置或假定曾经在线访问过的部分克隆已经完整。

`git fsck` 对 promisor 仓库会按其承诺解释预期缺失对象。一次 fsck 通过不能证明仓库离线自给自足，也不能证明 LFS、submodule 或平台数据可恢复。

对象过滤不是目录授权。只要身份有权读取仓库，客户端通常可以在需要时取得被过滤对象。敏感路径需要仓库边界或服务端授权设计。

## 稀疏检出改变工作区，不改变 tree

在非裸、无进行中冲突的工作树中：

~~~bash
git status --short --branch
git sparse-checkout set app docs/api
git sparse-checkout list
~~~

`set` 更新稀疏配置、index 标记和工作区。默认 cone 模式按目录选择，并保留必要父目录与顶层文件。其他 tracked paths 仍存在于提交 tree 中，只是不在当前工作区展开。

未提交修改、未跟踪文件或冲突可能阻止路径移除。先用 `status` 判断归属，保存工作后可以用 `git sparse-checkout reapply` 重新应用规则。不要用文件系统删除命令把未展开路径“清理干净”。

恢复完整工作区：

~~~bash
git sparse-checkout disable
git status --short --branch
~~~

部分克隆中，这一步可能按需下载大量 blob，因此需要可用网络和足够磁盘。它不会加深 shallow 历史，也不保证所有历史对象已取得。

大仓库可以组合：

~~~bash
git clone --filter=blob:none --sparse "$source_url" "$target_dir"
git -C "$target_dir" sparse-checkout set app docs/api
~~~

实际收益要测量初次传输、checkout、日常 status、切换分支和按需取对象的尾延迟。工作流设计、构建输入契约与 sparse-index 由[稀疏与部分工作流](../part-09/04-sparse-partial-workflows.md)继续处理。

## 按任务要求选择恢复深度

| 任务 | 受限状态可接受条件 | 必须补齐的证据 |
| --- | --- | --- |
| 短生命周期 CI | 构建只依赖固定当前 tree，版本工具不读历史/tag | candidate OID、实际 checkout、依赖/LFS/submodule 输入 |
| 变更检测与发布 | 能取得正确 target、merge-base、tag 与完整差异 | shallow/refspec 状态、候选重建与制品来源 |
| 大仓库开发 | IDE、构建图和代码生成器理解未展开路径 | 路径闭包、按需对象延迟、离线失败方案 |
| 取证、归档和备份 | 受限 clone 只能作为线索或 donor 之一 | 完整 refs/对象、LFS、平台数据、恢复演练 |

浅克隆适合某些只构建当前 tree 的任务，但发布版本、bisect、blame 和变更范围常依赖祖先。部分克隆适合可持续访问 promisor 的开发环境，不适合作为唯一离线恢复源。普通 clone 也不包含服务端隐藏 refs、reflog、hooks、评审、权限或审计日志。

## 失败方式与恢复边界

| 现象 | 先确认 | 恢复方向 |
| --- | --- | --- |
| Fetch 后看不到分支 | fetch refspec、负映射、`ls-remote --heads` | 修正映射或显式 fetch，不先创建假同名分支 |
| `log`/`merge-base`/`blame` 过早结束 | shallow 状态、`.git/shallow`、边界输出 | 按需 deepen，容量允许时 unshallow |
| 离线读取历史文件失败 | promisor、filter、对象是否本地存在 | 恢复只读远端或创建完整 clone |
| Sparse 后文件“不见了” | sparse 规则、目标 tree、status | 调整范围或 disable，不把未展开当删除 |
| `--depth` 对本地 clone 无效 | URL 形式、警告、shallow 状态 | 改用 `file://` 或真实传输复验 |
| Clone 很快但后续命令变慢 | 按需 fetch、packet/Trace2、缓存与网络 | 测量完整 workload，不只比较 clone 时间 |
| `fsck` 通过却无法离线构建 | promisor、LFS、submodule、外部依赖 | 按输入清单逐层水合或重建完整环境 |

`fetch --prune` 按 refspec destination 清理本地映射，不是泛化的“删除旧数据”。显式映射 tags 后配合 prune，可能删除本地独有标签。运行前读取全部 refspec、保存重要 OID，并在隔离 clone 验证。

## 隔离实验

在本书仓库根目录运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-refspec-partial-clone.sh
~~~

脚本要求 Bash、Git 2.28 或更高版本和可写临时目录。它使用 `file://` bare 仓库验证正/负 refspec、显式 push refspec、浅克隆的 deepen/unshallow、`blob:none` 的 promisor 与按需获取，以及 sparse-checkout 的收缩和恢复。成功时最后输出：

~~~text
Refspec, shallow-clone, partial-clone, and sparse-checkout experiments passed.
~~~

服务端在临时 bare 仓库显式启用 `uploadpack.allowFilter`。实验只证明当前 Git 版本的数据面语义，不证明托管平台支持相同过滤器，也不模拟真实网络、认证、配额、大仓库性能、LFS、CI 或平台隐藏 refs。

## 小结

Refspec 决定引用范围，协商决定为所选结果传哪些对象，shallow 截断祖先，partial clone 延迟对象，sparse-checkout 收缩工作区。每次优化都要写清本地缺什么、谁承诺补齐、离线时怎样失败，以及发布、取证和恢复是否仍有足够证据。

## 资料

- [Git wire protocol v2](https://git-scm.com/docs/protocol-v2)
- [git-fetch](https://git-scm.com/docs/git-fetch)
- [git-clone](https://git-scm.com/docs/git-clone)
- [Partial clone design](https://git-scm.com/docs/partial-clone)
- [git-sparse-checkout](https://git-scm.com/docs/git-sparse-checkout)
