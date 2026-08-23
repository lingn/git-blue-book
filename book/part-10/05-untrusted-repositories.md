# Clone 不等于执行：不受信任仓库、配置、filters 与 hooks

“我只是 clone 下来看看”比“我直接运行项目”安全，但不是零风险。Clone 要连接远端、调用传输与凭据组件、创建本地仓库，并在默认情况下把 tree 写入工作区。写入工作区时，受跟踪的 `.gitattributes` 可以选择本机已有的 filter；本机模板可以把 hook 安装进新仓库；显式递归选项还会根据 `.gitmodules` 发起更多 clone。

反过来，普通 clone 不会把源仓库的 `.git/config` 或 `.git/hooks/` 当作历史传过来。受跟踪的 hook 脚本也只是一个普通可执行文件，除非本机配置、hook 管理器、构建系统或操作者把它接入执行入口。安全审计必须分清“对象到达”“配置选择程序”“程序真正运行”三个时刻。

进入本章前，读者应理解对象与 tree、配置作用域、clone/fetch、认证、submodule 的 gitlink 直觉，以及 CI 中不受信任候选与受保护凭据的分离。读完后，应能解释 `safe.directory` 的准确边界，审计 clone 前后的本地控制面，判断 attributes、filters、hooks 和递归依赖何时执行，并在不确定时使用隔离环境保全证据。

本章在 Git 2.49.0 和 macOS 上验证。文件所有权、symlink、可执行位、sandbox、OpenSSH、容器和企业终端策略会影响实际结果；先记录 Git、操作系统和文件系统环境。本文不把“Git 命令没有报错”扩大为代码或依赖安全结论。

## 先画出四类输入

接触外部仓库时，把输入按控制面拆开：

| 输入 | 普通 clone 是否取得 | 何时可能执行本机程序 | 典型风险 |
| --- | --- | --- | --- |
| Git refs 与对象 | 是，按 refspec 与可达性取得 | checkout、diff、merge、构建等后续动作 | 恶意路径、脚本、CI 配置、依赖描述 |
| 源仓库 `.git/config`、hooks、reflog | 否，不属于被 fetch 的对象历史 | 不适用；但打包的完整工作目录或共享磁盘可能直接带来 | 本地命令、凭据 helper、hook 与引用状态被预置 |
| 目标机 system/global/local 配置和模板 | 由目标机提供，不来自远端历史 | clone 的传输、初次 checkout、hook、filter、pager 等阶段 | 高权限 helper、filter 或模板 hook 被意外复用 |
| 仓库外部资源 | 由 `.gitmodules`、LFS pointer、构建清单等间接指向 | 显式递归、filter、包管理器或构建工具运行时 | 第二个远端、凭据扩散、依赖替换与任意构建脚本 |

这张表解释了两个看似矛盾的事实：远端不能靠一次普通 fetch 直接把自己的 `.git/hooks/pre-commit` 塞进目标 `.git/hooks`；但远端可以提交 `tools/hooks/pre-commit`、`.gitattributes`、`.gitmodules` 或构建脚本，等待本机另一个受信任组件选择并执行它。

“文件带有 executable bit”也不等于 Git 会自动运行。它只保存 tree mode；真正执行仍需要 Shell、构建器、hook 路径、CI runner 或用户动作。

## Clone 的安全起点是延迟 checkout 与递归

对来源尚未建立信任的仓库，首次获取可在低权限、无生产凭据的临时环境中进行。下面只展示命令契约；`source_url` 必须由操作者从可信渠道取得并核对，不能从不受信任文本直接拼进 Shell：

```bash
review_root="$(mktemp -d "${TMPDIR:-/tmp}/git-review.XXXXXX")"
mkdir "$review_root/empty-template"
source_url=https://example.invalid/review/repository.git

git clone \
  --no-checkout \
  --no-recurse-submodules \
  --template="$review_root/empty-template" \
  "$source_url" \
  "$review_root/repository"
```

