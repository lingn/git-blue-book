# Refspec、传输协商与受限克隆

“从 `origin` 获取更新”听起来像复制一个仓库，实际包含三个选择：交换哪些引用，为这些引用取得哪些对象，最后把哪些路径写入工作区。refspec、浅克隆、部分克隆和稀疏检出分别控制这三个维度中的不同部分，不能互相替代。

进入本章前，读者应理解引用、远程跟踪分支、fetch/push 和远程传输。本章完成后，应能读懂 fetch 与 push 的 refspec，判断一个仓库缺的是引用、祖先、对象还是工作区文件，并能为 CI、大仓库开发和备份选择不同克隆策略。

本章的命令主线兼容 Git 2.28 或更高版本，实验在 Git 2.49.0 上验证。部分克隆需要服务器支持对象过滤；托管平台是否支持某种过滤器，必须按产品当前文档核对。

## Refspec 是引用之间的映射

refspec 是一个引用选择与映射表达式，基本形式为：

```text
[+]source:destination
```

source 和 destination 的位置取决于操作方向：

| 操作 | source | destination |
| --- | --- | --- |
| fetch | 远端引用 | 本地引用 |
| push | 本地引用或对象表达式 | 远端引用 |

冒号不是“同步”运算符。它明确说出哪一端的什么对象要更新另一端的哪个引用。命令行中若出现 `*`，应把整个 refspec 放进单引号，避免 Shell 先把星号展开为文件名。

### clone 留下的默认 fetch 映射

在普通克隆中执行：

```bash
git config --show-origin --get-all remote.origin.fetch
```

常见值为：

```text
+refs/heads/*:refs/remotes/origin/*
```

它表示远端 `refs/heads/` 下每个分支，映射到本地 `refs/remotes/origin/` 下同名的远程跟踪引用。两个 `*` 各出现一次，匹配到的中间部分会代入目标。例如远端 `refs/heads/release/1.x` 映射到本地 `refs/remotes/origin/release/1.x`。

开头的 `+` 允许 fetch 在本地更新目标引用时接受非快进移动。它只影响当前仓库保存的远程跟踪引用，不会强制修改服务器分支，也不等于 push 的安全租约。远端若改写了功能分支，下一次 fetch 可以让 `origin/feature` 跟随新位置；旧位置是否仍能从 reflog 找到取决于本地日志和过期策略，不能把远程跟踪引用当永久审计档案。

上述配置读取命令不连接远端，也不修改任何状态。没有输出时，可能是远程名不同、仓库不是由普通 clone 建立，或者映射来自其他配置。先运行 `git remote` 和带 `--show-origin` 的配置查询，不要直接写入一条“看起来标准”的默认值覆盖定制工作流。

### 负 refspec 从正向集合中排除引用

fetch refspec 可以用 `^` 开头表示排除。例如一条正向模式选择全部分支，再用下面的负模式排除 `wip/` 命名空间：

```text
+refs/heads/*:refs/remotes/origin/*
^refs/heads/wip/*
```

负 refspec 只有 source，没有 destination；它可以使用一个 `*` 模式，但不能写完整对象 ID。引用必须先匹配至少一个正 refspec，才有“从中排除”的意义。

排除只控制客户端此次选择和本地引用映射，不是服务端权限规则。拥有仓库读取权限的客户端仍可能通过其他允许的引用取得相同对象；多个分支也可能共享提交和 blob。不能用负 refspec 隔离机密代码。

修改 `remote.origin.fetch` 会改变今后所有无显式 refspec 的 fetch，属于仓库级持久配置。生产仓库变更前应记录全部旧值、评估 CI 和维护脚本，并在隔离克隆中验证。安全的学习路径是运行本章实验，而不是在日常仓库照抄排除规则。

### 命令行 refspec 与配置 refspec 的关系

执行 `git fetch origin` 而没有额外 refspec 时，Git 使用 `remote.origin.fetch` 决定获取哪些远端引用和更新哪些本地引用。若命令行显式指定分支，例如：

