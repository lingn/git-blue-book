# 分支是引用：给提交位置一个可移动的名字

记住提交 OID 只适合短期定位。日常开发需要一个会随新提交移动的名字，这就是分支。分支不复制目录，也不把一组提交装进一个容器。它只是某个 ref，当前值通常是一个 commit OID。

## 进入条件与完成标准

在至少有一条提交的练习仓库根目录执行。先确认：

~~~bash
git status --short --branch
git rev-parse --verify HEAD^{commit}
~~~

工作区不干净时先保存现场。不要在真实项目里为了演示分支而删除未知来源的 ref。

读完本章后，你应能：

- 说明 `refs/heads/<name>` 与提交对象的关系；
- 在不切换工作区的情况下创建、检查和删除本地分支；
- 从指定提交创建分支，判断分支是否包含某个提交；
- 区分本地分支、远程跟踪分支和标签；
- 解释删除分支为什么不等于立刻删除对象；
- 处理非法名称、分支已存在和未合并删除等失败路径。

## 分支引用只保存一个当前位置

假设提交图是：

~~~text
A <- B <- C
          ^
          main
~~~

`main` 实际上是 `refs/heads/main` 的简写，值是 C 的 OID。创建新提交 D 后，当前分支引用更新为 D：

~~~text
A <- B <- C <- D
               ^
               main
~~~

A、B、C 并没有被修改。分支移动是引用写入，提交创建是对象写入，两者经常同时发生但不是同一件事。

查看引用和值：

~~~bash
git branch --list
git show-ref --heads
git for-each-ref refs/heads/ --format='%(refname) %(objectname)'
~~~

`git branch` 的星号表示当前 `HEAD` 所在的分支，不表示该分支是全仓库最新。完整 ref 名适合审计和脚本，短名适合交互阅读。

## 创建分支不会切换工作区

在当前提交创建功能分支：

~~~bash
git branch feature/quick-start
git branch --verbose --no-abbrev
git branch --show-current
~~~

预期新分支和当前分支指向同一个完整 OID，当前分支仍未改变。工作区和 index 也不会因为创建分支而变化。

也可以从指定提交创建：

~~~bash
git branch maintenance HEAD~1
git show-ref --verify refs/heads/maintenance
~~~

`HEAD~1` 必须存在父提交。仓库历史太短时命令会失败，保留原始状态即可；不要为了让相对写法可用而造出空提交。

分支名中的斜杠只是 ref 名的一部分。例如 `feature/login` 不是一个工作区目录，也不决定平台评审或权限。

## 分支名的安全边界

分支名必须符合 Git 的 ref 命名规则。不能包含空格控制字符、连续点、以点或斜杠结尾，不能包含 `..\\`、`@{` 等特殊片段，也不能是单独的 `@`。不同文件系统和服务器对大小写、Unicode、路径长度的处理也可能不同。

创建前可以只在本地验证：

~~~bash
git check-ref-format --branch feature/quick-start
~~~

退出码 0 表示名称可作为分支名，非零表示非法或参数错误。远端平台可能再施加保留字、长度或命名策略，不能用本地通过替代服务端验收。

避免把用户输入未经校验直接拼到 shell 命令。脚本应使用安全的参数数组或固定前缀，并拒绝以短横线开头的未验证字符串。

## 分支包含什么历史

分支只指向尖端提交。它“包含”的历史是从该提交沿父关系可达的提交集合：

~~~bash
git merge-base --is-ancestor <commit> feature/quick-start
git branch --contains <commit>
git branch --merged main
git branch --no-merged main
~~~

这些命令依赖本地 refs 和对象。`--contains` 不能证明远程平台或其他 clone 已经看到相同历史，`--merged` 也不等于某个平台的合并请求状态。

判断分支是否已经合入时使用 OID 和祖先关系，不要比较分支名、最后提交时间或文件当前内容。两条分支可能内容相同但历史不同，也可能历史包含关系成立而工作区因 sparse 或过滤器看起来不同。

## 本地分支、远程跟踪分支和标签

| 名称 | 典型 ref | 会随本地提交自动移动吗 | 作用 |
| --- | --- | --- | --- |
| 本地分支 | `refs/heads/main` | 当前检出时会 | 开发工作线入口 |
| 远程跟踪分支 | `refs/remotes/origin/main` | 只有 fetch 等更新它时 | 本地保存的远程观察点 |
| 标签 | `refs/tags/v1.0.0` | 不会 | 稳定标记某个对象 |
| 特殊引用 | `HEAD`、`MERGE_HEAD` 等 | 由操作状态管理 | 当前上下文或进行中操作 |

创建 `feature/quick-start` 不会创建 `origin/feature/quick-start`。要让远程可见，需要 push，并受认证、授权和接收端规则控制，详见远程篇。

## 删除分支的含义

删除本地分支：

~~~bash
git branch -d feature/quick-start
~~~

小写 `-d` 会检查该分支的提交是否已在当前可见历史中合入；如果还有未合并提交，Git 会拒绝。被拒绝时先查看：

~~~bash
git log --oneline --decorate --graph --all
git branch --no-merged main
~~~

只有确认提交已备份、标签或其他 ref 仍能到达，才考虑强制 `-D`。强制删除只删除 ref 名，不会立即擦除对象，但会减少恢复入口，并可能在后续维护后丢失不可达对象。书稿练习不使用 `-D`。

删除当前分支会失败，因为 `HEAD` 仍需要一个有效的当前位置。先切换到明确的接收分支，再删除。

## 从误删分支恢复

发现分支误删后，先查引用日志：

~~~bash
git reflog --all --date=iso-strict
git fsck --no-reflogs --unreachable
~~~

找到正确 OID 后先建立恢复引用，不要立即切换或重写：

~~~bash
git branch recovery/quick-start <full-commit-id>
git show --no-patch --format=fuller recovery/quick-start
~~~

恢复引用只是把已有对象重新挂到一个名字上。它不证明该对象曾经推送到远程，也不替代外部备份和平台审计。reflog 的保留时间和对象清理窗口受配置与维护影响，越早建立恢复引用越可靠。

## 失败路径

| 现象 | 原因候选 | 处理 |
| --- | --- | --- |
| branch already exists | 名称已有 ref | 先查看其 OID 和用途，不覆盖 |
| not a valid branch name | ref 规则或平台命名限制 | 使用经过校验的新名称 |
| 删除被拒绝 | 分支有未合入提交 | 先备份并评估，再决定保留或强制删除 |
| 不能删除当前分支 | `HEAD` 正指向它 | 切换到已确认的其他分支 |
| bad object | 起点拼错、浅边界或对象缺失 | 验证 OID、浅状态和对象库 |
| 分支列表与网页不同 | 本地 refs 过期或平台控制面不同 | 记录 fetch 时间并分开核对 |

错误时保存命令、当前目录、完整 OID 和 stderr。不要用 `git branch -D`、`reset --hard` 或删除 `.git` 作为通用修复。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-3-basics.sh
~~~

实验验证创建分支不改变当前分支，切换后 `HEAD` 与分支关系正确，功能提交只移动功能分支，快进合并后两个本地分支指向同一提交，最后删除已合入分支。实验使用临时仓库和合成身份，不验证远端分支创建、平台命名规则、权限或评审状态。

## 小结

分支是保存一个提交 OID 的可移动引用。创建分支不会复制文件，提交时当前分支才向前移动；判断合入关系要沿父提交检查可达性。删除分支删的是名字，恢复依赖其他引用、reflog、对象保留和备份，不应把短暂可见当作永久保障。