前提是隔离账号已配置可信 DNS/TLS/SSH 主机校验和只读凭据，并且 `example.invalid` 已替换为实际审核地址。命令创建目标 `.git`、取得远端对象与引用，但不执行初次工作区 checkout，也不初始化 submodule。空模板避免把本机默认 template hook 复制到新仓库；它不能禁用传输 helper、凭据 helper 或其他 system/global 配置。

成功输出中的 URL、对象数量和默认分支会随服务器变化。失败时保留完整传输错误，区分服务器身份、认证、授权、协议和对象校验；不要靠关闭 TLS/主机校验“恢复”。临时目录的清理由审核流程在证据保存后完成，本章不提供对任意路径的递归删除命令。

`--no-checkout` 不是通用沙箱。Git 仍需要连接 URL，并可能调用 `credential.helper`、`core.sshCommand` 或外部 remote helper。高风险来源应使用一次性虚拟机/容器、网络出口限制、只读凭据和无共享缓存环境，而不是只叠加 Git 选项。

### 不 checkout 也能先读 tree

固定实际审核的对象，而不是继续使用会移动的远端分支名：

```bash
repo="$review_root/repository"
candidate="$(git -C "$repo" rev-parse --verify 'refs/remotes/origin/main^{commit}')"

git -C "$repo" show --no-patch --format='%H%n%P%n%T%n%s' "$candidate"
git -C "$repo" ls-tree -r --full-tree "$candidate"
git -C "$repo" show "$candidate:.gitattributes"
git -C "$repo" show "$candidate:.gitmodules"
```

前提是远端确有 `main`；若默认分支不同，应先只读 `git remote show origin` 与 `git show-ref`，不能猜名字。前两条读取 commit 与 tree，不写工作区。后两条只有在路径存在时才成功；退出码非零可能只是该提交没有对应文件，不代表仓库损坏。

`ls-tree` 输出中的对象 ID、mode 和路径是数据。人工查看适合初筛；自动化处理任意文件名时必须使用 `-z` 并按 NUL 分隔解析，不能按空格或换行拆分。重点审计 executable mode、symlink、`.gitattributes`、`.gitmodules`、CI 配置、安装脚本、Makefile/任务文件和包管理器生命周期脚本。

## `safe.directory` 是所有权门禁，不是恶意代码扫描

默认情况下，Git 拒绝访问由其他操作系统用户拥有的仓库；它不会解析该仓库的 local config，更不会运行其 hooks。`safe.directory` 用于声明某个不同所有者的路径是有意共享的例外。

该设置只在 Git 所称的 protected configuration 中生效，例如 system 或 global 范围。仓库不能在自己的 `.git/config` 中加入 `safe.directory=*` 来批准自己，这是这道门禁的关键设计。

遇到 “detected dubious ownership” 时先采证：

```bash
suspect_repo=/absolute/path/to/repository
ls -ld "$suspect_repo" "$suspect_repo/.git"
git config --show-origin --show-scope --get-all safe.directory
```

命令不修改所有权和配置。路径必须先替换为错误中显示的确切仓库；不要把仓库内容、用户名或内部目录原样贴到公开渠道。要判断的是：目录为什么由另一个账号拥有、共享是否符合预期、该账号能否继续写入 `.git/config` 或 hooks。

只有完成所有权与用途核对后，才可增加精确例外：

```bash
git config --global --add safe.directory "$suspect_repo"
git config --show-origin --show-scope --get-all safe.directory
git -C "$suspect_repo" status --short --branch
```

第一条修改当前用户的 global config，使这个路径的不同所有者仓库可被 Git 读取；随后 Git 也可能读取其 local config 和 hooks。状态命令成功只证明门禁放行，不证明仓库内容或配置可信。

若判断有误，撤销刚添加的精确值：

```bash
git config --global --fixed-value --unset-all safe.directory "$suspect_repo"
```