```bash
git fetch origin main
```

命令行决定此次只获取 `main`。`main` 可理解为 source 为 `main`、destination 为空的简写；配置中的 fetch 映射仍可能让 Git“顺便”把这个已取得的引用写到匹配的 `origin/main`。需要完全自定义目标映射时可使用显式 `source:destination` 或 `--refmap`，但自动化应写完整引用名并先在隔离仓库验证。

每次普通 fetch 还会写 `.git/FETCH_HEAD`，记录此次取得的引用与对象 ID，供 `git pull` 等后续动作使用。默认下次 fetch 会覆盖它，`FETCH_HEAD` 不是长期审计日志，也不能替代远程跟踪引用。

## Push refspec 是服务端引用更新请求

下面的命令把本地当前提交发布为远端专用评审分支：

```bash
git push origin HEAD:refs/heads/review/refspec-lab
```

source 是本地 `HEAD` 解析到的提交，destination 是远端完整分支名。它不会创建同名本地分支。普通成功输出通常包含新分支标记和目标名，具体 URL、摘要和对象 ID会变化。

这条命令只能在获得授权的专用测试仓库或明确归属于操作者的评审命名空间使用。执行前应运行 `git fetch origin`，记录 `git rev-parse HEAD`，并用下面的只读命令确认目标是否已经存在：

```bash
git ls-remote --heads origin refs/heads/review/refspec-lab
```

无输出可能表示目标不存在，也可能是读取范围受限；还要检查退出状态和平台权限。推送后重复查询，远端对象 ID 应等于推送前记录的本地 `HEAD`。终端成功只证明引用更新被接受，不证明 CI、评审或部署成功。

空 source 表示删除远端 destination：

```bash
git push origin :refs/heads/review/refspec-lab
```

这与 `git push origin --delete review/refspec-lab` 的核心引用效果相同，是共享状态的破坏性操作。本章实验会在临时裸仓库中真实创建再删除该分支。真实仓库只有在确认评审、CI、部署和协作者都不再依赖它，且服务端允许删除时才执行。删除错误后能否恢复取决于平台审计、远端保留策略和其他克隆保存的对象，不能假定服务器有 reflog。

Push refspec 开头的 `+` 表示无条件允许非快进请求，风险相当于对相应映射强制推送，不提供并发租约。共享仓库不要用它替代显式 `--force-with-lease` 和协作者协调。服务器的保护规则、hooks 和授权仍可拒绝任何 refspec。

脚本还应避免依赖 Git 对短名称的猜测。`HEAD:review/refspec-lab` 可能触发目标命名空间推断；完整写成 `refs/heads/review/refspec-lab`，审计时更容易知道实际更新了什么。

## 获取不是复制所有磁盘内容

一次 fetch 的对象协商可以抽象为：客户端和服务器先确定协议能力与目标引用，客户端说明自己已有的一部分提交，服务器据此生成足以补全目标可达历史的 pack。实际消息会随协议版本、服务端实现、位图、过滤器和仓库状态变化，不应把某次 trace 当成固定流程输出。

“完整克隆”也有边界。普通 clone 通常取得所映射分支及相关标签的可达历史，不承诺复制服务端所有隐藏引用、reflog、不可达对象、hooks、平台评审、权限或审计日志。`git clone --mirror` 扩大引用映射，但仍不等于托管平台灾难恢复方案。

客户端已经拥有的对象通常不会重复传输。提交和 tree 可能被多个分支共享，排除一个引用也不保证对应对象不会因另一条历史而到达本地。讨论网络与存储成本时，应测量实际 pack 和后续按需取对象，而不是用“分支数量乘仓库大小”估算。

## 四种“少取一点”改变的是不同状态

