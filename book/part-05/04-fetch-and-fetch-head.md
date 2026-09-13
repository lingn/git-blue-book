# Fetch 与 FETCH_HEAD：取得远端状态，不替本地分支做决定

`git fetch` 把远端可见对象和引用带回当前仓库，再按 refspec 更新 remote-tracking refs。它通常不移动 `refs/heads/*`、不改当前工作区，也不把远端历史自动整合进本地分支。

`FETCH_HEAD` 是本次 fetch 的短期结果文件。它可以记录多个远端头及其来源，默认会被下一次 fetch 重写，使用 `--append` 才追加。它不是服务器审计日志，也不是长期备份。

## 进入条件与完成标准

在已配置 remote 的 clone 根目录执行。开始前保存本地状态和远端配置：

~~~bash
git status --short --branch
git remote get-url --all origin
git config --show-origin --get-all remote.origin.fetch
git rev-parse --show-object-format
git rev-parse --show-ref-format
~~~

Fetch 可能写对象、remote-tracking refs、`FETCH_HEAD`、reflog 和维护辅助文件。真实仓库先确认磁盘、网络、认证、授权和并发 writer；本章写操作只在临时 bare 仓库和 clone 中执行。

读完本章后，应能解释 fetch 的对象和引用副作用，读取新增/删除/非快进 remote-tracking 更新，区分 `FETCH_HEAD` 与持久 ref，选择 `--prune`、`--atomic`、`--tags`、`--append` 和 `--no-write-fetch-head`，并在失败后保留旧缓存和原始错误。

## Fetch 的写入范围

一次普通 fetch 可能完成：

| 层 | 典型变化 |
| --- | --- |
| 对象库 | 接收远端缺少的 commit、tree、blob、tag 或 pack |
| remote-tracking refs | 按 fetch refspec 更新 `refs/remotes/origin/*` |
| `FETCH_HEAD` | 写入本次取得的 ref、OID、来源和 merge 标记 |
| reflog | 某些本地引用更新会记录 old/new OID |
| 工作区和本地分支 | 通常不变 |

Fetch 不执行 merge、rebase、checkout 或 commit。对象已经传到本地，不表示任何本地分支已经采用它；remote-tracking ref 已更新，也不表示平台审批或部署完成。

核对前后 OID：

~~~bash
before_main="$(git rev-parse 'refs/heads/main^{commit}')"
before_tracking="$(git rev-parse 'refs/remotes/origin/main^{commit}')"
git fetch origin
after_main="$(git rev-parse 'refs/heads/main^{commit}')"
after_tracking="$(git rev-parse 'refs/remotes/origin/main^{commit}')"
printf 'main=%s -> %s\norigin/main=%s -> %s\n' \
  "$before_main" "$after_main" "$before_tracking" "$after_tracking"
~~~

`after_main` 通常等于 `before_main`，而 `after_tracking` 可以变化。若 fetch 没有新对象，两个 tracking OID 相同也不说明服务器未来不会变化。

## 输出摘要不是机器协议

终端可能显示：

~~~text
old..new  main -> origin/main
* [new branch]  feature/a -> origin/feature/a
- [deleted]     (none) -> origin/old
~~~

摘要受 Git 版本、语言、颜色和 ref 类型影响。脚本使用稳定接口：

~~~bash
git for-each-ref refs/remotes/origin/ \
  --format='%(refname) %(objectname) %(objecttype)'
git show-ref --verify refs/remotes/origin/main
git rev-parse --verify 'origin/main^{commit}'
~~~

保存原始 stdout/stderr 便于人工调查，但不要按箭头、短 OID 或英文提示判断成功。完整 OID、refname、退出码和 fetch 时刻才是可复核字段。

## FETCH_HEAD 是一次 fetch 的结果投影

查看文件：

~~~bash
fetch_head="$(git rev-parse --path-format=absolute --git-path FETCH_HEAD)"
sed -n '1,20p' "$fetch_head"
~~~

每行通常包含 OID、远端 ref 名、时间和 `not-for-merge` 等标记。默认 fetch 会重写该文件：

~~~bash
git fetch origin main
git fetch origin feature/review
~~~

第二次执行后，文件内容以第二次请求为准。需要保留多个请求结果时使用 `git fetch --append origin ...`，但追加文件仍只是客户端本地记录，不能当作服务器事件流。

若只想更新对象和 remote-tracking refs、避免写 `FETCH_HEAD`，可使用：

~~~bash
git fetch --no-write-fetch-head origin
~~~

具体命令组合按当前 Git 帮助核对。`--no-write-fetch-head` 不会让 fetch 变成完全只读，objects 和 remote-tracking refs 仍可能更新。

Pull、merge 或其他命令可能读取 `FETCH_HEAD`，但可靠自动化应保存明确 ref/OID，而不是依赖文件中的“第一行”。

## 新增、删除和强制移动

远端新增 branch 时，fetch 按映射创建新的 remote-tracking ref。远端删除 branch 时，普通 fetch 通常不会自动删掉本地旧 ref；使用：

~~~bash
git fetch --prune origin
~~~

Prune 只删除 fetch refspec destination 中已经确认远端 source 不存在的本地映射。它不删除同名本地分支、tag、对象、服务器数据或平台评审。执行前保存重要 remote-tracking OID，事故现场不要直接 prune。

