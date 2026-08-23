# revert 用新提交撤销共享历史中的变化

错误提交已经进入共享分支时，删除原提交会改变其他人和自动化系统使用的历史坐标。`git revert` 保留原提交，并创建一条反向变化提交。

```text
A <- B <- C                 B 引入错误，C 是后续正确提交

A <- B <- C <- R            R 尝试抵消 B 的变化
```

R 的父提交是 C，B 仍然是当前历史的祖先。revert 处理的是 Git tree 的变化，不会撤销已经执行的数据库迁移、外部 API 调用、消息发送或部署动作。

## 操作前确认目标提交和后续依赖

执行位置是准备接收反向提交的本地分支。普通 revert 要求 index 和工作区相对 `HEAD` 干净，开始前读取：

```bash
git status --short --branch
git log --graph --decorate --oneline --all --max-count=30
bad_commit="replace-with-the-verified-full-object-id"
git show --stat --summary "$bad_commit"
```

把说明文字替换为核对后的完整 ID。还要查看错误提交之后修改过相同路径的历史：

```bash
affected_path="path/to/affected-file"
git log --oneline --ancestry-path "$bad_commit"..HEAD
git log --oneline "$bad_commit"..HEAD -- "$affected_path"
```

第一条只在错误提交是当前 `HEAD` 祖先时有意义；不是祖先时会没有可用的 ancestry path，需要重新确认为什么要把该提交的反向补丁应用到当前分支。第二条中的路径必须替换为真实文件。

回滚基础接口、schema 或公共重构时，后续提交可能依赖 B。Git 能自动应用反向补丁，也不能证明 C 在没有 B 的情况下仍能工作。

## 单提交 revert 的状态变化

```bash
git revert "$bad_commit"
```

Git 计算目标提交相对其父提交引入的变化，在当前 `HEAD` 上反向应用，并准备一条新 commit。终端交互运行时通常打开编辑器。提交说明应保留被回滚 ID，并补充事故原因、影响和恢复条件，不只留下自动生成的主题。

成功后发生以下变化：

- 原提交及后续提交保持不变；
- index 和工作区成为反向变化后的新 tree；
- 当前分支向前移动到 revert commit；
- 目标提交仍可沿父关系从新 `HEAD` 到达。

自动化环境需要明确跳过编辑器时可以使用：

```bash
git revert --no-edit "$bad_commit"
```

它保留 Git 生成的默认说明。真实事故通常需要更具体的原因，流水线可以先用 `--no-commit` 准备变化，再创建符合审计模板的提交。

## 完成后验证历史和最终 tree

记录新提交并检查关系：

```bash
revert_commit="$(git rev-parse HEAD)"
git show --stat --summary "$revert_commit"
git merge-base --is-ancestor "$bad_commit" "$revert_commit"
git status --short --branch
```

`merge-base --is-ancestor` 成功时没有输出，返回状态为 0，证明错误提交仍在新历史中。它不证明变化已经完全抵消。

若有已知正确提交或发布标签，可以比较 tree：

```bash
known_good="replace-with-the-verified-known-good-object-id"
git diff --stat "$known_good" "$revert_commit"
git diff "$known_good" "$revert_commit"
```

后续正确提交 C 可能让最终 tree 合理地不同于 B 之前的状态。不能把“与 A 完全相同”作为所有 revert 的统一验收。测试应覆盖错误行为、C 的后续行为、配置兼容和发布路径。

## 冲突表示当前上下文已经变化

后续提交修改了同一区域时，反向补丁可能冲突。先查看：

```bash
git status
git show --stat --summary REVERT_HEAD
git diff
```

`REVERT_HEAD` 指向当前正在撤销的提交。根据当前业务行为决定最终内容，解决并暂存后继续：

```bash
git add -- path/to/resolved-file
git revert --continue
```

决定放弃整个 revert 序列时：

```bash
git revert --abort
```

`--abort` 返回序列开始前的分支、index 和工作区状态。`git revert --quit` 只清除 sequencer 状态，保留当前 `HEAD`、index 和工作区，适合明确要手工接管现场的情况，不是 abort 的替代写法。

多个目标组成序列时，`--skip` 会跳过当前整条反向补丁并继续。只有确认该提交无需撤销时才使用，不能把它当作跳过冲突。

## 多个提交可以逐条回滚或合成一条

