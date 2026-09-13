# Pull 是 fetch 加本地整合：两阶段必须分开诊断

`git pull` 通常先 fetch，再对当前分支执行 fast-forward、merge 或 rebase。它把网络获取和本地历史操作放在一次命令中，使用起来方便，失败时却容易让人误以为“什么都没发生”。Fetch 可能已经更新对象、remote-tracking refs 和 `FETCH_HEAD`，整合阶段才进入冲突或拒绝。

## 进入条件与完成标准

在有明确 upstream 的本地分支根目录执行。开始前固定：

~~~bash
git status --short --branch
git branch -vv
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
git config --show-origin --show-scope --get-regexp \
  '^(pull|branch\..*\.rebase|branch\..*\.merge|remote\.)'
~~~

工作区和 index 应处于可解释状态。Pull 会先访问 remote 并写入本地观察点，随后可能改写当前分支、index、工作区或进行中操作目录。生产主线不要在未保存现场时试 pull。

读完本章后，应能拆解 pull 的 fetch/整合边界，选择 `--ff-only`、`--no-rebase` 或 `--rebase`，解释成功/失败后的 OID 和状态，处理 autostash、上游缺失、hook/冲突和远端竞态，并知道什么时候必须改用显式 fetch + 审查 + 整合。

## 先把 pull 拆成两条命令

最容易审计的等价流程：

~~~bash
git fetch origin
git show-ref --verify refs/remotes/origin/main
git merge --ff-only origin/main
~~~

这不是所有配置下的字面展开，但能揭示两阶段。实际 pull 使用的 remote/refspec 来自当前分支 upstream、命令参数和配置；`pull.rebase`、`branch.<name>.rebase`、`pull.ff` 等都可能改变整合方式。

保存阶段证据：

~~~text
fetch_started / fetch_finished
remote_url / refspec
old_remote_tracking_oid / new_remote_tracking_oid
old_local_head / new_local_head
FETCH_HEAD snapshot
integration_mode / status / error
~~~

不要只保存最终 HEAD。最终相同可能意味着没有新变化，也可能意味着 fetch 成功后 merge 判断 Already up to date。

## `--ff-only` 把分叉变成拒绝

~~~bash
git pull --ff-only
~~~

Pull 先 fetch。若取得的 upstream 是当前 HEAD 的后代，本地分支可以快进；若双方分叉，整合阶段拒绝，不创建 merge commit。Fetch 已经可能更新 `origin/main` 和 `FETCH_HEAD`。

失败后核对：

~~~bash
local_head="$(git rev-parse HEAD)"
tracking_head="$(git rev-parse '@{upstream}')"
git rev-list --left-right --count HEAD..."$tracking_head"
git status --short --branch
~~~

不要用 `reset --hard origin/main` 让 pull 变绿。它会丢弃本地 commit 或工作区内容，改变的问题层次与 ff-only 拒绝不同。

## `--no-rebase` 允许本地 merge

~~~bash
git pull --no-rebase
~~~

Fetch 后，如果本地和 upstream 分叉且内容可组合，Git 以当前本地 HEAD 为第一父，远程更新为第二父，创建 merge commit。冲突时进入 `MERGE_HEAD` 状态，应按第四篇解决、abort 或 quit。

Merge 方式适合需要保留两条历史接合点的本地分支，但共享主线是否允许自动 merge 仍由团队策略决定。Pull 成功不能证明评审、CI 或发布条件满足。

## `--rebase` 会重建本地独有提交

~~~bash
git pull --rebase
~~~

Fetch 后，Git 将本地相对共同祖先的独有提交逐个重放到 upstream 之后，产生新 commit 并移动当前分支。原 commit 可能只剩 reflog 或其他 refs。已经推送的本地历史使用该选项前，必须确认共享边界和显式租约策略。

验证重建：

~~~bash
old_local_oid="$(git rev-parse HEAD)"
git pull --rebase
new_local_oid="$(git rev-parse HEAD)"
git merge-base --is-ancestor '@{upstream}' HEAD
test "$old_local_oid" != "$new_local_oid"
~~~

最后一条只适用于确实存在本地独有提交并成功重放的场景。无本地独有提交时可能直接快进，不能强行期待 OID 变化。

Rebase 冲突的状态目录和 ours/theirs 视角与普通 merge 不同。使用 `git rebase --continue`、`--abort` 或 `--quit`，不要在 rebase 状态执行 merge abort。

## 配置默认值必须带来源

~~~bash
git config --show-origin --show-scope --get pull.rebase
git config --show-origin --show-scope --get pull.ff
git config --show-origin --show-scope --get-regexp \
  '^branch\..*\.rebase$'
~~~

没有输出时 Git 使用内置默认和命令上下文。个人全局配置可能让同一 `git pull` 在不同开发者机器上产生不同历史。团队规范应在受控脚本、服务端合并流程或仓库配置中明确，而不是依赖每个人记住个人配置。