命令只移除完全相同的 global 值，不恢复已经执行的 hook/filter，也不改变文件所有权。若值来自 system config，需由管理员在对应来源处理。

不要把 `safe.directory=*` 当作容器、CI 或共享盘的常规修复。它会关闭所有权检查；`/shared/*` 则放行该目录下所有仓库。更安全的修复通常是纠正镜像/挂载所有权、为专用路径添加精确值，或让任务在与文件 owner 一致的低权限账号运行。

同一用户自己 clone 的恶意仓库通常能通过所有权检查。这再次说明 `safe.directory` 只处理“谁控制本地仓库元数据”，不判断 tree 是否有恶意代码。

## `safe.bareRepository=explicit` 限制隐式发现

Git 也可以把当前目录识别成 bare repository。若日常工作不依赖进入 bare 目录后隐式运行 Git，可在 protected config 中要求显式指定：

```bash
git config --global safe.bareRepository explicit
git config --show-origin --show-scope --get safe.bareRepository
```

这会修改 global config。之后，进入某个 bare 目录直接运行 Git 会被拒绝；明确使用顶层 `--git-dir=/absolute/path/repository.git` 或 `GIT_DIR` 的操作仍可工作。它能降低“普通仓库 tree 中嵌入 bare repo，用户进入目录后无意使用其 config/hooks”的风险。

该策略可能破坏已有管理脚本。部署前先盘点 bare 仓库工作流并在测试账号回归。回退自己添加的值：

```bash
git config --global --unset safe.bareRepository
```

回退恢复默认发现能力，不清除任何 bare 仓库。若组织在 system config 中强制该策略，本地 unset 不会覆盖来源；使用 `--show-origin` 定位责任边界。

## Config 被解析不等于程序已经执行

Git config 是控制面。大多数值在读取时只是数据，只有相应 Git 路径使用它们时才会调用外部程序或改变网络行为。排障时要同时记录“危险值存在”和“哪个命令触发了它”。

在已经决定允许访问的仓库中只读审计配置：

```bash
git -C "$suspect_repo" config --show-origin --show-scope --list
```

输出可能包含内部 URL、helper 名称、代理甚至误配的秘密，保存时应限制权限并脱敏。自动化采集要使用 `--null` 处理特殊字符。除 system/global/local/worktree 外，条件 include 和命令行 `-c` 也会影响最终值；只看 `.git/config` 不足以还原行为。

优先检查会选择外部程序或扩大访问面的键：

| 配置族 | 触发动作 | 风险边界 |
| --- | --- | --- |
| `core.hooksPath` | commit、merge、push、checkout 等特定 hook 点 | 指向仓库内或外部可执行程序 |
| `filter.<name>.clean/smudge/process` | add、checkout、restore、merge 等内容转换 | 程序读写 blob，可访问网络与当前进程环境 |
| `diff.<name>.command/textconv` | diff、log 等展示路径 | “只看 diff”也可能启动外部程序 |
| `merge.<name>.driver` | 自定义 merge driver 被 attribute 选择时 | 可修改合并结果并执行任意工具 |
| `credential.helper` | HTTPS 等认证需要凭据时 | helper 可读取、返回或保存凭据 |
| `core.sshCommand`、remote helper、URL rewrite | clone/fetch/push | 改变实际连接程序与目标地址 |
| `alias.<name>=!…`、editor、pager | 用户调用 alias 或需要编辑/分页时 | 不是解析即执行，但调用点可能进入 Shell |

这不是完整枚举。签名程序、fsmonitor、文本转换和第三方 Git 扩展也可能启动进程。Git 没有一个能让任意仓库在所有命令下都“绝不执行外部程序”的通用 safe mode；高风险分析需要操作系统级隔离。

