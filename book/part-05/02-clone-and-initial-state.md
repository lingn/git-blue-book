# Clone 初始状态：复制哪些 Git 数据，建立哪条本地工作线

`git clone` 不是把服务器目录逐字节复制到本机。它创建新仓库，配置 remote，取得所选 refs 可达的对象，并按对端 symbolic `HEAD` 或显式 `--branch` 建立初始 `HEAD`。普通 clone 还会初始化 index 和工作区；`--no-checkout`、bare、mirror、shallow、partial 与 sparse 选项会改变结果。

Clone 成功只证明当前身份取得了本次映射所需的 Git 数据。服务端 reflog、hooks、工作区、未跟踪文件、平台评审、权限、审计、LFS payload 和制品不在普通 Git clone 的保证中。

## 进入条件与完成标准

Clone 会创建目录并可能传输大量数据。执行前确认来源 URL、目标父目录、磁盘、网络、凭据和仓库信任。目标目录应不存在，或满足 Git 允许的空目录条件。

~~~bash
source_url="https://host.example/team/repository.git"
target_dir="/absolute/new/path/repository"
git ls-remote --symref "$source_url" HEAD
~~~

示例 URL 不可连接，必须替换。`ls-remote` 是网络查询，可能触发认证；不要在命令行嵌入 token。

读完本章后，应能解释普通 clone 的 remote、refs、HEAD、upstream、index 和工作区初态，处理空仓库/默认分支异常，区分 `--no-checkout`、bare 与 mirror，判断本地路径优化、submodule/LFS 和配置/hooks 信任边界，并在失败后安全清理精确目标。

## 普通 clone 建立多层本地状态

~~~bash
git clone "$source_url" "$target_dir"
git -C "$target_dir" status --short --branch
git -C "$target_dir" remote -v
git -C "$target_dir" symbolic-ref HEAD
git -C "$target_dir" symbolic-ref refs/remotes/origin/HEAD
git -C "$target_dir" rev-parse HEAD '@{upstream}'
~~~

对端默认分支为 `main` 且非空时，常见结果：

- `remote.origin.url` 保存来源 URL；
- fetch refspec 映射远端 heads 到 `refs/remotes/origin/*`；
- 本地 `main` 与 `origin/main` 初始指向同一 commit；
- `HEAD` 附着到本地 main；
- main 的 upstream 是 `origin/main`；
- index 和工作区对应 `HEAD` tree；
- `origin/HEAD` 是指向 `origin/main` 的本地 symbolic ref。

这些是本次 clone 的初态，不保证服务器随后未变化。Clone 后立即显示 `behind 0` 也只是相对于取得的 remote-tracking ref。

验收候选 tree：

~~~bash
candidate="$(git -C "$target_dir" rev-parse 'HEAD^{commit}')"
test "$(git -C "$target_dir" write-tree)" = \
  "$(git -C "$target_dir" rev-parse "$candidate^{tree}")"
git -C "$target_dir" status --porcelain=v1 --untracked-files=all
~~~

Filter、LFS、submodule、symlink 和文件系统差异仍可能让外部输入不完整，不能只看工作树干净。

## 默认分支来自对端 HEAD 与显式选择

服务器 bare 仓库的 `HEAD` 通常是指向 `refs/heads/main` 的 symbolic ref。Clone 查询它来选择初始分支。若对端 HEAD 指向不存在的 ref、当前身份看不到目标或服务返回异常，clone 可能取得对象但无法 checkout，并给出 warning。

先查询：

~~~bash
git ls-remote --symref "$source_url" HEAD
~~~

需要固定其他分支：

~~~bash
git clone --branch release/2.x --single-branch \
  "$source_url" "$target_dir"
~~~

`--branch` 可接受 tag；若选择 tag，初始 `HEAD` 会分离。`--single-branch` 限制初始 ref/历史范围，后续看不到其他远程分支不等于服务器没有。

自动化保存对端 HEAD 响应、显式 branch、最终本地 HEAD/OID 和 fetch refspec。平台 UI 的默认分支是控制面事实，可能与 Git symbolic HEAD 更新存在时间差。

## 空仓库只有分支意图，没有 commit

空 bare 仓库可让 `HEAD` 指向 `refs/heads/main`，但该 ref 尚不存在。Clone 后：

~~~bash
git -C "$target_dir" symbolic-ref HEAD
git -C "$target_dir" rev-parse --verify 'HEAD^{commit}'
~~~

