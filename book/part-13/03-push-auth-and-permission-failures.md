# push 被拒绝并不都是权限：传输、认证、授权与引用策略

一次 git push 失败，可能发生在连接远端之前，也可能已经通过认证却被仓库策略拒绝。把所有错误都归结为“权限不够”，常见后果是扩大令牌权限、关闭主机校验，或者用 --force 覆盖别人已经发布的历史。

本章把一次写入请求拆成可观察的层：远端 URL 与传输、服务器身份、客户端认证、仓库授权、对象/引用更新规则，以及托管平台的评审和策略控制面。排障先确定请求到达了哪一层，再选择不会扩大影响的下一步。传输和认证的完整机制见《远程 URL、传输协议与认证边界》，非快进整合见《推送为什么会被拒绝》，保护规则见《受保护分支》。

本章以 Git 2.49.0 和本地 bare 仓库实验为基线。SSH 主机密钥、HTTPS TLS、令牌、SSO、平台权限、评审检查和服务端审计必须在获批目标环境核对；本地 hook 只能证明接收端拒绝某个 ref 更新，不能冒充任何托管平台。

## 先把“写入失败”分成六层

| 层 | 要回答的问题 | 典型证据 | 不应据此推出 |
| --- | --- | --- | --- |
| URL/传输 | 客户端是否能连接到声明的 endpoint | remote get-url、DNS/TLS/SSH 原始 stderr、连接退出码 | 仓库存在或账号有写权限 |
| 服务器身份 | 对方是否是预期主机/证书/SSH host key | 受控 known_hosts、证书链、轮换记录 | 当前用户已被授权 |
| 客户端认证 | 服务端把请求识别成谁 | SSH 实际用户/key、HTTPS credential context、平台登录审计 | 这个主体能写目标 ref |
| 仓库授权 | 该主体能否读取/更新这个仓库和动作 | 服务端授权结果、角色/令牌 scope、SSO 状态 | 更新一定满足历史和规则 |
| Git 引用规则 | new OID 是否允许替换 old OID | old/new OID、祖先关系、receive hook、ref namespace | 平台评审/CI 已通过 |
| 平台控制面 | 评审、检查、规则、配额或策略是否允许发布 | 平台事件、规则版本、检查绑定提交、审计记录 | 本地 bare hook 的结果就是平台结果 |

错误文案可能隐藏仓库存在性，或把多层失败合并成一个状态码。结论要写成“在某时间、某 endpoint、某身份上下文、某动作上观察到 X”，不要写成“用户没有权限”这种未分层归因。

## 第一轮只做不会写远端的确认

在发生 push 的同一个客户端 worktree 中，先保存第十三篇第一章的最小排障证据集，再执行：

    git --version
    git status --short --branch
    git remote get-url --all origin
    git branch -vv
    git rev-parse HEAD
    git rev-parse --verify refs/remotes/origin/main

示例假定远程名是 origin；先用 git remote 确认名称。上述命令读取本地配置、HEAD 和远程跟踪引用，不连接服务器，也不改变 refs。remote get-url 可能输出嵌入 userinfo 的 URL，原件必须限制访问；分享时只保留 scheme、主机类别和是否包含 userinfo 等必要信息。

origin/main 是上一次 fetch 保存的本地值，缺失可能代表尚未 fetch、refspec 没映射、空仓库或本地配置异常，不代表服务器没有 main。解析 HEAD 失败可能是未出生分支或当前仓库错误；保存退出码和 stderr，不要为了得到一个 OID 而先提交空文件。

### 只读探测远端 ref

初始本地快照固定后，在已获网络授权的终端运行：

    git ls-remote --exit-code origin refs/heads/main

它连接远端并使用当前认证上下文，但不会更新本地 refs 或 FETCH_HEAD。成功通常输出服务器向本次会话公开的 <OID><TAB>refs/heads/main；退出 2 表示没有匹配 ref，其他非零要结合 stderr 区分 URL、DNS/TLS/SSH、认证和服务端错误。

无匹配只证明当前 endpoint、主体、权限和时刻下没有可见的匹配项。平台可能隐藏仓库存在性，或者 main 实际是另一个默认分支。不要因为 ls-remote 无输出就创建同名远端分支或修改本地历史。

## 先处理传输和服务器身份，再谈账号权限