普通网络 clone 会在目标端新建 local config，不复制源 `.git/config`。但下载的完整工作目录压缩包、共享开发盘、缓存恢复、容器层或被攻陷的 CI workspace 可能直接带来预置 `.git/config`。它们不能套用“clone 不传 config”的结论。

## `.gitattributes` 选择 driver，命令定义留在 config

受跟踪的 `.gitattributes` 可以为路径声明：

```gitattributes
*.asset filter=media
*.bin diff=binary-report
*.lock merge=lockfile
```

这些行会随 commit 到达 clone，选择名为 `media`、`binary-report` 或 `lockfile` 的 driver。实际命令定义在本机 config，例如 `filter.media.smudge`；远端 tree 不能仅靠上述三行定义任意 Shell 命令。

选择与定义的组合仍会形成执行链：

```text
tracked .gitattributes
        -> 某路径选择 filter=media
local/system/global config
        -> filter.media.smudge=/path/to/program
checkout/restore
        -> Git 启动该程序并把 blob 交给它
```

`clean` 在内容进入 index 前转换，`smudge` 在 blob 写入工作区时转换，`process` 是可复用的长运行 filter。程序与普通子进程拥有相同账号权限，能读取环境、网络和可访问文件；“它只是 Git LFS/格式化器”不是权限隔离。

在 checkout 前只读检查选择器和本机定义：

```bash
git -C "$repo" show "$candidate:.gitattributes"
git -C "$repo" config --show-origin --show-scope --get-regexp '^filter\.'
```

第二条没有匹配时退出 1，并不保证其他执行入口为空。Checkout 后可对具体路径运行 `git check-attr -a -- path`；该命令读取 attribute 结果，不主动执行对应 filter。

普通 filter 缺失或失败时，Git 可能把内容原样透传；`filter.<name>.required=true` 会把失败升级为命令失败。这是 LFS 或加密 pointer 等“仓库内内容本身不可用”场景的重要正确性保障，但也意味着 checkout/restore 可在工作区写入一部分内容后停止。失败时先检查 `status`、目标路径和 filter 日志，不要直接把 `required` 关闭后继续构建。

修改 clean 规则后，官方工作流可能要求 `git add --renormalize .`。它会让大量路径经过 clean 转换并改写 index 候选；在 driver 代码、版本和恢复分支未审计前，不要在真实工作区执行。

## Hooks 是本地程序，tracked hook 需要安装动作

Git 默认从 `$GIT_DIR/hooks/` 查找可执行 hook，`core.hooksPath` 可以改到其他目录。普通 clone 不传输源 `$GIT_DIR/hooks/`；默认 template 中的 sample hooks 也因 `.sample` 后缀而禁用。

但有三条常见安装路径：

1. 目标机的 Git template 在 init/clone 时复制 hook；clone 完成 checkout 后可触发目标仓库的 `post-checkout`；
2. bootstrap 或 hook manager 把 tracked 脚本复制/链接到 `.git/hooks`；
3. local/global `core.hooksPath` 直接指向仓库中的 tracked 目录。

在允许访问的仓库中先定位，不执行：

```bash
git -C "$repo" rev-parse --git-path hooks
git -C "$repo" config --show-origin --show-scope --get core.hooksPath
ls -la "$(git -C "$repo" rev-parse --git-path hooks)"
```

第二条无输出可能表示使用默认 hooks 目录。`ls` 只列目录，但 Shell 初始化、文件系统工具或终端插件仍属于环境边界；对高度可疑现场应在取证镜像/沙箱操作。

Pre-commit、commit-msg、pre-push 等 hook 可用非零退出阻止对应动作；post-commit、post-checkout 等可能在主要状态变化完成后才运行，失败不能自动回滚 commit 或 checkout。Hook 获得 Git 环境变量和当前账号权限，不能把它当成低权限插件。

`--no-verify` 只绕过部分 hook，不是全局禁用开关，也不是处理恶意 hook 的安全办法。发现意外 hook 时应停止执行、记录路径/摘要/配置来源，转移到隔离环境；若 hook 已经运行，还要按可能的凭据与主机泄漏调查，不能只删除脚本。