第一条可能成功输出 `refs/heads/main`，第二条失败。工作区为空，remote 已配置，但没有 `origin/main` 和可构建候选。这是 unborn 状态，不是损坏。

首个发布者要按组织规则创建根 commit 并显式 push。并发初始化可能生成两个独立根；服务器保护、expected-old 和协调流程应拒绝无意覆盖。不要用 `--allow-unrelated-histories` 自动拼接两个根。

## `--no-checkout` 不展开工作区

~~~bash
git clone --no-checkout "$source_url" "$target_dir"
~~~

命令取得对象和 refs，设置初始 HEAD，但不执行普通 checkout。Index 可能尚未按 HEAD tree 初始化，工作区没有 tracked 文件；status 可以把 HEAD 路径显示为 staged delete。实际状态按版本查询：

~~~bash
git -C "$target_dir" rev-parse HEAD
git -C "$target_dir" ls-files --stage
git -C "$target_dir" status --porcelain=v1
~~~

需要检出时先确认目标目录没有要保留的文件，再使用受控 `switch`/`reset`/sparse-checkout 流程。不要把 `--no-checkout` clone 的空工作区当成仓库内容为空。

该模式适合先设置 sparse/partial 策略、只读对象分析或工具导入，但工具必须明确 index/工作区还未建立。

## Bare clone 没有工作区

~~~bash
git clone --bare "$source_url" repository.git
git --git-dir=repository.git rev-parse --is-bare-repository
git --git-dir=repository.git for-each-ref \
  --format='%(refname) %(objectname)'
~~~

Bare clone 的 Git directory 就是目标目录，没有工作区和普通 index。来源分支通常直接成为本地 `refs/heads/*`，而不是 `refs/remotes/origin/*`。Remote 配置与 fetch 映射不能按普通 clone 假设，必须读取实际配置。

Bare 适合服务器、备份/迁移中间仓库和不需 checkout 的工具。它不自动拥有平台权限、hooks、LFS 或审计数据。

## Mirror clone 扩大 ref 映射和更新风险

~~~bash
git clone --mirror "$source_url" mirror.git
git --git-dir=mirror.git config --get remote.origin.mirror
git --git-dir=mirror.git config --get-all remote.origin.fetch
~~~

Mirror 隐含 bare，并通常配置 `+refs/*:refs/*`，让后续 remote update 覆盖广泛 refs。它会比普通 clone 取得更多可见引用，但仍不含服务端 reflog、隐藏于当前身份的 refs、不可达对象、平台数据库、LFS payload 或制品。

向错误目标 mirror push 可能强制覆盖和删除大量 refs。镜像只在明确源/目标、全 refs manifest、只读验证、备份与审批齐备时使用，具体见备份/迁移章节。

## 本地路径 clone 可能使用复制优化

`git clone /path/source target` 可以使用 hardlink 或本地对象复制优化，并可能忽略 `--depth` 等传输语义。验证 shallow、filter、协议或网络行为时使用 `file://` 或实际传输：

~~~bash
git clone --depth=1 "file:///absolute/source.git" "$target_dir"
git -C "$target_dir" rev-parse --is-shallow-repository
~~~

Hardlink 不是独立故障域。源端磁盘损坏、对象替换或权限问题可能影响假设；安全边界下使用 `--no-hardlinks` 或受控传输，并验证对象完整性。

不要从不受信任、由其他用户拥有的本地仓库复制对象后立即执行代码。配置/hooks 传输边界不等于工作区内容安全。

## Clone 不复制全部本地或平台状态

| 状态 | 普通 clone 是否保证复制 |
| --- | --- |
| 映射 refs 可达的 commit/tree/blob/tag | 是，受 shallow/partial/filter 影响 |
| 源仓库工作区、index、未跟踪/忽略文件 | 否 |
| 源仓库 reflog、stash、不可达对象 | 否 |
| 源仓库 local config 与 hooks | 否；clone 创建自己的 remote/config |
| Git notes、自定义 refs | 取决于 refspec，不默认保证 |
| LFS payload、submodule 仓库 | 需要各自协议/递归操作 |
| 平台 issue/评审/权限/规则/审计 | 否 |
| CI 制品、package、部署和秘密 | 否 |

`git fsck` 通过只能检查当前 Git 对象范围，不能证明上表外部数据完整。灾备不能只保留一个开发者 clone。

## Submodule、LFS 与 filters 扩大执行和网络面