命令行显式选项优先于配置，但只影响当前调用。自动化记录实际 argv 和配置来源，避免把“我以为是 merge”写成事实。

## 工作区修改与 autostash

Pull 可能因未提交修改会被目标覆盖而拒绝。某些路径不冲突时，Git 也可能携带本地修改。若使用：

~~~bash
git pull --rebase --autostash
~~~

Git 会先创建临时 stash，整合后尝试应用。应用阶段仍可能冲突，未跟踪/忽略文件和外部生成物不一定在 stash 中。执行前保存 status、两类 diff、未跟踪清单和 stash 位置；失败后保留 stash，不运行 clean 或 hard reset。

Autostash 是本地恢复辅助，不是备份，也不把 pull 变成原子操作。共享主线和发布 clone 默认先清理工作区，或者使用独立 worktree。

## 上游缺失、删除和重命名

没有 upstream 时，pull 通常拒绝并提示没有跟踪信息。确认目标后设置：

~~~bash
git branch --set-upstream-to=origin/main main
~~~

这只改本地配置，不 fetch、不 merge、不移动提交。远端把 main 重命名为 trunk 后，服务器 symbolic HEAD、origin/HEAD、remote-tracking refs 和 branch config 需要分阶段更新；不能因为页面默认分支已变就直接改本地 HEAD。

上游 ref 被 prune 删除时，本地分支和提交仍可能存在，但 status/pull 无法比较。先用 `ls-remote` 或显式 fetch 确认远端，再决定更新配置或保留分支。

## Pull 的两个失败阶段

### Fetch 失败

URL、DNS、host key、TLS、认证、授权、协议和 pack 错误发生在整合前。保留原始 stderr、旧 tracking OID 和对象统计。部分对象已进入本地不代表 ref 已更新。

### 整合失败

Fetch 成功后，ff-only 拒绝、merge/rebase 冲突、hook、编辑器、签名或工作区覆盖会停止流程。判断：

~~~bash
git status --short --branch
git rev-parse --verify MERGE_HEAD
git rev-parse --verify REBASE_HEAD
git rebase --show-current-patch
git rev-parse '@{upstream}'
~~~

`MERGE_HEAD` 和 rebase 状态目录代表不同状态机。只调用对应 abort/continue；不要删除状态文件伪造完成。

## Pull 与远端竞态

Pull 的 fetch 和整合不是服务器事务。Fetch 得到 B 后，其他协作者可能把服务器推进到 C；本地整合完成后 push 仍可能因 non-fast-forward 被拒绝。高风险修复记录 fetch 时点、B 的 OID、最终本地 OID 和 push 的 expected-old。

合并队列、评审审批、必需检查、保护分支、平台审计和部署不由 pull 自动等待或验证。需要平台候选时使用第六、八篇的对象绑定流程。

## 什么时候不要用 pull

下列情况优先拆开：

| 场景 | 推荐流程 | 原因 |
| --- | --- | --- |
| 需要审查远端变化 | fetch → log/diff → merge/rebase | 先看输入再整合 |
| 远端分支已重写 | fetch → 保存旧/new OID → 选择恢复/重建 | 避免 pull 隐藏强制更新 |
| 发布/取证 clone | fetch 指定 refs，保存 manifest | pull 会改当前工作状态 |
| 工作区含未知修改 | 保存/提交/stash/worktree → fetch | 防止 autostash 或覆盖扩大范围 |
| 团队主线要求条件更新 | 候选、检查、服务端更新 API | pull 不提供平台审批与队列事务 |

Pull 适合可解释的日常工作线。越接近发布、事故和共享主线，越应显式记录两阶段和每个 OID。

## 隔离实验

运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-pull-composition.sh
~~~

实验在独立 clone 中验证：远端前进时 `pull --ff-only` 快进；本地与远端分叉时 fetch 更新 tracking ref、ff-only 拒绝且本地 HEAD 不动；`pull --no-rebase` 创建二父 merge；另一 clone 的 `pull --rebase` 重建本地独有 commit。每个阶段保存 old/new OID 和工作区状态。

实验不模拟 SSH/TLS、凭据、平台保护、合并队列、autostash 冲突、业务测试或部署。

## 小结

Pull 把 fetch 和本地整合合在一起，可能同时改变缓存与当前历史。先区分 fetch 失败和 merge/rebase 失败，再按 `--ff-only`、merge 或 rebase 的状态机恢复。发布、取证和共享主线优先拆成显式 fetch、审查和条件整合，保留每个阶段的 OID 与外部证据。

## 资料

- [git-pull](https://git-scm.com/docs/git-pull)
- [git-fetch](https://git-scm.com/docs/git-fetch)
- [git-merge](https://git-scm.com/docs/git-merge)
- [git-rebase](https://git-scm.com/docs/git-rebase)
