# Porcelain 与 plumbing：便利工作流和底层原语的责任边界

Git 文档常把面向用户的高层命令称为 porcelain，把实现对象、引用和 index 操作的底层命令称为 plumbing。这个分类说明接口层次，不表示 porcelain 永远安全、plumbing 永远危险，也不保证某条命令只能属于一侧。

真正影响工程决策的是责任范围。`git commit` 编排 index、身份、说明、hooks、签名选项和当前引用；`hash-object`、`mktree`、`commit-tree`、`update-ref` 可以把同一链路拆成独立原语。拆开以后，调用者必须自己维护对象类型、父关系、并发前置条件、恢复入口和策略证据。

## 进入条件与完成标准

本章所有写入示例只在一次性仓库执行。读取真实仓库时先固定位置、格式和受限对象来源：

~~~bash
git version
git rev-parse --show-toplevel
git rev-parse --show-object-format
git rev-parse --show-ref-format
git config --show-origin --get-regexp \
  '^remote\..*\.promisor$|^remote\..*\.partialclonefilter$'
~~~

最后一条没有匹配时返回 1，这是“未发现显式 promisor/filter 配置”，不是命令损坏。部分克隆中看似只读的对象查询可能触发 lazy fetch；离线、取证或受限网络环境要单独验证。

读完本章后，应能按对象、引用、index、工作区和外部控制面拆解高层命令，选择面向人的展示与面向机器的稳定格式，判断 plumbing 写入的前置条件，并从未被引用的对象、部分 ref 更新或绕过工作流的 commit 中恢复。

## 分类不等于安全等级

典型高层命令包括 `status`、`add`、`commit`、`switch`、`merge`、`rebase`、`fetch` 和 `push`。它们根据用户意图组合多个内部动作，提供错误检查、提示和恢复状态。典型底层命令包括 `hash-object`、`cat-file`、`mktree`、`read-tree`、`write-tree`、`commit-tree`、`update-index`、`update-ref` 和 `for-each-ref`。

边界并不绝对：

- `rev-parse`、`ls-files` 和 `for-each-ref` 经常直接用于脚本，也出现在人工诊断中；
- `status --porcelain=v2` 名字含 porcelain，却专门提供机器可读格式；
- `fetch` 是高层工作流，但会访问网络、写对象、远程跟踪 refs 和 `FETCH_HEAD`；
- `cat-file` 通常只读本地对象，在 partial clone 中却可能请求 promisor remote；
- `update-ref` 是底层原语，但它比手写 ref 文件更安全，因为支持锁、reflog 和 expected-old 条件。

判断风险时列出实际读取和写入，不根据命令所属类别猜测。一本命令速查表若只标注 porcelain/plumbing，却不标对象、引用、index、工作区、网络和平台副作用，仍不足以指导事故操作。

## 高层命令提供的是编排

普通提交可以抽象为：

~~~text
工作区 --add/filter--> blob + index
index --write-tree--> root tree
tree + parents + metadata --commit--> commit object
当前引用 --conditional update--> new commit
~~

`git commit` 负责其中后半段的完整用户工作流。它确认 index 可写成 tree，解析作者和提交者身份，取得父提交，准备说明，运行适用 hooks，可按配置或选项签名，创建 commit，并更新当前分支或分离 `HEAD`。失败时还要维持 index、工作区和进行中操作的可恢复状态。

这些责任不能简化成“commit 等于 commit-tree”：

| 责任 | `git commit` 工作流 | 直接调用 `commit-tree` 后调用者要做什么 |
| --- | --- | --- |
| 候选快照 | 从当前 index 取得并检查未合并状态 | 提供已经验证的 tree OID |
| 父关系 | 从 `HEAD`/合并状态构造 | 按顺序传入每个 `-p` |
| 身份和时间 | 解析配置、环境与选项 | 明确环境、格式和审计来源 |
| 提交说明 | 编辑器、模板、cleanup 与校验流程 | 直接提供字节并自行校验 |
| Hooks | 运行 `git commit` 定义的适用 hooks | 不具备完整 commit hook 工作流，调用者另行执行策略 |
| 签名 | 按配置/选项创建签名 | 显式使用支持的签名选项并验证 |
| 引用移动 | 更新当前位置并写相应日志 | 另行使用带 expected-old 的引用更新 |
| 平台策略 | 本地命令本身不提供 | 仍由接收端/平台评审、权限和队列执行 |