| 机制 | 主要限制 | 本地提交图 | 本地对象 | 工作区 | 后续风险 |
| --- | --- | --- | --- | --- | --- |
| `--single-branch` 或窄 refspec | 引用范围 | 所选引用的历史可完整 | 所选历史所需对象可完整 | 正常检出 | 后续看不到未映射分支 |
| 浅克隆 | 祖先深度或时间边界 | 边界之外不在本地历史中 | 边界外对象通常缺失 | 当前版本正常检出 | merge-base、describe、blame、bisect 可能证据不足 |
| 部分克隆 | 对象过滤器 | 常见 `blob:none` 下提交与 tree 图仍完整 | 某些 blob 等对象由 promisor 远端承诺按需提供 | 检出所需对象会被取回 | 离线访问缺失对象失败，按需请求造成延迟 |
| 稀疏检出 | 工作区路径 | 不改变提交图 | 单独使用时通常不减少已下载对象 | 只展开所选目录 | 工具可能误把未展开路径当不存在 |

`--depth` 默认蕴含 `--single-branch`，除非显式使用 `--no-single-branch`。因此一个浅克隆可能同时缺其他分支引用和更早祖先。诊断前先分别检查 refspec 与 shallow 状态。

部分克隆与稀疏检出经常组合：前者减少初始对象传输，后者减少工作区文件和 index 压力。只启用稀疏检出，已有对象库不会自动变小；只启用部分克隆，默认检出仍可能立即取回当前提交所需的大量 blob。

## 浅克隆截断的是祖先关系

CI 只构建最新提交时常使用浅克隆，但版本号生成、变更范围计算、回归定位和发布工具可能依赖更早祖先。是否适合不能只看 checkout 成功。

下面的操作在目标目录尚不存在或为空、并且源仓库地址可信时执行：

```bash
source_url=https://host.example/team/repository.git
target_dir=/absolute/path/to/shallow-repository

git clone --depth=50 --branch=main "$source_url" "$target_dir"
git -C "$target_dir" rev-parse --is-shallow-repository
git -C "$target_dir" rev-list --count main
```

示例主机不可连接，运行前必须替换为实际 URL 和新的目标目录。clone 创建新仓库、写入对象和引用，并用 `.git/shallow` 记录被视作历史根的边界。第一个诊断命令预期输出 `true`；提交数量不一定恰好为 50，例如历史不足、合并图或服务端限制都会影响可达计数。

直接用本地路径 clone 时，Git 可能采用本地复制优化并忽略 `--depth`。需要验证传输语义的本书实验使用 `file://` URL，避免把本地硬链接复制误当浅克隆。

需要增加当前边界之前的 50 层历史时，在浅仓库中执行：

```bash
git fetch --deepen=50 origin main
git rev-parse --is-shallow-repository
git rev-list --count main
```

`--deepen=50` 是从现有浅边界继续增加深度，和把总深度设为 50 的 `--depth=50` 不同。fetch 会下载新增对象、调整 `.git/shallow`，并可能更新 `origin/main` 与 `FETCH_HEAD`；不会自动移动当前本地 `main` 到远端新提交。输出计数应增加，但精确数值依赖提交图。

源仓库完整且需要恢复完整祖先时：

```bash
git fetch --unshallow origin
git rev-parse --is-shallow-repository
```

成功后第二条输出 `false`。这个动作可能传输大量历史，执行前要评估时间、磁盘和 CI 超时。若源仓库本身也是浅仓库，客户端最多取得源端拥有的历史，不能凭命令名字推断已经恢复到原始完整仓库。网络失败时保留当前浅仓库状态，修复连接后重试；不要删除 `.git/shallow` 伪造完整历史。

## 部分克隆延迟取得对象

部分克隆要求服务端理解并允许请求的过滤器。最常见的 `blob:none` 先省略文件内容，Git 在 checkout、show、diff 等操作真正需要某个 blob 时，再从标记为 promisor 的远端获取。

在新目录克隆：

```bash
source_url=https://host.example/team/repository.git
target_dir=/absolute/path/to/partial-repository

git clone --filter=blob:none "$source_url" "$target_dir"
git -C "$target_dir" config --get remote.origin.promisor
git -C "$target_dir" config --get remote.origin.partialclonefilter
git -C "$target_dir" rev-parse --is-shallow-repository
```

