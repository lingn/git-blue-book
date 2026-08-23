# 仓库损坏、锁文件残留与并发操作：先分清谁在写

“Git 提示另一个进程正在运行”“仓库损坏”“删掉 `.lock` 就好了”经常出现在同一段报障记录里，但三者的恢复边界完全不同。锁文件可能表示一个仍在运行的写入者，也可能是进程崩溃后留下的残留；对象损坏则是 pack、loose object、index 或底层存储的完整性问题；并发更新还可能在没有任何锁文件的情况下通过旧值竞争覆盖或拒绝引用。

本章把症状分成三条路径：锁和写入者、引用并发、对象/文件系统完整性。目标不是给出一个“强制清理”命令，而是让读者先找出真正的写入边界，再选择等待、条件更新、隔离副本、可信 donor 或恢复点。第十一篇已经详细讲过对象取证；本章只负责现场分流和最小安全动作。

本章以 Git 2.49.0、Bash 和本地文件系统为基线，核对日期为 2026-08-22。锁的路径和存储行为会受 Git ref backend、linked worktree、操作系统、网络文件系统和托管服务实现影响；生产环境还必须核对进程管理、快照、权限和存储平台文档。

## 三种表象，三种第一问题

| 表象 | 第一问题 | 首要证据 | 不应立即做的事 |
| --- | --- | --- | --- |
| `index.lock`、`refs/...lock` 或 `packed-refs.lock` 已存在 | 哪个进程或任务拥有写入权？ | 锁路径、mtime/size、进程/任务、Git/common directory | 删除所有 `.lock`、重启多个 writer |
| 更新被拒，旧值与期望值不同 | 是否有另一个合法 writer 先更新了同一 ref？ | old/new OID、expected old、服务端事件或 lease 结果 | 换凭据、无条件 force push |
| `fsck`、`verify-pack` 或读取对象失败 | 是 missing、corrupt、pack/index 不匹配，还是 I/O/权限？ | 完整 stderr、对象 OID、pack/idx 摘要、存储日志 | `gc`、`prune`、repack 覆盖原现场 |

锁文件不是“仓库正在损坏”的证据，`fsck` 通过也不能证明没有并发写入。每个结论都要写出它观察到的路径、时间和范围。

## 第一轮只读采证

在报障发生的同一工作树执行。若怀疑这是事故现场，先按第十一篇冻结写入，再在证据副本执行可能耗时的完整检查。

```bash
git version
git rev-parse --show-toplevel
git rev-parse --git-dir
git rev-parse --git-common-dir
git rev-parse --path-format=absolute --git-path index
git rev-parse --path-format=absolute --git-path objects
git status --porcelain=v2 --untracked-files=all
git symbolic-ref --quiet HEAD || git rev-parse HEAD
git show-ref --head
git for-each-ref --format='%(refname) %(objectname)' \
  | LC_ALL=C sort
```

这些命令读取当前工作树、Git directory、common directory、index、对象路径和 refs。`status` 可能运行 fsmonitor、clean filter 或其他 helper，受信任仓库中也应保存配置和 helper 版本；如果现场不允许任何外部程序，使用第十一篇的受控采集方式，不要把 `GIT_OPTIONAL_LOCKS=0` 当成完整沙盒。

盘点精确锁路径，而不是递归删除：

```bash
git_dir="$(git rev-parse --path-format=absolute --git-dir)"
common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
find "$git_dir" "$common_dir" -type f -name '*.lock' -print \
  | LC_ALL=C sort -u
```

对每个结果保存路径、owner、权限、字节数、mtime、摘要和采集时间。`find` 的重复路径、权限拒绝和网络文件系统延迟都应记录；空结果只说明这次扫描没有看到锁，不说明此前没有并发写入。

同时从操作系统或任务调度器查询写入者。示例命令依系统权限而异：

```bash
ps -axo pid,ppid,lstart,command | grep '[g]it\|maintenance\|backup' || true
lsof "$git_dir/index.lock" 2>/dev/null || true
```

