# 远程引用过期、默认分支变化与删除残留：先确认远端事实

“远程分支不见了”“默认分支还是旧名字”“本地显示分支已删除，但提交还在”经常被当成同一个问题。它们实际涉及至少三种不同状态：远端引用是否存在，本地远程跟踪引用是否更新，以及当前工作分支的上游配置是否仍指向旧名字。标签、拉取规则和托管平台的隐藏引用又属于另外的引用命名空间。

第十三篇前面的章节已经把远程跟踪引用定义为一次通信后的本地记录。本章只处理这份记录与远端事实发生漂移的场景：分支重命名、远端删除、默认分支切换、标签改指向、局部可见性和多次查询之间的竞态。它不把 `fetch` 输出当作平台审计记录，也不把本地 bare 仓库当作 GitHub、GitLab 或其他托管服务的完整控制面。

本章以 Git 2.49.0、临时 `file://`/本地路径远端为基线，核对日期为 2026-08-22。真实服务器的隐藏 refs、默认分支设置、分支保护、权限过滤、评审引用和事件日志，要按目标产品版本、权限和套餐单独核对。

## 先把“远端”拆成四个事实

排障时先固定远端名称和候选引用，不要只截一张网页截图。至少分别回答下面四个问题：

| 事实 | 常用证据 | 证据范围 | 不能替代的判断 |
| --- | --- | --- | --- |
| 远端当前公开了什么 | `git ls-remote`、受控平台只读 API | 一次查询看到的 refs 和 OID | 平台隐藏引用、历史事件和权限之外的 refs |
| 本地上次记录了什么 | `refs/remotes/<remote>/*`、`git fetch` 日志 | 当前 clone 的远程跟踪缓存 | 远端当前状态 |
| 本地分支跟谁协作 | `branch.<name>.remote`、`branch.<name>.merge`、`git branch -vv` | 当前 worktree 的配置关系 | 远端仍然保留同名引用 |
| 平台控制面声明什么 | 默认分支、保护规则、评审/合并引用、审计事件 | 目标平台的控制面 | Git 对象库本身的完整内容 |

远程跟踪引用不是远端的镜像，也不是一个实时指针。一次 `fetch` 会根据 fetch refspec 更新它；没有执行通信，它可以无限期保持旧值。反过来，`fetch --prune` 也不是“把远端恢复成这样”，它只会在本地删除已经判断为不再被远端广告的远程跟踪引用。

## 第一轮证据：只读查询和会写入的查询分开

下面的命令在出现症状的客户端仓库根目录执行。先保存当前引用和上游配置，再执行任何 prune、`remote set-head` 或 `update-ref`：

```bash
git version
git remote -v
git branch -vv
git config --show-origin --show-scope \
  --get-regexp '^(remote\..*\.(fetch|prune|tagOpt)|branch\..*\.(remote|merge|pushRemote)|fetch\.prune)$' || true
git show-ref --head
git symbolic-ref --quiet refs/remotes/origin/HEAD || true
```

这些命令只读取本地状态。输出中的 OID、远端 URL、条件 include 和路径可能是敏感信息，应写入受限证据目录并脱敏。`git branch -vv` 里的 `[origin/old: gone]` 只是本地跟踪记录与最近一次通信的比较结果，不是平台删除事件的时间戳。

在确认远端名称后，从客户端发起一次明确的只读远端查询：

```bash
remote_name=origin
git ls-remote --symref "$remote_name" HEAD
git ls-remote "$remote_name" \
  'refs/heads/*' 'refs/tags/*'
```

`ls-remote` 读取远端当前可见的引用和 OID，不修改客户端 refs。`--symref` 若收到 `ref: refs/heads/main HEAD`，说明这次响应中远端把 `main` 广告为默认分支；没有 symref 可能是服务器、协议或权限没有提供该信息，不能据此推断默认分支是空的。通配符列表只覆盖服务器愿意广告的命名空间，隐藏的 pull-request refs、内部发布 refs 和权限受限 refs 需要平台控制面证据。