真实运行前替换 URL 和目标目录。服务器支持并接受过滤时，常见配置输出依次为 `true`、`blob:none` 和 `false`。这说明 `origin` 承诺提供缺失对象、过滤器为 blobless、仓库并未截断提交历史。它不证明“本地没有任何 blob”：默认 checkout 会立即取回当前工作区需要的文件内容。

服务端不支持过滤时，clone 可能失败，也可能警告过滤未被识别并退化为传输更多对象。必须检查命令标准错误、上述 promisor 配置和实际对象规模，不能只因目标目录出现就宣称部分克隆成功。自建服务端是否启用过滤属于管理员决策，公网平台能力则要按当前官方文档核对。

按需取对象把初始成本推迟到了后续命令。离线时查看一个尚未取得的历史文件会失败；高延迟网络上，工具逐个触发取回可能比一次完整获取更慢。修复方式是恢复 promisor 远端连通并重试需要对象的命令。若构建、审计或归档要求离线完整性，应创建并验证普通完整克隆，而不是假定一个曾经在线工作的部分克隆已经自给自足。

过滤器不是目录权限。拥有 promisor 远端读取权限的客户端通常能够在需要时取得被过滤对象；`blob:none` 只优化传输，不把某些路径变成秘密。路径级访问控制需要仓库边界或服务端授权设计。

## 稀疏检出只决定展开哪些路径

在已有工作树中只展开 `app` 和 `docs/api` 目录：

```bash
git status --short
git sparse-checkout set app docs/api
git sparse-checkout list
```

执行位置必须是非裸仓库工作树。操作前先处理未提交修改和冲突，尤其是即将移出稀疏范围的路径。`set` 会更新稀疏配置、index 标记和工作区；默认 cone 模式按目录选择，并会保留必要的父目录与顶层文件。预期 `list` 显示所选目录，工作区中其他受跟踪路径不再展开，但它们仍存在于提交中。

未跟踪文件、冲突或外部工具写入可能阻止某些路径被移除。不要用文件系统删除命令强行“修好”稀疏状态；先用 `git status` 判断文件归属，保存工作后可运行 `git sparse-checkout reapply` 重新应用规则。

恢复完整工作区：

```bash
git sparse-checkout disable
git status --short
```

这会关闭稀疏检出并重新展开当前提交的全部受跟踪路径。部分克隆中，该过程可能从 promisor 远端下载此前缺少的 blob，因此要在网络可用且磁盘足够时执行。它不会把浅仓库变完整，也不保证所有历史 blob 都已下载。

对于大型仓库，可以组合：

```bash
git clone --filter=blob:none --sparse "$source_url" "$target_dir"
git -C "$target_dir" sparse-checkout set app docs/api
```

`--sparse` 初始只展开顶层文件，第二条再选择目录。实际收益要同时测量初始传输、首次 checkout、日常 status、切换分支和按需取对象的尾延迟，不能只比较 clone 命令耗时。

## 按工程目标选择策略

### CI 构建

先列出构建和版本工具依赖：是否读取 tag、merge-base、变更范围、子模块或历史文件。仅编译当前树的短生命周期作业可以评估浅克隆；发布、变更检测和 bisect 类作业通常需要更完整历史。缓存若保存部分克隆，还必须保证后续作业有同一 promisor 远端的读取凭据。

### 大仓库开发

开发者只维护少数目录时，可评估 `blob:none` 与 cone 模式稀疏检出。需要同时验证 IDE、构建系统、代码生成器和重构工具是否理解未展开路径。目录所有权和构建图比“团队平时只改这里”更可靠。

### 取证、归档和备份

浅克隆和部分克隆都不适合作为唯一恢复来源：前者明确缺祖先，后者依赖 promisor 远端。普通 clone 也没有平台元数据和隐藏引用。恢复方案要分别覆盖 Git 引用与对象、LFS、评审/issue、权限、hooks、审计日志和恢复演练。

### 镜像与迁移