`--recurse-submodules` 会继续读取 `.gitmodules` URL 并克隆其他仓库；LFS smudge/filter 可能请求外部对象；checkout 还会处理 symlink、attributes 和平台文件系统。

来源不受信任时，优先 `--no-checkout`，先审查 tree、`.gitmodules`、`.gitattributes`、CI/构建脚本和对象规模，再决定展开。Clone 本身不复制源 hooks，但 checkout 后的工具和后续 Git 命令可能执行本地配置指定的 filter 或 hook。

生产 clone 记录递归仓库列表、gitlink OID、LFS pointer/payload、filter 来源、凭据范围和失败状态。子模块某个 OID 不可取得时，主仓库 clone 成功也不算完整构建输入。

## 失败会留下部分目标目录

网络中断、磁盘耗尽、认证失败、filter checkout 失败或对象损坏时，目标目录可能已经存在并含部分 `.git`。不要直接重试到同一未知状态，也不要递归删除宽泛父目录。

处理顺序：

1. 保存 clone 命令的脱敏参数、时间、stderr 与退出码；
2. 确认目标是本次新建的精确目录，没有用户文件；
3. 需要调查时保留目录并检查 refs/object/config；
4. 决定重试时移动到隔离位置或删除精确目标；
5. 使用新目录重试，避免把部分对象误当完整缓存。

自动化先用 `mktemp -d` 创建专用父目录，再让 clone 写固定子目录，trap 校验前缀后清理。

## Clone 后的验收

~~~bash
git -C "$target_dir" remote get-url --all origin
git -C "$target_dir" config --get-all remote.origin.fetch
git -C "$target_dir" symbolic-ref HEAD
git -C "$target_dir" rev-parse 'HEAD^{commit}' '@{upstream}'
git -C "$target_dir" rev-parse --is-shallow-repository
git -C "$target_dir" config --get-regexp \
  '^remote\..*\.(promisor|partialclonefilter)$'
git -C "$target_dir" status --porcelain=v1
git -C "$target_dir" fsck --connectivity-only
~~~

配置查询无匹配时可返回 1。验收还要检查 sparse、submodule、LFS、磁盘、平台候选和业务构建；根据 clone 类型选择，不用一条固定脚本误判所有模式。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| Clone 成功但没有 checkout | `--no-checkout`、bare、对端 HEAD、warning | 识别模式/默认分支，再受控展开 |
| `HEAD^{commit}` 失败 | 空仓库、symbolic HEAD、权限和对象 | Unborn 时协调首个 commit；其他情况调查 |
| 只看到一个远程分支 | `--single-branch`、depth、fetch refspec | 扩大映射并 fetch，不创建假 refs |
| 本地 `--depth` 无效果 | 来源是否本地路径、警告、shallow 状态 | 用 `file://`/真实传输验证 |
| Checkout 因 filter/LFS 失败 | refs、index、pointer、filter 和凭据 | 保留对象状态，恢复外部依赖后重试 |
| Submodule clone 失败 | gitlink、URL、权限和发布顺序 | 先取得精确依赖 commit，不改父仓 OID |
| Mirror 看似完整但平台数据缺失 | ref manifest 与平台资产清单 | 分层备份，不把 mirror 当平台快照 |
| 失败目录阻止重试 | 精确路径、owner、是否含用户数据 | 隔离/保留后用新目录重试 |

## 隔离实验

运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-clone-initial-state.sh
~~~

实验验证普通 clone 的 origin/main/upstream/index/worktree，空仓库的 unborn `HEAD`，`--no-checkout` 的空 index/工作区，bare clone 的直接 heads，以及 mirror 的 `+refs/*:refs/*` 与 mirror 配置。它还断言源仓库 local config、hook 和未跟踪文件不进入普通 clone。

实验使用本地 `file://` 和虚构身份，不验证网络、凭据、平台默认分支、LFS/submodule 或本地 hardlink 故障。

## 小结

普通 clone 建立 remote、远程跟踪 refs、本地分支、upstream、index 和工作区；空仓库、`--no-checkout`、bare 与 mirror 各有不同初态。Clone 只复制所选 Git 数据，不包含源工作区、日志、hooks 和平台状态。验收必须按 clone 模式检查 refs、对象、限制和外部依赖。

## 资料

- [git-clone](https://git-scm.com/docs/git-clone)
- [gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)
- [git-remote](https://git-scm.com/docs/git-remote)
- [gitmodules](https://git-scm.com/docs/gitmodules)
- [partial clone](https://git-scm.com/docs/partial-clone)
