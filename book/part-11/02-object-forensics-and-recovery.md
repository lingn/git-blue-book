# 对象还在不等于历史能回来：fsck、lost-found、pack 与替代对象库

分支被删后，提交可能仍在对象库；对象 ID 已知，也可能因为对应 blob 缺失而无法读出完整 tree；git fsck 报告通过，还可能只是因为 alternates 提供了本地没有的对象。对象取证不能只问“有没有这个哈希”，而要回答：对象字节来自哪里、类型和内容是否匹配、哪些根使它可达、是否有 replacement 改变解释、恢复后的历史是否满足业务目标。

本章延续上一章的约束：所有写入型探查和恢复都在受控证据派生出的可销毁副本中进行。原始文件系统快照、平台 refs/audit、LFS payload 与运行环境证据保持只读。实验基线为 Git 2.49.0、Bash 和 macOS；不同对象格式、reftable、partial clone、文件系统和托管平台需要单独验证。

进入本章前，读者应理解 blob/tree/commit/tag、可达性、reflog、packfile、partial clone、alternates、现场保护和证据摘要。读完后，应能：

- 准确区分 reachable、unreachable、dangling、missing 与 corrupt；
- 解释 git fsck 的根、选项、配置和 replacement/alternate 边界；
- 在恢复副本使用 --lost-found，而不把输出直接当正确历史；
- 检查 loose object、pack/idx 和 delta 链，选择可信 donor 恢复；
- 验证恢复后的对象、refs、tree、签名和外部依赖。

## 先统一五种状态

| 状态 | 工作定义 | 常见原因 | 直接恢复含义 |
| --- | --- | --- | --- |
| reachable | 从本次检查选定的 refs、HEAD、index、reflog 等根可遍历到 | 正常分支、tag、暂存对象或 reflog | 不等于业务上正确，也不等于所有副本健康 |
| unreachable | 对象存在，但从本次根集合不可达 | 删除分支、reset、rebase、临时接收对象 | 在被清理前可能建立恢复 ref |
| dangling | 不被其他对象直接使用的对象，常是一个不可达对象岛的候选 tip | 删除一段历史后留下末端 commit | 从它开始检查可能带回一组对象 |
| missing | 另一个对象或 ref 声明需要该 OID，但当前解析环境无法提供 | loose object 丢失、pack 缺失、alternate/remote 不可用 | 必须从可信来源取得精确字节 |
| corrupt | 找到的文件、pack 或对象解压/哈希/格式不符合声明 | 磁盘损坏、截断、并发写入、恶意篡改 | 先保全，不能靠重命名或跳过检查变健康 |

“本次根集合”是关键。默认 git fsck 会考虑 refs、index 和 reflogs；加 --no-reflogs 后，原本只受 reflog 保护的对象会变成 unreachable。指定一个或多个对象参数，又是在回答另一个范围的问题。报告中必须保存完整命令，而不是只写“跑过 fsck”。

Dangling 不是“坏对象”，missing 也不总是“本地仓库损坏”。Shallow repository 有显式浅边界，partial clone 允许 promisor remote 承诺缺失对象，alternates 允许从外部 object directory 读取。取证要先记录这些契约，再解释缺失。

## 在证据副本建立两个观察视角

假设 evidence_repo 是从已固定原始快照派生、禁止网络且允许销毁的副本：

~~~bash
evidence_repo=/absolute/restricted/work/INC-2026-001/repository-copy

git --no-optional-locks -C "$evidence_repo" \
  rev-parse --show-object-format --show-ref-format
git --no-optional-locks -C "$evidence_repo" \
  rev-parse --is-shallow-repository
git --no-optional-locks -C "$evidence_repo" \
  config --show-origin --show-scope --get-regexp \
  '^(extensions\.partialClone|remote\..*\.promisor|remote\..*\.partialclonefilter|fsck\.|fetch\.fsck\.|receive\.fsck\.)'
~~~

