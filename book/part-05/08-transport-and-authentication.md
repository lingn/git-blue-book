# 传输与认证：连接、身份和授权必须分层排查

`clone`、`fetch` 和 `push` 都会与另一个仓库交换 Git 数据，但一条命令成功需要多层条件同时成立。URL 要能解析，传输通道要可信，服务端要识别客户端身份，该身份还要拥有仓库和目标 ref 的权限。最后，Git 的引用规则与平台策略仍可拒绝写入。

把这些条件统称为“账号问题”，常会走错修复方向。修改提交邮箱不会解决 HTTP 403，换 SSH key 不会解决 non-fast-forward，关闭 TLS 校验也不会修复过期令牌。

## 进入条件与完成标准

本章以 Git 2.49.0 的本地行为和 Git 官方手册为基线。SSH 服务、HTTPS 证书、令牌类型、SSO 与平台权限会随部署变化，真实系统必须记录产品版本、身份类型、规则和核对日期。

开始前先在目标仓库中只读采集：

~~~bash
git --version
git remote -v
git remote get-url --all origin
git remote get-url --push --all origin
git config --show-origin --show-scope \
  --get-regexp '^remote\..*\.(url|pushurl)$|^url\..*\.(insteadOf|pushInsteadOf)$|^credential\.'
~~~

输出可能包含内部主机、仓库路径、用户名和凭据助手位置，分享前要脱敏。上述命令不连接网络，也不修改对象、refs、index 或工作区。

读完本章后，应能区分 URL、承载传输、Git wire protocol、服务器身份、客户端认证、仓库授权和引用策略，能为 SSH、HTTPS 与本地传输选择验证方法，并在不泄漏秘密、不关闭身份校验的前提下定位失败层。

## 一次远程操作至少经过七层

以 `git fetch origin` 为例：

~~~text
Git 意图：读取哪些引用和对象
  -> remote/refspec：使用哪个地址，映射哪些引用
  -> 名称与网络：DNS、代理、路由、端口
  -> 承载传输：本地文件、SSH、HTTPS 或 git://
  -> 服务器身份：主机密钥或 TLS 证书
  -> 客户端认证与仓库授权：请求者是谁，允许做什么
  -> Git wire protocol：能力、引用、对象协商与 pack
  -> 引用/平台策略：是否接受目标更新并记录事件
~~~

不同实现可能把认证与授权放在代理、Git 服务或托管平台中，顺序也可能交错。诊断时仍应分别保存证据。HTTPS 完成 TLS 握手不代表令牌有读取权限；SSH 公钥认证成功不代表仓库路径正确；读取成功也不证明能够更新主线。

## URL 选择地址和承载方式

| URL 形式 | 保护边界 | 常见用途 |
| --- | --- | --- |
| `/srv/git/project.git`、`file:///srv/git/project.git` | 操作系统文件权限；没有网络主机认证 | 同机实验、受控共享存储 |
| `ssh://git@host.example/team/project.git` | SSH 主机校验、加密和客户端密钥 | 工程师交互式访问、受控自动化 |
| `git@host.example:team/project.git` | SSH 的类 scp 写法；冒号后为远端路径 | 与上一项相同，但解析形式不同 |
| `https://host.example/team/project.git` | TLS、HTTP 认证、代理和凭据助手 | 桌面、企业代理、CI |
| `git://host.example/project.git` | Git 原生传输本身不提供加密与认证 | 只用于明确接受风险的环境 |

`origin` 只是本地名称。真正连接的地址还可能受 `pushurl`、`remote.pushDefault`、`branch.<name>.pushRemote`、`url.*.insteadOf` 和 `pushInsteadOf` 影响。排查“为什么推到了另一个仓库”时，要读取最终 fetch URL 与 push URL，不能只看平台页面上复制的地址。

本地路径与 `file://` 也不天然可信。它们把认证边界换成了本机账号、目录权限、挂载点和来源仓库。书中的 bare 仓库实验用它验证 Git 数据面，不模拟网络安全或托管平台。

## Protocol v2 不提供加密或授权

Git wire protocol 负责能力声明、引用发现、对象协商与传输。Protocol v2 调整了应用层交互，可以减少某些引用通告并支持按命令扩展，但它可以承载在 SSH、HTTPS 或本地进程之上。

因此，protocol v2 不是 HTTPS 2，也不会自动带来 TLS、主机校验、客户端认证或仓库授权。遇到兼容问题时，分别记录 Git 客户端版本、URL、承载方式、代理、服务端实现和 packet trace。不要用关闭证书校验来测试协议版本。

`GIT_TRACE_PACKET=1` 会显示协议包行，可能暴露引用名、对象 ID、能力、仓库结构和服务端信息。只在受控环境采集，并把 trace 当作当次实现证据，不把它写成所有服务端固定执行顺序。协商细节由[协商与受限克隆](09-negotiation-and-limited-clones.md)继续展开。

## 四类身份回答四个问题

