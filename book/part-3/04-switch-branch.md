# 创建和切换分支：移动 HEAD 前先保护工作区

分支操作经常被描述成“切换到另一份代码”。更准确的说法是：Git 把当前工作区上下文移动到另一个提交入口，同时尝试让 index 和工作区与目标快照一致。这个过程可能覆盖文件，所以切换前的状态检查比命令本身更重要。

## 进入条件与完成标准

准备一个已经提交的练习仓库，在根目录执行：

~~~bash
git status --short --branch
git rev-parse --verify HEAD^{commit}
~~~

工作区和 index 必须是你能解释的状态。若存在未提交内容，先提交、保存到临时位置或使用独立 worktree。不要用强制切换掩盖未知修改。

读完本章后，你应能：

- 分别使用 branch、switch、switch -c 和 detach；
- 证明创建分支不会切换 HEAD 或修改工作区；
- 解释切换时 index、工作区和分支引用各自发生什么；
- 处理未提交修改、未跟踪文件、路径冲突和分支已存在；
- 把旧教程中的 checkout -b、checkout <branch> 映射到现代命令；
- 在临时提交位于分离 HEAD 时先创建恢复引用。

## 只创建，不切换

在当前提交创建功能分支：

~~~bash
git branch feature/quick-start
git branch --list
git branch --show-current
git rev-parse refs/heads/feature/quick-start
git rev-parse HEAD
~~~

最后两个 OID 应相同，当前分支仍是原来的分支，工作区也没有变化。分支创建只写入一个 ref。

如果名称已存在，Git 会拒绝覆盖。先查看：

~~~bash
git show-ref --verify refs/heads/feature/quick-start
git log --oneline --decorate -1 feature/quick-start
~~~

不要为了重新开始直接删除同名分支。先确认它是否被其他工作树、评审或自动化使用。

## 切换到已有分支

~~~bash
git switch feature/quick-start
git branch --show-current
git symbolic-ref --short HEAD
git status --short --branch
~~~

成功后，HEAD 附着到 feature/quick-start。Git 用该分支尖端提交的 tree 更新 index，并把目标快照写入工作区。没有发生内容变化时，工作区文件的字节应与目标提交一致。

可以不依赖终端主题，直接比较：

~~~bash
git rev-parse HEAD
git rev-parse refs/heads/feature/quick-start
~~~

二者相等只能证明当前位置和分支尖端相同，不证明远端或其他分支是最新。

## 创建并立即切换

日常新建功能分支：

~~~bash
git switch --create feature/navigation
~~~

如果你想从指定提交开始：

~~~bash
git switch --create maintenance HEAD~1
~~~

这两个命令同时创建 ref、更新 HEAD、重建 index 并尝试更新工作区。创建失败时，Git 通常保持原分支和工作区，但应重新运行 status 验证，不要假定失败一定没有写入任何元数据。

如果目标分支名已经存在，switch --create 会拒绝。只有明确要重置该分支且已保存旧 OID 时，才在专用场景使用 switch --force-create 或等效的引用操作。覆盖分支会让其他协作者失去预期入口。

## 旧式 checkout 的对应关系

旧教程常见：

~~~bash
git checkout -b feature/navigation
git checkout feature/navigation
git checkout <commit-id>
~~~

它们分别大致对应：

~~~bash
git switch --create feature/navigation
git switch feature/navigation
git switch --detach <commit-id>
~~~

checkout 同时承担分支切换、分离 HEAD 和恢复路径等多种职责，旧脚本的参数含义要结合上下文判断。不要把所有 checkout 都机械替换成 switch，路径恢复场景应使用 restore 并重新审查来源。

## 切换前的工作区安全检查

目标分支会覆盖某个未提交路径时，Git 通常拒绝切换。先观察：

~~~bash
git status --short
git diff
git diff --staged
git ls-files --others --exclude-standard
~~~

按意图选择一种处理：

- 变化已经完整且属于当前工作线，先形成原子提交；
- 变化暂时不能提交，使用 stash 或独立 worktree；
- 变化只是临时实验，保存副本后再丢弃明确路径；
- 未跟踪文件与目标分支路径冲突，先移动或重命名到受控位置。

不要用 switch -f 或 checkout -f 作为第一反应。强制切换会覆盖工作区和 index 中无法保留的内容，恢复可能只能依赖编辑器、备份或文件系统快照。

## 分支提交和图形验证

在功能分支创建文件并提交：

~~~bash
printf '# Quick Start\n' > QUICKSTART.md
git add -- QUICKSTART.md
git diff --staged --check
git commit -m "docs: add quick start guide"
~~~

查看分支各自的位置：

~~~bash
git log --graph --decorate --oneline --all
git rev-parse main
git rev-parse feature/quick-start
git merge-base --is-ancestor main feature/quick-start
~~~

在尚未让 main 独立前进的练习中，feature/quick-start 通常包含 main，祖先判断退出码为 0。提交只移动当前功能分支，main 仍停留在创建分支时的 OID。

## 分离 HEAD 的安全离开

切换到一个提交进行检查：

~~~bash
git switch --detach HEAD~1
git status --short --branch
~~~

如果在这里创建了临时提交，离开前先保留名字：

~~~bash
git branch recovery/detached-check HEAD
git switch main
git show --no-patch recovery/detached-check
~~~

如果没有创建提交，直接切回分支即可。分离状态下的提交没有本地分支自动追踪，越晚建立恢复引用，越依赖 reflog 和对象保留窗口。

## 切换失败和恢复

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| local changes would be overwritten | status、工作区 diff、目标 tree | 保存或提交后重试，不强制覆盖 |
| untracked working tree files would be overwritten | 未跟踪路径、目标 tree | 移动未跟踪文件或先确认目标路径 |
| branch already exists | 分支 OID、worktree list、使用者 | 不覆盖，改用新名或经过审批的移动 |
| invalid reference name | check-ref-format、输入来源 | 修正名称，拒绝未经校验的 shell 拼接 |
| cannot lock ref | 进程、锁文件、并发 worktree | 停止并发写入，按锁流程处理 |
| detached HEAD 警告 | HEAD OID、reflog、是否有新提交 | 先创建 recovery 分支，再切回主线 |

切换命令失败时先检查 HEAD 是否仍指向原分支、index 是否仍可读、工作区是否发生部分变化。不要通过删除 index 或 .git 让命令“重新开始”。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-3-basics.sh
~~~

实验验证只创建分支不移动当前分支，switch 后 HEAD 与功能分支一致，功能提交留在功能分支，随后 main 可以对该分支做快进合并。它不验证强制切换的真实数据丢失、IDE 自动保存、网络文件系统或平台分支保护。

## 小结

branch 只创建引用，switch 才移动当前工作上下文。切换会同时涉及 HEAD、index 和工作区，遇到未提交内容先保存证据和字节，再决定提交、暂存、收纳或移动。分离 HEAD 可以用于检查，但临时提交必须先建立恢复名字。