Plumbing 适合实现 Git 工具、导入器、取证、可重复实验和受控恢复。日常开发若没有一个需要直接构造对象的明确理由，优先使用高层命令，让 Git 保留完整状态机。

## 从 blob 到 commit 的真实构造链

以下命令只在新建的可销毁仓库运行，并使用简单、受控的 ASCII 路径。先写 blob：

~~~bash
printf 'hello from plumbing\n' > payload.txt
blob_oid="$(git hash-object -w -- payload.txt)"
git cat-file -e "$blob_oid^{blob}"
~~~

`hash-object -w` 写入对象数据库，不更新 index、tree、commit 或 ref。`cat-file -e` 成功时没有输出。对象已存在时重复写入返回同一 OID，不产生第二份逻辑对象。

再用 tree 输入格式建立根 tree：

~~~bash
tree_oid="$(
  printf '100644 blob %s\tREADME.md\n' "$blob_oid" |
    git mktree
)"
git cat-file -e "$tree_oid^{tree}"
git ls-tree "$tree_oid"
~~~

`mktree` 默认校验输入对象存在，并把一层目录清单写为 tree。它不读取工作区中的 `README.md`，也不更新 index。真实路径可能包含制表符、换行、反斜线或非 ASCII 字节；工具应使用 `mktree -z`、NUL 安全解析和受信任结构化输入，不能把未知文件名拼进文本行。

用 tree 创建根 commit：

~~~bash
commit_oid="$(printf 'plumbing root\n' | git commit-tree "$tree_oid")"
git cat-file -e "$commit_oid^{commit}"
git rev-list --parents --max-count=1 "$commit_oid"
~~~

Commit 对象已经存在，但还没有普通 ref 指向它。`git log --all` 可以完全看不到该对象；它仍可用完整 OID 读取，并可能在后续维护前被恢复。

最后带“不存在”前置条件创建分支：

~~~bash
git update-ref -m 'import: publish verified root' \
  refs/heads/main "$commit_oid" ""
git rev-parse 'refs/heads/main^{commit}'
~~~

空的 expected-old 表示只在引用不存在时创建。若同名 ref 已被其他 writer 创建，命令失败且不覆盖。对象构造和 ref 更新不是一个跨步骤事务：进程可能在两者之间退出，留下合法但不可达的 commit。工具要保存候选 OID，重试前查询 ref 实际值，并为孤立对象提供恢复和清理策略。

## 引用更新不会同步 index 和工作区

刚才的 `update-ref` 只更新分支。新 commit 包含 `README.md`，当前 index 和工作区却没有这个路径。状态可能显示 index 相对新 `HEAD` 删除了它，同时原始 `payload.txt` 仍是未跟踪文件：

~~~bash
git status --porcelain=v1
git ls-files --stage
git ls-tree -r HEAD
~~~

这不是对象损坏，而是调用者只完成了对象与引用层。若该一次性仓库确实要检出刚构造的提交，可以在确认没有需要保留的工作区/index 内容后运行高层恢复：

~~~bash
git reset --hard HEAD
~~~

它会把 index 和已跟踪工作区重置到 `HEAD`，可能覆盖本地内容，因此不能照搬到真实项目。未跟踪的 `payload.txt` 不会因 `git reset --hard` 自动删除；不要追加 `clean` 只为得到空状态。

导入器若不需要工作区，应在 bare 仓库构造对象和 refs；需要工作区时使用受支持的 checkout/read-tree 流程并定义未跟踪冲突、filters、submodule、LFS、mode 和失败恢复。单独移动 ref 从来不是完整 checkout。