Fetch refspec 常带 `+`，允许 remote-tracking ref 接受非快进更新。远端强制改写 feature 后，本地 tracking ref 可能从旧 OID 直接移动到新 OID；这不是 push 强制写入，也不代表新历史可信。保存 tracking reflog、服务器事件和候选映射。

~~~bash
git reflog show --date=iso-strict refs/remotes/origin/feature
git rev-parse refs/remotes/origin/feature
~~~

如果需要在保留旧观察的情况下接受强制更新，先建立 `refs/recovery/*`，再执行明确 refspec fetch。不要删除旧对象或覆盖本地工作分支来消除 diverged 提示。

## `--atomic` 只约束本地 ref 更新组

~~~bash
git fetch --atomic origin
~~~

服务器和客户端支持时，fetch 取得的一组本地 ref 要么一起更新，要么都不更新。它不把对象传输、`FETCH_HEAD`、工作区、平台审批或 CI 结果纳入同一事务，也不能撤销已经进入对象库的未引用对象。

Atomic 失败时保存旧 refs、错误和对象统计。是否支持、哪些 ref 属于同一组、遇到 prune 或自定义 refspec 的具体行为，要在目标 Git 版本和服务端中实测。不能仅凭命令接受参数就宣称远端更新原子。

## 标签获取需要明确范围

分支历史中可达的 tag 可能随 fetch 取得，但不会保证所有标签都在本地。需要完整可见标签时：

~~~bash
git fetch --tags origin
git for-each-ref refs/tags/ --format='%(refname) %(objectname)'
~~~

`--tags` 会扩大引用和对象范围，可能带来网络、磁盘和审计成本。它不取得当前身份看不到的隐藏 tag，也不把本地 tag 推回远端。附注 tag 的 tag object 与 peeled commit 要分别记录。

如果本地 tag 已存在而远端 tag 改指向其他对象，普通 fetch 可能拒绝覆盖或保留旧值。先保存旧 tag OID 和远端查询，再用经过审批的显式强制 refspec，并建立 recovery ref。不要把 tag 改指向当作普通分支更新。

## Fetch 失败不等于本地没有变化

错误可能出现在 URL/DNS、主机校验、认证、授权、协议协商、pack 校验、对象写入或 ref 锁。失败后依次保存：

~~~bash
git status --short --branch
git for-each-ref refs/remotes/origin/ --format='%(refname) %(objectname)'
git rev-parse --verify 'HEAD^{commit}'
git count-objects -v
git fsck --connectivity-only
~~~

部分对象可能已进入对象库，某些 refs 可能已更新，另一些没有。不能用对象数量或一行进度输出推断 fetch 已完整。

常见分流：

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| URL/DNS/超时 | remote URL、代理、网络、时间 | 修传输，不改 refs |
| host key/TLS 错误 | 可信指纹、证书、端口 | 修信任链，不关闭校验 |
| authentication/authorization 失败 | 凭据来源、主体、仓库权限 | 轮换/修权限，不改提交身份 |
| early EOF/pack 校验失败 | stderr、对象统计、server 状态 | 保留副本，确认来源后重试 |
| cannot lock ref | writer、lock、old/new OID | 停止并发，按锁流程处理 |
| remote-tracking 未更新 | refspec、隐藏 refs、prune、FETCH_HEAD | 重新固定映射，不造本地 ref |

Fetch 失败后不要立即运行 `gc`、`prune`、`reset --hard` 或删除 `.git/FETCH_HEAD`。先保护现状，必要时在新 clone 重试。

## Fetch 后再选择整合

取得 `origin/main=B`、本地 `main=A` 后，先计算关系：

~~~bash
git rev-list --left-right --count main...origin/main
git merge-base main origin/main
git merge-base --is-ancestor main origin/main
~~~

结果可能是本地落后、领先、分叉或相同。Fetch 不替你选择 merge、rebase、reset、cherry-pick 或保留分叉。共享分支还要加入评审、检查、队列、权限和发布证据。

需要诊断 pull 时拆开：

~~~bash
git fetch origin
git show-ref --verify refs/remotes/origin/main
git diff --stat main..origin/main
git merge --ff-only origin/main
~~~

这样可以证明冲突或拒绝发生在 fetch 之后的本地整合阶段。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-fetch-remote-tracking.sh
~~~

实验验证远端新增、删除和强制移动 ref，`fetch --atomic --prune` 更新 tracking refs、删除过期映射且不移动本地分支；`FETCH_HEAD` 默认覆盖、`--append` 追加，`--no-write-fetch-head` 不写该文件；错误 URL 失败后旧 tracking OID 保持。实验还验证 tag 显式强制获取前建立 recovery ref。

实验只使用本地 bare 仓库和 `file://` 传输，不模拟服务器协议协商、网络中断、权限、平台隐藏 refs、审计、LFS 或性能收益。

## 小结

Fetch 取得对象并更新本地远程观察点，`FETCH_HEAD` 记录一次请求的短期结果，本地工作分支通常不动。`--prune`、强制 tracking 更新、`--atomic`、标签范围和 fetch 失败都要按 refspec、OID、退出码和时点解释。Fetch 完成后，整合策略仍由后续命令和团队流程决定。

## 资料

- [git-fetch](https://git-scm.com/docs/git-fetch)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
- [git-refspec](https://git-scm.com/docs/git-fetch#_refspec)
- [git-remote](https://git-scm.com/docs/git-remote)
