# 远程状态模型：服务器事实、本地缓存和工作分支不能混写

一个 clone 里可以同时出现 `main`、`origin/main` 和 `origin/HEAD`。它们都存放在本地，却回答不同问题：本地工作线在哪里，上次 fetch 观察到服务器 main 在哪里，本地认为远端默认分支叫什么。服务器真正的 `refs/heads/main` 只能通过本次通信、服务端副本或平台审计观察。

远程协作的核心不是“同步文件夹”，而是两个仓库交换对象并尝试更新 refs。工作区、index、平台评审、权限和发布状态位于不同层，任何一条 Git 命令都只能覆盖其中一部分。

## 进入条件与完成标准

真实仓库先做不改变 refs 的本地观察：

~~~bash
git version
git status --short --branch
git remote -v
git for-each-ref refs/heads/ refs/remotes/ \
  --format='%(refname) %(objectname) %(upstream) %(upstream:track)'
~~~

`remote -v` 可能显示内部路径、用户名或嵌入式秘密，分享前脱敏。需要查询服务器时使用受控身份和目标，并记录查询时间。

读完本章后，应能分开服务器 ref、查询响应、remote-tracking ref、本地分支、upstream、`FETCH_HEAD`、远端 symbolic `HEAD` 和平台控制面，预测 clone/fetch/pull/push 的写入范围，并按连接、认证、授权、引用和整合层分流失败。

## 远程只是另一个仓库

~~~text
开发者仓库                         服务器仓库
objects/                            objects/
refs/heads/main                     refs/heads/main
refs/remotes/origin/main   <---->   其他可见 refs
HEAD / index / 工作区                通常是 bare，无工作区
~~~

“远程”描述当前仓库与另一个仓库的连接关系，不保证跨互联网，也不自动说明哪边权威。本书实验中的 bare 目录、公司自建 Git 服务和托管平台都可成为 remote；团队对主写入端、镜像和灾备的选择属于治理。

Remote 名 `origin` 只是本地别名。Clone 常默认使用它，但 Git 不把 origin 视为中央、可信或可写。URL 决定连接位置和传输方式，修改 URL 不搬运服务器数据，也不改已有对象。

## 六层状态必须分别记录

以本地 `main` 跟踪 `origin/main` 为例：

| 层 | 典型表示 | 回答的问题 |
| --- | --- | --- |
| 服务器 Git ref | 服务端 `refs/heads/main` | 服务器当前接收的 main OID 是什么 |
| 本次查询响应 | `ls-remote` 返回的 OID/ref | 该身份在该时点看到了什么 |
| 本地远程跟踪 ref | `refs/remotes/origin/main` | 最近一次成功更新后本地缓存什么 |
| 本地工作分支 | `refs/heads/main` | 当前仓库自己从哪里继续提交 |
| Upstream 配置 | `branch.main.remote/merge` | status/pull 默认比较和整合谁 |
| 平台控制面 | 默认分支、保护、评审、队列、审计 | 哪些更新获准、由谁执行、留下什么事件 |

`FETCH_HEAD` 是 fetch 命令写入的临时记录，可含多个 ref/OID 及 merge 标记。新 clone 不一定已有该文件；后续 fetch 会创建、覆盖或追加内容。它不是 remote-tracking ref，也不是服务器持续权威，脚本不能把旧文件或文件缺失当作当前远端快照。

平台默认分支与服务器 symbolic `HEAD` 通常相关，但不等于每个 clone 的 `refs/remotes/origin/HEAD` 已更新。平台还可能异步更新保护规则、评审目标和 UI 缓存。

## 服务器更新不会推送到本地缓存

假设 Bob clone 时三者都指向 A：

~~~text
server main      A
Bob origin/main  A
Bob main         A
~~~

Alice 推送 B 后：

~~~text
server main      B
Bob origin/main  A
Bob main         A
~~~

Bob 的磁盘没有后台连接。此时：

~~~bash
git rev-parse refs/remotes/origin/main
git rev-parse refs/heads/main
~~~

仍返回 A。网页显示 B 与本地 `origin/main` 显示 A 可以同时正确，因为观察时点与数据源不同。

`behind 0` 也只表示本地 main 相对当前缓存没有落后。没有 fetch 时间与 OID，ahead/behind 不能证明服务器一致。

## `ls-remote` 查询服务器，不刷新本地 refs

~~~bash
git ls-remote --symref origin HEAD refs/heads/main
~~~

命令向当前 URL 发起查询，成功时返回该身份可见的 symbolic HEAD 和 ref OID。它不把对象下载到本地对象库，不更新 `origin/main`、本地 `main`、index 或工作区，也不替平台写审计结论。