多个相关提交需要回滚时，最容易审计的方式是按依赖逆序逐条 revert，通常先撤销最新提交：

```bash
newer_bad_commit="replace-with-the-newer-full-object-id"
older_bad_commit="replace-with-the-older-full-object-id"
git revert "$newer_bad_commit"
git revert "$older_bad_commit"
```

每条反向提交分别记录目标和冲突，便于恢复其中一部分。如果发布系统要求一个原子回滚提交，可以使用 `--no-commit`：

```bash
git revert --no-commit "$newer_bad_commit" "$older_bad_commit"
git status
git diff --staged
git commit -m "revert: remove incomplete search rollout"
```

`--no-commit` 把反向变化应用到 index 和工作区，不自动创建 commit；它允许开始时 index 不等于 `HEAD`，因此更容易混入已有暂存内容。团队流程应要求开始前仍保持干净，并逐项核对最终 staged diff。

不要凭日期或一段范围字符串猜撤销顺序。先用 `git log --reverse` 或提交图确认依赖，再把确切 ID 明确列入操作记录。回滚两条内容相同或相互抵消的提交，结果可能与预期不同。

## 合并提交必须选择 mainline 父提交

merge commit 有两个或更多父提交，Git 无法自行判断要保留哪一侧。先查看父顺序和提交图：

```bash
merge_commit="replace-with-the-merge-commit-full-object-id"
git show --no-patch --format='commit %H%nparents %P%nsubject %s' "$merge_commit"
git rev-parse "${merge_commit}^1"
git rev-parse "${merge_commit}^2"
git log --graph --decorate --oneline --all --max-count=30
```

父编号从 1 开始。`-m 1` 表示把第一个父提交视为 mainline，反向应用 merge tree 相对第一个父 tree 引入的变化：

```bash
git revert -m 1 "$merge_commit"
```

`-m` 不是提交说明参数，也不是“通常写 1 就行”。第一个父往往是执行 merge 时所在分支，但 octopus merge、自动化生成历史或后续移植都需要根据实际父关系核对。

回滚 merge 还会影响未来合并语义。Git 历史仍记录原分支提交是 merge commit 的祖先，之后再次 merge 同一分支时，不会自动重新引入那些已有祖先的旧 tree 变化。需要重新启用时，通常先 revert 这条 merge-revert，或让功能分支产生新的修复提交，再按提交图设计合并。复杂情况应参考 Git 官方的 revert-a-faulty-merge 说明并在沙盒复现。

## 回滚完成后再次启用变化

单提交 revert 产生 R 后，再 revert R 可以重新应用原变化：

```bash
revert_to_reapply="replace-with-the-revert-commit-id"
git revert "$revert_to_reapply"
```

这会创建另一条新提交，历史完整保留。B 之后的代码、配置或数据状态可能已经变化，重新应用仍可能冲突或产生新的业务错误。不要把它描述成“取消按钮”，应重新走评审、测试和发布流程。

## Git 回滚与运行状态回退分开验证

revert 成功只说明源码分支新增了一条反向提交。完整事故流程还要回答：

- 哪个提交触发构建，生成了哪个制品摘要；
- 当前生产实例运行哪个制品；
- 数据库和消息格式是否允许旧代码运行；
- 已发生的外部副作用怎样补偿；
- 是先部署旧制品止血，还是等待 revert 后的新制品；
- 回滚后怎样验证错误率、数据完整性和积压。

远端分支普通 push 成功，也不能替代这些运行证据。发布章节会把提交、制品、部署和实例串成一条可审计链。

## 隔离实验覆盖普通、冲突和 merge revert

**前置条件**：Git 2.28 或更高版本、Bash、`mktemp` 和本书工作区。在仓库根目录执行：

```bash
./scripts/verify-revert.sh
```

脚本创建三个临时仓库：普通场景验证错误提交仍是 revert commit 的祖先，且后续正确文件保留；冲突场景验证 `REVERT_HEAD` 后执行 `--abort` 恢复原分支头和 tree；合并场景验证缺少 `-m` 会拒绝，选择第一个父为 mainline 后只移除合入分支带来的文件。

成功时输出：

```text
Single-commit revert, conflict abort, and merge mainline revert passed.
```

实验只验证本地 Git 历史与 tree，不连接远程，不模拟 CI、数据库或部署回退。对象 ID 和临时路径每次不同，断言失败时返回非零状态并清理实验目录。
