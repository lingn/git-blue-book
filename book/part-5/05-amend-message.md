# 只修改最近一次提交说明：文字变化也会改变 OID

提交说明属于 commit 对象内容的一部分。即使文件快照和父提交完全不变，只改主题、正文、任务号或 trailers，也会生成新的提交对象。能否这样做，首先取决于这条提交是否已经被共享。

## 进入条件与完成标准

在最近一次提交的本地分支根目录执行。开始前保存：

~~~bash
git status --short --branch --untracked-files=all
git show --no-patch --format=fuller HEAD
git rev-parse HEAD
git rev-parse HEAD^{tree}
git reflog -1
~~~

工作区和 index 最好干净。确认最近提交没有被推送、评审、CI、制品、部署、标签或其他 worktree 引用。不能只看分支名判断共享边界。

读完本章后，你应能：

- 说明 amend 说明为什么会生成新 OID；
- 用 -m 或编辑器安全修改说明；
- 保留作者、提交者和签名的正确语义；
- 处理任务号、trailer、编码和 hook 失败；
- 找回修改前的提交；
- 在共享历史中选择追加修正而不是直接改写。

## 修改前先确认对象和范围

查看当前提交：

~~~bash
git show --no-patch --format='%H%n%P%n%T%n%an%n%ae%n%cn%n%ce%n%s%n%b' HEAD
git status --short --branch
git diff --staged --name-status
git diff --name-status
~~~

本章目标是只修改说明，因此 index、工作区和 tree 都不应有意外变化。先创建恢复引用：

~~~bash
old_tip="$(git rev-parse HEAD)"
old_tree="$(git rev-parse HEAD^{tree})"
git branch recovery/before-message-amend "$old_tip"
~~~

恢复引用不是备份整个外部系统，但能保留旧 commit 的可达入口。

## 用 -m 改写短说明

~~~bash
git commit --amend -m "docs: clarify recovery workflow"
~~~

Git 用新的说明、当前 tree 和当前身份创建替代提交。验证：

~~~bash
new_tip="$(git rev-parse HEAD)"
new_tree="$(git rev-parse HEAD^{tree})"
git show --no-patch --format='%H%n%P%n%T%n%s' HEAD
test "$new_tip" != "$old_tip"
test "$new_tree" = "$old_tree"
test "$(git rev-parse HEAD^)" = "$(git rev-parse recovery/before-message-amend^)"
git status --short --branch
~~~

父提交和根 tree 应保持不变，commit OID 应变化。提交者身份和时间通常会更新，作者字段通常保留。签名字段如果存在，需要重新验证，因为签名覆盖的是旧对象内容。

如果说明包含换行、非 ASCII 文字或 shell 特殊字符，先在受控编辑器中准备文件，避免 shell 转义错误。不要把真实凭据放进说明或命令历史。

## 使用编辑器修改长说明

不带 -m：

~~~bash
git commit --amend
~~~

Git 打开 commit message 编辑器。保存并退出后创建替代 commit，取消或退出失败时先查看 status、HEAD 和 stderr。不同编辑器的退出方式不属于 Git 语义，团队应在开发环境文档中说明。

也可以使用环境变量指定一次性编辑器：

~~~bash
GIT_EDITOR=true git commit --amend --no-edit
~~~

true 只适合验证不修改说明的自动化场景。生产脚本不要用它掩盖需要人工审查的正文。

## 主题、正文和 trailers 的边界

说明应让读者知道动机、风险和验证。任务号和 trailers 可以帮助检索：

~~~text
fix: correct retry deduplication

Persist the request key before the external call so retries reuse the
same operation. This commit is compatible with the previous worker.

Tests: unit retry case, provider stub
Refs: INC-2026-001
~~~

Git 会把正文当作字节保存，不会验证 INC-2026-001 是否真的存在，也不会验证 Tests 行是否执行。平台、工单和 CI 事件要单独取证。

不要用 Co-authored-by、Signed-off-by 或 Reviewed-by 冒充未发生的协作、法律声明或审批。提交说明应与真实记录一致。

## 身份、签名和提交者

普通 amend 通常保留作者，提交者和提交时间更新。查看：