`ps`/`lsof` 的空结果可能只是进程已经退出或当前主体不可见，不能把它解释成“锁一定陈旧”。服务端仓库还要查接收进程、维护队列、对象池 owner 和平台事件，而不是只看客户端磁盘。

## 锁属于不同状态域

不同路径的锁保护不同资源。路径可能因为 linked worktree 或 reftable 变体而变化，下表是常见 files ref backend 的诊断入口：

| 锁路径 | 常见保护对象 | 典型冲突 | 恢复关注点 |
| --- | --- | --- | --- |
| `$GIT_DIR/index.lock` | 当前 worktree 的 index 写入 | 两个 `add`、IDE 与命令行同时改 index | 当前 worktree 是否有 writer；暂存内容是否要保留 |
| `$GIT_COMMON_DIR/refs/heads/name.lock` | 分支 ref 更新 | commit、merge、receive 或脚本更新同一分支 | old/new OID、reflog、是否有条件更新 |
| `$GIT_COMMON_DIR/packed-refs.lock` | packed refs 重写 | pack-refs、fetch、维护任务并发 | refs 快照和 pack/loose 状态，不要手工拼文件 |
| `$GIT_COMMON_DIR/shallow.lock` | 浅边界文件更新 | deepen、unshallow 与 fetch 并发 | 当前 shallow 边界和 fetch 任务 |
| `$GIT_DIR/config.lock` | 本地配置替换 | IDE、脚本同时改 config | 配置来源、凭据和 include 是否泄漏 |
| linked worktree 专属 index/HEAD 路径 | 单个工作树状态 | 两个工作树各自操作 | 用 `git rev-parse --git-path` 定位，不凭目录猜 |

对象写入通常先写临时文件再原子重命名，可能没有一个长期存在的对象锁文件可供排查。Git 的锁协议能减少同一文件的并发破坏，却不替组织调度器协调备份、GC、repack、镜像和平台控制面。

## 先判断进程，再处理残留锁

### 仍有写入者：等待或按任务流程停止

如果进程、维护任务或另一个终端仍在运行，记录 PID、父进程、命令行、开始时间、仓库/common directory、任务 ID 和预计完成时间。优先等待其正常退出；确需停止时按任务的取消协议，让 Git 完成临时文件清理。不要在进程仍持有锁时删除文件，两个 writer 可能同时写同一个 index 或 ref。

在容器、网络文件系统或远程执行环境中，PID 只能在对应 host/namespace 内解释。服务端锁由服务进程管理，客户端 `ps` 看不到；跨节点时还要查询调度器和存储租约。

### 没有写入者：先保留，再精确处置

只有在确认没有活跃 writer、锁的 owner/mtime 与任务记录不符、文件系统健康，且负责人批准恢复后，才可处理疑似残留锁。建议顺序：

1. 保存锁文件原始字节、权限、mtime、摘要和同目录文件清单；
2. 保存当前 HEAD、refs、index、工作区状态和未完成操作；
3. 把**单个已确认路径**移入受限 quarantine，或按组织批准删除；不要用 `rm -rf .git` 或通配符；
4. 只重试原来失败的一条命令，记录新旧 OID 和输出；
5. 若再次出现锁，停止重试，检查隐藏进程、网络存储和权限，而不是连续删除。

移动锁文件本身也是现场变更。若这是取证事件，先复制并摘要，再在恢复副本处理；原现场保留原路径和保管链。删除锁不会恢复丢失的 index 内容，也不会解决对象损坏或错误的 expected old。

### `GIT_OPTIONAL_LOCKS=0` 的边界

```bash
GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2
```

该变量可以减少某些可选维护写入，例如刷新辅助信息，但它不阻止 `add`、`commit`、`fetch`、`reset`、`gc`、`update-ref` 等必要写操作，也不消除外部 filter、hook 或文件系统竞争。把它当作“尽量少写”的诊断选项，而不是并发控制或证据保全开关。

## 没有锁文件也可能有并发引用