如果同时需要比较多个引用，把它们放在同一个查询中，并记录查询时间、远端 URL 摘要和完整输出。不要把两次独立的 `ls-remote` 结果拼成一个不存在过的“快照”：两次查询之间远端可能已经发生了更新。

## 分支重命名：创建和删除是两个动作

远端分支从 `legacy` 改名为 `archive/legacy`，在 Git 数据面通常表现为：新引用指向某个 OID，旧引用被删除。提交对象可能完全没有变化。

客户端先普通拉取：

```bash
git fetch origin
git show-ref --verify refs/remotes/origin/legacy
git show-ref --verify refs/remotes/origin/archive/legacy
```

正常情况下，新远程跟踪引用会出现，旧的远程跟踪引用仍可能保留。默认 fetch refspec 不会因为服务器删除了一个引用就自动删除本地缓存，除非启用了 prune 或显式传入 `--prune`。因此，“两个名字都能看到”并不表示远端仍有两个分支。

确认远端新名字和 OID 后，再保存旧缓存的恢复引用：

```bash
old_oid="$(git rev-parse --verify refs/remotes/origin/legacy)"
git update-ref refs/recovery/remote/legacy "$old_oid"
git fetch --prune origin
```

这里的 `update-ref` 和 `fetch --prune` 都会改变本地引用。前者创建一个明确的恢复根，后者删除不再被远端广告的 `refs/remotes/origin/legacy`。它们不会删除本地分支 `refs/heads/legacy`，也不会立刻物理删除对象；恢复引用、其他分支或 reflog 仍可能让对象可达。执行后必须核对：

```bash
git show-ref --verify refs/recovery/remote/legacy
git show-ref --verify refs/heads/legacy
git branch -vv legacy
```

如果本地分支仍有业务价值，先让负责人确认新远端引用确实对应同一条历史，再更新上游：

```bash
git branch --set-upstream-to=origin/archive/legacy legacy
```

这只修改当前 clone 的 branch 配置，不会创建或删除远端引用。若新 OID 与旧 OID 不同，不要直接设置上游掩盖差异，先按合并、迁移或错误更新流程固定两边的候选提交。

### 不要把 prune 当作修复

`git fetch --prune` 的失败方式包括：远端名称错误、网络/认证失败、fetch refspec 没有覆盖目标命名空间、服务器只返回部分 refs，或者本地仓库在并发操作中被另一个进程写入。任何一种失败都不能通过反复执行 prune 解决。

尤其要注意全局 `fetch.prune=true` 和 `remote.origin.prune=true`。它们能减少陈旧缓存，却会让每次 fetch 自动删除本地远程跟踪引用。组织若需要保留删除前证据，应在自动 prune 前生成 refs 清单或恢复引用，并把清理窗口与对象保留策略分开。

## 默认分支：远端的 HEAD 和本地的 origin/HEAD

远端仓库的 `HEAD` 是一个 symbolic ref，平台控制面通常还会保存默认分支设置。客户端 clone 后会把它记录为 `refs/remotes/origin/HEAD`，这是一份本地缓存。默认分支在平台上从 `main` 改成 `stable` 后，客户端可能仍然显示：

```text
origin/HEAD -> origin/main
```

先从远端重新获取候选分支，再刷新本地 symbolic ref：

```bash
git fetch origin
git remote set-head origin --auto
git symbolic-ref refs/remotes/origin/HEAD
```

`git remote set-head --auto` 会读取远端广告并写入本地 `refs/remotes/origin/HEAD`，所以它不是纯观察命令。若服务器没有广告 symref、默认分支名称尚未被 fetch、权限看不到目标分支或远端返回多个不一致事实，命令可能失败或给出不完整结果。恢复办法是先取得平台控制面确认的分支 OID，再用显式、可审计的本地引用更新；不要仅凭网页上的默认分支文字切换生产构建入口。

默认分支变化还会影响这些消费者：