| 层次 | 回答的问题 | 常见证明 | 不能证明什么 |
| --- | --- | --- | --- |
| 服务器身份 | 连接的是预期主机吗 | SSH 主机密钥、HTTPS 证书链与主机名 | 客户端是否有仓库权限 |
| 客户端认证 | 服务端把请求识别为谁 | SSH 公钥、令牌、OAuth、客户端证书 | 该主体允许执行哪些动作 |
| 授权 | 该主体能对哪个资源做什么 | 仓库角色、部署 key 范围、ref 规则 | 提交内容由谁编写 |
| 历史身份 | commit/tag 声称谁是作者或提交者 | `user.name`、`user.email`、对象签名 | 谁完成 push、代码是否正确 |

一次审计至少要能关联 authenticated principal、仓库、动作、目标 ref、old/new OID 和服务端事件。提交作者、提交者和签名结果是另一组字段。只看网页头像或 commit 邮箱，无法还原推送主体。

## SSH 先校验主机，再选择客户端密钥

首次连接时出现主机密钥指纹，表示本机还没有对应信任记录。应从平台官方文档、管理员公告或另一条可信渠道取得预期指纹，再逐字核对。`ssh-keyscan` 只能告诉你当前网络端点提供了什么，不能独立证明端点身份。

出现 `REMOTE HOST IDENTIFICATION HAS CHANGED` 时先停止。计划轮换、DNS 或负载均衡变化会触发该错误，中间人攻击也可能触发。保留主机、端口、密钥类型与新旧指纹，确认变更后只更新对应记录，不要删除整个 `known_hosts`。

在任意目录只读检查 SSH 最终配置：

~~~bash
git_host=host.example
ssh -G "$git_host" | sed -n \
  '/^hostname /p;/^user /p;/^port /p;/^identityfile /p;/^userknownhostsfile /p'
ssh-keygen -F "$git_host"
ssh-add -l
~~~

示例主机必须替换。`ssh -G` 只展开客户端配置，不连接主机；输出可能包含私有路径。`ssh-add -l` 无身份时会返回非零，无法连接 agent 时问题仍在本地会话。

托管服务常让所有人使用 URL 中的 `git` 用户，再按公钥映射到平台主体。URL 用户名相同不代表共享操作系统账户。`ssh -T` 也不是通用 Git 验收：服务可能没有交互式 shell，认证成功后仍返回自定义消息或非零状态。读取路径应使用更接近真实操作的命令：

~~~bash
git ls-remote origin
~~~

它会连接远端并查询当前身份可见的 refs，不更新本地 remote-tracking ref。空仓库成功时可以没有输出，应同时保存退出状态。`Host key verification failed` 指向服务器身份；`Permission denied (publickey)` 指向密钥选择或登记；认证后 repository not found 还可能来自路径错误、无权限或平台的存在性隐藏策略。

SSH agent 转发会让远端会话调用本地签名能力。只有受控跳板和明确威胁模型需要时才启用。CI 更适合短期、单仓库、最小权限的机器身份，详见[机器身份](../part-10/02-machine-identities.md)。

## HTTPS 要分别验证 TLS 和凭据

TLS 先校验证书链与 URL 主机名，并保护连接内容；HTTP 服务随后处理客户端凭据。企业代理可能终止并重建 TLS，应由组织确认代理身份、分发受控 CA，并定义轮换与回退流程。

不要把下面的配置当作排障办法：

~~~text
http.sslVerify=false
~~~

它取消关键的服务器身份校验，可能把凭据发送给错误端点。证书错误应检查系统时间、URL、主机名、代理、可信 CA 和证书轮换。若组织要求自定义 CA，先用 `--show-origin` 确认作用域，再按目标环境配置，避免把仓库级问题扩大成用户全局变更。

令牌不要写进 URL。带秘密的 URL 可能进入 `.git/config`、Shell 历史、进程参数、日志和截图。先检查凭据助手的来源：

~~~bash
git config --show-origin --show-scope --get-all credential.helper
git config --show-origin --show-scope --get-regexp '^credential\.'
~~~

命令不会显示助手保存的密码本身，但可能暴露主机、用户名和程序路径。无输出只说明 Git 配置没有声明助手，不排除 IDE、系统会话或环境另行提供凭据。

## Credential helper 管理取用，不发放权限

Git credential 协议按 protocol、host 以及可选 path 查询一个或多个助手。认证成功后可以发送 `approve`，认证失败后可以发送 `reject`。助手保存的是客户端秘密，不决定平台角色、分支保护或令牌 scope。

`git credential fill` 会把取得的用户名和秘密写到标准输出。不要对真实账号随手运行，更不要把输出粘贴到工单。本书实验把全局配置重定向到临时文件，用虚构主机和令牌验证 `approve`、`fill`、`reject`。

默认 HTTP 凭据匹配可能忽略 URL path。同一主机使用多账号或不同仓库范围令牌时，需要评估：

~~~bash
git config --show-origin --get credential.useHttpPath
~~~

将 `credential.useHttpPath` 设为 `true` 会让助手按仓库路径区分记录，也可能要求用户分别登录。它是作用域设计，不是越安全越应全局开启的开关。修改前盘点现有助手、多账号与平台 URL 规范，回退时只删除自己添加的同一作用域配置。