这些命令只读配置和仓库格式；没有匹配的配置查询返回 1，应记录为“未显式配置”，不能丢掉退出码。fsck.skipList、fsck.<msg-id> 以及 fetch/receive 对应设置可以降级或忽略某些检查信息，调查时必须保存来源。不要为了得到绿色结果临时添加 skip list。

接着分别观察 replacement 生效和禁用时的 refs/对象：

~~~bash
git --no-optional-locks -C "$evidence_repo" \
  for-each-ref --format='%(refname) %(objectname)' \
  refs/replace refs/heads refs/tags
GIT_NO_REPLACE_OBJECTS=1 \
  git --no-optional-locks -C "$evidence_repo" \
  cat-file -p HEAD
~~~

refs/replace/<原OID> 可以让很多 Git 命令在请求原对象时使用 replacement；历史 graft 也可能改变父关系解释。普通 show/log/cat-file 输出适合复现操作者当时看到什么，禁用 replacement 的输出适合读取原始对象。两者都要保存，不能发现 replace ref 后直接删除。

## fsck 是检查器，不是自动修复器

### 连接性初筛

~~~bash
fsck_exit=0
GIT_NO_REPLACE_OBJECTS=1 \
  git --no-optional-locks -C "$evidence_repo" \
  fsck --connectivity-only --no-progress \
  > connectivity.stdout \
  2> connectivity.stderr || fsck_exit="$?"
printf '%s\n' "$fsck_exit" > connectivity.exit
~~~

--connectivity-only 验证可达对象之间的连接，避免完整读取 blob 内容，适合先判断“哪个 commit/tree 声称需要一个当前拿不到的对象”。它不能证明 blob 字节健康，也不能发现秘密、恶意内容或业务错误。禁用 replacement 避免替代对象掩盖原对象关系。

命令可能因仓库规模、I/O 或 promisor 获取边界耗时；在证据副本禁网能防止调查不知不觉从远端补对象，但 partial clone 的结果必须标记“离线、承诺对象未取得”。非零退出不能中止证据保存，最终结论也不能写成通过。

### 完整对象检查

~~~bash
full_exit=0
GIT_NO_REPLACE_OBJECTS=1 \
  git --no-optional-locks -C "$evidence_repo" \
  fsck --full --strict --no-progress \
  > full.stdout \
  2> full.stderr || full_exit="$?"
printf '%s\n' "$full_exit" > full.exit
~~~

--full 显式检查 packs 和 alternate object stores，--strict 启用更严格检查。它会比连接性检查昂贵很多；在大仓库应记录开始/结束时间、CPU/I/O、Git 版本、alternates 与对象格式。成功表示这个解析环境未发现对应结构错误，不表示仓库自包含：对象可能全部由 alternate 提供。

不要在命令后立即运行 gc、repack 或 prune。它们会改变物理布局和不可达对象窗口，使“检查前的现场”无法复现。

## 从 refs、reflog 到不可达对象逐层找候选

先用有语义的来源，不从全库随机挑哈希：

1. refs 与 annotated tags；
2. HEAD/分支 reflog 和操作状态文件；
3. 评审、CI、发布清单保存的完整 OID；
4. 其他受控 clone、mirror、bundle 或备份；
5. 最后才是 unreachable/dangling 对象枚举。

在证据副本中比较 reflog 是否改变根集合：

~~~bash
git --no-optional-locks -C "$evidence_repo" \
  fsck --unreachable --no-progress \
  > unreachable-with-reflogs.txt 2>&1
git --no-optional-locks -C "$evidence_repo" \
  fsck --no-reflogs --unreachable --no-progress \
  > unreachable-without-reflogs.txt 2>&1
~~~

第一条把 reflogs 当根，第二条故意不把它们当根。只在第二份出现的 commit 通常仍受本地 reflog 保护；两份都出现的对象不由普通 refs/index/reflog 保持。结果受 replace refs、alternates、shallow/promisor 和配置影响，报告要附带前一节的环境记录。

拿到候选 OID 后逐步验证，不先建正式分支：