- 没有显式上游的 clone、脚本和新工作树初始化；
- CI 默认 checkout 的 ref 和合并队列目标；
- 发布工具使用的 `HEAD`、标签策略和保护规则；
- 文档、webhook 和平台 API 中把默认分支当作参数的逻辑。

Git 客户端只能验证对象和引用，不能证明这些控制面消费者已经完成迁移。把默认分支切换当成平台变更事件，保留旧名、目标 OID、审批、检查和回滚窗口。

## 删除、隐藏和权限变化：看不见不等于不存在

远端列表中没有一个引用，至少有四种解释：

1. 引用确实被删除，服务器返回删除事件或新的 refs 快照。
2. 当前 fetch refspec 没有选择它，例如只获取 `refs/heads/main`。
3. 服务器隐藏了 namespace，或当前主体没有读取权限。
4. 引用被平台控制面替换成评审、队列或临时 candidate 引用，普通 Git 客户端看不到。

因此，排障记录要同时保留 fetch refspec、主体/权限上下文、服务器响应和平台事件 ID。不要用“本地 `git branch -r` 没看到”直接推断远端删除，也不要为了找回隐藏引用而扩大生产凭据权限。若平台控制面不可用，结论应标记为 `inconclusive`，而不是 `deleted`。

## 标签改指向：名称相同不代表对象相同

标签位于 `refs/tags/`，与分支引用分开。发布系统把 `v1.0.0` 从旧提交改到新提交时，客户端可能保留旧标签；普通 fetch 通常不会静默覆盖已有标签，具体输出和退出码会随 Git 版本、refspec 和传输场景变化。必须比较 OID：

```bash
tag_ref=refs/tags/v1.0.0
local_tag="$(git rev-parse --verify "$tag_ref")"
remote_line="$(git ls-remote origin "$tag_ref")"
printf 'local=%s\nremote=%s\n' "$local_tag" "$remote_line"
```

若远端 OID 与本地不同，先把本地值保存到恢复引用：

```bash
git update-ref refs/recovery/tags/v1.0.0 "$local_tag"
git fetch origin "+$tag_ref:$tag_ref"
git rev-parse --verify "$tag_ref"
```

前导 `+` 明确允许本地标签被改写，是有副作用的修复动作。它不会修改远端，也不会自动证明新标签签名、制品摘要、发布记录和部署对象正确。签名 tag 还要按第十篇和上一章的顺序核对 tag object、剥离目标 OID、签名主体和外部发布证据。若标签属于不可变发布命名空间，正确动作通常是停止并升级，而不是 force-fetch 后继续构建。

不要默认启用 `fetch.pruneTags=true`。它会把远端不再广告的本地标签删除，可能破坏离线发布证据；需要清理时，应先保存完整 tag 清单、签名和恢复根。

## 多次查询之间的竞态

以下写法看似严谨，实际上没有共同时间点：

```bash
main_oid="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
default_oid="$(git ls-remote origin HEAD | awk '{print $1}')"
```

如果平台在两次查询之间合并、回滚或切换默认分支，两个 OID 可能来自不同状态。改进方式是：

1. 先确定目标事件或候选 OID，优先使用平台提供的不可变事件 ID、合并队列 candidate 或部署记录。
2. 在同一次 Git 查询中请求需要对照的 refs，并保存原始响应。
3. 在执行 fetch、checkout 或构建前再次比较候选 OID；不一致就停止。
4. 对远端写入使用服务器提供的条件更新、显式租约或等价的旧值检查，而不是用本地缓存覆盖当前值。

一个查询响应也不等于跨系统事务。Git 客户端无法把平台默认分支、评审状态、CI 结论、制品库和部署控制面锁在同一时刻；这些系统之间需要事件 ID、candidate OID 和时间窗口关联。

## 恢复决策卡

