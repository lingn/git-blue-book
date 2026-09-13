# Pack、delta 与对象生命周期：物理整理不会改写历史

对象逻辑身份与磁盘布局是两层状态。一个 blob 可以先作为 loose object 单独压缩，随后进入 packfile，甚至以另一个对象为 delta base；通过 OID 读取时，Git 仍返回同一类型和完整 payload。`repack` 改变存放方式，不等于 rebase 或 amend 那样创建新历史。

## 进入条件与完成标准

本章实验只在可销毁临时仓库运行。开始观察日常仓库时，使用不改变对象布局的命令：

~~~bash
git rev-parse --git-path objects
git count-objects -v
git for-each-ref --format='%(refname) %(objectname)'
git fsck --connectivity-only
~~~

`count-objects -v` 报告 loose object、pack 和垃圾文件统计，不承诺性能好坏。`fsck --connectivity-only` 检查当前根集合需要的对象连通性，不扫描所有对象内容，也不能证明业务正确。

读完本章后，应能区分 loose/packed/delta 与 commit diff，解释可达、不可达和 dangling，判断 reflog/index/进行中操作怎样延长对象寿命，并知道何时停止 `gc`、`repack`、`prune` 和 maintenance。

## Loose object 是物理表示

SHA-1 仓库中，一个 loose object 常位于：

~~~text
.git/objects/ab/cdef...
~~~

目录名取 OID 前两个十六进制字符，其余字符作为文件名。SHA-256 使用更长 OID，仍遵循当前仓库布局规则。文件内容经过压缩，不能把磁盘文件直接当作原始 blob；对象头和 payload 也需要按格式解析。

使用 Git 自身读取：

~~~bash
oid="$(git hash-object -w sample.bin)"
git cat-file -t "$oid"
git cat-file -s "$oid"
git cat-file blob "$oid" > restored.bin
cmp sample.bin restored.bin
~~~

`hash-object -w` 写对象但不创建路径、tree、commit 或 ref。`cmp` 无输出且退出 0，表示恢复字节相同；它不证明这个 blob 属于正确提交。

## Packfile 与 index 分工

Packfile 把许多对象存入一个文件，配套 `.idx` 负责从 OID 定位 pack 中的对象。运行：