| 线索 | 优先验证 | 安全恢复 |
| --- | --- | --- |
| 无法解析主机、连接超时、代理失败 | URL 主机、VPN/DNS、代理、服务状态 | 修复连接后重试同一只读探针；不改提交图 |
| SSH Host key verification failed 或指纹变化 | 端口、受控 known_hosts、可信轮换公告 | 停止写入，核对指纹；不删除全部 known_hosts、不关闭校验 |
| TLS 证书链/主机名错误 | 系统时间、URL、企业 CA、代理终止 | 修复 CA/endpoint；不设置 sslVerify=false |
| SSH Permission denied (publickey) | 实际 SSH 用户、agent、选用 key、服务端登记 | 用最小测试身份验证；不修改 user.name 解决登录 |
| HTTP 401/反复提示登录 | credential helper 的 host/path/context、令牌有效期和登录方式 | 在受控环境轮换/清理旧凭据；不把 token 写入 URL |
| HTTP 403 或 repository not found | 仓库路径、主体授权、SSO/组织策略和隐藏存在性 | 让仓库 owner/管理员核对；不盲目扩大令牌 scope |

原始 stderr 只是线索，不是跨产品稳定协议。详细 SSH/libcurl trace 可能含 URL、代理、用户名、引用甚至 header；只在受控终端按最小范围采集，分享前生成脱敏副本。若怀疑凭据泄漏，先按第十篇的凭据泄漏流程撤销秘密。

## 认证成功仍可能没有写权限

认证回答“你是谁”，授权回答“这个主体能否对这个资源执行这个动作”。同一个身份可能有 clone 权限但没有 push 权限；令牌可能允许读取一个仓库但不能写受保护 ref；机器人可能能写发布 tag，却不能更新 refs/heads/main。

在目标平台可见的前提下，分别记录：

- principal 的稳定 ID、委托链和登录/令牌来源；
- 仓库 locator、稳定资产 ID、组织/项目范围和数据分类；
- 动作是读取、创建 ref、非快进更新、删除、创建 tag、合并还是发布；
- 目标完整 ref、old OID、new OID 和是否已经有评审/检查上下文；
- 令牌/key/app 的 scope、到期、SSO/组织授权和最近轮换；
- 服务端返回的授权决定、规则版本和审计事件。

客户端不能通过自设环境变量“证明”自己是谁。GIT_AUTHOR_NAME、user.name 和提交中的 author/committer 只影响对象元数据，不提供远程认证。不要把修改提交身份、换 SSH key、删除 .git/config 当成授权修复。

## 非快进拒绝：远端有你必须保留的历史

当远端 old 不是本地待推送 new 的祖先时，普通 push 不应把 old 移到 new。在拿到远端当前 OID 后，先记录本地状态，再比较：

    git fetch origin
    git log --left-right --graph --oneline refs/remotes/origin/main...HEAD
    git merge-base --is-ancestor refs/remotes/origin/main HEAD

这里的 fetch 是有副作用的诊断动作：它会写对象、远程跟踪 ref 和 FETCH_HEAD，所以必须保存 fetch 前快照。若 merge-base 返回 0，当前 HEAD 至少包含 fetch 后的远端 tip，可按团队规则普通推送；返回 1 表示存在分叉，不能把它解释成认证失败。

### 选择 merge、rebase 或停止

| 条件 | 动作 | 风险边界 |
| --- | --- | --- |
| 分支已共享，需保留两条历史 | merge 远端 tip，解决冲突，测试后 push | 产生合并提交；评审/CI 需覆盖新 tip |
| 本地提交未共享，团队允许整理 | 在确认工作区与恢复点后 rebase 到远端 tip | 本地提交 OID 改变；不得覆盖协作者工作 |
| 无法判断谁依赖哪条历史 | 停止并让 owner 协调 | 不用 --force“试试看” |

普通 git pull 可能把 fetch 与 merge/rebase 组合成一次动作，失败时状态更难分辨。排障记录优先拆开执行。merge/rebase 过程中若进入冲突，转到对应 abort/resolve 流程；不要在未固定冲突现场时连续 pull。

### 显式租约不是权限提升

个人分支确实需要改写时，--force-with-lease 可以要求远端仍等于你保存的预期 OID。它只提供并发条件，不绕过平台保护、授权或审计：

    expected_remote='FULL-OID-SAVED-BEFORE-REWRITE'
    git push --force-with-lease=refs/heads/topic:"$expected_remote" origin HEAD:refs/heads/topic

成功会更新服务器 topic，失败不会接受该 ref 更新；失败时重新获取并比较新旧 OID，不要改成无条件 --force。完整租约竞态见第五篇对应章节。

## 保护规则/接收 hook 拒绝：请求已到达写入层

如果错误来自 pre-receive、update、protected branch、required checks、审批或规则集，说明请求至少已经进入服务端接收/控制面；换 key 或重试不会自动解决。

先保存目标完整 ref、old/new OID、push options、发起主体、代理/机器人委托、规则版本、被拒 rule ID、缺少的审批/检查、检查绑定的候选提交、服务端原子性结果、审计事件和客户端退出码。