引用更新的危险不是只有锁冲突。两个合法 writer 可以先各自读取同一个 old OID，再依次产生不同后继。无条件 `update-ref` 或 force push 可能覆盖先完成的更新。

本地恢复候选应使用 expected old：

```bash
ref=refs/heads/main
expected_old="$(git rev-parse --verify "$ref")"
candidate_oid='FULL-OID-FROM-ISOLATED-CANDIDATE'
git update-ref "$ref" "$candidate_oid" "$expected_old"
```

前置条件是 `candidate_oid` 已在隔离副本验证、当前 ref 快照仍是 `expected_old`，并且变更负责人批准了本地 ref 写入。若另一个进程先移动 ref，命令会失败而不覆盖新值；保存失败证据，重新采集和审批。不能把失败改成无 expected old 的第二次重试。

远端个人分支改写使用 `git push --force-with-lease` 或服务器等价的条件更新；它保护的是远端 ref 的旧值，不是工作区或对象完整性。共享主线、保护分支、合并队列和发布 tag 应使用平台控制面提供的条件更新与审批，不把客户端 lease 当作全套并发治理。

linked worktree 还会把风险拆成两层：每个 worktree 有自己的 `HEAD` 和 index，但共享 common directory、refs 和对象库。一个工作树的 `git add` 不应被另一个工作树的 index 锁误判为同一个文件；反过来，两个工作树同时改同一共享 ref 仍然会竞争。始终用 `git rev-parse --git-dir --git-common-dir --git-path index` 记录实际路径。

## `fsck` 失败时进入对象完整性路径

锁错误通常在命令启动前就拒绝写入；对象损坏则可能在读取 commit、pack 或 tree 时失败。把两者混在一起会导致错误恢复：

```bash
set +e
git --no-optional-locks fsck --full --strict --no-progress \
  > fsck.stdout 2> fsck.stderr
fsck_status="$?"
set -e
printf 'fsck_exit=%s\n' "$fsck_status"
```

前置条件是仓库副本已冻结，且有足够时间和磁盘空间完成检查。保存完整 stdout/stderr、Git 版本、根集合和配置。`fsck` 非零后先分类：

- `missing`：解析需要的 OID 在当前对象来源不可读，检查 loose、pack、alternate、promisor 和共享对象池；
- `corrupt`、checksum 或 pack/index mismatch：文件、压缩数据、pack trailer 或 index 与声明不符；
- `dangling`/`unreachable`：对象暂时没有当前根可达，不等于损坏；
- 权限、I/O、磁盘满或网络存储错误：先修复/隔离底层环境，不能把空目录当成对象删除。

使用 `git verify-pack -v <pack>.idx`、`git cat-file -e <oid>` 和 `GIT_NO_REPLACE_OBJECTS=1` 时，都在恢复副本运行并保留原始 pack/idx。不要在原现场运行 `repack -ad`、`prune`、`gc` 或 `fsck --lost-found`：它们可能改变物理布局、写入 `lost-found` 或缩短不可达对象的恢复窗口。对象恢复、alternate 和 donor 的详细步骤见第十一篇。

### 为什么“恢复一个 pack”仍要重新验收

从 donor 复制 pack、重新写入缺失 blob 或移除 alternate 只能产生候选恢复。恢复后至少验证：

```bash
git --no-optional-locks fsck --full --strict --no-progress
git show-ref --head
git rev-parse HEAD^{tree}
git status --porcelain=v2 --untracked-files=all
```

若 refs、HEAD tree 和工作区不变量一致，还要在没有 donor alternate 的空环境 clone 里重试。`fsck` 通过不代表 LFS payload、submodule commit、平台审计或构建制品完整；这些外部数据面按各自证据链验收。

## 常见失败与恢复边界

