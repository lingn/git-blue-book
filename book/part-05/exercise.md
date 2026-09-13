# 综合场景：同步远程主线，再固定可追溯候选

一次功能发布常被描述成“拉一下再推上去”。实际至少包含远程观察、共同祖先、整合方式、候选验证和目标 ref 更新。每一步都会改变不同状态，拆开记录才能知道失败后应该重试、恢复还是停止。

## 场景和目标

你在一个尚未共享的 `feature/search-filter` 分支上有两条提交，远程 `main` 被同事推进了一次。目标是：

- 先取得远程最新观察点，不移动本地功能分支；
- 固定共同祖先和功能差异，判断 rebase、merge 或停止协调；
- 在整合后重新生成候选 OID，并运行真实检查；
- 用完整 refspec 首次发布功能分支，核对服务端 ref；
- 把本地 Git 证据与评审、CI、制品和部署证据分开记录。

本练习只负责 Git 远程同步。评审审批、必需检查、合并队列和受保护引用见[第六篇](../part-06/README.md)，不要用本地命令伪造平台结果。

## 前置条件和安全边界

- Git 2.28 或更高版本；
- POSIX shell、`mktemp` 和可写临时目录；
- 一个获批的测试远程，或使用下面的本地 bare 仓库实验；
- 功能分支尚未被其他人使用，且开始时工作区与 index 干净；
- 不使用 `--force`，不删除远程引用，不在真实主线上试推；
- 所有 OID、路径和 URL 都以本次命令输出为准，不能照抄占位符。

本地实验不会连接网络，不读取用户凭据，也不验证平台认证、保护规则、评审或 CI。

## 1. 建立隔离实验远程（可选）

若没有专用测试远程，在任意安全目录执行。`lab_root` 只能指向本次练习目录，不能指向当前蓝皮书仓库。

~~~bash
lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-remote-exercise.XXXXXX")"
trap 'rm -rf "$lab_root"' EXIT

git init --bare --initial-branch=main "$lab_root/remote.git"
git init --initial-branch=main "$lab_root/author"
git -C "$lab_root/author" config user.name 'Exercise Author'
git -C "$lab_root/author" config user.email 'exercise-author@example.invalid'
printf 'base\n' > "$lab_root/author/README.md"
git -C "$lab_root/author" add README.md
git -C "$lab_root/author" commit -m 'docs: create exercise base'
git -C "$lab_root/author" remote add origin "file://$lab_root/remote.git"
git -C "$lab_root/author" push --set-upstream origin HEAD:refs/heads/main

git clone "file://$lab_root/remote.git" "$lab_root/work"
git -C "$lab_root/work" config user.name 'Feature Author'
git -C "$lab_root/work" config user.email 'feature-author@example.invalid'
git -C "$lab_root/work" switch --create feature/search-filter
printf 'filter=v1\n' > "$lab_root/work/filter.conf"
git -C "$lab_root/work" add filter.conf
git -C "$lab_root/work" commit -m 'feat: add search filter'
printf 'tests=search-filter\n' > "$lab_root/work/filter-test.txt"
git -C "$lab_root/work" add filter-test.txt
git -C "$lab_root/work" commit -m 'test: cover search filter'

printf 'base\nteam-note\n' > "$lab_root/author/README.md"
git -C "$lab_root/author" add README.md
git -C "$lab_root/author" commit -m 'docs: update shared readme'
git -C "$lab_root/author" push origin HEAD:refs/heads/main
~~~

预期：远端 `main` 有同事的新提交，而工作 clone 的 `origin/main` 仍是旧缓存。每次 commit 都会创建新的对象；最后一次 push 只更新远端 `main`，不会发布功能分支。

## 2. 保存现场并取得远程观察点

在工作 clone 根目录执行。真实仓库先确认没有进行中的 merge、rebase 或 cherry-pick：

~~~bash
cd "$lab_root/work"
git status --short --branch --untracked-files=all
git branch --show-current
git rev-parse --show-toplevel
git config --show-origin --show-scope --get-regexp '^remote\.origin\.|^branch\.'
old_origin="$(git rev-parse --verify origin/main^{commit})"
old_feature="$(git rev-parse --verify HEAD^{commit})"
git fetch origin
new_origin="$(git rev-parse --verify origin/main^{commit})"
printf 'origin_before=%s origin_after=%s feature=%s\n' \
  "$old_origin" "$new_origin" "$old_feature"
git rev-parse --verify FETCH_HEAD^{commit}
~~~

预期：`new_origin` 与 `old_origin` 不同，功能分支 HEAD 仍等于 `old_feature`。Fetch 可能新增对象、更新 `refs/remotes/origin/main` 和 `.git/FETCH_HEAD`，不会自动整合功能分支。

Fetch 失败时保存原始 stderr、退出码、URL、时间和 Git 版本，转到[传输与认证](08-transport-and-authentication.md)。若 OID 没变化，检查 refspec、可见性和 `git ls-remote origin refs/heads/main`，不要先 reset。

## 3. 固定共同祖先和差异

~~~bash
base="$(git merge-base origin/main HEAD)"
candidate_before="$(git rev-parse HEAD)"
printf 'base=%s candidate_before=%s\n' "$base" "$candidate_before"
git log --oneline "$base"..HEAD
git log --oneline HEAD..origin/main
git diff --stat "$base"...HEAD
git diff "$base"...HEAD
~~~