~~~bash
candidate=0123456789abcdef0123456789abcdef01234567

GIT_NO_REPLACE_OBJECTS=1 \
  git -C "$evidence_repo" cat-file -e "$candidate^{commit}"
GIT_NO_REPLACE_OBJECTS=1 \
  git -C "$evidence_repo" show \
  --no-patch --format='%H%n%P%n%T%n%aI%n%cI%n%s' "$candidate"
GIT_NO_REPLACE_OBJECTS=1 \
  git -C "$evidence_repo" ls-tree -r --full-tree "$candidate"
~~~

示例 OID 只适用于 SHA-1 仓库，必须替换为报告中的完整候选；SHA-256 仓库长度不同。cat-file -e 成功只证明对象可解析为 commit，随后还要核对父关系、tree、时间、提交说明、签名和业务内容。不要根据一行 subject 自动恢复。

## --lost-found 会写仓库

git fsck --lost-found 会在 Git directory 的 lost-found/commit 或 lost-found/other 写入 dangling 对象的线索/内容。因此它不属于原始现场只读采集。

只在可销毁副本运行：

~~~bash
git_dir="$(
  git -C "$evidence_repo" \
    rev-parse --path-format=absolute --git-dir
)"
test ! -e "$git_dir/lost-found"

git -C "$evidence_repo" \
  fsck --no-reflogs --lost-found --no-progress \
  > lost-found.stdout 2> lost-found.stderr
find "$git_dir/lost-found" -type f -print
~~~

命令新增 lost-found 文件，不自动建立 refs/heads，不判断哪个 dangling commit 属于事故目标。输出为空可能表示没有候选、对象已被清理、仍由其他根保持，或检查失败；必须结合退出码和 stderr。

确认候选后先建隔离命名空间：

~~~bash
git -C "$evidence_repo" \
  update-ref refs/recovery/INC-2026-001/candidate-01 \
  "$candidate" \
  0000000000000000000000000000000000000000
~~~

前提是当前对象格式为 SHA-1；SHA-256 仓库应使用对应长度的全零 OID，或使用本章实验中的分支创建方式。带期望旧值的 update-ref 只在目标 ref 不存在时创建，避免覆盖另一位调查者的候选。它会写恢复副本的 refs/reflog，不得在原始证据执行。

## Loose object 缺失：先确认是谁提供对象

一个 loose object 的路径通常由 object directory、OID 前两位和其余字符组成，但取证时不要手工按路径猜内容。先请求类型、大小和原始内容：

~~~bash
oid=0123456789abcdef0123456789abcdef01234567

GIT_NO_REPLACE_OBJECTS=1 \
  git -C "$evidence_repo" cat-file -t "$oid"
GIT_NO_REPLACE_OBJECTS=1 \
  git -C "$evidence_repo" cat-file -s "$oid"
~~~

如果命令成功，字节可能来自当前 loose object、pack、alternate 或 partial clone 按需下载。禁网环境不会排除 alternate。用 git count-objects -v、objects/info/alternates、GIT_ALTERNATE_OBJECT_DIRECTORIES 和受控系统调用证据确认来源。

### Alternate 会掩盖本地缺失

假设损坏副本丢了一个 blob，却配置了 donor object directory：

~~~text
damaged/.git/objects/info/alternates
    -> /restricted/donor.git/objects
~~~

此时 cat-file 和 fsck --full 可能成功，因为解析环境完整；移走 donor 后同一仓库失败。正确结论是“仓库依赖该 alternate”，不是“本地对象库自包含且健康”。备份必须同时保存 alternate 或把依赖对象显式收拢到经过验证的新对象库。

不要在原现场删除 alternates 来测试。复制其配置与依赖目录，在恢复副本做有/无 alternate 的对照，并保存两次结果。

### 从可信 donor 恢复单个 blob

只有已经确认 donor 的对象格式、OID、来源时间点和访问授权后，才在恢复副本写对象：

