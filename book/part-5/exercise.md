# 综合场景：四类事故的恢复决策

以下现场都可能被口头称为“回滚”，但它们处于不同层：工作区、index、私有提交、共享引用或远程并发。每个场景先保存证据，再执行最小动作，并在动作后验证不变量。

## 练习边界

- 执行位置：一次性临时 Git 仓库根目录；
- 前置条件：Git 2.28 或兼容版本、Bash、可写临时目录；
- 身份：只使用合成姓名和邮箱；
- 网络：本地 remote 场景使用 bare 仓库，不连接托管平台；
- 安全：不要替换成真实凭据、客户数据或生产分支；
- 完成标准：每个场景都能说明 source、target、共享边界、动作、后置验证和不可恢复范围。

如果目录已经存在，换一个新目录。不要为了重跑练习删除来源不明的仓库。

## 1. 丢弃尚未暂存的工作区修改

建立基线并制造一个明确不要的修改：

~~~bash
git init --initial-branch=main
git config user.name "Git Blue Book Recovery Lab"
git config user.email "recovery@example.invalid"
printf 'stable configuration\n' > config.yml
git add -- config.yml
git commit -m "config: add stable baseline"
printf 'temporary experiment\n' >> config.yml
git status --short
git diff -- config.yml
git diff --staged -- config.yml
~~~

证据应显示 config.yml 只有工作区修改，index 与 HEAD 一致。确认差异确实不要后：

~~~bash
git restore --worktree -- config.yml
git status --short
git diff -- config.yml
test "$(cat config.yml)" = "stable configuration"
~~~

这个动作覆盖工作区字节，Git 通常没有办法从 reflog 找回从未暂存或提交的内容。若文件重要，先复制到仓库外的受控位置。不要用全仓库 reset --hard 代替路径级恢复。

## 2. 取消暂存，但保留文件修改

制造一份暂存版本和一份工作区版本：

~~~bash
printf 'reviewed line\n' >> config.yml
git add -- config.yml
printf 'not ready line\n' >> config.yml
git status --short
git diff -- config.yml
git diff --staged -- config.yml
~~~

此时通常是 MM。目标是保留两行在文件中，只把 index 退回 HEAD：

~~~bash
git restore --staged -- config.yml
git status --short
git diff -- config.yml
git diff --staged -- config.yml
grep -F 'not ready line' config.yml
~~~

预期 staged diff 为空，工作区仍有两行修改。若仓库没有 HEAD，使用 restore --staged 的默认来源可能不可用；先保存文件，再按首次提交边界使用 rm --cached。

## 3. 私有提交漏了同一意图的测试

把当前修改整理成可提交内容，然后故意遗漏测试：

~~~bash
git add -- config.yml
git commit -m "config: update reviewed value"
printf 'test fixture\n' > tests.txt
git status --short --untracked-files=all
~~~

确认 tests.txt 与最近提交属于同一个私有意图，且最近提交没有被推送、评审、CI 或其他 worktree 使用。先建立恢复引用：

~~~bash
old_tip="$(git rev-parse HEAD)"
git branch recovery/before-amend "$old_tip"
git add -- tests.txt
git diff --staged --check
git commit --amend --no-edit
new_tip="$(git rev-parse HEAD)"
test "$new_tip" != "$old_tip"
test "$(git rev-parse HEAD^)" = "$(git rev-parse recovery/before-amend^)"
git show --stat --format=fuller HEAD
~~~

验证测试已进入新 tree，工作区没有意外变化。旧提交仍应可通过 recovery/before-amend 找到。若测试本来属于另一意图，应取消暂存并创建独立提交，而不是 amend。

## 4. 已共享错误提交使用 revert

先把当前仓库补成可回滚的稳定基线，再创建一个本地 bare server 和两个 clone：

~~~bash
printf 'stable behavior\n' > app.txt
git add -- app.txt
git commit -m "feat: add stable behavior"
~~

~~~bash
git clone --bare . ../recovery-server.git
git clone ../recovery-server.git ../alice
git clone ../recovery-server.git ../bob
git -C ../alice config user.name Alice
git -C ../alice config user.email alice@example.invalid
git -C ../bob config user.name Bob
git -C ../bob config user.email bob@example.invalid
~~~

在 Alice 中创建并推送一个错误修改，再由 Bob 获取：

~~~bash
printf 'broken behavior\n' > ../alice/app.txt
git -C ../alice add -- app.txt
git -C ../alice commit -m "feat: introduce broken behavior"
bad_commit="$(git -C ../alice rev-parse HEAD)"
git -C ../alice push origin main
git -C ../bob fetch origin
git -C ../bob pull --ff-only
~~~

Bob 还可以在错误提交后创建一条正确提交，证明共享历史不能简单移动回旧节点：

~~~bash
printf 'later correct work\n' > ../bob/README.md
git -C ../bob add -- README.md
git -C ../bob commit -m "docs: add later work"
later_commit="$(git -C ../bob rev-parse HEAD)"
~~~

在 Bob 中执行反向提交：

