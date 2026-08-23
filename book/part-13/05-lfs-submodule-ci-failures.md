# LFS、子模块与 CI clone 异常：外部对象和固定依赖

“代码已经 clone 下来了，但构建找不到文件”可能有三种完全不同的原因：Git tree 中保存的是 LFS pointer，外部 payload 没有水合；当前提交只保存了 submodule 的 gitlink，嵌套仓库没有取得被固定的 commit；CI checkout 了一个错误候选、浅历史或未展开的工作区。它们的共同点是，Git 主仓库的 refs 和对象可能完全健康。

本章把这三种症状接入第十三篇的证据路径。先确认主仓库的候选 commit 和 tree，再分别核对 pointer/payload、gitlink/嵌套仓库、CI checkout/构建输入。修复时不能用“把当前目录里的文件 add 回去”掩盖外部对象缺失，也不能把 submodule 分支最新提交当成父仓库已经批准的依赖版本。

本章以 Git 2.49.0、Git LFS 3.7.1 文档边界和本地 file 传输实验为基线，核对日期为 2026-08-22。当前实验不安装或冒充真实 Git LFS，不连接托管平台、LFS 服务或 CI runner；真实 endpoint、权限、锁、配额、缓存、制品留存和平台审计必须按目标环境单独核对。

读完本章后，你应能：

- 证明一个路径是普通 blob、LFS pointer 还是 submodule gitlink，而不是只看文件名和扩展名；
- 区分 Git fetch 成功、LFS payload 可取、submodule commit 已发布和工作区可用这几种状态；
- 为 CI 固定候选 commit，显式处理 shallow/partial、LFS 水合和递归 submodule，保存可审计的输入清单；
- 在外部对象或依赖缺失时保留原始 OID、错误和 refs，选择安全恢复顺序；
- 说明本地实验验证了什么，以及不能替代哪些平台和服务端证据。

## 先做三层分流

在出现“文件缺失”“clone 成功但构建失败”或“子模块无法检出”时，先在候选 commit 所在的主仓库根目录保存第十三篇第一章的最小证据集。不要先执行 add、clean、reset、lfs prune 或修改父仓库 gitlink。

| 表象 | 第一处证据 | 可能的真实边界 | 初始动作 |
| --- | --- | --- | --- |
| 文件内容像 LFS pointer | cat-file、ls-tree、check-attr | Git 只有 pointer，payload 在 LFS cache/service/backup | 保存 pointer Git OID、LFS OID 和 size；不要把 pointer 当二进制提交 |
| 子目录为空或 status 显示减号 | ls-tree、submodule status | tree 只有 mode 160000 的 gitlink，嵌套仓库未初始化或缺 commit | 保存 gitlink OID、.gitmodules URL 和远端可见性 |
| CI 源码目录存在但构建输入不全 | CI 实际 HEAD、候选 OID、浅/部分配置、工作区状态 | 错误提交、受限历史、未水合 LFS 或未递归 submodule | 先固定候选和输入清单，再分别恢复外部数据面 |
| Git fsck 通过但构建失败 | pointer/gitlink 对象和 refs | Git 完整性不包含 LFS payload、submodule 仓库或制品 | 结论写成“主仓库对象图完整”，不写成“源码完整” |

git fsck --full 只检查 Git 能看到的对象图。它不能证明 LFS payload、子模块远端、CI cache、制品仓库或平台控制面存在。

## LFS：pointer、payload 和工作区不是同一份数据

假设候选提交 C 的路径是 assets/model.bin。在主仓库根目录执行：

~~~bash
candidate='FULL-COMMIT-OID'
path='assets/model.bin'

git cat-file -e "$candidate^{commit}"
git ls-tree "$candidate" -- "$path"
git cat-file -p "$candidate:$path"
git cat-file -t "$candidate:$path"
git check-attr -a -- "$path"
~~~

前置条件是当前仓库已确认可信，candidate 是完整 commit OID，path 是相对仓库根目录的路径。前两条确认提交和 tree 中的路径，cat-file 输出实际 blob 内容，类型通常是 blob，check-attr 观察当前工作树属性规则。命令只读本地对象和配置，不连接 LFS 服务；输出可能含敏感文件内容和 endpoint，不应直接贴到公共工单。

如果 blob 内容符合 LFS pointer 规范，至少保存：