查询空输出可能表示匹配模式无结果、空仓库、权限隐藏或对端实现差异；非零可能来自 URL、网络、服务器身份、认证或授权。保存退出码和 stderr，不能把“没看到”直接写成“不存在”。

两次独立 `ls-remote` 不是同一事务。服务器可在两次查询之间变化；需要一致快照时尽量一次请求列出相关 refs，并记录响应时间和主体。即使一次响应，也不包含之后发生的更新。

## Fetch 更新对象和本地观察点

~~~bash
before_main="$(git rev-parse refs/heads/main)"
git fetch origin
after_tracking="$(git rev-parse refs/remotes/origin/main)"
after_main="$(git rev-parse refs/heads/main)"
test "$after_main" = "$before_main"
~~~

Fetch 通常完成三类写入：取得所需对象，按 fetch refspec 更新 remote-tracking refs，写 `FETCH_HEAD`。它不自动整合当前本地分支。

Fetch 成功后 Bob 的状态可能是：

~~~text
server main      B  （本次 fetch 响应中的观察）
Bob origin/main  B
Bob main         A
FETCH_HEAD       含 B 与来源描述
~~~

服务器可能在 fetch 完成后立即前进到 C，因此 `origin/main=B` 仍是带时点的缓存。需要发布或条件写入时重新取得服务器 old OID，并由服务端比较 expected-old。

## Pull 在 fetch 后继续本地整合

`git pull` 先执行 fetch，再根据配置/选项对当前分支执行 merge 或 rebase。即使整合阶段冲突或 `--ff-only` 拒绝，fetch 已经可能写入对象、remote-tracking refs 和 `FETCH_HEAD`。

排障时保存两阶段证据：

~~~bash
git rev-parse HEAD
git rev-parse '@{upstream}'
git show-ref --verify refs/remotes/origin/main
git rev-parse --git-path FETCH_HEAD
git status --short --branch
~~~

“Pull 失败，所以没有变化”通常不成立。第五章会把组合行为和恢复展开。

## Push 尝试更新服务器引用

~~~bash
git push origin refs/heads/topic:refs/heads/topic
~~~

Push 读取本地对象与源 ref，把对端缺少的对象发送到服务器，并请求更新目标 ref。服务端按当前 old OID、快进规则、认证授权、hooks 和平台策略接受或拒绝。

被拒绝时，本地 commit 和分支通常仍在；服务器也可能已经接收对象但没有更新 ref。客户端不能只看对象传输进度判断发布成功。成功后也要记录服务端返回与后续查询，平台审计和复制状态另行核对。

Push 不自动更新当前工作区。Remote-tracking ref 是否在 push 后被本地更新取决于 refspec、配置和实现路径，工作流不要靠这一副作用作为服务器证据；显式读取并在需要时 fetch。

## Upstream 是本地默认关系

~~~bash
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
git config --show-origin --get-regexp '^branch\.main\.(remote|merge)$'
~~~

常见值把本地 main 关联到 remote `origin` 的 `refs/heads/main`。Status 用对应 remote-tracking ref 计算 ahead/behind，pull 用它选择 fetch/整合目标，push 的默认行为还受 `push.default`、`remote.pushDefault` 等配置影响。

Upstream 不授予权限，不保证远端 ref 存在，也不会刷新缓存。修改 upstream 只写本地配置：

~~~bash
git branch --set-upstream-to=origin/main main
~~~

配置错误时不应通过 reset 本地历史让提示消失，先修正 remote/ref 映射。

## Remote symbolic HEAD 也有服务器与缓存

服务器 bare 仓库的 `HEAD` 可指向 `refs/heads/main`。Clone 会据此选择初始分支，并常创建本地 `refs/remotes/origin/HEAD` 指向 `origin/main`。

服务器默认分支改成 `stable` 后，本地缓存不会自动变化：

~~~bash
git ls-remote --symref origin HEAD
git symbolic-ref refs/remotes/origin/HEAD
git fetch origin
git remote set-head origin --auto
~~~

前两条可能显示不同状态。先 fetch 让目标 remote-tracking ref（例如 `origin/stable`）在本地存在，再由第四条查询并更新 `origin/HEAD`；否则 `set-head --auto` 可能因本地目标 ref 缺失而失败。这些命令不改变平台默认分支、保护规则、现有本地分支或 upstream。完整故障分流见[远程引用漂移](../part-13/07-remote-ref-drift-failures.md)。

## 认证、授权和提交身份彼此独立

| 层 | 例子 | 证明什么 |
| --- | --- | --- |
| 服务器身份 | SSH host key、TLS 证书链 | 客户端连接的 endpoint 身份 |
| 客户端认证 | SSH key、令牌、证书、会话 | 谁在尝试访问 |
| 仓库/ref 授权 | 读、写、强推、标签等权限 | 该主体可执行哪些动作 |
| Commit/tag 身份 | author、committer、签名 | 对象中记录和签名了什么 |
| 平台控制面 | 评审、检查、队列、审计 | 更新是否满足平台政策 |

