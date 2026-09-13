# Push 与远端引用更新：发布的是对象和 ref 请求

`git push` 读取本地 source ref 或 OID，把对端缺少的对象发送到远端，然后请求把 destination ref 从当前值更新到新值。成功的关键证据是远端目标 ref 的 old/new OID，不是“文件上传完了”或本地工作区干净。

Push 不执行远端 checkout，也不自动创建评审、发布制品或部署。托管平台可以在 Git 引用更新之外增加认证、权限、分支保护、检查、队列和审计控制。

## 进入条件与完成标准

真实写入前固定本地候选、目标和远端观察：

~~~bash
git status --short --branch
source_oid="$(git rev-parse 'HEAD^{commit}')"
git remote get-url --push --all origin
git config --show-origin --get-all remote.origin.push
git config --show-origin --get push.default
git ls-remote origin refs/heads/topic
~~~

URL 和输出可能含内部信息，保存到受控位置。`ls-remote` 只能证明当前身份在该时点看到什么。所有写入示例在专用测试 ref 或本书临时 bare 仓库执行。

读完本章后，应能解释 push 的 source/destination、对象传输与 ref 更新，选择显式 refspec，区分 upstream、pushRemote 和 remote-tracking ref，安全创建/更新/删除分支与标签，并在成功或拒绝后核对本地和远端状态。

## 显式 refspec 消除目标猜测

~~~bash
git push origin \
  refs/heads/topic:refs/heads/topic
~~~

冒号左侧是本地 source，右侧是远端 destination。Source 可以是本地分支、标签或明确 OID；destination 应使用完整 namespace。命令不会切换本地分支，也不会修改工作区。

省略 destination、使用短名或无参数 push 时，Git 会结合 upstream、`push.default`、`remote.pushDefault`、`branch.<name>.pushRemote` 和 remote 配置推断目标。不同机器配置可能产生不同结果，发布自动化使用完整 refspec 并记录实际 argv。

## 新建与快进更新

远端 ref 不存在时，普通 push 可以创建它：

~~~bash
git push origin HEAD:refs/heads/review/topic
~~~

远端已存在时，heads 默认要求 old OID 是 new OID 的祖先。快进请求成立后，服务器把 ref 移到新 commit。Tag 更新规则更严格，普通 push 通常拒绝覆盖已有 tag。

成功后核对：

~~~bash
local_oid="$(git rev-parse HEAD)"
remote_oid="$(git ls-remote origin refs/heads/review/topic | awk '{print $1}')"
test "$local_oid" = "$remote_oid"
~~~

两次查询之间仍可能有并发更新。高风险流程保存服务器返回、审计事件和后续固定快照，不把客户端查询当原子证明。

## 对象接收和引用接受是两个阶段

服务端可能先接收 pack，再因 non-fast-forward、hook、权限或平台规则拒绝 ref。对象可能暂时存在于服务端却不可达，客户端不能用传输字节数证明发布成功。

Push 返回成功也只证明 Git 接收路径接受了请求。服务器复制、平台缓存、CI、LFS、制品和部署可能仍未完成。发布证据链继续记录 candidate、ref event、artifact digest 和运行实例。

## `-u` 同时写本地 upstream

~~~bash
git push --set-upstream origin \
  refs/heads/topic:refs/heads/topic
~~~

成功后 Git 通常写 `branch.topic.remote=origin` 与 `branch.topic.merge=refs/heads/topic`，供 status/pull 等使用。Upstream 是本地配置，不授予远端权限，也不证明服务器 ref 永久存在。

核对：

~~~bash
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
git config --get-regexp '^branch\.topic\.(remote|merge)$'
~~~

`pushRemote` 只影响推送目标，upstream 仍可指向另一个只读上游。多远程流程要分别记录 fetch source、push destination 和评审目标。

## Push 后的 remote-tracking ref 不是服务器审计

