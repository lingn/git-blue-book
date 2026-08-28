# 发布本地提交：push、上游与引用更新

本地提交只存在于当前仓库。push 是向远端发送对象并请求更新远端引用的动作。它不是“把文件上传”这么简单：服务器会基于旧值、祖先关系、认证主体、仓库权限和接收规则决定是否接受引用更新。

## 进入条件与完成标准

在准备发布的本地分支根目录执行。发布前必须有可解释的候选提交、干净或明确的工作区，并确认远程和目标 ref：

~~~bash
git status --short --branch
git remote get-url origin
git rev-parse --verify HEAD^{commit}
git branch -vv
~~~

不要把命令中的 origin、main 或 feature/search 当作永久正确值。先读取当前仓库配置和目标分支。

读完本章后，你应能：

- 解释 push 先传对象、再请求远端 ref 更新；
- 用明确 refspec 发布分支、标签和 review ref；
- 通过 upstream 简化重复操作，但不把它当作权限；
- 处理新分支、无上游、非快进、认证和保护规则拒绝；
- 区分本地提交成功、远端 ref 更新成功与平台评审/CI/部署成功；
- 在需要改写历史时把风险交给显式租约章节，而不是默认强推。

## 一个普通 push 会改变什么

执行：

~~~bash
git push origin main
~~~

Git 通常经历：

1. 读取本地 main 的候选 OID 和远端已知状态；
2. 通过传输发送远端缺少的对象；
3. 向接收端请求把 refs/heads/main 更新到候选 OID；
4. 接收端检查认证、授权、旧值、祖先关系和策略；
5. 被接受后，远端 ref 移动；本地工作区和本地 main 通常不因 push 改变。

远端可能已经拥有这些对象，传输阶段会复用，不代表 push 没有进行引用检查。拒绝时对象可能已经被接收端暂存，但远端分支没有移动；不要根据“发送了很多对象”判断发布成功。

发布前后保存：

~~~bash
old_remote="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
local_tip="$(git rev-parse main)"
git push origin main
new_remote="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
printf 'old=%s local=%s new=%s\n' "$old_remote" "$local_tip" "$new_remote"
~~~

ls-remote 会访问远端，需要网络和认证。输出中的 OID、URL 和主体按组织要求脱敏。

## 显式 refspec

默认 push 目标由 remote.pushDefault、branch.*.remote、branch.*.merge 和 push.default 等配置影响。高风险发布可以使用显式 refspec：

~~~bash
git push origin HEAD:refs/heads/feature/search
git push origin <local-commit>:refs/heads/review/search-123
git push origin refs/tags/v0.1.0
~~~

冒号左侧是本地来源，右侧是远端目标。HEAD:refs/heads/feature/search 明确把当前提交发布到指定远端分支，不依赖当前短分支名。发布前核对目标 ref，避免把功能提交推到 main。

删除远程分支：

~~~bash
git push origin :refs/heads/feature/search
~~~

这是远端引用删除，不会自动删除本地分支、对象、评审、制品或其他 clone。它需要明确授权和并发检查。

## 新分支与 upstream

第一次发布功能分支：

~~~bash
git switch --create feature/search
git push --set-upstream origin feature/search
~~~

成功后，本地 branch 配置会把 feature/search 与 origin/feature/search 关联。以后可以使用：

~~~bash
git push
git pull --ff-only
git branch -vv
~~~

upstream 只定义默认比较和交换对象，不授予远端权限，也不会保证服务器实时状态。改变 upstream：

~~~bash
git branch --set-upstream-to=origin/main main
~~~

这是本地配置修改，执行前确认目标 ref 和仓库用途。

## 推送标签

分支 push 不会自动发送所有本地标签。显式发布已核对的标签：

~~~bash
git push origin refs/tags/v0.1.0
~~~

正式标签发布前保存 tag object OID、target commit OID、制品摘要和审批。标签同名竞态、不可变策略和远端删除属于共享状态变更，不要用本地 tag -f 代替协作流程。

## 远端拒绝的层次

| 错误类别 | 说明 | 本地提交是否通常保留 |
| --- | --- | --- |
| endpoint/主机/证书错误 | 没有可靠建立传输 | 保留 |
| authentication failed | 客户端身份未被接受 | 保留 |
| repository not found/permission denied | URL、可见性或仓库授权问题 | 保留 |
| non-fast-forward | 远端 ref 含本地不保留的历史 | 保留 |
| protected ref/policy rejected | 接收端规则、审批、签名或检查门禁拒绝 | 保留 |
| hook/pre-receive rejected | 接收端脚本拒绝候选 | 保留 |
| atomic push failed | 同一批引用没有按原子条件全部更新 | 保留 |

不要把所有拒绝都归类为“权限不足”。先保留 stderr、目标 ref、old/new OID 和本地状态，再按传输、认证、授权、引用规则和平台控制面分流。

## 非快进不是网络故障

当远端 main 从 B 变为 C，而本地基于 B 产生 D：

~~~text
      C remote
     /
A <- B
     \
      D local
~~~

普通 push 被拒绝，因为把远端从 C 改为 D 会让 C 从 main 不再可达。安全流程是：

~~~bash
git fetch origin
git log --left-right --graph --oneline origin/main...main
git merge-base origin/main main
~~~

然后按共享边界选择 merge、rebase 或保留分支。已经推送并被别人依赖的历史不能无协调改写。允许改写的个人分支也要使用显式租约，见第五篇。

## push 成功后的外部状态

终端显示远端 ref 更新成功，只证明 Git 数据面的一次引用更新。还需要单独核对：

- 平台评审是否打开、更新到哪个 commit；
- 必需检查和合并队列是否重新计算；
- 构建制品摘要是否来自同一 candidate；
- 部署实例实际运行哪个 digest；
- 数据库迁移和回退状态；
- 审计事件和权限主体。

不要用 push 输出代替 CI 绿色、发布成功或线上运行证据。

## 失败后的恢复

| 现象 | 先保存 | 恢复 |
| --- | --- | --- |
| 无上游 | branch -vv、remote 配置 | 确认目标后 push -u |
| non-fast-forward | 远端 old OID、本地 OID、merge-base | fetch 后审查整合，不强推 |
| protected branch | ref、规则提示、评审/检查状态 | 走评审或策略例外流程 |
| pre-receive 拒绝 | hook stderr、候选 OID | 修正候选，保留原提交 |
| 标签目标不符 | tag/target OID、发布清单 | 停止提升，按版本策略处理 |
| push 中断 | 本地 refs、远端查询、对象统计 | 不重复盲推，先确认远端 ref |
| 推向错误 URL | remote fetch/push URL、日志 | 停止写入，启动凭据与远端处置 |

推送失败通常不需要重新创建提交。先确认本地提交仍可达，再处理远端状态。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-remotes.sh
~~~

实验使用本地 bare server 验证初次 push、远程跟踪更新、upstream、标签发布和后续 pull。它不证明真实 SSH/TLS、令牌、平台保护分支、评审、CI、制品、部署或审计。

## 小结

push 先传对象，再请求更新远端引用；真正的成功条件是目标 ref 被按预期接受。使用显式 refspec 和 upstream 控制目标，遇到拒绝先比较 old/new OID 和祖先关系，发布后再补齐评审、CI、制品和运行证据。强制改写应由显式租约和团队授权保护。
