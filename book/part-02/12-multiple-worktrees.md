# 同时维护多个工作目录：worktree 的共享与隔离

本章是 v2 第二篇补充内容。linked worktree 共享对象库和大部分 refs，不能当作权限、运行环境或异地备份边界。

当功能分支需要运行服务、主线又要处理修复时，反复 stash 和切换会增加状态风险。worktree 允许同一个 Git 仓库拥有多个工作目录，每个目录有自己的工作区、index 和 HEAD，同时共享对象库和大部分引用。

它解决的是本地工作目录并行，不是权限隔离、构建环境隔离或远程副本隔离。

## 进入条件与完成标准

在一个已提交且工作区可解释的仓库根目录执行。开始前检查：

~~~bash
git status --short --branch
git rev-parse --git-common-dir
git worktree list --porcelain
git rev-parse --verify HEAD^{commit}
~~~

准备一个仓库外、尚不存在的工作树路径。不要把另一个真实项目目录作为目标，也不要把 worktree 当作备份目录。

读完本章后，你应能：

- 区分主工作树、linked worktree、common Git directory 和每树独有状态；
- 安全创建、查看、锁定、移动和移除 worktree；
- 解释同一分支为什么默认不能同时在两个工作树检出；
- 在并发提交、共享 refs、对象维护和误删除后恢复；
- 判断 worktree 何时比 stash 更适合；
- 识别 worktree 不提供的安全与环境边界。

## worktree 的数据模型

假设主工作树和一个热修复工作树：

~~~text
仓库 common dir
├── objects/              所有工作树共享
├── refs/                 大部分分支和标签共享
└── worktrees/
    └── hotfix/           linked worktree 的管理元数据

主目录
├── .git -> common dir
├── HEAD                  主工作树独有
└── index                 主工作树独有

热修复目录
├── .git                  指向 worktrees/hotfix 的文件
├── HEAD                  热修复工作树独有
└── index                 热修复工作树独有
~~~

具体布局会因普通仓库、分离 Git 目录和 Git 版本变化。权威查询是：

~~~bash
git rev-parse --git-dir
git rev-parse --git-common-dir
git rev-parse --git-path HEAD
git rev-parse --git-path index
git worktree list --porcelain
~~~

多个工作树共享对象库，因此一个工作树的提交可以被另一个工作树看到。它们也共享大多数 refs，移动同一个分支仍然是共享写入，不是完全隔离。

## 创建一个热修复工作树

在主仓库根目录执行：

~~~bash
git fetch origin
git worktree add ../project-hotfix -b hotfix/payment origin/main
~~~

这条命令创建相邻目录、从 origin/main 创建 hotfix/payment，并在新目录检出该分支。执行前确认：

- 目标路径不存在，或符合团队允许的空目录规则；
- origin/main 是已更新且可信的本地远程跟踪 ref；
- hotfix/payment 没有被其他工作树或协作者使用；
- 当前主工作树的未提交内容已经保存。

验证新树：

~~~bash
git -C ../project-hotfix status --short --branch
git -C ../project-hotfix branch --show-current
git -C ../project-hotfix rev-parse --git-dir
git -C ../project-hotfix rev-parse --git-common-dir
git worktree list --porcelain
~~~

新树的工作区和 index 由目标提交初始化。创建操作可能写 common dir、worktrees 管理文件和新分支 ref，不能称作纯只读查询。

## 在不同工作树中工作

在热修复树中提交：

~~~bash
cd ../project-hotfix
printf 'hotfix fixture\n' > FIX.md
git add -- FIX.md
git diff --staged --check
git commit -m "fix: add payment correction"
git rev-parse HEAD
~~~

回到主工作树：

~~~bash
cd -
git status --short --branch
git rev-parse hotfix/payment
~~~

主工作树的当前分支、index 和未提交修改不会因为热修复树的工作区变化而自动切换。它仍然可以通过共享 ref 和对象看到 hotfix/payment 的新提交。

两个工作树不能默认同时检出同一个本地分支：

~~~bash
git worktree add ../duplicate-main main
~~~

通常会被拒绝，以避免两个 index 同时移动 refs/heads/main。拒绝是保护机制，不要直接使用 --force 或 --ignore-other-worktrees。

## 共享与隔离边界

| 内容 | 是否共享 | 影响 |
| --- | --- | --- |
| objects、pack、commit-graph | 是 | 维护和磁盘容量属于共同仓库 |
| 大多数 refs | 是 | 一个工作树移动分支，其他树可见 |
| HEAD | 否 | 每个工作树可处于不同分支或分离状态 |
| index | 否 | 暂存内容和冲突状态各自独立 |
| 工作区文件 | 否 | 不同目录可同时编辑不同版本 |
| hooks/config | 部分共享 | common config、worktree config 和 hooks 路径需单独核对 |
| 进程、环境变量、构建缓存 | 否 | 仍可能通过端口、数据库和外部资源互相影响 |