- pointer blob 的 Git OID；
- pointer 中的 payload OID 和 size；
- .gitattributes 中命中的 filter、diff、merge、lockable 属性；
- Git LFS 客户端版本、endpoint、include/exclude 和 cache 位置；
- 实际水合文件的 SHA-256 和字节数。

Git OID 和 pointer 的 SHA-256 属于两个命名空间。前者识别 Git blob，后者识别外部 payload。把它们写进同一个 artifact hash 字段，会让恢复和审计无法判断验证了哪一层。

### 判断 LFS 工具和配置是否存在

在已经安装并获组织批准的 Git LFS 客户端环境中执行：

~~~bash
git --version
git lfs version
git lfs env
git config --show-origin --get-regexp '^(filter\.lfs\.|lfs\.)' || true
git check-attr filter diff merge lockable -- "$path"
~~~

git lfs env 可能输出内部 URL、代理、本机 cache 路径和凭据线索，原件必须限制访问。若命令报告不是 Git 子命令，停止水合和迁移，不要手工拼 filter 命令假装安装成功；按组织批准渠道安装受支持版本，在一次性 clone 中验证客户端和 hook。

.gitattributes 只选择 filter 名称，clean、smudge 或 process 的具体程序来自本机配置。clone 不会复制源仓库的 local config，所以一台机器能水合不代表 CI 或同事环境也能水合。打开不受信任仓库前，还要按第十篇检查配置、filters 和 hooks 的执行边界。

### 丢失 payload 时按 OID 恢复

先把工作区和当前 refs 固定，必要时设置 GIT_LFS_SKIP_SMUDGE=1 让 clone 只取得 Git pointer：

~~~bash
GIT_LFS_SKIP_SMUDGE=1 git checkout --detach "$candidate"
git lfs fetch origin "$candidate"
git lfs checkout
git lfs fsck --objects "$candidate"
git status --porcelain=v1
~~~

这些命令必须在一次性 CI 目录或受控恢复副本执行。checkout 会改变 HEAD、index 和工作区；lfs fetch 会写本地 LFS cache；lfs checkout 写入可安全更新的工作区路径；fsck 检查指定 revision 的本地对象。成功不移动远程 Git refs，也不证明远端备份完整。

按错误层分流：

| 错误 | 说明 | 恢复办法 |
| --- | --- | --- |
| candidate 不是 commit | CI 事件、变量或 ref 解析错误 | 保留事件原文，回到上游候选固定流程 |
| LFS 客户端不存在 | runner 环境不满足前置条件 | 使用批准镜像/工具链，不在 job 中下载未知二进制 |
| 401/403、对象不可见 | endpoint、身份、scope 或组织授权边界 | 记录 request ID 和 OID，请 owner 核对；不要扩大长期令牌 |
| 对象不存在或校验不符 | 服务端保留、备份或上传链断裂 | 停止构建，隔离 cache，寻找可信 donor/备份；不要重新上传来源不明字节 |
| checkout 后仍是 pointer | cache 未命中、include/exclude、属性或工作区被修改 | 比较 pointer OID、cache 清单、属性来源和工作区摘要 |
| fsck 通过但构建失败 | Git 对象完整，不包含 payload | 把故障升级到 LFS/制品数据面，而不是运行 Git gc |

实际字节恢复后，重新计算 SHA-256 和 size，与 pointer 完全相等才允许继续构建。CI 清单至少记录 candidate commit、路径、pointer Git OID、payload OID/size、实际字节摘要、Git/Git LFS 版本和 endpoint 身份。cache 只能加速，不能作为唯一副本；来自不受信任分支的 cache 不得覆盖发布任务的可信输入。

不要在调查窗口运行 git lfs prune。它依据本地可见提交和配置判断可删除对象，不等同于组织级保留策略；共享自定义 LFS storage 的多个仓库尤其不能把一个仓库的 prune 当作全局安全动作。

## Submodule：父仓库固定的是 gitlink

父仓库的 tree 对 submodule 路径保存 mode 160000 和一个 commit OID，不保存嵌套仓库的 tree。先在父仓库确认：

~~~bash
candidate='FULL-SUPERPROJECT-COMMIT'
module_path='modules/engine'

git ls-tree "$candidate" -- "$module_path"
git config --file .gitmodules --get-regexp '^(submodule\..*\.(path|url))$'
git submodule status --recursive
git submodule foreach --recursive 'printf "%s\t%s\n" "$name" "$(git rev-parse HEAD 2>/dev/null || printf missing)"'
~~~