~~~bash
missing_blob=0123456789abcdef0123456789abcdef01234567
donor_repo=/absolute/restricted/donor-copy
recovery_repo=/absolute/restricted/recovery-copy
payload_file=/absolute/restricted/work/missing-blob.payload

GIT_NO_REPLACE_OBJECTS=1 \
  git -C "$donor_repo" cat-file blob "$missing_blob" \
  > "$payload_file"
test "$(
  git -C "$recovery_repo" hash-object "$payload_file"
)" = "$missing_blob"
test "$(
  git -C "$recovery_repo" hash-object -w "$payload_file"
)" = "$missing_blob"
~~~

第一条从 donor 读取完整 blob 字节，第二条在不写对象时按 recovery repo 的对象格式重算身份，第三条才写入恢复副本。路径必须位于受控工作目录，payload 可能含秘密。恢复 commit/tree/tag 时应先验证对象原始格式，不能把任意字节声明成相应类型。

如果 donor 只有相同文件的工作区副本而没有来源证明，重算得到同一 OID 可以证明字节一致，但不能证明该副本在何时、由谁保管。调查记录要区分“内容已重建”和“来源链完整”。

## Pack/idx 故障：不要抽取压缩片段拼对象

Packfile 把多个对象压缩在一起，对象可能使用 OFS_DELTA/REF_DELTA 依赖另一个基础对象。idx 把 OID 映射到 pack offset，并保存校验信息；rev、bitmap、MIDX 和 commit-graph 是辅助数据。一个对象的磁盘片段不等于可独立恢复的完整对象。

在恢复副本列出 pack 文件与摘要后：

~~~bash
pack_dir="$(
  git -C "$evidence_repo" \
    rev-parse --path-format=absolute --git-path objects/pack
)"
find "$pack_dir" -maxdepth 1 -type f -print
git -C "$evidence_repo" verify-pack -v \
  "$pack_dir/pack-REPLACE_WITH_EXACT_NAME.idx" \
  > verify-pack.stdout 2> verify-pack.stderr
~~~

占位文件名必须换成清单中的精确 idx。verify-pack -v 检查对应 pack/index 并列出对象、大小、offset 和 delta 信息，可能产生很大输出；-s 只给统计，不适合替代完整故障诊断。非零退出时保留 pack/idx 原件、文件摘要、大小、mtime、I/O 错误和并发进程。

恢复顺序：

1. 从同一时间点的已验证快照恢复匹配的完整 pack/idx 组合；
2. 若 donor packing 不同，从 donor 按逻辑 OID 导出缺失对象，并在新对象库重新写入；
3. 对大量对象缺失，优先从完整 mirror/bundle/备份派生新仓库，再比较 refs；
4. 只有对象完整后，才重建 MIDX、bitmap、commit-graph 等辅助数据。

不要在原 pack 上运行会覆盖文件的修复工具，不要从另一个仓库复制“名字相似”的 idx，也不要先删除坏 pack 再希望 gc 自动下载缺失对象。Repack 只能重新组织当前可读对象，不能凭空恢复已经丢失的字节。

## Shallow 与 partial clone 的缺失契约

~~~bash
git -C "$evidence_repo" rev-parse --is-shallow-repository
git -C "$evidence_repo" \
  config --show-origin --get-regexp \
  '^extensions\.partialClone$|^remote\..*\.promisor$|^remote\..*\.partialclonefilter$'
~~~

Shallow boundary 记录在仓库元数据中，边界之外祖先未取得是既定状态；promisor remote 则承诺可按需提供某些对象。两者都增加恢复依赖：

- 服务端不可用时，本地 clone 可能从未拥有完整历史；
- 按需读取会改变本地对象库并接触网络，不适合未授权原现场；
- remote 提供一个同 OID 对象只证明内容寻址一致，服务身份和完整 refs 仍需验证；
- 普通 bundle/备份若只从受限 clone 生成，也可能继承不完整性。

灾难恢复设计不能把浅/部分 clone 当唯一备份。至少有一个受控来源验证全 refs、对象、LFS payload 和平台元数据的恢复能力。