## `.gitmodules` 会把一次 clone 扩展成多个信任决定

Superproject tree 中的 gitlink 只记录 submodule commit ID；`.gitmodules` 则记录路径和建议 URL。普通 `git clone` 默认不初始化 submodule，而 `--recurse-submodules` 或后续 `git submodule update --init --recursive` 会解析 URL、连接更多仓库、取得对象并 checkout 各自 tree。

初次审核至少读取：

```bash
git -C "$repo" show "$candidate:.gitmodules"
git -C "$repo" ls-tree -r "$candidate" | grep '^160000 '
```

第一条检查 URL、路径和递归范围；第二条列出 gitlink mode 与记录的对象 ID。无输出可能表示没有 submodule。自动化仍应使用 NUL-safe 解析，不把这个 `grep` 人工检查示例直接扩展为安全扫描器。

Git 2.49 的默认协议策略把 `http`、`https`、`git`、`ssh` 视为可用传输，把 `ext` 默认禁用，把 `file` 和未知协议设为 `user`：用户直接发起时可用，由 submodule 等无用户输入的递归命令发起时受限。这只是“是否允许使用某种 transport”的门禁，不表示 HTTPS URL、SSH 服务器或依赖内容可信。

不要为了让递归 clone 通过而全局设置 `protocol.file.allow=always` 或 `protocol.allow=always`。确需本地 fixture 时，在一次性实验中用命令级 `-c protocol.file.allow=always` 明确放行，并确认路径由当前账号控制。生产依赖应使用经过认证、授权和可用性治理的来源。

`git submodule update --remote` 还会按子模块远程分支选择新提交，而不是严格使用 superproject 记录的 gitlink；可重复构建和安全审查不应无记录地把固定对象改成“取当前最新”。Submodule 的完整运维模型将在第九篇展开，本章只建立递归信任边界。

LFS 具有相似但不相同的外部对象边界：Git tree 保存 pointer，smudge/process filter 可能访问 LFS 服务取得真实内容。签名 commit 会绑定 pointer，不自动证明外部 LFS 对象可获取、无恶意或符合配额策略。

## CI 必须假定候选会修改执行入口

候选提交可以合法修改 CI YAML、构建脚本、`.gitattributes`、`.gitmodules`、依赖锁文件和 tracked hook。审查这些变化时，先回答谁的权限会执行、会读取哪些 secrets、能写哪些缓存/制品/引用，以及依赖是否固定到不可变身份。

最低隔离边界是：不受信任候选的验证 job 使用只读源码权限、无发布 secret、隔离网络和隔离缓存；使用生产凭据的 job 不重新执行候选提供的任意脚本，只消费已验证的不可变制品和证据。信任策略、allowed signers、runner 初始化与发布脚本还要来自候选之外的受保护来源。

第三方 Action、复用 workflow、远程模板、容器镜像、工具下载、cache 和来源证明的完整治理见[第三方 CI 依赖与来源证明](03-ci-dependency-supply-chain.md)。本章只负责说明候选 tree 与本地/平台执行入口何时组合，不在这里重复维护固定、更新和事故清单。

某个平台何时向派生仓库 job 注入 secret、是否允许修改 runner 或 cache，是易变产品事实，必须按厂商、权限和核对日期登记，不能用本地 Git 实验替代。

## 事故现场按“是否已经执行”分流