## 对象、引用和多引用事务分层处理

Git 对象按内容寻址。先写 blob/tree/commit，进程失败时通常留下可验证的不可达对象，不会得到一个“半个 commit”。引用更新则需要锁和比较前置条件：

~~~bash
git update-ref refs/heads/main "$new_oid" "$expected_old_oid"
~~~

多个 refs 需要一起变化时，使用当前版本的 `update-ref --stdin` 事务协议，在隔离环境验证 `start`、`prepare`、`commit` 与失败回滚。它只负责本地引用事务，不把以下状态纳入同一个原子边界：

- 新对象写入和对象物理清理；
- index、工作区和 linked worktree 的操作状态；
- 远端服务器 refs；
- 平台评审、CI 结果、权限和审计数据库；
- LFS、submodule、制品与部署状态。

本地多 ref 更新成功后，外部系统仍可能失败。迁移和发布需要幂等步骤、状态清单、old/new OID、补偿或前进恢复，不要把一个本地事务包装成分布式原子提交。

## 机器接口要显式选择

面向人的输出会因版本、配置、颜色、本地化、终端宽度和引用装饰变化。脚本不要解析默认 `status`、`branch` 或 `log --oneline`。优先使用命令提供的稳定模式：

| 需求 | 机器接口 | 关键边界 |
| --- | --- | --- |
| 工作区/index 状态 | `status --porcelain=v2 -z` | 按 NUL 和版本字段解析 |
| Index entries | `ls-files --stage -z` | 路径可含换行，OID 长度取决于格式 |
| 引用清单 | `for-each-ref --format=...` | 明确 namespace 和字段分隔 |
| 提交集合 | `rev-list --format=...` | 明确查询根、顺序和浅边界 |
| Tree entries | `ls-tree -z --format=...` | mode/type/OID/path 分开处理 |
| 批量对象元数据 | `cat-file --batch-check=...` | 处理 `missing`、promisor 和进程协议 |
| 远端 refs | `ls-remote --symref` | 网络、认证、权限和查询竞态 |

“Porcelain 格式”不意味着可以按空格切字符串。比如 rename/copy 状态含两个路径，路径本身可含换行。使用 `-z` 时按字节协议读取，不先转成 shell 变量；shell 变量不能保存 NUL。

自定义 `--format` 也需要格式版本管理。字段新增、缺失对象、replace refs、mailmap 和本地化都会影响解释。证据包保存 Git 版本、完整命令、配置来源、退出码、stdout/stderr 摘要和原始二进制输出，不只保存解析后的 JSON。

## `cat-file --batch` 适合长进程对象读取

逐对象启动 Git 会增加进程和对象库初始化成本。`cat-file --batch-check` 可以从标准输入连续接收对象表达式，返回类型和大小：

~~~bash
printf '%s\n%s\n' "$commit_oid" "$tree_oid" |
  git cat-file --batch-check='%(objectname) %(objecttype) %(objectsize)'
~~~

若输入无法解析，批处理协议会返回带 `missing` 等标记的记录；调用者要把它作为数据分支，不能假设每行永远有三个正常字段。`--batch-command` 和 `--buffer` 允许更细的请求/刷新控制，长驻进程必须处理写入关闭、超时、内存、协议同步和 Git 子进程退出。

不要把不受信任的 revision 文本直接交给允许 `:<path>`、`^{type}` 等语法的接口，再假设它只是 OID。需要精确对象时先验证对象格式和完整 OID，使用 `--end-of-options` 的命令应显式加上，并限制可访问仓库与 promisor 网络。

## Plumbing 不替代服务端与平台控制面

直接在本地生成一个 tree 与 commit，可以证明对象结构自洽，不能证明它经过团队要求的流程：