~~~bash
git -C ../bob revert --no-edit "$bad_commit"
revert_commit="$(git -C ../bob rev-parse HEAD)"
git -C ../bob push origin main
test "$(git --git-dir=../recovery-server.git rev-parse refs/heads/main)" = "$revert_commit"
git -C ../bob merge-base --is-ancestor "$bad_commit" "$revert_commit"
test "$(git -C ../bob show HEAD:app.txt)" = "stable behavior"
test "$(git -C ../bob show HEAD:README.md)" = "later correct work"
~~~

revert 保留 bad_commit 和 later_commit 的父关系，新增一个撤销提交。若错误提交涉及数据库、消息或外部副作用，代码 tree 恢复不等于数据和运行状态恢复，必须补充发布和数据动作。

## 5. 误删未合并功能分支

在临时仓库中建立一个尚未合入 main 的提交：

~~~bash
git switch --create feature/recoverable
printf 'recoverable draft\n' > draft.md
git add -- draft.md
git commit -m "docs: add recoverable draft"
deleted_tip="$(git rev-parse HEAD)"
git switch main
git branch -D feature/recoverable
~~~

强制删除只移除分支名字。先确认对象仍能从 HEAD reflog 找到：

~~~bash
git reflog --all --date=iso-strict
git show --no-patch --format=fuller "$deleted_tip"
git branch recovery/deleted-feature "$deleted_tip"
git show --stat recovery/deleted-feature
~~~

建立 recovery ref 后再决定是合并、cherry-pick 还是继续保留。不要先 gc、prune 或重新初始化仓库。对象长期不可达后可能过期，恢复窗口受配置、维护和其他副本影响。

## 6. 个人远程分支改写和租约

下面是一张操作卡，不在前面的本地恢复链中直接执行。只有在另一个专用测试远程中确认分支允许改写、没有协作者依赖旧历史，并已保存远程旧 OID 时，才执行：

~~~bash
expected_remote="$(git ls-remote origin refs/heads/feature/search | awk '{print $1}')"
git branch recovery/remote-before-rewrite "$expected_remote"
git commit --amend -m "docs: corrected search draft"
git push --force-with-lease=refs/heads/feature/search:"$expected_remote" \
  origin HEAD:refs/heads/feature/search
~~~

如果 ls-remote 失败，不能把空值当成 expected value。查询和推送之间仍可能有并发更新，租约拒绝时重新 fetch、保存 old/new OID 并通知协作者。不要升级为无条件 force。

生产记录至少包含：

~~~text
remote_ref: refs/heads/feature/search
expected_old: <完整 OID>
new_tip: <完整 OID>
recovery_ref: <恢复引用>
approved_by: <批准人>
shared_consumers: <评审、CI、制品、部署和其他 clone>
verification: <远端 ref、测试和发布证据>
~~~

租约保护引用更新，不提供备份、授权或外部副本清理。

## 7. 正在进行的 merge/rebase/cherry-pick

如果 status 显示进行中的操作，不要套用前面场景。先识别：

~~~bash
git status --short --branch
git rev-parse --verify MERGE_HEAD
git rev-parse --verify REBASE_HEAD
git rev-parse --verify CHERRY_PICK_HEAD
git ls-files --unmerged
~~~

根据存在的状态选择对应 continue、skip 或 abort。保存当前 HEAD、操作提交、stages 和工作区差异。不要删除状态文件或用 reset --hard 让 status 归零。

## 8. 最终验收

每个场景完成后保存：

~~~bash
git status --short --branch --untracked-files=all
git log --graph --decorate --oneline --all
git for-each-ref --format='%(refname) %(objectname) %(objecttype)'
git reflog --all -5
git count-objects -v
~~~

验收必须回答：

1. 哪一层发生变化，source 和 target 是什么；
2. 操作是否创建新 commit 或移动 ref；
3. 原始提交和工作区字节是否仍可恢复；
4. 是否已有远端、评审、CI、制品、部署或数据消费者；
5. 哪个测试或状态不变量证明动作完成；
6. 哪些内容 Git 本身无法恢复或验证。

## 失败路径和恢复

| 现场 | 不要做 | 先做 |
| --- | --- | --- |
| 未暂存修改不要了 | 直接 restore 全仓库 | 保存 diff，按路径恢复 |
| 误暂存 | 再次 add . | staged diff 后 restore --staged |
| 私有提交漏文件 | 直接创建无关补丁 | 确认同一意图后 amend |
| 共享提交错误 | reset 和无条件 force | fetch、revert、测试和发布验证 |
| 分支误删 | gc 或重新 init | reflog、对象查询、recovery ref |
| 租约拒绝 | 改用 force | 获取新远端 OID，重新协调 |
| 状态机中断 | 删除 MERGE_HEAD 等文件 | 对应 status、continue 或 abort |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-2.sh
./scripts/verify-part-5-local-history.sh
./scripts/verify-reset-reflog.sh
./scripts/verify-revert.sh
./scripts/verify-force-with-lease.sh
~~~

这些脚本在临时仓库中验证工作区、index、amend、reset、reflog、revert 和租约状态。它们不证明真实托管平台权限、文件系统恢复、LFS、子模块、数据库、CI、制品或运行实例。

## 小结

恢复动作没有通用的“回滚键”。先定位变化层，再确认提交是否共享，写出恢复来源和影响范围，最后选择 restore、unstage、amend、rebase、revert、recovery ref 或显式租约。每个动作都要保存前后 OID、路径和验证结果，Git 无法覆盖的外部系统则必须单独取证。
