# push 为什么会被拒绝：先区分传输、认证和历史保护

push 被拒绝时，最重要的证据通常已经在本地保留。不要把所有错误都归为“权限问题”，也不要在不知道远端新状态时直接强推。先确定失败发生在 endpoint、身份、仓库授权、引用规则还是平台控制面。

## 进入条件与完成标准

本章使用两个从同一远程基线克隆的临时仓库。真实协作时，先保存：

~~~bash
git status --short --branch
git remote get-url origin
git rev-parse --verify HEAD^{commit}
git branch -vv
~~~

读完本章后，你应能：

- 还原非快进拒绝的提交图；
- 区分 endpoint、服务器身份、客户端认证、仓库授权和 ref 策略；
- 在拒绝后保留本地提交并获取新远程证据；
- 选择 merge、rebase、review ref 或放弃本次发布；
- 解释 force-with-lease 的保护条件和失效边界；
- 把本地 Git 拒绝与平台评审、检查和部署门禁分开。

## 非快进拒绝的因果链

Alice 和 Bob 都从远端 B 开始。Alice 先发布 C，Bob 在没有 fetch 的情况下基于 B 创建 D：

~~~text
      C 远程 main
     /
A <- B
     \
      D Bob 的 main
~~~

如果 Bob 执行：

~~~bash
git push origin main
~~~

接收端会拒绝 non-fast-forward。让远程 main 直接从 C 改为 D，会让 C 不再从 main 可达，等于覆盖已经公开的历史。拒绝不是网络故障，而是引用更新保护。

拒绝后本地提交 D 仍在：

~~~bash
git rev-parse HEAD
git show --no-patch --format='%H%n%P%n%s' HEAD
~~~

不要重新创建一个内容相同的提交，也不要删除本地仓库。

## 先 fetch，再比较两侧

~~~bash
git fetch origin
git rev-parse origin/main
git rev-parse main
git log --left-right --graph --oneline origin/main...main
git merge-base origin/main main
~~~

记录 fetch 之后的两个 OID。范围命令的左、右方向要写进报告：

~~~bash
git log --oneline main..origin/main
git log --oneline origin/main..main
~~~

第一条是远端缓存中本地 main 没有的提交，第二条是本地独有提交。若任一命令没有输出，要同时保存引用 OID 和范围，空输出可能表示确实没有独有提交，也可能表示 ref 尚未更新或可见范围受限。

## 三种正常处理方式

### 合并远端变化

站在当前本地分支：

~~~bash
git merge origin/main
git diff --staged --check
git push origin main
~~~

merge 保留 C 和 D，并创建新的合并提交（如果存在冲突，先按冲突流程完成）。最终 push 的前提是远端仍接受本地更新；合并期间其他人仍可能继续提交。

### 变基本地提交

如果 D 尚未被别人基于其工作，并且团队允许改写本地功能历史：

~~~bash
git rebase origin/main
git diff origin/main...HEAD
git push origin main
~~~

D 会被重建为 D'，其 OID 改变。已公开并被协作者使用的提交不能无协调变基。变基冲突、abort 和强制更新见后续章节。

### 使用专用 review ref

如果主线受保护或当前不应直接更新：

~~~bash
git push origin HEAD:refs/heads/review/search-fix
~~~

这仍需要远端授权和接收规则，但不会请求更新 main。平台是否把该 ref 连接到评审、CI 或合并队列，是控制面事实，不能由 Git 命令证明。

## 认证和授权错误不是同一个问题

| 现象 | 常见层级 | 首要证据 |
| --- | --- | --- |
| could not resolve host/timeout | endpoint 和网络 | remote URL、代理、DNS、原始 stderr |
| host key/证书错误 | 服务器身份或 TLS | known_hosts、证书链、时间和代理 |
| authentication failed | 客户端凭据 | SSH agent、credential helper、令牌有效期 |
| repository not found | URL、可见性或仓库授权 | 脱敏 URL、主体和仓库存在性 |
| permission denied | 仓库/ref 授权 | 目标 ref、认证主体、服务端策略 |
| non-fast-forward | 远端 ref 历史保护 | old/new OID、merge-base |
| protected branch/policy rejected | 平台控制面 | 保护规则、评审、检查和例外 |
| pre-receive rejected | 接收端 hook 或策略 | hook stderr、候选 OID 和规则版本 |

本地 user.name、commit 签名或 clone 成功都不能替代 push 授权。错误报告不要附带令牌、Authorization header 或私钥。

## fetch 后远端又变化的竞态

fetch 到 push 之间不是服务器事务。另一位协作者可能把远端从 C 更新到 E，你基于 C 整合并准备推送 F。普通 push 会再次检查远端旧值，可能拒绝；这是预期保护。

发布前保存：

~~~bash
remote_before="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
local_candidate="$(git rev-parse HEAD)"
printf 'remote_before=%s local_candidate=%s\n' "$remote_before" "$local_candidate"
~~~

ls-remote 只证明这次查询看到的 ref，不能冻结后续变化。需要条件更新时使用服务端或 Git 支持的租约机制，并在拒绝后重新取证。

## 为什么不要默认 force

git push --force 请求无条件更新远端 ref，可能删除其他人的新提交。即使目标是个人分支，也应确认：

- 分支确实允许改写；
- 协作者和自动化没有依赖旧 OID；
- 已保存旧远端 OID、候选 OID 和恢复来源；
- 平台保护和审计允许本次动作；
- 发布、评审、CI 和部署记录能关联新旧对象。

force-with-lease 只是一层 expected-old 条件，不是授权、备份或绝对并发锁。远端可见范围、后台 fetch、多个 worktree 和显式 lease 配置都会影响它的安全边界。

## 原子推送和多引用发布

一次发布可能同时更新分支和标签。若两个更新必须一起成功：

~~~bash
git push --atomic origin main refs/tags/v1.0.0
~~~

远端不支持 atomic 或其中一个 ref 被拒绝时，整批应保持未更新。服务端是否实现原子性、哪些 refs 允许更新，需要按目标平台验证。不要把“命令没有报错”当作平台制品和部署已经完成。

## 拒绝后的恢复清单

1. 保存原始 stderr、命令、时间和执行目录；
2. 保存本地 HEAD、目标 ref、上游和工作区状态；
3. 用 fetch 或受控远端查询获取新 OID；
4. 判断失败层级和共享边界；
5. 先建立恢复引用或保存 bundle，再选择 merge、rebase、review ref 或停止；
6. 发布后核对远端 ref 和外部评审/CI/部署证据。

命令失败通常不需要回滚本地提交。只有当你明确要放弃某个本地候选时，才进入 restore、reset 或历史恢复决策。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-history.sh
~~~

实验在本地 bare server 中制造 Alice/Bob 非快进拒绝，验证 fetch 后两侧各有独有提交，rebase 会生成新 OID，随后 push 可以更新远端；它还验证维护分支上的 cherry-pick 会生成独立提交。实验不模拟真实 SSH/TLS、平台授权、分支保护、评审、CI、合并队列或审计。

## 小结

push 拒绝首先是证据问题。先分清传输、认证、授权和引用历史，再保存 old/new OID 和共同祖先。非快进用 fetch 后的 merge 或 rebase 处理，共享历史改写需要显式租约和团队授权；平台门禁和运行证据另行核对。