执行位置必须是非裸 superproject 工作树。ls-tree 应显示 160000 commit module-oid modules/engine；submodule status 前缀可表示未初始化、已修改或 HEAD 与 gitlink 不同；.gitmodules 是提交中的输入，但 URL 仍需按协议、主机和身份策略审核。foreach 会进入嵌套仓库执行命令，不能对不受信任仓库盲目运行。

git submodule update --init --recursive 的目标是 gitlink 指定的精确 commit，不是子模块远端当前分支的最新提交。它可能写 .git/modules、初始化工作树并把子模块置于 detached HEAD。前置条件是远端可达、对象已发布、协议允许、凭据可用和磁盘充足。

### “子模块目录空”不等于父仓库丢文件

| 状态 | 证据 | 安全动作 |
| --- | --- | --- |
| 未初始化 | status 以减号开头，目录不存在或为空 | 核对 .gitmodules、目标 URL 和权限，再按固定 OID 初始化 |
| 已初始化但 detached HEAD | 子模块 HEAD 等于 gitlink，symbolic-ref 失败 | 这是默认固定依赖状态；不要为了显示分支而移动 HEAD |
| 子模块工作树被修改 | git -C module status 非空，父仓库显示加号 | 先保存或丢弃子模块自己的修改，再决定是否更新 gitlink |
| gitlink commit 在远端不可见 | update 报找不到 commit | 先发布依赖 commit，再发布父仓库 gitlink；或把父仓库改回已发布 OID |
| .gitmodules URL 改变 | 父提交中的 URL 与本机覆盖配置不同 | 审查 URL、协议和身份；不要从不可信提交自动执行递归 URL |

依赖发布顺序是一个跨仓库事务约束：

1. 在依赖仓库创建并测试 commit；
2. 先把该 commit 发布到允许读取的远端 ref；
3. 在 superproject 更新 gitlink，记录 old/new OID；
4. 用 push --recurse-submodules=check 或等价检查确认依赖可达；
5. 再发布父仓库 ref；
6. 从空目录递归 clone，验证父候选、gitlink 和嵌套 HEAD 完全一致。

递归协议、SSH 主机密钥、HTTPS TLS、凭据助手、私有子模块授权和 .gitmodules URL 重定向都属于外部边界。不要为了让递归 clone 通过而全局设置 protocol.file.allow=always、关闭 TLS 校验或把 token 写进 .gitmodules。

恢复时记录父候选 commit、module path、gitlink OID、.gitmodules 原始和最终 URL、子模块远端可见性、认证主体、嵌套 HEAD、失败 stderr/退出码，以及是否写入 .git/modules。

## CI clone：候选、历史、外部数据面分开验收

CI 的 checkout 成功只证明 runner 在某个时刻把某个 Git tree 写到了工作区。它不自动证明 checkout 的是触发事件要求的 candidate，不自动证明浅/部分克隆满足版本计算，不自动证明 LFS payload 已水合，也不自动证明 submodule gitlink 可取得。

在 CI job 的实际 checkout 根目录先保存：

~~~bash
candidate_oid='FULL-OID-FROM-TRUSTED-EVENT'
test -n "$candidate_oid"
test "$(git rev-parse HEAD)" = "$candidate_oid"
git rev-parse --show-toplevel
git rev-parse --is-shallow-repository
git status --porcelain=v1
git submodule status --recursive
git rev-parse --git-dir
git config --show-origin --get-regexp \
  '^remote\..*\.(promisor|partialclonefilter)$' || true
~~~

HEAD 在 CI 常常是 detached，这是可接受的；真正的门禁是它等于可信候选 OID。status 应在构建前按约定为空；如果生成步骤需要修改工作树，先把源码快照和生成物分开。partial clone 配置只说明缺对象可以向 promisor 请求，不能证明 job 离线可用。

CI 输入清单建议使用以下字段：

| 层 | 必须记录 |
| --- | --- |
| Git 候选 | event/request ID、candidate OID、父 OID、目标基线、Git 版本 |
| 历史范围 | shallow 深度、是否 partial、filter、promisor endpoint、fetch refspec |
| LFS | pointer Git OID、payload OID/size、实际摘要、客户端版本、cache 来源 |
| Submodule | module path、gitlink OID、URL 摘要、嵌套 HEAD、递归状态 |
| 构建输出 | 源码归档摘要、工具链版本、制品 digest、发布/部署记录 |

