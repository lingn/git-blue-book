# 只获取，不整合：fetch 的对象和引用变化

fetch 是远程协作中的观察动作。它把远端可见的新对象和引用信息带回本地，更新 remote-tracking refs 和 FETCH_HEAD，但不会自动把远程历史合入当前工作分支。理解这个边界，可以避免把“已经获取”误报成“已经同步”。

## 进入条件与完成标准

在已配置 origin 的仓库根目录执行。先保存当前引用和工作区：

~~~bash
git status --short --branch
git rev-parse HEAD
git rev-parse --verify origin/main^{commit} || true
~~~

fetch 需要远端地址、网络或可访问的本地仓库。真实传输还需要服务器身份校验、客户端认证和仓库授权；本章实验使用本地 bare 仓库。

读完本章后，你应能：

- 说明 fetch 下载什么、更新什么、不会改变什么；
- 区分 remote-tracking ref、FETCH_HEAD 和本地工作分支；
- 读取新增、删除和强制更新的 ref 状态；
- 用 prune 处理远端删除的缓存引用；
- 判断 fetch 失败后哪些本地状态仍可用；
- 在 fetch 后基于 OID、范围和 merge-base 选择整合动作。

## fetch 的状态变化

执行：

~~~bash
git fetch origin
~~~

一次成功 fetch 可能：

- 从远端传输本地缺少的 commit、tree、blob、tag 等对象；
- 更新 refs/remotes/origin/*；
- 写入或更新 FETCH_HEAD；
- 按 refspec 删除被 prune 的本地远程跟踪引用。

它通常不会：

- 移动 refs/heads/main 或当前其他本地分支；
- 把远端文件写进当前工作区；
- 自动创建合并提交或重放本地提交；
- 自动上传本地对象。

获取前后保存 OID：

~~~bash
before="$(git rev-parse --verify origin/main^{commit})"
git fetch origin
after="$(git rev-parse --verify origin/main^{commit})"
printf '%s -> %s\n' "$before" "$after"
git rev-parse HEAD
~~~

HEAD 的 OID 不变只说明当前分支没有被 fetch 移动。若远端没有新提交，before 与 after 相同；若有更新，after 可能变化。FETCH_HEAD 是本次获取结果的记录，不能替代长期 remote-tracking ref。

## 输出怎样读

典型输出可能类似：

~~~text
abc1234..def5678  main -> origin/main
* [new branch]     feature/search -> origin/feature/search
- [deleted]        (none) -> origin/old
~~~

短 OID 和箭头只是摘要。精确证据使用：

~~~bash
git for-each-ref refs/remotes/origin/ --format='%(refname) %(objectname) %(objecttype)'
git show-ref --verify refs/remotes/origin/main
git rev-parse --verify FETCH_HEAD^{commit}
~~~

输出文本会因 Git 版本、终端和语言改变。脚本不要解析整行摘要来判断成功，应读取 ref OID 和命令退出码。

## 获取后如何判断本地差异

假设 origin/main 已更新：

~~~bash
git log --oneline main..origin/main
git log --oneline origin/main..main
git merge-base main origin/main
git merge-base --is-ancestor main origin/main
~~~

第一条是远端缓存中本地 main 没有的提交，第二条是本地 main 有而缓存没有的提交。祖先判断的退出码应按 0、1、其他错误分流。

fetch 只更新“本地知道的远端状态”。它成功后仍可能受到服务器隐藏 refs、复制延迟、权限范围和查询竞态影响。需要远端实时事实时，另行执行受控远端查询并记录时间。

## FETCH_HEAD 的短期语义

不带特殊 refspec 的 fetch 会把本次获取的结果写入 .git/FETCH_HEAD。查看：

~~~bash
git show-ref --head
sed -n '1,20p' .git/FETCH_HEAD
~~~

FETCH_HEAD 可能包含多个远端头、是否可合并的标记和 URL 来源。后续 pull 或 merge 可以使用它，但另一次 fetch 会覆盖或追加不同内容。它不是长期审计日志，发布和事故记录应把完整 OID、远端名称、refspec 和时间写入受控清单。

## prune 处理删除缓存

服务器删除 origin/old 后，本地缓存可能仍保留。显式清理：

~~~bash
git fetch --prune origin
~~~

prune 删除本地 refs/remotes/origin/old，不删除同名本地分支、标签、对象或服务器数据。执行前保存 remote-tracking refs，尤其是镜像和事故调查场景。错误的 remote 或 refspec 可能把仍有价值的本地观察点删掉。

如果只想查看将要清理的引用，先用：

~~~bash
git remote prune origin --dry-run
~~~

不同 Git 版本对 dry-run 支持略有差异，失败时保留原始输出，不直接执行删除。

## 标签的获取边界

相关分支历史中的可达标签可能在 fetch 时一并取得。需要明确所有远端标签：

~~~bash
git fetch --tags origin
~~~

--tags 会扩大获取的引用和对象范围，可能增加网络与本地容量。它不会把本地标签自动推回远端，也不保证获取平台私有或隐藏的 tag refs。

## fetch 失败时本地发生了什么

传输可能在认证、网络、中断、对象校验或 ref 更新阶段失败。失败后：

~~~bash
git status --short --branch
git for-each-ref refs/remotes/origin/
git rev-parse --verify HEAD^{commit}
git count-objects -v
git fsck --connectivity-only
~~~

部分对象可能已经进入本地对象库，但 remote-tracking ref 可能尚未移动；不要把“对象数量增加”解释成“远端状态完整”。对象校验失败时先保留目录和错误日志，不运行 gc/prune。

常见分流：

| 现象 | 可能层级 | 恢复 |
| --- | --- | --- |
| could not resolve host | DNS/endpoint | 核对 URL、代理和网络，不改 refs |
| authentication failed | 客户端身份 | 检查凭据来源和有效期，不把 token 写日志 |
| repository not found | URL/授权/可见性 | 脱敏后核对仓库和主体 |
| early EOF/pack error | 传输/对象校验 | 保存错误和对象统计，重试前确认服务端状态 |
| cannot lock ref | 并发/残留锁 | 识别活跃 writer 后按锁流程处理 |
| fetch 成功但预期分支没变化 | refspec/隐藏权限 | 检查 fetch refspec、远端可见 refs 和 FETCH_HEAD |

不要用 reset --hard 解决 fetch 错误。fetch 没有移动当前工作分支时，本地工作仍可保留。

## 与 pull 的关系

pull 把 fetch 和 merge 或 rebase 组合在一次命令中。需要先审查远端变化、控制合并方向或排障时，拆成：

~~~bash
git fetch origin
git log --graph --decorate --oneline --all
git merge origin/main
~~~

这样能确认 fetch 已经完成、origin/main 的 OID 是什么，以及整合失败发生在哪一步。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-remotes.sh
~~~

实验使用本地 bare server，验证 Alice push 后 Bob fetch 更新 origin/main 但保持本地 main 不动，随后 pull --ff-only 才移动 Bob 的 main；它还验证 prune、分支和 tag 的基础传输。实验不模拟网络中断、SSH/TLS、凭据助手、隐藏 refs、平台复制或配额。

## 小结

fetch 把对象和远端引用带回本地，更新的是本地观察点，不是当前工作分支。先记录 fetch 前后 OID，再用范围和共同祖先判断整合方案；prune 只清理本地缓存引用。传输失败时保留对象、refs 和错误证据，不用 destructive reset 代替诊断。