| 现象 | 可能原因 | 安全恢复 | 不可越过的边界 |
| --- | --- | --- | --- |
| `index.lock` 存在 | 活跃 IDE/命令、崩溃残留或另一个 worktree | 查进程和任务，保存状态；确认无人写入后只处理该路径 | 无法证明锁 owner 已退出 |
| `refs/heads/x.lock` 存在 | commit、fetch、脚本或服务端 ref 更新 | 保存 old/new OID，等待或恢复副本重试条件更新 | 用无条件 ref 写入覆盖并发更新 |
| 删除锁后又立即出现 | 隐藏进程、网络 FS、维护调度或权限问题 | 停止重试，围栏 writer，检查 host/storage | 把重复出现当作“多删几次” |
| `fatal: cannot lock ref` 且无 lock 文件 | expected old 失配、ref 重命名或 packed/loose 竞态 | 重新采集 refs，按批准的 expected old 更新 | 换认证或 force 覆盖共享 ref |
| `fsck` 报 missing | loose/pack/alternate/promisor 缺对象 | 在副本定位来源，从可信 donor/备份恢复并验收 | 运行 prune 或让不完整副本成为 donor |
| `fsck` 报 corrupt/pack mismatch | pack、idx、磁盘或复制损坏 | 停写保全原件，校验存储，从独立副本恢复 | 在原文件上 repack 覆盖证据 |
| 多个维护任务互相阻塞 | 组织调度没有按 object pool/volume 互斥 | 用 owner/lease/心跳围栏任务，恢复后再运行 | 只看某个 Git lock 就宣称全局互斥 |
| `GIT_OPTIONAL_LOCKS=0` 仍写入 | 命令需要写 index/ref 或 helper 在写 | 分析实际命令和外部程序，改用受控副本 | 把环境变量当成只读模式 |

## 隔离实验：锁阻塞、并发 writer 与对象损坏要分开

本书提供 `scripts/verify-repository-corruption-locks-concurrency.sh`。在仓库根目录执行：

```bash
bash scripts/verify-repository-corruption-locks-concurrency.sh
```

实验前置条件是 Git 2.49.0 或兼容版本、Bash、可创建临时目录的本地文件系统；不需要网络或真实凭据。脚本在 `mktemp` 目录中创建虚构身份的临时仓库，并在可销毁副本操作损坏文件。

实验验证：

1. 一个带慢速 clean filter 的 `git add` 持有 `index.lock` 时，第二个 writer 被拒绝，第一条操作完成后 index 和工作树仍可读；
2. 在没有活跃 writer 的隔离实验中放置伪造的 `index.lock` 与分支 ref lock，失败命令不改变旧 index/旧 ref，移除**精确路径**后带 expected old 的更新才成功；
3. 截断 disposable copy 的 pack 后 `fsck --full --strict` 失败，但 refs 文件保持原 OID；从 pristine donor 恢复 pack/idx 后完整性和 HEAD tree 恢复；
4. 实验不把锁删除当成生产建议，也不模拟进程崩溃、网络文件系统 lease、reftable、平台对象池、真实磁盘坏道或多主服务端写入。

脚本结束时删除整个临时目录。真实现场必须保留锁原件、进程/任务证据和原始 pack/idx，不能照抄实验的清理动作。

## 小结

锁文件首先是写入边界，不是清理目标。先确认 writer、common directory、锁路径和时间，再决定等待、围栏或处理单个残留；引用并发要用 expected old/lease，不能用无条件覆盖；对象损坏则进入 fsck、pack、alternate 和 donor 的取证恢复路径，禁止用 GC 或 repack 覆盖现场。

诊断完成的证据不是“命令终于成功”，而是：写入者和锁状态有解释，refs 的 old/new OID 可对账，对象在独立来源中通过完整性检查，恢复后的 HEAD/tree/worktree 与外部数据面都完成验收。任何一项只能猜测时，结论应保持 `inconclusive` 并停止扩大变更。

## 资料

- [gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)
- [git-update-ref](https://git-scm.com/docs/git-update-ref)
- [git-index-pack](https://git-scm.com/docs/git-index-pack)
- [git-verify-pack](https://git-scm.com/docs/git-verify-pack)
- [git-fsck](https://git-scm.com/docs/git-fsck)
- [git-rev-parse](https://git-scm.com/docs/git-rev-parse)
- [git-worktree](https://git-scm.com/docs/git-worktree)