平台规则可能要求通过合并请求而非直接 push；本地 bare 仓库中的 hook 只能做一个有限的接收端拒绝示例。不要把“本地 hook 允许”写成“平台主线可直接写入”。

## 远端 URL 配错：改的是本地配置，不是历史

如果只读探针失败且 endpoint 明显错误，先记录旧 URL 的受限原件，再在当前客户端仓库修改：

    remote_name=origin
    new_url='ssh://git@host.example/team/repository.git'
    old_url="$(git remote get-url "$remote_name")"
    git remote set-url "$remote_name" "$new_url"
    git remote get-url --all "$remote_name"
    git ls-remote "$remote_name"

remote set-url 只写本地 .git/config，不移动对象、refs、index 或工作区。成功的 ls-remote 只证明读取路径可用，不证明能 push；失败时可恢复旧配置。若 URL 含 token、密码或内部路径，命令历史、配置备份、日志和错误报告都可能留下副本。优先使用 credential helper/短期凭据，不把秘密嵌入 URL；已暴露的秘密先撤销。

## 接受 push 不等于发布链完成

客户端看到目标 ref 更新成功，只证明一次 Git 引用更新被接收。还要分别核对源码 OID、流水线实际 checkout、制品 digest、部署记录和运行版本。CI 绿色只证明某个候选提交或合并结果通过检查；平台显示可合并也可能在排队期间过期。

## 常见失败与恢复

| 症状 | 常见误判 | 安全动作 |
| --- | --- | --- |
| non-fast-forward | 登录失败或远端坏了 | 保存 fetch 前后 OID，比较分叉，merge/rebase 后再推 |
| Permission denied (publickey) | Git author 身份错 | 核对 SSH 用户、agent、key 和服务端登记，不改 user.name |
| HTTP 401 | 仓库被删除 | 核对 credential context、令牌状态和 endpoint；不要把 token 写进 URL |
| HTTP 403/repository not found | 一定是路径错误 | 让 owner/平台审计核对授权和隐藏存在性，不盲目扩大 scope |
| protected branch/hook declined | 换 key 或强推能绕过 | 查规则、评审、检查和例外流程；不把本地 hook 当平台规则 |
| fetch 后本地分支没移动 | fetch 失败 | fetch 只更新对象/远程跟踪 ref，不自动整合当前分支 |
| --force-with-lease 被拒 | 租约参数无效或权限不够 | 保留当前远端 OID，重新协调租约；不退回 --force |
| push exit 0 但发布失败 | Git 已完成所以系统恢复 | 按 OID、制品、部署、数据库和运行状态继续验收 |
| 认证探针在 CI 卡住 | 运行器等待交互输入 | 使用 GIT_TERMINAL_PROMPT=0 让缺凭据明确失败，修复机器身份 |

## 隔离实验：把 ref 拒绝和 endpoint 失败分开

本书提供 scripts/verify-push-auth-permission-boundaries.sh。在仓库根目录执行：

    bash scripts/verify-push-auth-permission-boundaries.sh

脚本在 mktemp 中使用虚构身份和本地 bare 仓库，验证：

1. 客户端可通过 file:// 只读探测目标 ref，endpoint 错误时命令失败且远端 refs 不变；
2. 两个客户端从同一 OID 分叉，陈旧客户端普通 push 被非快进拒绝，远端 ref 保持不变；
3. fetch 会更新远程跟踪 ref/FETCH_HEAD，但不会移动客户端当前分支；
4. 受保护 main 的本地 pre-receive hook 拒绝直接 push，专用 review/* ref 仍可更新；
5. hook 拒绝时客户端保留本地 commit，修复为 review ref 后能安全发布；
6. push 成功后以 ls-remote 核对 new OID，并明确平台评审/CI 不在本地实验范围；
7. remote URL set-url 只改变本地配置，恢复旧 URL 后对象、refs、index 和工作区摘要不变。

实验不会模拟 SSH 主机校验、HTTPS TLS、真实凭据、SSO、平台规则集、评审、CI、配额或审计；本地 hook 不是 GitHub/GitLab 行为。认证/授权能力必须在专用测试组织按产品版本、权限、套餐和核对日期验证。

## 小结

push 失败先问“请求到达哪一层”：连接、服务器身份、客户端认证、仓库授权、Git 引用规则还是平台控制面。non-fast-forward 是历史保护，不能用换凭据解决；认证成功也不代表能写受保护 ref；本地 hook 通过也不代表托管平台会接受。

修复流程始终保留初始 refs/OID 和原始错误，把 fetch、URL 修改、merge/rebase、租约推送分别记录并验证。push exit 0 只证明一次 ref 更新，不证明评审、CI、制品和部署链已完成。

## 资料

- git-push
- git-fetch
- git-ls-remote
- git-remote
- git-receive-pack
- githooks
- gitcredentials