~~~bash
git show --no-patch --format=fuller HEAD
git cat-file -p HEAD
~~~

如果要修正自己的身份，先使用第二篇的配置来源和 git var，确认当前仓库身份后再评估是否使用 reset-author。不要把作者字段当作远程登录主体，也不要把修改邮箱当作签名或审批。

如果原 commit 有签名，amend 后新对象需要重新签名。旧签名不能证明新对象的内容：

~~~bash
git verify-commit <new-commit>
~~~

验证工具、信任根和组织授权见第十篇。没有配置验证环境时，应如实标记未验证，不写成“签名通过”。

## hook 和失败后的状态

amend 可能执行 commit-msg、pre-commit、签名或组织 hook。失败后先保存：

~~~bash
git rev-parse HEAD
git diff --staged
git status --short --branch
git reflog -2
git config --show-origin --get-regexp '^(core\.hooksPath|commit\.|gpg\.|ssh\.)'
~~~

通常 hook 拒绝不会移动 HEAD，但 hook 可以生成文件、写日志、修改 index 或调用外部服务。修复具体原因后重新检查 staged diff。不要用 no-verify 绕过未知门禁；如果组织批准例外，记录理由和补做的检查。

如果提交说明脚本要求任务号、长度或格式，失败是提交输入不符合规则，不代表对象损坏。保留 old_tip 和恢复引用，避免连续 amend 让证据混乱。

## 共享边界决定动作

说明修改会改变提交 OID，影响范围包括：

- 其他人的分支、worktree 和本地缓存；
- 评审评论、审批、CI 结果和合并队列；
- 发布标签、制品清单、部署和审计记录；
- 备份、镜像和恢复引用。

尚未共享的个人提交可以按本章 amend。已经共享的提交通常追加一个清楚的修正提交；主线和发布分支不应为了拼写或标题美化而改写。若团队明确允许个人评审分支改写，先保存远端 expected-old、通知依赖者，并使用显式租约。

平台可能提供不改 commit 的标题展示或关联字段。优先使用平台控制面的修正方式，但要核对它是否真的不改变 Git 对象。

## 找回修改前的说明和提交

amend 后发现新说明不准确：

~~~bash
git show --no-patch --format=fuller recovery/before-message-amend
git show --no-patch --format=fuller HEAD
git branch recovery/correct-message recovery/before-message-amend
~~~

若确认旧对象应恢复为当前功能分支：

~~~bash
git switch --detach recovery/before-message-amend
git switch --create feature/recovered-message
~~~

不要把恢复分支直接强行覆盖共享分支。先确认旧 OID 是否已发布、哪个版本应作为权威，以及外部记录怎样关联。

## 失败路径和恢复

| 现象 | 首先收集 | 处理 |
| --- | --- | --- |
| 新说明写错 | old/new OID、恢复分支、共享状态 | 私有分支再次 amend，共享分支追加修正 |
| 文件内容被意外带入 | staged diff、tree OID、工作区状态 | 取消暂存并重新审查，再决定是否重建 |
| hook 拒绝 | stderr、配置来源、HEAD、index | 修复具体规则，不用 no-verify |
| 旧 OID 找不到 | recovery ref、reflog、其他 refs、bundle | 先建立恢复引用，停止 gc/prune |
| 签名失效 | 新对象、签名工具、信任根 | 重新签名并重新验证 |
| 已推送却修改说明 | 远端 old OID、评审/CI/制品引用 | 停止普通 push，协调并按共享边界处理 |
| 任务号或 trailer 不真实 | 工单、评审和审计事件 | 删除虚假声明，用真实来源补充 |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-5-local-history.sh
./scripts/verify-signatures-trust.sh
~~~

实验验证 amend 改说明会生成新 OID、文件 tree 可保持不变，签名实验验证对象签名和目标 OID 的独立关系。它不证明真实工单、评审、CI、平台显示、审计或发布记录。

## 小结

提交说明不是对象外的便签，改一个字也会生成新 commit。修改前保存旧 OID、tree 和恢复引用，只在私有边界内 amend；共享提交优先追加修正。提交者、作者、签名、工单、评审和部署各需独立证据，不能让一段文字替代整条历史链。