| 缺失证据 | 需要从哪里取得 |
| --- | --- |
| 作者/提交者对应受信 principal | 签名验证、身份目录和组织映射 |
| 候选经过目标基线上的测试 | CI 候选、流水线版本、runner 和结果 |
| 代码所有者批准 | 平台评审状态与候选绑定 |
| 分支更新获授权 | 接收端策略、主体、old/new OID 和审计事件 |
| 发布制品来自该 commit | 构建输入、制品摘要、签名与 provenance |

本地 hook 也不是完整信任边界。Plumbing 可以绕过高层命令触发的本地 hook 流程，调用者还能修改仓库配置和 hook 文件。强制策略应在受控接收端、CI 和发布系统中执行，并对所有写入入口进行行为测试。

托管平台的数据存储和引用实现属于厂商内部。管理员不应在平台磁盘上用 `update-ref` 绕过支持的 API、权限、复制、缓存和审计流程。本章实验只证明本地 Git 原语。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| `mktree` 报对象 unavailable | 输入 mode/type/OID、对象格式和仓库 | 补齐可信对象或修输入，不使用 `--missing` 掩盖缺口 |
| `commit-tree` 成功但 `log --all` 看不到 | commit OID、refs、reflog 和对象可读性 | 验证后创建 recovery/import ref，不先 prune |
| `update-ref` 旧值不匹配 | 实际 ref、并发 writer、候选基线 | 重算并重新审批，不去掉 expected-old |
| Ref 已移动但工作区像删除文件 | `HEAD` tree、index、工作区和替代 index | 识别未同步层；保护本地内容后使用受控检出 |
| 直接构造 commit 没触发检查 | 实际命令、hooks、签名、CI/平台策略 | 把候选送入强制验证流程，不补写虚假状态 |
| 批处理解析错位 | 原始输入/输出、NUL/换行、missing 记录 | 停止复用进程，从已知协议边界重新开始 |
| “只读”对象查询访问网络 | promisor/filter、对象是否本地、网络日志 | 在隔离完整副本读取，或明确批准 lazy fetch |
| 脚本在 SHA-256 仓库失败 | 固定 40 位正则、空 OID 和字段解析 | 从仓库格式取得长度，使用 Git API 解析 |

如果工具已经发布错误 ref，先阻止后续消费并保存 old/new OID、对象、index 和外部状态。未共享的本地错误可在建立恢复引用后修正；共享或发布状态按第七、八篇的历史与发布流程处置。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-porcelain-plumbing.sh
~~~

实验用 plumbing 从受控 payload 创建 blob、tree 和根 commit，验证每一步只写对象，commit 在 ref 创建前不属于 `--all` 可达集合。它再用 expected-old 创建 `main`，断言引用移动不会同步 index/工作区，随后只在可销毁仓库中用 `git reset --hard` 同步三层状态。

第二段用普通 `add`/`commit` 创建后继提交，核对其 tree、父提交和 stage 0；再验证 `mktree` 拒绝不存在对象、`cat-file --batch-check` 区分正常对象与 missing 输入，以及过期 expected-old 不能覆盖分支。实验不模拟 hooks、签名服务、平台权限、CI、部分克隆网络或生产导入事务。

## 小结

Porcelain 把常见意图编排成可恢复工作流，plumbing 暴露对象、引用和 index 原语。原语让工具精确控制数据模型，也把父关系、锁、环境、hooks、签名、错误恢复和外部策略的责任交给调用者。脚本选择机器格式并不等于安全完成；每一次写入仍要说明前置状态、实际副作用、条件更新和跨系统证据。

## 资料

- [gitglossary](https://git-scm.com/docs/gitglossary)
- [git](https://git-scm.com/docs/git)
- [git-hash-object](https://git-scm.com/docs/git-hash-object)
- [git-mktree](https://git-scm.com/docs/git-mktree)
- [git-commit-tree](https://git-scm.com/docs/git-commit-tree)
- [git-update-ref](https://git-scm.com/docs/git-update-ref)
- [git-cat-file](https://git-scm.com/docs/git-cat-file)
- [git-status](https://git-scm.com/docs/git-status)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