| 现象 | 先固定 | 可执行的恢复 | 立即停止的条件 |
| --- | --- | --- | --- |
| 新分支已出现，旧跟踪引用仍在 | 远端新旧 OID、fetch refspec | 保存旧 OID，确认后 `fetch --prune`，重新设置上游 | 新旧 OID 不一致且没有迁移/合并决定 |
| 本地默认分支仍是旧名 | `ls-remote --symref`、平台变更事件 | fetch 目标分支，再刷新 `origin/HEAD` | 远端未提供 symref 或控制面事实冲突 |
| 远端列表没有引用 | 权限、隐藏规则、refspec、事件日志 | 走平台只读查询或权限核对 | 只有客户端空列表，没有服务端证据 |
| 标签名称相同但 OID 不同 | 本地/远端 OID、签名和制品摘要 | 保存旧标签，按发布规则显式更新或创建新版本 | 目标是不可变发布标签或签名/制品不一致 |
| 两次查询得到不同候选 | 每次原始响应和时间 | 固定可信 candidate，重新查询并重跑检查 | checkout、制品或部署 OID 无法与候选关联 |

恢复结束时至少验证：目标 remote-tracking ref、当前分支上游、`origin/HEAD`、标签/签名（如适用）、构建 candidate 和工作区不变量。不要把 `git gc`、删除恢复引用或清空旧 clone 放在第一次恢复动作里；这些会缩短后续取证窗口。

## 隔离实验：引用漂移不等于对象消失

本书提供 `scripts/verify-remote-ref-drift-failures.sh`。在仓库根目录执行：

```bash
bash scripts/verify-remote-ref-drift-failures.sh
```

实验前置条件是 Git 2.49.0 或兼容版本、可创建临时目录的本地 shell；不需要网络、真实凭据或托管平台权限。脚本在 `mktemp` 目录中创建 seed 仓库、bare 远端和客户端 clone，并配置虚构身份。

实验依次验证：

1. 远端把 `legacy` 改名为 `archive/legacy` 后，普通 fetch 发现新引用但保留旧 remote-tracking 缓存；保存 `refs/recovery/remote/legacy` 后，`fetch --prune` 只删除缓存，不删除本地分支或恢复对象。
2. 客户端显式重新设置本地分支上游，远端引用名称和配置关系分别可验证。
3. 远端把 symbolic `HEAD` 从 `main` 切到 `stable` 后，`remote set-head --auto` 更新本地 `origin/HEAD`。
4. 远端标签改指向后，普通 fetch 保留本地标签；只有显式 force refspec 才改变它，旧值通过恢复引用保留。
5. 两次独立 `ls-remote` 之间远端发生更新时，响应不同；同一次查询请求多个 refs 才能形成可比较的单次响应。

脚本只证明本地 Git 引用、OID 和查询时序的边界。它不模拟平台隐藏 refs、SSO/SCIM、分支保护、评审/合并队列、审计事件、真实 SSH/TLS、网络中断或平台标签不可变策略。实验结束会删除临时目录，不修改本书仓库和真实远端。

## 小结

远程跟踪引用是缓存，默认分支是本地 symbolic ref 的缓存，标签是独立命名空间，平台控制面又是另一组事实。分支重命名要分别处理创建、删除、prune 和上游配置；默认分支变化要核对远端 symref 和所有消费者；标签改指向要比较 OID、签名和制品；删除或不可见状态要保留权限、refspec 和平台事件证据。

排障的安全顺序是：先保存本地和远端快照，再明确哪些动作会写引用，最后在确认 OID 和共享边界后执行 prune、重设上游或 force refspec。任何无法证明远端事实、候选不一致或控制面状态冲突的情况，都应标记为 `inconclusive` 并停止扩大变更。

## 资料

- [git-ls-remote](https://git-scm.com/docs/git-ls-remote)
- [git-fetch](https://git-scm.com/docs/git-fetch)
- [git-remote](https://git-scm.com/docs/git-remote)
- [git-update-ref](https://git-scm.com/docs/git-update-ref)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
- [git-config](https://git-scm.com/docs/git-config)