## 恢复验收不是 fsck 变绿

| 层 | 必须验证 | 仍不能证明 |
| --- | --- | --- |
| 物理对象 | pack/loose 字节可读，OID、类型、大小和 fsck 符合 | 候选属于正确历史 |
| 图与 refs | 父关系、tree、tags、recovery refs 与预期映射一致 | 工作区、LFS、submodule 完整 |
| 仓库依赖 | 无意外 alternates/replace refs，shallow/promisor 状态已登记 | 平台规则和审计已恢复 |
| 内容与签名 | tree diff、构建测试、commit/tag 签名按事故时间策略验证 | 当前签名者仍有发布授权 |
| 外部系统 | LFS payload、submodule OID、CI artifact、评审和权限核对 | 生产数据与运行状态正确 |

恢复对象后至少重新运行禁用 replacement 的 fsck --full，比较事故前/后 ref 快照，验证关键 commit/tree，并在新 clone 测试可迁移性。若 recovery repo 仍依赖 donor alternate，断开 donor 后再验一次；否则上线后删除取证存储可能再次造成缺失。

任何恢复到正式远端的引用更新都要独立审批、带 old/new OID、使用条件更新并保留平台审计。对象层恢复完成不授权强推。

## 合成实验：四类对象现场

本书提供 scripts/verify-object-forensics-recovery.sh，只在 mktemp 下创建可销毁仓库，不接触本书对象库或远端。

在仓库根目录执行：

~~~bash
bash scripts/verify-object-forensics-recovery.sh
~~~

脚本验证：

1. 删除实验分支后，默认 reflog 仍保护 commit；--no-reflogs --unreachable 才列出该对象；
2. --lost-found 在恢复副本写入候选文件，原证据副本保持无 lost-found；
3. 移走一个 loose blob 后 fsck 失败，配置 donor alternate 会暂时通过；移除 alternate 又暴露缺失；
4. 从 donor 读取完整 blob、先重算 OID、再 hash-object -w，使恢复副本重新通过；
5. replace ref 让普通读取呈现另一个 tree，GIT_NO_REPLACE_OBJECTS=1 仍读取原对象；
6. 实验 pack 被截断后 verify-pack 和 fsck 失败，恢复同一快照的完整 pack/idx 后重新通过；
7. 最终检查 refs、关键 tree 和对象自包含性，随后才建立恢复 ref。

实验通过不能外推真实磁盘、加密卷、SHA-256 仓库、reftable、cruft pack、partial clone、平台隐藏 refs 或法律取证。真实损坏中先保全原始字节，再让存储/Git 专家在副本分析。

## 小结

对象取证的核心不是“让 fsck 不报错”，而是为每个候选建立根、字节来源、对象身份、依赖和业务语义。Reflog 可能暂时保护历史，lost-found 只输出线索，alternates 和 replace refs 会改变解释，pack delta 又让物理片段不能独立恢复。

恢复工作必须在副本中逐层推进：先检查范围和配置，再找有语义的候选；从可信 donor 取精确字节，验证 OID 后写入；最后检查 refs、tree、签名和外部系统。下一章将把对象证据扩展为历史归因，处理 blame、pickaxe、pathspec、rename 和“某段逻辑究竟何时改变”的调查链。

## 资料

- [git-fsck](https://git-scm.com/docs/git-fsck)
- [git-cat-file](https://git-scm.com/docs/git-cat-file)
- [git-hash-object](https://git-scm.com/docs/git-hash-object)
- [git-verify-pack](https://git-scm.com/docs/git-verify-pack)
- [gitformat-pack](https://git-scm.com/docs/gitformat-pack)
- [git-index-pack](https://git-scm.com/docs/git-index-pack)
- [git-replace](https://git-scm.com/docs/git-replace)
- [gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)
- [git-count-objects](https://git-scm.com/docs/git-count-objects)
- [Partial Clone Design Notes](https://git-scm.com/docs/partial-clone)