worktree 不是容器。多个工作树仍可能使用同一数据库、消息队列、端口、凭据、制品缓存和远程 ref。高风险命令的并发保护仍需团队规则。

## 锁定和移动工作树

长时间离线或即将移动目录时，可以锁定：

~~~bash
git worktree lock --reason "offline release investigation" ../project-hotfix
git worktree list --porcelain
~~~

锁定防止某些 prune 或移动操作误认为工作树已失效。解锁：

~~~bash
git worktree unlock ../project-hotfix
~~~

移动到新路径：

~~~bash
git worktree move ../project-hotfix ../project-hotfix-archive
git worktree list --porcelain
~~~

移动前确认目标不存在、工作树没有运行中的构建和服务，并在移动后验证 git-dir、common-dir、HEAD 和 index。手工移动目录可能留下过期管理记录，不要在未核对时运行 prune。

## 安全移除和失效记录

完成热修复并确认提交已保留后：

~~~bash
git -C ../project-hotfix status --short --branch
git show --no-patch --format='%H%n%P%n%s' hotfix/payment
git worktree remove ../project-hotfix
git worktree list --porcelain
~~~

remove 会删除目标工作目录及其管理记录，默认不删除 hotfix/payment 分支。若工作区不干净，Git 通常拒绝移除。强制移除会删除未提交文件，必须先备份并得到明确授权。

如果目录被外部工具删除，管理记录可能仍在：

~~~bash
git worktree list --porcelain
git worktree prune --dry-run
git worktree prune
~~~

prune 删除 Git 认为失效的管理元数据，不会恢复已经删除的工作区文件。事故调查时先保存 worktree 清单和路径，再决定是否清理；不要把 prune 当成普通收尾命令。

## worktree 与 stash 的选择

| 场景 | 更适合的选择 | 原因 |
| --- | --- | --- |
| 几分钟内切换，改动少 | stash | 操作快，目录数量少 |
| 功能分支要运行服务，主线也要修复 | worktree | 两套工作区和 index 独立 |
| 需要长期协作和评审 | 分支与提交 | 让历史、责任和验证可追踪 |
| 需要跨设备或灾难恢复 | bundle/备份 | worktree 共享本地对象，不是异地副本 |
| 需要安全执行不受信任代码 | 隔离环境 | worktree 不隔离 hooks、filters、凭据和宿主资源 |

## 并发与维护风险

一个工作树运行 maintenance 或 repack 时，其他树的 Git 命令可能受到对象锁和磁盘竞争影响。一个工作树执行条件 ref 更新，另一个工作树的上游观察可能立即变旧。检测和恢复时记录：

~~~bash
git worktree list --porcelain
git for-each-ref --format='%(refname) %(objectname)'
git count-objects -v
git rev-parse --git-common-dir
~~~

不要在任意工作树里同时执行清理、强制改写或删除共享 ref。确认 active writer、锁和协作者状态后再行动。

## 失败路径和恢复

| 现象 | 先收集 | 恢复 |
| --- | --- | --- |
| target path already exists | 目录清单、所有权、是否为空 | 换明确的新路径 |
| branch is already checked out | worktree list、HEAD、分支使用者 | 使用新分支或切换拥有者 |
| remove 被拒绝 | status、未提交 diff、分支 OID | 备份或提交后再移除 |
| worktree 列表有失效路径 | 管理记录、路径是否被手工删除 | 确认无进程后 prune |
| common dir 找不到 | git-dir、git-common-dir、.git 内容 | 修复路径引用，不删除管理目录 |
| 两树同时改同一共享 ref | reflog、ref OID、进程 | 暂停并发写入，按 expected-old 恢复 |
| 热修复目录文件丢失 | 提交、stash、文件系统备份 | 从 refs/对象/备份恢复，不能依赖 prune |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-6-engineering.sh
~~~

实验验证创建 linked worktree、在热修复树提交后主树可读取分支 OID，并安全移除工作树。它不验证容器隔离、端口/数据库冲突、网络文件系统租约、跨设备备份或真实并发崩溃。

## 小结

worktree 让一个仓库拥有多套独立工作区、index 和 HEAD，适合同时维护功能和热修复。对象和大部分 refs 仍然共享，工作树不是备份或安全沙箱。创建、移动和移除前后都要核对路径、分支、状态和共同 Git 目录，遇到并发先保护共享引用。
