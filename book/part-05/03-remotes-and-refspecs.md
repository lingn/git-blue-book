# Remotes 与 refspec：连接目标和引用映射是两类配置

Remote 把一个本地名称关联到 fetch/push URL、refspec 和其他行为。URL 说明连接哪里，refspec 说明对端 ref 与本地/远端目标 ref 怎样映射。修改 URL 不移动 refs，修改 refspec 也不自动传输对象；下一次 fetch/push 才执行映射。

一个 remote 可以从只读上游 fetch，却向个人派生仓库 push；也可以只获取部分分支、排除敏感或高噪声 namespace。名称 `origin` 不提供权威、权限或中心化保证。

## 进入条件与完成标准

真实仓库先只读采集，输出可能含内部 URL 或嵌入式秘密：

~~~bash
git remote -v
git remote get-url --all origin
git remote get-url --push --all origin
git config --show-origin --show-scope --get-regexp '^remote\.origin\.'
git for-each-ref refs/remotes/origin/ \
  --format='%(refname) %(objectname)'
~~~

分享前脱敏，不把 token 写入命令。Remote 变更和传输实验只在本地临时仓库执行。

读完本章后，应能区分 remote 名、fetch URL、pushURL、fetch/push refspec，解释 `+`、通配和负 refspec，安全执行 add/set-url/rename/remove，判断 prune 边界、多个远程和 mirror 风险，并从配置错误恢复而不重写提交。

## Remote 名只是本地配置键

~~~bash
git remote
git remote get-url origin
git remote get-url --push origin
~~~

Clone 常创建 origin，但可按职责命名 `upstream`、`fork`、`mirror` 或 `disaster-recovery`。名称不会验证 URL 所有者，也不限制读写。

添加 remote：

~~~bash
git remote add upstream "$source_url"
git config --get-regexp '^remote\.upstream\.'
~~~

只写 `.git/config`，不连接服务器、不创建对象、不改变工作区。名称已存在时命令拒绝；先读取现有配置，不用 remove/add 覆盖未知用途。

## Fetch URL 与 pushURL 可以分离

默认 push URL 与 fetch URL 相同。可以显式设置：

~~~bash
git remote set-url --push origin "$write_url"
git remote get-url --all origin
git remote get-url --push --all origin
~~~

常见用途是从上游只读镜像 fetch、向个人 fork push。配置错误也可能把源码发送到错误仓库。变更前保存旧 fetch/push URL、remote refs 和 owner，变更后先 `ls-remote` 验证只读目标；写权限在专用测试 ref 验证，不向主线试推。

同一 remote 可配置多个 URL。Git 对多 fetch URL 与多个 pushURL 的使用语义不同，脚本使用 `--all` 完整采集，并按当前文档验证 failover/广播行为，不从第一行推断全部目标。

## Fetch refspec 映射对端 refs 到本地 namespace

普通 clone 常配置：