当 destination 与配置的 fetch refspec 对应时，成功 push 后 Git 可能更新相应 remote-tracking ref。工作流仍应显式核对：

~~~bash
git rev-parse refs/remotes/origin/topic
git ls-remote origin refs/heads/topic
~~~

本地 tracking ref 是缓存，不是远端实时指针。自定义 pushURL 指向另一个仓库时，`origin/topic` 的 fetch 来源甚至可能与 push 目标不同；不能把两者 OID 相等作为固定假设。

## 删除远端 ref 是显式写操作

~~~bash
git push origin :refs/heads/review/topic
~~~

空 source 请求删除 destination。它不删除本地分支、对象、其他 clone、评审、制品或部署。删除可能被权限/保护规则拒绝。

执行前记录远端 OID、owner、评审/发布依赖和恢复来源。优先使用 `--delete` 或完整空 source，让意图清晰；不要把删除混入未经审查的批量 refspec。

## Dry-run 不会证明真实写入一定成功

~~~bash
git push --dry-run origin \
  refs/heads/topic:refs/heads/review/topic
~~~

Dry-run 用当前连接与状态预测更新，不应移动远端 ref。正式 push 前远端仍可能变化，某些 hook/平台行为也只在真实写入时发生。它是预检证据，不是审批或锁。

## 标签与分支必须区分 namespace

~~~bash
git push origin refs/tags/v2.0.0:refs/tags/v2.0.0
~~~

正式标签同时核对 tag object 与 peeled commit。`--tags` 会扩大到所有缺失标签，`--follow-tags` 也有特定选择规则；发布清单显式列出目标。

分支/tag 同短名时，`git push origin release` 可能歧义。始终使用完整 refname，避免把分支误发成标签或反之。

## 推送成功后的验收

至少记录：

~~~text
remote_name / push_url / authenticated_principal
source_ref / source_oid / source_tree
destination_ref / expected_old / observed_new
push_options / atomic_mode / server_response
platform_policy_and_audit_event
candidate_checks / artifact_and_release_state
~~~

本地 Git 无法填充平台字段时标记为未验证。不要用合成值伪造审批或审计成功。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| Everything up-to-date 与预期不符 | source/destination OID、push.default | 修正目标，不造空 commit |
| 新分支推到错误 remote | pushURL、pushRemote、服务端 refs | 停止写入，评估并删除/更正专用 ref |
| Non-fast-forward | 远端 old、本地 new、merge base | Fetch 后整合或协调改写，不直接 force |
| Tag 已存在 | tag object、peeled target、发布记录 | 新版本或审批撤销，不覆盖 |
| Hook/protected ref 拒绝 | 原始 stderr、主体、规则和候选 | 走评审/例外流程，不改作者邮箱 |
| Push 成功但平台无发布 | ref event、平台控制面、制品 | 分层补证，不重复 push 主线 |
| 删除后仍有消费者 | 镜像、clone、评审、制品和部署 | 通知并逐层处置，Git 删除不是全局撤回 |

失败通常不需要回滚本地 commit。保留候选和错误，根据失败层修复。

## 隔离实验

运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-push-ref-updates.sh
~~~

实验验证显式 refspec 创建/快进/删除远端分支，`--set-upstream` 写本地配置，dry-run 不更新远端，普通 tag push 与同名覆盖拒绝。第二部分由下一章验证 atomic、push options 和租约。

实验使用 `file://` bare 仓库，不模拟真实认证、平台保护、复制、LFS、CI 或部署。

## 小结

Push 发送对象并请求更新远端 ref，source/destination、old/new OID 和服务端接受结果才是数据面证据。Upstream、pushRemote 与 remote-tracking ref 都是本地状态；删除、标签和 dry-run 也有独立边界。平台审批、制品和运行状态需要继续补证。

## 资料

- [git-push](https://git-scm.com/docs/git-push)
- [git-config](https://git-scm.com/docs/git-config)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