迁移前先定义引用范围和目标平台数据，不能把窄 refspec 当作仓库级权限过滤。`--mirror` 会映射并强制同步广泛的引用，错误目标上风险很高，应在迁移与灾难恢复篇单独设计清单，不与开发者克隆命令混用。

## 常见失败怎样判断

| 症状 | 首要证据 | 恢复方向 |
| --- | --- | --- |
| fetch 后看不到某个远端分支 | `remote.origin.fetch`、负 refspec、`git ls-remote --heads origin` | 修正映射或显式获取；不要先创建同名本地提交 |
| `log`、`merge-base` 或 `blame` 过早停止 | `git rev-parse --is-shallow-repository`、`.git/shallow` | 按需 deepen，或在容量允许时 unshallow |
| 部分克隆离线查看历史文件失败 | `remote.origin.promisor`、过滤器、远端连通性 | 恢复远端读取后重试；需要离线完整性时重新做完整克隆 |
| sparse-checkout 后“文件不见了” | `git sparse-checkout list`、`git status`、目标提交中的 tree | 调整 `set` 范围或 `disable`，不要把未展开误判为删除 |
| `--depth` 对本地 clone 没有效果 | clone 警告、URL 是否为本地路径、shallow 状态 | 用 `file://` 或真实传输做实验，不用本地复制结果证明网络行为 |
| prune 删除了意外引用 | 当前 fetch refspec、是否显式映射 tags、原始引用 ID | 从记录、平台或其他克隆恢复；变更前先用隔离仓库验证映射 |

`git fetch --prune` 是按 refspec 的 destination 清理已确认远端不存在的映射，不是抽象的“清理旧分支”。若显式把远端 tags 映射到本地 `refs/tags/*`，配合 prune 可能删除本地独有标签。执行前读取全部 refspec 并保存重要引用对象 ID。

多引用操作还要区分本地与远端原子性。`git fetch --atomic` 要么完成所有本地引用更新，要么一个也不更新；`git push --atomic` 只有服务器支持时才让远端多引用更新全成或全败，否则命令失败。它们不让工作区、CI、部署或平台审批一起成为同一个事务。

## 隔离实验验证了什么

在本书仓库根目录运行：

```bash
./scripts/verify-refspec-partial-clone.sh
```

脚本要求 Bash、Git 2.28 或更高版本和可写临时目录。它创建专用源仓库与 `file://` 裸远端，不读取用户级 Git 配置、不连接网络，并在退出时删除临时目录。

实验依次验证：正 refspec 映射 `main` 和 `release/1.x`；负 refspec 不创建 `origin/wip/private`，也不取得该分支独有提交；显式 push refspec 创建再删除专用远端分支；`--depth=2` 建立 shallow 边界，`--deepen=2` 扩展历史，`--unshallow` 恢复完整主线；`blob:none` 记录 promisor 配置并把历史 blob 标记为预期缺失，`git show` 触发按需获取；最后用 sparse-checkout 收缩和恢复工作区。

成功时最后输出：

```text
Refspec, shallow-clone, partial-clone, and sparse-checkout experiments passed.
```

实验中的服务端显式启用 `uploadpack.allowFilter`，这只证明当前 Git 版本的本地 upload-pack 支持过滤。它不能证明任何托管平台已启用相同能力，也不能模拟网络时延、认证、配额、服务端隐藏引用或大仓库性能。实验仓库很小，结果只验证语义，不支持性能外推。

## 小结

Refspec 决定引用从哪里映射到哪里；协商决定为这些引用传哪些对象；浅克隆截断祖先，部分克隆延迟对象，稀疏检出缩小工作区。只有把四层分别检查，才能准确解释“为什么分支看不到”“为什么历史到这里结束”“为什么离线缺对象”或“为什么文件没展开”。

工程选择应从任务需要的证据出发：CI 是否依赖历史，开发工具是否理解稀疏路径，离线任务是否允许 promisor 依赖，恢复目标是否包含平台数据。节省一次 clone 的时间，不应以失去发布、取证和恢复所需证据为代价。