~~~bash
git repack -ad
git count-objects -v
git verify-pack -v "$(git rev-parse --git-path objects)"/pack/*.idx
~~~

`repack -ad` 会写新 pack/index 并删除被新 pack 替代的冗余 pack，属于改变物理布局的维护操作。它可能消耗大量临时磁盘、CPU 和 I/O，也会与其他维护竞争锁。不要为了观察命令在事故现场运行。

`verify-pack -v` 检查指定 pack index 和对象记录，输出可能很大。通配符由 shell 展开；仓库没有 pack 或有多个 pack 时，要先列出精确 `.idx` 路径。验证 pack 成功不代表 refs 完整，也不代表所有工作区、LFS 和 submodule 可用。

## Delta 不是提交差异

Pack 可以把一个对象表示为另一个 base object 加一组重建指令。Base 可能是同一文件的其他版本，也可能只是字节相似的另一个对象。Git 不承诺 delta 链按提交时间、父子关系或路径组织。

因此：

- `git diff A B` 是按两个 tree/文件视图计算的展示结果；
- pack delta 是磁盘或传输层的压缩表示；
- 修改 delta 选择、链深或 base 不改变完整对象 OID；
- 一个 commit 没有“保存相对父提交的补丁”，它保存根 tree 与父对象名。

排障时不要从 delta base 推断业务演化，也不要把 `verify-pack` 的链深当成提交历史深度。

## 可达性决定逻辑保留根

对象从一组根开始遍历。常见根包括 refs、`HEAD`、reflog、index、进行中的 merge/rebase/cherry-pick 状态，以及命令显式提供的对象。哪些根参与某条命令取决于命令和选项。

状态需要区分：

| 状态 | 含义 | 恢复结论 |
| --- | --- | --- |
| reachable | 从当前选定根可遍历到 | 对象可读，不代表业务版本正确 |
| unreachable | 对象存在，但当前根集合走不到 | 清理前可能建立 recovery ref |
| dangling | 常指不可达对象岛的末端候选 | 是调查线索，不自动等于丢失分支头 |
| missing | 其他对象或 ref 需要它，但当前对象来源无法提供 | 需从可信 donor/promisor/备份取得精确对象 |
| corrupt | 找到的字节无法按声明 OID/格式验证 | 先保全损坏范围，不能靠忽略报错恢复 |

`git fsck --unreachable` 的结果受 reflog、index、alternates、promisor 和 replace refs 影响。加 `--no-reflogs` 会改变根集合，不是“更准确”的固定模式。调查记录必须保存完整命令。

## Reflog 与恢复引用延长选择窗口

分支 reset、amend 或 rebase 后，旧 commit 可能离开分支历史，但仍由 reflog 或显式 `refs/recovery/*` 保持。Reflog 有过期策略，恢复引用则一直有效，直到被删除或其上层存储丢失。

日常误操作先按[reflog 与 recovery ref](../part-07/12-reflog-and-recovery-refs.md)验证候选并建立名字。对象已经 missing/corrupt、pack 损坏或来源依赖异常时，进入[对象取证与恢复](../part-11/02-object-forensics-and-recovery.md)。不要在寻找对象时同时运行清理。

## gc、repack、prune 与 maintenance 不是同义词

- `git repack` 重新组织 pack，选项决定纳入和删除哪些已有 pack；
- `git prune` 按根集合和过期条件删除不可达 loose objects，也会处理部分相关目录；
- `git gc` 编排对象整理、引用和日志等维护，具体任务受配置与版本影响；
- `git maintenance` 调度 commit-graph、loose-objects、incremental-repack、gc 等任务，不同 task 有不同写入和网络边界。

默认过期宽限用于降低并发写入和近期误操作对象被立即删除的风险。`--prune=now`、`prune --expire=now` 和立即过期 reflog 会显著缩短恢复窗口，只能在可销毁实验或经过审批的维护流程使用。

生产维护前至少固定：仓库路径和角色、当前 refs、对象来源、并发 writer、磁盘余量、备份/恢复点、任务和 Git 版本。维护后验证 refs、可达对象集合、`HEAD` tree、工作区和代表性 clone/fetch，而不是只看命令退出 0。

## Alternates 与 promisor 会改变“对象在不在”

Alternate object database 允许当前仓库从外部对象目录读取对象。Partial clone 的 promisor remote 则声明某些缺失对象可按需取得。`cat-file` 成功不一定表示对象字节存放在当前仓库，离线失败也不一定表示本地 pack 损坏。

采集时记录：

~~~bash
git config --show-origin --get-regexp '^(core\.repositoryFormatVersion|extensions\.|remote\..*\.promisor|remote\..*\.partialclonefilter)'
git rev-parse --git-path objects/info/alternates
git count-objects -v
~~~

不要把 alternate 目录当作可随意删除的缓存，也不要用从未知仓库取得的同 OID 文件覆盖当前对象库。Donor 的对象格式、OID、类型和 payload 都要验证。

## 隔离实验与破坏性边界

在仓库根目录运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-object-format-lifecycle.sh
~~~

实验先保存 commit、tree 和 blob OID，执行 `repack -ad` 后再次读取并比较，证明物理整理没有改变对象身份。随后写入一个不被 refs、reflog 或 index 引用的合成 blob，先验证它属于 unreachable，再在同一个可销毁仓库中执行立即 prune，并断言该对象不再可读。

立即 prune 只用于证明生命周期边界。实验通过 trap 删除整个临时目录，不连接远端，不接触当前书稿仓库。日常仓库和事故副本不得为复现实验运行同样清理。

## 失败方式与恢复

| 现象 | 先固定 | 安全动作 |
| --- | --- | --- |
| repack 后对象读不到 | refs、pack/idx 清单、stderr、磁盘与并发进程 | 停止维护，在副本执行 fsck/verify-pack，从可信 donor 恢复 |
| 磁盘在新 pack 写入时耗尽 | 原/新 pack、临时文件、锁和可用空间 | 停止新增维护，不手删来源不明的 pack/idx |
| `fsck` 报 dangling 就立即 prune | 完整命令、根集合、reflog、index 和操作状态 | 验证是否为恢复候选，事故窗口暂停清理 |
| alternate 不可用导致 missing | alternate 配置、外部路径和对象 OID | 恢复可信对象来源，不把依赖缺失误报为本地损坏 |
| partial clone 离线读取失败 | promisor/filter、对象类型和网络错误 | 恢复远端或取得完整副本，不伪造空对象 |
| pack verify 通过但 clone 仍失败 | refs、服务端协商、权限、其他 pack 与外部对象 | 分层诊断，不能用单个 pack 健康证明仓库完整 |

## 小结

Loose object、pack 和 delta 只描述物理存储，完整对象仍由同一 OID、类型和 payload 识别。对象能否继续恢复取决于 refs、reflog、index、进行中操作和外部对象来源构成的根集合，以及维护何时让不可达对象过期。整理和清理前先保住根与恢复点，维护后同时验证逻辑状态和物理完整性。

## 资料

- [gitformat-pack](https://git-scm.com/docs/gitformat-pack)
- [git-pack-objects](https://git-scm.com/docs/git-pack-objects)
- [git-repack](https://git-scm.com/docs/git-repack)
- [git-prune](https://git-scm.com/docs/git-prune)
- [git-gc](https://git-scm.com/docs/git-gc)
- [git-maintenance](https://git-scm.com/docs/git-maintenance)
- [git-fsck](https://git-scm.com/docs/git-fsck)