任何一层缺少证据都应让构建进入明确的 inconclusive 或失败状态，而不是靠“目录里看起来有文件”继续发布。status 为空只能说明工作区与 index 的 Git 视角一致，不能证明 LFS payload、submodule 远端或制品服务可恢复。

## 恢复顺序：先保持引用，再补外部对象

外部依赖故障的安全顺序是：

1. 固定主仓库 candidate、refs、tree 和原始错误；
2. 保存 pointer/gitlink OID 和配置/URL 原文的受限副本；
3. 判断外部对象或依赖 commit 是未下载，还是权威服务/备份中已经缺失；
4. 优先从同一 OID 的可信服务或 donor 恢复，不创建新内容替代旧 OID；
5. 对恢复的 payload 做 hash/size 校验，对 submodule 核对 gitlink 与嵌套 HEAD；
6. 从空 CI/恢复目录重放 checkout、LFS 水合、递归 submodule 和最小构建；
7. 把仍不可见的服务端、权限、缓存、制品和审计证据登记为缺口。

如果只能找到工作区里一份内容，却无法证明它对应 pointer OID，不要直接覆盖 LFS 对象或提交新的 gitlink。那是一个新的候选输入，应走供应链和发布审批，不能伪装成恢复。

## 隔离实验：证明三种边界，而不是伪造平台

本书提供 scripts/verify-external-dependency-ci-failures.sh。在仓库根目录执行：

~~~bash
bash scripts/verify-external-dependency-ci-failures.sh
~~~

脚本在 mktemp 中使用虚构身份和本地 file 传输，依次验证：

1. LFS-like pointer 的 Git blob 与外部 payload 分离；移走 payload 后，required smudge 失败而 Git fsck 仍通过，恢复相同 OID 后才能水合；
2. superproject 的 tree 保存固定 gitlink；父仓库可以先被推送，但依赖 commit 尚未发布时，递归更新失败，依赖 commit 发布后同一 gitlink 才能成功检出；
3. CI fixture 以可信 candidate OID detached checkout，验证主仓库候选、gitlink 和外部 payload 的输入清单必须分别核对；
4. 失败输出、退出码和 recovery path 可在临时目录内被保留和验证，实验结束不修改本书仓库。

实验不模拟 Git LFS 服务 API、SSH/TLS、真实令牌、锁、配额、平台缓存、CI runner、合并请求、制品库或审计日志。自建 filter 只证明 pointer/payload 的层次和校验边界，不代表 Git LFS 3.7.1 的全部客户端行为；file URL 的协议开关也不能代表托管平台的授权策略。

## 小结

LFS 路径要同时证明 pointer、payload 和工作区字节；submodule 路径要同时证明 gitlink、.gitmodules URL、嵌套仓库和固定 commit 已发布；CI 路径要同时证明 candidate、历史范围、LFS 水合、递归依赖和构建输入。主仓库 fsck 通过只能说明 Git 对象图完整，不能升级成“外部数据面完整”。

恢复时先保存 OID 和引用，再从可信来源补对象或依赖；不要用当前工作区字节、子模块分支最新提交或不明 cache 覆盖原始身份。任何真实平台、服务端、凭据、锁、配额和审计结论，都要在目标环境按版本、权限、套餐和日期单独验证。

## 资料

- [Git LFS pointer specification](https://github.com/git-lfs/git-lfs/blob/v3.7.1/docs/spec.md)
- [git-lfs-fetch](https://github.com/git-lfs/git-lfs/blob/v3.7.1/docs/man/git-lfs-fetch.adoc)
- [git-lfs-checkout](https://github.com/git-lfs/git-lfs/blob/v3.7.1/docs/man/git-lfs-checkout.adoc)
- [git-lfs-fsck](https://github.com/git-lfs/git-lfs/blob/v3.7.1/docs/man/git-lfs-fsck.adoc)
- [git-submodule](https://git-scm.com/docs/git-submodule)
- [gitsubmodules](https://git-scm.com/docs/gitsubmodules)
- [gitmodules](https://git-scm.com/docs/gitmodules)
- [git-clone](https://git-scm.com/docs/git-clone)
- [git-rev-parse](https://git-scm.com/docs/git-rev-parse)
- [git-push](https://git-scm.com/docs/git-push)
