# Push 拒绝、原子更新与 options：服务端接受条件要逐层证明

Push 失败可能发生在连接、服务器身份、客户端认证、仓库授权、对象接收、引用规则、hook 或平台控制面。Non-fast-forward 只是其中一类。错误处理的第一步是保存 source/destination、远端 old、本地 new、主体和原始响应，不是换密钥、pull 或强推碰运气。

本章同时处理多 ref 原子更新和 push options。`--atomic` 只有服务端支持时才让目标 refs 全成或全败；push option 只是客户端传给 receive-pack/hook 的字符串，不自带权限、可信身份或平台统一语义。

## 进入条件与完成标准

在专用测试仓库执行写入。先记录：

~~~bash
git remote get-url --push --all origin
git rev-parse 'HEAD^{commit}'
git ls-remote origin refs/heads/main refs/tags/v2.0.0
git config --show-origin --get push.default
~~~

读完本章后，应能按失败层分流 non-fast-forward、认证/授权、hook/保护规则，使用显式 `--force-with-lease=<ref>:<oid>`，解释 atomic 的边界，验证 push options 的服务端能力与审计，并在部分/全部拒绝后保留本地候选。

## 拒绝层级不能靠一句 stderr 猜测

| 层 | 常见线索 | 需要的证据 |
| --- | --- | --- |
| Endpoint/网络 | DNS、超时、连接失败 | URL、代理、时间、网络路径 |
| 服务器身份 | host key、TLS 证书错误 | 可信指纹/CA、主机名和端口 |
| 客户端认证 | publickey、401 | 实际 key/token/helper 与有效期 |
| 仓库授权 | 403、not found | 主体、仓库角色、SSO/策略 |
| 引用规则 | non-fast-forward、删除拒绝 | old/new OID、祖先关系 |
| Hook/平台策略 | hook declined、protected | 规则版本、候选、审批/检查和审计 |

平台可能为防泄露而用同样文案表示不存在与无权限。保留 HTTP/SSH 层和平台事件，不把字符串匹配当根因。

## Non-fast-forward 保护远端独有历史

远端 main 已从 A 到 B，本地从 A 到 C：

~~~text
      B  remote main
     /
A <-
     \
      C  local main
~~~

普通 push C 到 main 会拒绝，因为 B 不是 C 的祖先。失败后本地 C 仍在，远端 B 不动：

~~~bash
git fetch origin
git rev-list --left-right --count HEAD...origin/main
git merge-base HEAD origin/main
~~~

选择 merge、在私有历史 rebase、创建 review ref，或停止协调。不要用 `--force` 消除提示；它会请求删除 B 的可达入口。

## 显式租约固定 expected-old

确有授权改写个人分支时：

~~~bash
expected_old="<经过查询和协调的完整远端 OID>"
git push \
  --force-with-lease=refs/heads/topic:"$expected_old" \
  origin HEAD:refs/heads/topic
~~~

服务端当前值不等于 expected-old 时拒绝。显式形式比仅依赖 `origin/topic` 缓存更可审计，也不受后台 fetch 悄悄刷新缓存后改变默认租约基准。

租约只提供比较前置条件，不证明改写获授权、旧历史有备份、评审/签名可转移或平台允许。操作前建立 recovery ref，记录协作者、外部引用、CI/发布坐标和恢复方案。完整流程见[显式强制租约](../part-07/10-explicit-force-lease.md)。

## `--force-if-includes` 不能替代协调

部分 Git 版本支持 `--force-if-includes`，要求远端更新已被本地 reflog 可达历史包含，用于加强基于 tracking ref 的租约判断。它依赖本地 reflog 和具体调用组合，不是授权或跨 clone 锁。

自动化优先显式 `<ref>:<expected-old>`。若采用该选项，记录 Git 版本、tracking/ref reflog、命令组合和拒绝行为，并在后台 fetch、多 worktree 场景实测。

## `--atomic` 让多 ref 全成或全败

发布可能需要同时更新分支与标签：

~~~bash
git push --atomic origin \
  refs/heads/release:refs/heads/release \
  refs/tags/v2.0.0:refs/tags/v2.0.0
~~~

服务端支持 atomic 时，任一目标因权限、非快进、hook 或同名冲突拒绝，所有目标 refs 保持原值。服务端不支持时整个 atomic 请求失败，客户端不能降级为非原子继续。

Atomic 只覆盖同一次 receive-pack 的 Git refs。对象可能已经传输，平台审计、release、LFS、制品、数据库和部署不在事务内。跨仓库推送也不是一个原子组。

成功/失败后查询每个完整 ref，并与操作前 manifest 比较。只看总体退出 0/1 不足以证明目标集合。

## Push options 是不透明字符串

客户端可传：