CI 中可以设置 `GIT_TERMINAL_PROMPT=0` 让缺少凭据立即失败，但这个变量不提供认证。作业仍需可信 CA、明确身份、最小权限和日志掩码。不受信任分支的构建脚本能够读取环境与 Git 配置，不能默认接触发布凭据。

## 迁移 URL 时分开验证读写路径

真实仓库迁移前，取得新 URL 的可信来源，确认目标仓库和读取身份，记录当前工作状态与旧 URL。下面命令在目标本地仓库执行；示例主机不可连接：

~~~bash
remote_name=origin
new_url=ssh://git@host.example/team/repository.git

git status --short --branch
old_url="$(git remote get-url "$remote_name")"
git remote set-url "$remote_name" "$new_url"
git remote get-url --all "$remote_name"
git ls-remote "$remote_name"
~~~

`set-url` 只修改本地配置，不移动对象、refs、index 或工作区。`ls-remote` 发起只读查询，成功不代表有写权限。若验证失败，且当前 Shell 仍保存可信旧值：

~~~bash
git remote set-url "$remote_name" "$old_url"
git remote get-url --all "$remote_name"
~~~

这只恢复 URL，不撤销 CA、SSH、凭据或平台端变更。写权限应在专用测试 ref 或测试仓库验证，不要向主线试推。

## 按第一处失败分流

| 线索 | 优先检查 | 不应采取的动作 |
| --- | --- | --- |
| `Could not resolve host` | URL、DNS、VPN、split DNS | reset 或重写提交 |
| 连接/代理超时 | 路由、代理、防火墙、服务状态 | 反复生成令牌 |
| Host key 失败或变化 | 实际主机/端口、可信指纹、轮换公告 | 删除整个 `known_hosts` |
| TLS 证书失败 | 时间、主机名、证书链、企业代理 | 关闭 `sslVerify` |
| `Permission denied (publickey)` | SSH 用户、密钥、agent、服务端登记 | 修改 `user.email` |
| HTTP 401 | 凭据是否过期、助手旧记录、认证方式 | 把令牌写进 URL |
| HTTP 403、not found | 仓库路径、主体、角色、SSO、存在性隐藏 | 只凭文案断定仓库已删除 |
| Non-fast-forward、hook、protected | old/new OID、ref 规则、平台策略 | 换传输方式或无条件强推 |

先用 `git remote get-url` 固定 endpoint，再保存 Git 版本、时间、cwd、退出状态和原始错误。读路径成功后才能判断写路径。详细 trace 可能包含内部 URL、用户名、HTTP 头、refs 甚至外部助手输出，采集前设定最小范围，分享前人工脱敏。

认证或授权拒绝通常不会改变本地提交。远端状态未知时用只读查询重新观察；查询也失败则把结果标为未知，不要重复 push 猜测。

## 凭据泄漏先撤销，再清理载体

令牌、密码或私钥一旦进入配置、日志、提交或制品，先在身份控制面撤销或轮换。历史重写需要时间，也收不回已经被克隆、缓存或复制的秘密。

处理记录至少包含发现时间、秘密类型、权限范围、受影响仓库和自动化。撤销后清理 remote URL、凭据助手、CI 变量、缓存与制品，再检查身份和平台审计。秘密进入提交时，按[凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md)覆盖所有 refs、派生仓库、镜像和 LFS。

删除本地私钥不能阻止已复制的副本继续认证；删除提交也不等于服务端和旧 clone 已清除。恢复完成要证明旧凭据失效，并记录新凭据的最小权限和轮换时间。

## 隔离实验

在本书仓库根目录运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-remote-transport-auth.sh
~~~

前置条件是 Bash、Git 2.28 或更高版本以及可写临时目录。脚本用 `file://` bare 仓库验证 clone、fetch、push 的 Git 数据面，并把 Git 全局配置重定向到临时文件，用虚构 HTTPS 主机验证 credential helper 的 `approve`、`fill`、path 隔离和 `reject`。成功时最后输出：

~~~text
File transport and isolated credential-helper experiments passed.
~~~

实验不会连接网络或读取真实凭据。它不能证明 DNS、SSH 主机密钥、HTTPS TLS、真实令牌、SSO、平台授权、保护规则、审计或 CI 身份。对应问题必须在获批测试仓库按产品、版本、角色和核对时间留证。

## 小结

远程命令同时跨越 endpoint、传输、服务器身份、客户端认证、仓库授权、Git 协议和引用策略。每层证据只能回答自己的问题。排障从实际 URL 和第一处失败开始，保留本地候选，不用改历史或关闭校验掩盖连接与权限问题。

## 资料

- [Git URLs](https://git-scm.com/docs/git-clone#_git_urls)
- [Git protocol v2](https://git-scm.com/docs/protocol-v2)
- [gitcredentials](https://git-scm.com/docs/gitcredentials)
- [git-credential](https://git-scm.com/docs/git-credential)
- [git-config](https://git-scm.com/docs/git-config)
