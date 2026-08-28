# 查看和管理远程地址：remote 配置也是状态

remote 命令管理的是当前仓库如何找到其他仓库。它修改本地配置和 remote-tracking refs，不会搬运远程仓库，也不会自动改变当前工作分支。一个 URL 写错，可能让 fetch 读到错误项目，也可能让 push 把对象发往错误位置，所以修改前后都要留下证据。

## 进入条件与完成标准

在一个已配置远程的练习仓库根目录执行。可以使用第四篇的本地 bare 仓库，或一个只读 URL。远程地址可能含组织内部路径、用户名或令牌，输出转发前必须脱敏。

读完本章后，你应能：

- 区分 remote 名称、fetch URL、push URL 和 refspec；
- 查询远程配置的来源并判断当前命令将连接哪里；
- 添加、修改、重命名和删除本地 remote；
- 解释 remote remove 不会删除服务器仓库；
- 处理 URL 写错、多个远程、只读镜像和推送目标错配；
- 在变更前后核对远端 refs 与本地缓存，而不是依赖名称直觉。

## remote 名称只是本地别名

查看名称：

~~~bash
git remote
git remote -v
git remote get-url origin
git remote get-url --push origin
~~~

clone 默认把来源命名为 origin，但 origin 不是“中央仓库”的保留字，也没有特殊权限。你可以把个人派生仓库叫 origin，把原项目叫 upstream，也可以配置多个远程。

同一个 remote 可以有多个 fetch URL，也可以单独配置 push URL。get-url 默认可能只显示第一个值；脚本要明确是否使用 --all：

~~~bash
git remote get-url --all origin
git remote get-url --push --all origin
~~~

URL 的显示只证明本地配置，不证明服务器存在、当前账号可访问或 URL 没有被代理改写。

## 查看配置来源和 refspec

~~~bash
git config --show-origin --show-scope --get-regexp '^remote\.origin\.'
git config --local --get-all remote.origin.fetch
git config --local --get-all remote.origin.pushurl
~~~

常见 fetch refspec 类似：

~~~text
+refs/heads/*:refs/remotes/origin/*
~~~

左侧是远程仓库的引用，右侧是本地保存的远程跟踪引用。前面的加号表示允许更新本地目标 ref，即便不是快进；这只描述 fetch 对本地缓存的更新，不等于 push 可以覆盖服务器分支。refspec 的通配、负 refspec 和受限范围在第十四章处理。

不要只看 remote -v 就声称知道 fetch/push 范围。一个 remote 可能有自定义 refspec、tag 选项、镜像模式和不同 URL。

## 添加第二个远程

在确认 URL 和所有权后：

~~~bash
git remote add upstream <repository-url>
git remote
git config --get-regexp '^remote\.upstream\.'
~~~

remote add 修改当前仓库的 .git/config，不创建对象、不更新工作区，也不连接服务器。后续 fetch upstream 才会发生通信。

如果 URL 中包含凭据，禁止把它直接写入 shell 历史或仓库配置。优先使用凭据助手、短期令牌或 SSH agent，并按安全篇的最小权限规则配置。

## 修改和重命名远程

先保存原值：

~~~bash
old_url="$(git remote get-url origin)"
git remote set-url origin <correct-repository-url>
git remote get-url origin
~~~

set-url 只修改本地配置。执行后应再次核对 fetch 和 push URL，确认没有只改一侧：

~~~bash
git remote get-url origin
git remote get-url --push origin
git config --show-origin --show-scope --get-regexp '^remote\.origin\.'
~~~

重命名本地别名：

~~~bash
git remote rename upstream source
git remote
~~~

rename 会更新与该 remote 关联的 remote-tracking refs 名称和配置键，具体迁移结果应以 git remote 和 refs 清单验证。它不重命名服务器项目，也不改变提交对象。

## 删除 remote 的边界

~~~bash
git remote remove source
~~~

remove 删除当前仓库中的 remote 配置和对应远程跟踪引用。它不会删除服务器仓库、服务器分支、评审、制品或其他 clone 的对象。因为本地缓存入口会消失，删除前先保存 refs 和 URL：

~~~bash
git for-each-ref refs/remotes/source/
git remote get-url source
~~~

如果 remote 名称写错，命令会失败，不要为了清理而扩大到其他 remote。恢复时可以用原 URL 重新 add，但远程跟踪引用可能需要重新 fetch 才能回来。

## remote show 不是纯本地查询

~~~bash
git remote show origin
~~~

这条命令可能访问网络，报告远端 HEAD、跟踪分支和推送状态。网络失败只能说明本次查询无法完成，不代表本地对象库损坏。若需要不访问网络的证据，使用 remote get-url、show-ref 和 for-each-ref；若要服务器事实，记录访问时间、主体和原始错误。

## 多远程的同步边界

配置 origin 和 upstream 后：

~~~bash
git fetch origin
git fetch upstream
git log --oneline --left-right origin/main...upstream/main
~~~

两个 fetch 分别更新不同的本地 remote-tracking refs，不会互相合并。若它们指向同一仓库的不同镜像，差异可能来自复制延迟、可见性、refspec 或权限。不要用 remote 名字推断哪边一定权威，先登记所有权和用途。

## URL 错误的恢复

| 现象 | 先收集 | 恢复 |
| --- | --- | --- |
| repository not found | remote get-url、主体、仓库路径 | 在本地修正 URL，重新验证可见性 |
| fetch 得到意外分支 | fetch refspec、远端 refs、服务器响应 | 停止整合，核对来源和权限 |
| push 发往错误目标 | fetch/push URL、命令、服务器 ref | 立即停止后续推送，通知目标仓库负责人 |
| remote remove 后 refs 不见 | 操作前 ref 清单、本地配置 | 重新 add/fetch；不能把缓存当备份 |
| 多个 remote 状态不同 | 各自 OID、fetch 时间、refspec | 按用途分别比较，不自动覆盖 |
| URL 含秘密 | 配置文件、shell history、日志副本 | 先撤销/轮换凭据，再清理暴露副本 |

修改 URL 不会撤回已经推送的对象，也不会修复远端错误引用。涉及真实泄漏时直接进入凭据撤销和历史清理流程。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-remotes.sh
~~~

实验验证 clone 产生 origin，remote-tracking ref 的名称和本地分支分开，file URL 传输可以 fetch、pull、push 和推送 tag。它不验证真实 HTTPS/SSH 证书、凭据助手、代理、平台隐藏 refs、组织授权或远端控制面。

## 小结

remote 管理的是当前仓库的连接配置和本地远程观察点。名称不是权威，URL 不是权限，remote -v 也不是服务器实时状态。每次添加、修改、重命名或删除 remote，都先保存配置与 refs，再分别验证 fetch 目标、push 目标和本地缓存。