修改 `user.name`/`user.email` 不会修复 push 认证。能 clone 不代表能写，签名有效也不自动授权合并或发布。传输与认证章会展开 SSH/HTTPS、凭据助手、代理和主机校验。

## 本地 bare 实验能证明什么

本书用本机 bare 仓库作为服务器数据面：

~~~bash
git init --bare server.git
git clone "file://$PWD/server.git" client
~~~

它可以真实验证对象传输、refs、symbolic HEAD、fetch/push 和非快进规则。它不能验证 SSH/TLS、真实身份、平台权限、隐藏 refs、保护规则、审计、计费、复制或故障域。实验输出必须标注 `file://`，不能冒充 GitHub/GitLab 行为。

## 按失败层选择证据

| 现象 | 优先层 | 先收集 |
| --- | --- | --- |
| URL 解析、DNS 或超时 | endpoint/网络 | 脱敏 URL、代理、时间和 stderr |
| host key/证书错误 | 服务器身份 | 可信指纹、证书链、端口与轮换公告 |
| authentication failed | 客户端认证 | helper/agent、凭据有效期和主体 |
| repository not found/403 | 路径、可见性或授权 | URL、账号角色、SSO 和平台事件 |
| fetch 后 main 没变 | 正常本地分层 | `origin/main`、main、`FETCH_HEAD` OID |
| push non-fast-forward | 服务端 ref 条件 | 远端 old、本地 new、merge base |
| pull 冲突 | fetch 后本地整合 | remote-tracking 更新、`MERGE_HEAD`/rebase 状态 |
| 网页与本地不同 | 时点、缓存或平台层 | 查询主体、时间、两侧 OID 和隐藏范围 |

不要用 `reset --hard` 修复连接，用换密钥处理 non-fast-forward，或用 force push 消除平台拒绝。先定位层次。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| `origin/main` 不存在 | remote、fetch refspec、默认分支和权限 | 查询/获取真实 ref，不创建假缓存 |
| `ls-remote` 与 `origin/main` 不同 | 两个时点、URL、主体和 ref | 需要时 fetch，并保留旧观察 |
| Fetch 成功但本地 main 落后 | 正常分层、工作区和整合政策 | 选择 ff/merge/rebase，不 reset 猜测 |
| Upstream 指向失效名称 | branch config、远端重命名和缓存 | 修正本地配置，不移动提交 |
| `FETCH_HEAD` 与期望不同 | 最近 fetch 命令、refspec 和并发进程 | 重新固定输入，不把文件当长期日志 |
| Push 拒绝但对象似乎已上传 | 服务端 ref、返回状态、审计 | 保留本地 commit，按拒绝原因处理 |
| 平台显示合并而 Git ref 不符 | candidate、最终 OID、平台事件 | 分开控制面与数据面调查 |

任何远程写入前固定本地 source OID、远端 expected-old、目标完整 ref 和恢复方案。平台或远端状态不确定时先使用只读查询，不向主线试推权限。

## 隔离实验

运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-remote-state-model.sh
~~~

实验创建 bare server、Alice 和 Bob。Alice 推送新 commit 后，脚本断言 Bob 的 `origin/main` 与 main 都仍是旧 OID；`ls-remote` 看到 server 新 OID，但不修改 Bob refs，也不创建 `FETCH_HEAD`。Fetch 随后更新 `origin/main` 和 `FETCH_HEAD`，仍不移动 Bob main；upstream 配置与 remote symbolic HEAD 单独验证。

实验使用本地 `file://` 和虚构身份，不读取真实凭据，也不模拟平台控制面。已有 `verify-part-4-remotes.sh` 继续覆盖 pull、push、upstream 和 tag 基础行为。

## 小结

服务器 ref、本次查询、本地 remote-tracking ref、本地分支、upstream 和平台控制面是六类状态。`ls-remote` 只查询，fetch 更新对象与本地观察点，pull 继续整合，push 请求服务端条件更新。每个结论都要带 URL、主体、时点和 OID，不能把 `origin/main` 当实时网络指针。

## 资料

- [gitremote-helpers](https://git-scm.com/docs/gitremote-helpers)
- [git-remote](https://git-scm.com/docs/git-remote)
- [git-ls-remote](https://git-scm.com/docs/git-ls-remote)
- [git-fetch](https://git-scm.com/docs/git-fetch)
- [git-pull](https://git-scm.com/docs/git-pull)
- [git-push](https://git-scm.com/docs/git-push)
- [gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)
