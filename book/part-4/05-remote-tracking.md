# 远程跟踪分支：本地保存的远端观察点

origin/main 看起来像一个分支名，但它不是你可以直接在服务器上提交的分支，也不是实时连接。它是当前仓库中的 refs/remotes/origin/main，记录最近一次成功通信后本地掌握的远端 main OID。

## 进入条件与完成标准

在已配置 origin 的 clone 根目录执行。先更新或记录 fetch 时间：

~~~bash
git remote get-url origin
git for-each-ref refs/remotes/origin/ --format='%(refname) %(objectname)'
git status --short --branch
~~~

读完本章后，你应能：

- 区分本地分支、远程跟踪分支和服务器分支；
- 用 OID、范围和祖先关系判断 ahead/behind/diverged；
- 解释 stale remote-tracking ref 的风险；
- 通过上游配置找到 status/pull 默认使用的引用；
- 处理远端分支重命名、删除、prune 和默认分支变化；
- 认识本地缓存不能替代平台评审、权限和部署状态。

## 三个相同名字背后的三个对象

以 main 为例：

~~~text
服务器仓库                  refs/heads/main -> S
                                  |
                                  | fetch
                                  v
本地仓库                  refs/remotes/origin/main -> S
                                  |
                                  | merge/rebase/pull
                                  v
                         refs/heads/main -> L
~~~

服务器的 refs/heads/main、当前仓库的 refs/remotes/origin/main 和当前仓库的 refs/heads/main 可能指向三个不同 OID。它们分别表示服务器事实、本地最后一次观察和本地工作位置。

查看本地两种引用：

~~~bash
git show-ref --verify refs/heads/main
git show-ref --verify refs/remotes/origin/main
git rev-parse main
git rev-parse origin/main
~~~

show-ref 失败时，可能是仓库还没有该分支、远程跟踪引用尚未 fetch，或者当前命名不同。不要通过创建同名分支掩盖缺失原因。

## 四种关系

### 一致

~~~text
A <- B
     ^
main, origin/main
~~~

本地工作分支和最后一次观察的远端引用相同。远端在这之后仍可能变化。

### 本地领先

~~~text
A <- B <- C  main
     ^
origin/main
~~~

C 是本地尚未发布的提交。查看：

~~~bash
git log --oneline origin/main..main
~~~

### 本地落后

~~~text
A <- B <- C  origin/main
     ^
    main
~~~

C 已在本地远程跟踪缓存中，但还没有整合到 main。查看：

~~~bash
git log --oneline main..origin/main
~~~

### 分叉

两边都有独有提交。用：

~~~bash
git log --left-right --graph --oneline main...origin/main
git merge-base main origin/main
~~~

范围输出属于本地 refs 之间的比较，不是服务器实时查询。

## ahead/behind 不是健康证明

status 或 branch -vv 可能显示 ahead、behind 或 diverged：

~~~bash
git status --short --branch
git branch -vv
~~~

这些数字来自本地上游引用。如果长时间没有 fetch，behind=0 只表示本地不知道新的远端提交；ahead=1 也不保证远端当前仍是旧 OID。

需要新鲜度时先 fetch，然后保存：

~~~bash
fetch_time="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
git fetch origin
git rev-parse origin/main
printf 'fetched_at=%s\n' "$fetch_time"
~~~

日期、OID 和主体一起进入协作记录，不能只保存终端上的 ahead 数字。

## 上游配置从哪里来

查看当前分支的上游：

~~~bash
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
git config --local --get-regexp '^(branch|remote)\.'
~~~

常见配置：

~~~ini
[branch "main"]
    remote = origin
    merge = refs/heads/main
~~~

上游把本地分支与哪个远程跟踪 ref 关联起来，供 status、pull 和无参数 push 使用。它不是服务器权限，也不会自动同步。配置可能来自 clone、branch --set-upstream-to 或人工修改，审计时保存来源。

修改上游：

~~~bash
git branch --set-upstream-to=origin/main main
~~~

这只改变本地配置。执行前确认 origin/main 是目标引用，避免把工作分支默认发布到错误仓库。

## 远端删除和分支重命名

远端删除分支后，本地 origin/old 可能仍存在：

~~~bash
git fetch --prune origin
git for-each-ref refs/remotes/origin/
~~~

prune 删除的是本地缓存引用，不是服务器数据、同名本地分支或对象。

远端把 main 重命名为 trunk 时，默认分支控制面、服务器 symbolic HEAD、本地 origin/HEAD 和各工作树上游都可能需要分别更新。可以先查询：

~~~bash
git remote set-head origin --auto
git symbolic-ref refs/remotes/origin/HEAD
git branch --set-upstream-to=origin/trunk main
~~~

set-head 和 set-upstream-to 都是本地配置/ref 动作，不证明平台默认分支设置已完成。平台控制面、保护规则、评审入口和 CI 触发器需要独立核对。

## 远程跟踪引用不是恢复备份

删除或重置 origin/main 后，远程跟踪引用本身的 reflog 和对象可能暂时存在，但这受配置和维护窗口影响。重要候选应保存：

~~~bash
git for-each-ref --format='%(refname) %(objectname)' refs/remotes/origin/
git bundle create remote-observation.bundle origin/main
~~~

bundle 的恢复和保留边界在第十一篇。不能把所有 remote-tracking refs 自动当作完整备份，隐藏 refs、LFS、评审数据和制品都不在其中。

## 失败路径

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| origin/main 不存在 | remote 名称、fetch refspec、show-ref | fetch 或使用实际分支名 |
| ahead/behind 与网页不同 | fetch 时间、两端 OID、平台页面 | 分开记录缓存和平台事实 |
| prune 后引用消失 | prune 输出、操作前 refs | 从远端重新 fetch 或恢复清单 |
| 上游指向错误分支 | branch -vv、branch/remote 配置 | 设置正确上游，不重写提交 |
| 远端分支被重命名 | ls-remote、symbolic HEAD、平台控制面 | 分阶段更新缓存、上游和策略 |
| 本地工作分支被误移动 | reflog、完整 OID、备份 | 先建立 recovery ref，再评估恢复 |

不要用 reset --hard 让 ahead/behind 归零，也不要把 origin/main 直接强制写成猜测的 OID。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-remotes.sh
~~~

实验验证 Alice 推送后 Bob 的 origin/main 更新而 main 保持原位，pull --ff-only 才整合，新增功能分支可以建立 upstream，标签可以显式推送到 bare server。它不验证服务器隐藏 refs、平台默认分支、权限、审计或复制延迟。

## 小结

远程跟踪分支是本地观察点，价值在于记录“上次通信时我知道什么”。先 fetch 再比较 OID，区分一致、领先、落后和分叉；上游只是本地默认关系。远端事实、平台控制面和本地缓存要分别取证。