| 现象 | 首要证据 | 安全动作 |
| --- | --- | --- |
| dubious ownership | owner/group、挂载方式、safe.directory 来源 | 保持拒绝，核对共享理由；精确修复 owner 或例外 |
| clone 结束出现陌生进程/文件 | template、global/local config、post-checkout 与 filter 日志 | 隔离主机/runner，保存配置和进程证据，调查凭据访问 |
| restore/checkout 因 filter 失败 | attribute 来源、filter config、required、路径与 index | 停止构建，记录部分工作区；在无 filter 的隔离 clone 取原始 blob |
| commit 被陌生 hook 拦截 | hooksPath、默认 hooks 目录、脚本摘要、HEAD/index | 不用 `--no-verify` 强闯；隔离并确认 hook 安装来源 |
| hook 已运行后才发现异常 | hook 类型、时间、网络/文件/凭据日志 | 按代码执行事件处置，轮换可能暴露的秘密；删 hook 不等于恢复 |
| submodule/LFS 访问意外地址 | `.gitmodules`/LFS config、实际 URL、协议策略和凭据日志 | 终止递归，吊销泄漏凭据，验证固定对象与允许来源 |
| 设置 `safe.directory=*` 后问题消失 | system/global 配置来源和任务 owner | 移除通配，修复所有权或建立专用精确目录 |

Filter/hook 可能已经修改工作区、index、引用或仓库外状态。不要在包含用户未提交工作的现场直接运行 `reset --hard`、clean 或递归删除。先复制证据并在一次性 clone 重建可信基线；对网络、凭据和制品的影响需要在 Git 之外恢复。

## 隔离实验验证了什么

在本书仓库根目录运行：

```bash
./scripts/verify-untrusted-repository.sh
```

前置条件是 Bash、Git 2.49 或兼容实现、`grep`、`mktemp` 和可写临时目录。脚本创建临时仓库，隔离 system/global Git 配置，不连接网络，不读取真实凭据，退出时删除自己的 `mktemp` 根目录。

第一组断言使用 Git 自身测试套件采用的 `GIT_TEST_ASSUME_DIFFERENT_OWNER=1`，在不修改真实文件 owner 的情况下模拟不同所有者。该变量不是面向生产的 Git 接口；实验只用它验证当前 2.49 实现会忽略 repository-local `safe.directory=*`、接受 global 精确路径，并在删除例外后再次拒绝。真实事故必须读取操作系统 owner，不能设置这个变量制造结论。

第二组设置 protected `safe.bareRepository=explicit`，确认隐式进入 bare repo 被拒绝，而顶层 `--git-dir` 显式指定仍可读取。随后实验建立 source 与 clone：source 的 local filter 和 `.git/hooks/post-checkout` 没有传到目标，空 template 也没有安装 hook；受跟踪 `.gitattributes` 与 hook 脚本则作为普通 tree 内容到达。

目标仓库显式配置 filter 后，restore 触发 smudge helper；把 required filter 换成失败程序后，restore 返回非零，移除本地 driver 配置才恢复原始 blob。显式把 `core.hooksPath` 指向 tracked hook 后，pre-commit 运行并阻止 commit；unset 配置后，原 index 候选成功提交。

最后，superproject 记录临时本地 submodule URL。默认递归 update 因 `file` 协议策略失败，命令级显式放行后才取得固定 dependency commit。它验证的是协议门禁与 gitlink，不证明公网 submodule、LFS、托管平台、容器或 CI runner 安全。

成功时只输出：

```text
Ownership gates, bare discovery, clone boundaries, filters, hooks, and recursive protocol passed.
```

## 小结

普通 clone 传输 refs、对象和工作 tree，不传输源仓库的 local config 与 `$GIT_DIR/hooks`。真正的风险来自远端 tree 与本机控制面的组合：attributes 选择本机 filter，tracked hook 被安装或 `hooksPath` 选中，`.gitmodules` 让一次获取扩展到更多来源，构建与 CI 配置则能主动运行候选代码。

`safe.directory` 只阻止不同 owner 仓库控制本地 Git 元数据，`safe.bareRepository=explicit` 只限制隐式 bare 发现。面对不受信任来源，应延迟 checkout/递归、固定候选对象、审计配置来源和执行入口，并把真正的运行放进无生产凭据的操作系统级隔离环境。