~~~bash
git push -o ci.skip=false -o change-ticket=INC-42 \
  origin HEAD:refs/heads/review/topic
~~~

服务端必须宣告支持 push options，否则请求失败。Receive hooks 通过 `GIT_PUSH_OPTION_COUNT` 和 `GIT_PUSH_OPTION_<n>` 读取；Git 本身不解释这些字符串的业务语义。

托管平台可能把某些 option 映射到 CI、评审或合并请求行为，名称与权限会变化，必须按产品、版本、套餐和核对日期登记。不要把 ticket、身份或审批只放在未经验证的 option 中，也不要传 secret；options 可能进入 hook 日志和审计。

服务端应校验允许名称、长度、编码、重复项、主体权限和目标 ref。未知 option 是拒绝还是忽略要明确定义，不能由各 hook 随意解释。

## Hook 拒绝要保留候选和服务端上下文

`pre-receive` 可以观察本次所有 old/new/ref，任一失败会拒绝整批 receive；`update` 可逐 ref 决定；`post-receive` 在 refs 已更新后运行，不能用其失败回滚已接受更新。平台还可能有独立策略层。

本地测试 hook 的成功不证明平台执行同样入口。真实验收需要覆盖命令行、API、管理员、机器人、合并队列、标签、删除和 LFS/制品入口，并关联审计事件。

拒绝后保存本地 candidate、server old、hook stderr、规则版本和 actor。不要修改 commit author 或换传输协议试图绕过授权。

## 部分成功与客户端缓存

非 atomic 多 ref push 可能一部分 ref 成功、一部分失败。客户端必须逐项读取 porcelain 输出或重新查询服务器，不能因退出非零就假定全部未更新。

使用机器格式：

~~~bash
git push --porcelain origin \
  refs/heads/a:refs/heads/a \
  refs/heads/b:refs/heads/b
~~~

保存原始输出和最终 `ls-remote`。本地 remote-tracking refs 可能按成功项更新，失败项保持旧值；pushURL 与 fetch URL 分离时更不能把缓存当写目标证据。

## 失败恢复清单

1. 保存命令、时间、cwd、Git 版本和脱敏 URL；
2. 固定每个 source OID、destination ref、expected-old；
3. 保存 stdout/stderr、服务端/platform request ID；
4. 查询每个远端 ref，区分全部拒绝、部分成功和查询失败；
5. 保留本地候选与 recovery ref；
6. 按连接、认证、授权、历史或策略层修复；
7. 重新生成候选/审批/检查，不能转借旧结果；
8. 发布后核对审计、制品和运行状态。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| Non-fast-forward | 远端 old、本地 new、merge base | Fetch 后整合或授权租约，不默认 force |
| 显式租约拒绝 | 服务端 current、expected-old、协作者 | 重新协调和生成候选，不刷新后盲推 |
| Atomic 不支持 | capability/错误和所有目标旧值 | 保持失败，不拆成多次写 |
| Atomic 中一项被 hook 拒绝 | 每个 ref old/new、hook 日志 | 修正整组候选，确认所有 ref 未变 |
| Push option 不支持 | 服务端 capability、Git 版本 | 去掉非必要 option 或升级受控服务，不伪造效果 |
| Option 被忽略 | hook/platform 原始事件 | 视为未执行，不能宣称 CI/评审动作发生 |
| 非 atomic 部分成功 | porcelain 输出和逐 ref 查询 | 先围栏成功项，再按清单恢复 |
| Post-receive 报错 | refs 实际值、hook 日志和下游事件 | 不重复 push，修复下游并幂等重放 |

## 隔离实验

运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-push-ref-updates.sh
~~~

实验先验证普通 ref 更新、dry-run、upstream、删除与 tag 拒绝。随后启用本地 receive-pack push options，由 pre-receive hook 记录两个 option；update hook 拒绝指定 ref。Atomic push 中一项被拒绝时，两个目标 ref 都保持旧值；非 atomic 请求则出现一项成功、一项拒绝，并逐 ref 核对。

显式租约由 `verify-force-with-lease.sh` 继续覆盖。实验只验证本地 Git 服务端，不模拟 GitHub/GitLab 的 option、平台保护、审计、复制或 CI。

## 小结

Push 拒绝必须定位到连接、认证、授权、引用或策略层。显式租约固定 expected-old，atomic 只约束同一服务端 refs，push options 只是需校验的字符串。失败后逐 ref 查询实际结果并保留本地候选，不能用强推或重复请求掩盖未知状态。

## 资料

- [git-push](https://git-scm.com/docs/git-push)
- [git-receive-pack](https://git-scm.com/docs/git-receive-pack)
- [githooks](https://git-scm.com/docs/githooks)
- [git-config](https://git-scm.com/docs/git-config)
