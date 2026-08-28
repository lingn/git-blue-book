# pull 实际组合了哪两步：获取与整合必须分开诊断

pull 不是一个不可解释的“同步按钮”。它通常先执行 fetch，再把取到的上游历史通过快进、merge 或 rebase 整合进当前分支。两阶段分别改变不同状态，出错时必须知道停在哪一步。

## 进入条件与完成标准

在已配置上游的本地分支根目录执行。开始前保存：

~~~bash
git status --short --branch
git branch -vv
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
~~~

工作区和 index 如果不干净，先决定如何保护。pull 可能更新本地远程跟踪 ref，也可能启动合并或变基，不应在未确认状态下运行。

读完本章后，你应能：

- 把 pull 拆成 fetch 和 integrate 两个阶段；
- 解释 pull 成功或失败后本地哪些 refs、index 和工作区可能变化；
- 使用 ff-only、merge 和 rebase 选择整合策略；
- 处理 fetch 已成功但整合冲突、hook 拒绝和上游未配置；
- 认识自动暂存、配置默认值和远程新鲜度的边界；
- 在共享分支上避免用 pull 作为无审查的历史改写工具。

## 先拆开看一遍

在工作区干净、上游为 origin/main 时，最容易审查的流程是：

~~~bash
git fetch origin
git log --graph --decorate --oneline --all
git merge origin/main
~~~

fetch 更新 origin/main 和对象库，log 只读比较，merge 才决定是否移动本地当前分支。拆开后可以在整合前检查候选提交、冲突风险和测试基线。

pull 通常相当于：

~~~text
pull = fetch + (fast-forward | merge | rebase)
~~~

实际使用的远程和 refspec 来自 branch/remote 配置、命令参数和版本默认值。不要把这行等式理解成所有 Git 版本都使用同一个策略。

## 快进、合并和变基

### 只允许快进

~~~bash
git pull --ff-only
~~~

远端缓存的上游提交是当前 HEAD 的后继时，命令移动当前分支；如果双方分叉，命令拒绝且不创建 merge commit。它适合希望主线历史保持线性的团队，但不能替代先核对上游是否新鲜。

### 使用合并提交

~~~bash
git pull --no-rebase
~~~

获取后按 merge 整合，分叉时可能创建合并提交。是否允许自动创建 merge commit 属于团队策略。出现冲突时会进入 MERGE_HEAD 状态，按冲突章节处理。

### 使用变基

~~~bash
git pull --rebase
~~~

获取后把本地独有提交重新应用到上游之后，生成新 commit。已经分享的本地提交可能被改写，之后推送还涉及租约和协作者同步。不要在共享主线或不了解分支所有权时设置全局 rebase 默认。

`branch.<name>.rebase`、`pull.rebase` 和命令选项可能共同决定策略。审查时查看配置来源：

~~~bash
git config --show-origin --show-scope --get-regexp '^(pull|branch\..*\.rebase)'
~~~

## pull 成功后的状态变化

快进成功通常改变：

- 当前本地分支 ref；
- index；
- 工作区文件；
- origin/main 等远程跟踪 ref（fetch 阶段）。

merge 成功还会写入新的 merge commit 和父关系。rebase 成功会创建新的 commit 并移动当前分支，原提交可能只由 reflog 或其他 refs 保留。

成功后核对：

~~~bash
git status --short --branch
git rev-parse HEAD
git rev-parse '@{upstream}'
git log --graph --decorate --oneline --all
~~~

“已经 up to date”只表示 fetch 后没有需要整合的提交，不能证明工作区没有未跟踪文件，也不能证明外部平台、CI 或部署状态正常。

## pull 失败的两个阶段

### fetch 阶段失败

URL、DNS、服务器身份、认证、授权、网络或对象传输错误会在 fetch 阶段发生。此时可能没有更新远程跟踪 ref，也可能留下部分对象。先保存原始 stderr、远程配置和对象统计，不要 reset 当前工作。

### 整合阶段失败

fetch 已成功更新 origin/main 后，merge/rebase 可能因为冲突、hook、提交说明或工作区覆盖而停止。判断状态：

~~~bash
git status --short --branch
git rev-parse --verify MERGE_HEAD
git rev-parse --verify REBASE_HEAD
git rebase --show-current-patch
git ls-files --unmerged
~~~

MERGE_HEAD 和 REBASE_HEAD 不会同时代表同一种操作。先根据 status 判断是哪一个状态机，再使用 merge --abort 或 rebase --abort。不要把两个 abort 命令混用。

## 工作区不干净与 autostash

pull 默认可能拒绝覆盖本地修改。某些配置允许：

~~~bash
git pull --rebase --autostash
~~~

autostash 会把本地修改暂存到一个临时 stash，再尝试在整合后应用。应用阶段仍可能冲突，stash 也可能丢失可见入口。使用前保存 status、diff 和 stash 清单，生产自动化要明确允许的副作用。

不要用 reset --hard 为 pull 清空工作区。无法判断本地改动是否属于当前任务时，先提交临时节点、使用 stash 或独立 worktree。

## 上游未配置

没有上游时，git pull 可能提示没有跟踪信息。先查看：

~~~bash
git branch -vv
git config --local --get-regexp '^(branch|remote)\.'
~~~

确认应跟踪的远程和分支后设置：

~~~bash
git branch --set-upstream-to=origin/main main
~~~

这只修改本地配置，不会连接远端或移动提交。不要因为命令要求上游就随意把 main 绑定到第一个 origin/main。

## 远程新鲜度和 pull 竞态

pull 的 fetch 和整合不是一个不可分割的服务器事务。fetch 完成后，其他协作者仍可能更新远端；你的 push 也可能在整合后被 non-fast-forward 拒绝。发布或高风险修复应保存 fetch 时刻、上游 OID、当前 HEAD 和整合后的新 OID，必要时使用显式租约。

合并队列、评审审批、保护规则和 CI 结果属于平台控制面，pull 不会替你等待或验证它们。

## 失败路径和恢复

| 现象 | 先收集 | 恢复 |
| --- | --- | --- |
| no tracking information | branch -vv、上游配置、远程 refs | 确认目标后设置 upstream |
| fetch 认证/网络失败 | remote URL、凭据来源、原始 stderr | 修复传输层，不改本地提交 |
| pull 冲突 | FETCH_HEAD、MERGE_HEAD/REBASE_HEAD、index stages | 按对应状态机解决或 abort |
| autostash 应用冲突 | stash 清单、工作区 diff、整合 OID | 保留 stash，逐路径恢复和测试 |
| ff-only 拒绝 | 两端 OID、merge-base | 明确选择 merge/rebase，不强推 |
| pull 后历史被改写 | pull 策略、reflog、旧 OID | 建立恢复引用，按共享边界评估 |

错误时不要反复执行同一 pull，不要把强推当作整合失败的修复，也不要删除 .git 状态文件。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-remotes.sh
~~~

实验验证 Bob 在 fetch 后本地 main 不变、origin/main 前进，随后 pull --ff-only 才完成快进；它还验证 upstream 的建立和 tag 的显式传输。实验使用本地 bare server，不模拟真实网络、autostash、平台合并队列、CI、保护分支或身份系统。

## 小结

pull 把网络获取和本地整合放在一次命令中，因此方便但不透明。需要审查和排障时先拆成 fetch、查看、merge/rebase；成功后分别核对 refs、index、工作区和测试，失败时根据 MERGE_HEAD 或 REBASE_HEAD 选择恢复路径。