预期：第一条范围列出两条功能提交，第二条列出同事的主线提交，三点 diff 只显示功能相对共同祖先的变化。保存 base、candidate_before 和差异摘要，后续 rebase 会生成新 OID。

没有共同祖先时，先检查仓库、迁移、shallow 边界和 refspec。不要对两个无关根强行合并。

## 4. 根据共享边界整合

本地功能分支尚未发布，因此选择 rebase：

~~~bash
git rebase origin/main
candidate="$(git rev-parse HEAD)"
test "$candidate" != "$candidate_before"
git merge-base --is-ancestor origin/main HEAD
git log --oneline origin/main..HEAD
git status --short --branch
~~~

成功时功能提交被按顺序重放，当前分支引用和 commit/tree 对象改变，`origin/main` 不变。预期 candidate 与旧值不同，范围仍表达两条功能意图，工作区干净。

冲突时先采集：

~~~bash
git status --short --branch
git rebase --show-current-patch
git ls-files --unmerged
~~~

按来源提交意图逐路径解决，确认 index 变成 stage 0，再 `git add` 和 `git rebase --continue`。`git rebase --skip` 会跳过整个来源提交，不是普通解决。结果不对时使用 `git rebase --abort`，并核对 HEAD 回到 `candidate_before`。

如果功能分支已经被同事、评审或 CI 使用，停止 rebase，改为 merge 或协调后重建候选。

## 5. 重新固定候选并运行检查

~~~bash
candidate="$(git rev-parse HEAD)"
git show --no-patch --format='%H%n%P%n%T%n%s' "$candidate"
git diff --stat origin/main...HEAD
git diff --check
git diff --staged --check
git rev-list --left-right --count origin/main...HEAD
~~~

保存 candidate 完整 OID、父列表、tree OID、差异范围、Git 版本、测试命令和结果。没有运行的检查标记为“未验证”，不能填入绿色结果。

本地检查只证明当前候选对象和工作区，不能证明平台审批、CI checkout、制品摘要、数据库兼容或部署完成。

## 6. 首次发布功能分支

确认候选、远程目标和写权限后：

~~~bash
git push --set-upstream origin HEAD:refs/heads/feature/search-filter
git branch -vv
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
remote_feature="$(git ls-remote origin refs/heads/feature/search-filter | awk 'NR == 1 {print $1}')"
printf 'candidate=%s remote_feature=%s\n' "$candidate" "$remote_feature"
test "$candidate" = "$remote_feature"
~~~

成功时远端创建功能 ref，本地写入 upstream 配置。真实远程查询和 push 之间有并发窗口，应保存服务端响应、请求 ID 和平台 ref 事件。

## 7. 失败分流

| 现象 | 先固定 | 恢复方向 |
| --- | --- | --- |
| Fetch 失败 | URL、传输层、原始 stderr、当前 refs | 修复 endpoint、认证或授权，不移动功能分支 |
| Fetch 成功但主线没变 | refspec、可见 refs、old/new OID | 检查远端查询、权限和 shallow 边界 |
| Rebase 冲突 | 当前 patch、unmerged stages、开始 OID | 逐提交解决或 abort |
| Rebase 后差异不对 | old/new candidate、三点 diff、测试 | 恢复旧候选或从正确基线重建 |
| Push non-fast-forward | 服务端 old、本地 new、merge-base | Fetch 后整合，禁止无条件 force |
| Push 到错误目标 | fetch/push URL、pushRemote、服务器 refs | 停止继续写入，按专用 ref 清理并通知相关人 |
| Push 失败但状态未知 | porcelain 输出、逐 ref 查询、服务端事件 | 区分全部拒绝、部分成功和查询失败，不盲推 |

Push 成功后 CI 或制品没有对应 candidate 时，不要重复 push，相应证据应从平台事件、流水线 checkout、制品 manifest 和部署状态分别取得。

## 8. 交付记录和验收边界

至少保存：

~~~text
repository / remote URL / authenticated principal:
worktree / branch / Git version:
origin_before / origin_after / FETCH_HEAD:
base / candidate_before / candidate_after:
candidate parents / tree / diff range:
integration choice and reason:
tests / build / static checks and exact results:
destination ref / expected old / observed new:
platform review, CI, artifact and deployment evidence:
unverified boundaries / recovery source:
~~~

本练习能证明本地 Git 对象、remote-tracking ref、rebase、upstream 和显式 push refspec 的关系。它不能证明评审审批、保护规则、合并队列、CI 候选、制品、LFS、submodule、数据库、部署、审计或复制已经收敛；这些事实要从相应系统取证。

## 恢复与清理

本地实验由 `trap` 清理临时目录。调查失败时先复制日志和 OID，再临时保留隔离目录；不要在当前蓝皮书仓库执行实验中的 `git init`、`reset --hard` 或删除命令。

真实远程出现候选错绑或错误发布时，先冻结继续写入，固定目标 ref、old/new OID、评审/CI/制品事件和主体，再按共享历史政策决定 revert、向前修复或经过协调的显式租约。恢复动作也要生成新的候选和验证记录。

## 小结

可靠路径是：保存现场，fetch 得到观察点，固定 merge-base，按共享边界整合，重新生成 candidate，运行真实检查，最后用显式 refspec 发布并查询服务器 ref。每一步的状态变化和证据都不同，不能用一次 pull 或 push 的成功替代整条链路。