~~~text
+refs/heads/*:refs/remotes/origin/*
~~~

格式为 `<source>:<destination>`。Fetch 时 source 位于对端，destination 位于本地。通配符两侧各出现一个 `*`，匹配部分被带到目标。

开头 `+` 允许本地 remote-tracking ref 接受非快进更新。这不授权 push 强制覆盖服务器，也不改变本地工作分支。Remote-tracking ref 是缓存，需要跟随服务器重写时通常允许移动，但 reflog/恢复记录仍应保留。

查看全部映射：

~~~bash
git config --get-all remote.origin.fetch
~~~

没有默认通配时，fetch 可能只取得显式分支。网页存在而本地没有，先查 refspec 与权限，不创建同名本地分支掩盖缺口。

## 负 refspec 排除匹配引用

~~~text
+refs/heads/*:refs/remotes/origin/*
^refs/heads/wip/*
~~~

负 refspec 只有 source，没有 destination，用 `^` 排除正映射命中的 refs。它减少本地引用范围，不是服务器访问控制。被排除分支的对象仍可能因其他可达 refs、标签或历史共享而进入本地。

配置多值：

~~~bash
git config --add remote.origin.fetch \
  '+refs/heads/*:refs/remotes/origin/*'
git config --add remote.origin.fetch '^refs/heads/wip/*'
~~~

修改前保存所有旧值。错误排除可能让 CI、迁移或调查漏掉 refs；恢复后重新 fetch，并核对完整 OID 清单。

## 命令行 refspec 可以临时覆盖或追加

~~~bash
git fetch origin \
  refs/heads/release/2.x:refs/remotes/origin/release/2.x
~~~

显式命令适合一次性取得已确认 ref。它会写对象、destination ref 和 `FETCH_HEAD`。是否同时使用配置 refspec 取决于命令形式和选项，自动化不要凭记忆；在隔离仓库验证最终 refs。

只想把对象写入 `FETCH_HEAD` 而不建立远程跟踪 ref，可省略 destination，但后续恢复入口更弱。重要候选创建明确、命名受控的 ref。

## Push refspec 方向相反

~~~bash
git push origin \
  refs/heads/topic:refs/heads/review/topic
~~~

Push 的 source 在本地，destination 在远端。空 source 表示请求删除远端 ref：

~~~bash
git push origin :refs/heads/review/topic
~~~

完整 refname 可避免 Git 的 namespace 推断。删除前查询远端 OID、保护/审批和消费者，不能把空 source 当清理快捷方式。

Push refspec 前的 `+` 表示请求非快进覆盖，不提供并发租约。共享引用使用协调后的 `--force-with-lease=<ref>:<expected-old>`，服务端保护仍可拒绝。

## Rename remote 会迁移本地配置与缓存名称

~~~bash
git remote rename origin upstream
git remote
git for-each-ref refs/remotes/upstream/
git config --get-regexp '^remote\.upstream\.'
~~~

操作写本地配置并重命名关联的 remote-tracking refs。它不重命名服务器仓库，不移动本地 heads，也不修改对象。自定义或负 refspec 可能触发“非默认映射未自动更新”提示；source-only 排除规则即使不需改 remote 名，也要逐条复核。执行后比较 old/new namespace、全部 refspec 和 branch upstream 配置。

若 remote 被多个 worktree 共享，配置变化对同一 common directory 的所有工作树可见。先确认并发任务。

## Remove remote 删除本地连接和缓存

~~~bash
git remote remove upstream
~~~

命令删除本地 remote 配置和对应 remote-tracking refs。它不删除服务器、服务器 refs、本地分支、tag、对象、评审或其他 clone。

删除前保存：

~~~bash
git remote get-url --all upstream
git remote get-url --push --all upstream
git config --get-all remote.upstream.fetch
git for-each-ref refs/remotes/upstream/ \
  --format='%(refname) %(objectname)'
~~~

本地缓存入口消失后，未被其他 refs 引用的对象可能进入不可达生命周期。重要观察先建立 recovery ref 或 bundle。恢复 remote 配置不自动恢复 remote-tracking refs，仍需 fetch。

## Prune 必须按 destination 范围理解

~~~bash
git fetch --prune origin
~~~

Prune 删除本地 refspec destination 中、已确认对端 source 不再存在的 refs。它通常清理 `refs/remotes/origin/*`，不删除同名本地分支。

若把远端 tags 显式映射到本地 `refs/tags/*`，prune 可能影响本地标签。执行前读取所有 refspec，保存重要 refs，并用 dry-run 支持情况或测试仓库验证。远端查询受权限限制时，“看不到”也可能触发错误清理判断，平台维护窗口需格外谨慎。

## 多远程不是自动同步拓扑

~~~bash
git fetch origin
git fetch upstream
git rev-list --left-right --count \
  refs/remotes/origin/main...refs/remotes/upstream/main
~~~

两个 fetch 只更新各自本地观察点，不会让服务器互相同步。差异可能来自不同权威、复制滞后、权限、refspec 或镜像故障。组织为每个 remote 登记方向、owner、RPO/RTO、允许写入和故障转移流程。

不要在同一 remote 配置多个不明确写入目标来实现“备份”。Push 部分成功、删除传播和平台外部数据都需要显式状态机。

## Mirror 配置是广范围强制映射

Mirror clone 常有：

~~~text
remote.origin.mirror=true
+refs/*:refs/*
~~~

Fetch/remote update 可以覆盖本地所有映射 refs，mirror push 可以在目标创建、强制更新和删除广泛 refs。它适合受控迁移/镜像，不适合作为开发者 remote 默认值。

变更 mirror URL 前保存全 refs manifest、目标空闲/授权证明和恢复点。平台 issue、权限、LFS、CI 和审计不在 refs mirror 中。

## URL 变更先验证读，再验证窄写

~~~bash
old_fetch="$(git remote get-url origin)"
old_push="$(git remote get-url --push origin)"
git remote set-url origin "$new_fetch_url"
git remote set-url --push origin "$new_push_url"
git ls-remote origin HEAD
~~~

失败时用保存值恢复同一作用域，分别核对 fetch/push URL。URL 可能含秘密，不写公开日志。`ls-remote` 成功不证明写权限；用专用测试仓库/ref 验证写路径并清理。

`remote show origin` 默认可能访问网络；只要本地证据时使用 get-url/config/for-each-ref。网络失败不能解释成本地对象损坏。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| Fetch 读到错误项目 | fetch URL、server refs、仓库稳定 ID | 停止整合，恢复 URL 并隔离错误对象/refs |
| Push 发往错误 fork | pushURL、remote.pushDefault、日志 | 阻止后续写，检查远端影响并恢复配置 |
| 某分支未出现 | 正/负 refspec、权限、`ls-remote --heads` | 修映射并 fetch，不创建假分支 |
| Rename 后 upstream 失效 | branch config、old/new remote 名与 refs | 修正配置，不 reset 提交 |
| Remove 后缓存消失 | 删除前 manifest、服务器和 recovery ref | 重建 remote 后 fetch 精确 refs |
| Prune 删除意外标签 | refspec destination、原 OID、远端事实 | 从记录恢复，停止进一步 prune |
| `+` 映射覆盖本地观察 | reflog、旧新 OID、服务器事件 | 建 recovery ref，调查远端重写 |
| Mirror 指向错误目标 | 全 refs、删除/强推范围和审计 | 立即围栏，按迁移恢复流程处理 |

配置问题不通过重写历史修复。任何 URL/refspec 变更前后保存 config 来源、refs 和连接验证。

## 隔离实验

运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-remotes-refspecs.sh
~~~

实验验证 remote add 只写配置，fetch URL 与 pushURL 指向不同 bare 仓库，正 refspec 映射 heads、负 refspec 排除 `wip/*`，显式 push refspec 只更新写仓库。它再验证 remote rename 迁移 tracking refs、upstream 与配置并保留自定义映射 warning，remove 删除本地 remote/tracking refs，但保留本地分支和两个服务器。

现有 `verify-refspec-partial-clone.sh` 继续覆盖浅/部分/稀疏机制。实验不验证网络、凭据、平台权限、隐藏 refs 或 mirror 生产风险。

## 小结

Remote name、fetch URL、pushURL 和 refspec 是四类本地配置。Fetch refspec 从对端映射到本地，push refspec 从本地映射到对端；`+`、负映射、prune 和 mirror 都会扩大状态变化。Add、rename、remove 与 set-url 不传输对象，但会改变下一次命令的目标，必须保存配置和 refs 后再修改。

## 资料

- [git-remote](https://git-scm.com/docs/git-remote)
- [git-fetch](https://git-scm.com/docs/git-fetch)
- [git-push](https://git-scm.com/docs/git-push)
- [git-config](https://git-scm.com/docs/git-config)
- [gitglossary](https://git-scm.com/docs/gitglossary)
