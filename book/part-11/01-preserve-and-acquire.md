# 先冻结，再恢复：Git 事故现场保护与证据采集

事故现场最危险的动作通常不是某一条 Git 命令，而是没有先定义恢复目标就连续试错。一次新的 fetch 会移动远程跟踪引用和 `FETCH_HEAD`；一次 reset 可能覆盖 `ORIG_HEAD`；后台维护可能回收不可达对象；编辑器、IDE 或文件同步程序也可能继续写工作区。等到“仓库看起来正常”，关键证据可能已经改变。

本章的工作定义是：**现场保护**先停止或隔离会改变证据的活动；**证据采集**从固定时间点保存原始字节、Git 逻辑状态、平台控制面和运行环境信息；**恢复工作副本**则从受控证据派生，允许试验但不能反向污染原件。这三者不是同一个目录。

本章以 Git 2.49.0、Bash 和 macOS 为本地验证基线。文件系统快照、虚拟机快照、云盘一致性、平台审计、法律保全和内存取证依赖实际基础设施与权限，不能由本地 Git 实验代替。进入本章前，读者应理解对象、refs、index、reflog、worktree、submodule、LFS 与远程跟踪引用。

读完后，你应能：

- 按逻辑误操作、对象/存储故障、服务故障和安全/合规事件分流；
- 在恢复前保存工作区、index、refs、reflog、进行中操作和对象库证据；
- 识别 linked worktree、submodule、alternates 和 partial clone 的外部依赖；
- 为采集输出建立清单、摘要、退出状态、访问控制和保管记录；
- 解释普通 clone、mirror clone、bundle 和文件系统快照各自保留什么。

## 先写恢复目标，再决定要不要动现场

至少回答四个问题：

1. **恢复什么**：某个文件、分支头、完整对象库、服务能力，还是可供调查的原始状态？
2. **恢复到何时**：最后一次已知正确提交、事故前 ref 快照、备份时间点，还是业务一致性时间？
3. **允许丢什么**：未提交字节、reflog、平台评审状态、LFS payload、构建制品或审计日志能否丢失？
4. **谁有权决定**：仓库 owner、事件指挥、安全团队、存储管理员或法务，谁批准隔离、恢复和删除？

同一症状可能对应完全不同的事故：

| 事故类别 | 主要风险 | 第一目标 | 立即避免 |
| --- | --- | --- | --- |
| 逻辑误操作 | ref、index 或工作区被错误改变 | 保存当前状态和可恢复对象 | 连续 reset/rebase、GC、clean |
| 对象/存储故障 | pack、磁盘或文件系统字节损坏 | 阻止继续写，取得底层一致快照 | repack、prune、从不明来源覆盖对象 |
| 服务不可用 | 远端、网络、认证或区域故障 | 保留客户端/服务端时间点和依赖状态 | 把陈旧 clone 直接提升为权威远端 |
| 安全/合规事件 | 凭据、恶意对象、未授权更新或证据销毁 | 隔离访问并维持证据链 | 扩散秘密、擅自清理、让可疑主机继续联网 |

普通开发者可自行处理一个尚未推送的误删分支；疑似主机入侵、平台管理员滥用或法律保全不能沿用同一权限。若采集行为会触发恶意 filter、访问生产凭据、改变远端或违反保留要求，先升级事件等级。

## 四层证据必须分开

### 1. 文件系统现场

它包含工作区文件、未跟踪文件、index、对象库、refs、reflog、hooks、local config、锁文件、进行中操作目录和文件时间等原始字节。Linked worktree 的管理目录可能在 common Git directory 中，submodule 又有自己的 Git directory；只复制当前目录不一定复制了仓库。

### 2. Git 逻辑快照

这是用 Git plumbing/porcelain 读取出的 HEAD、refs、提交图、index stage、差异、reflog、对象统计和完整性结果。它便于解释，但属于派生证据；命令版本、配置和对象缺失都会影响输出。

### 3. 平台控制面

受保护分支规则、引用更新审计、评审、CI run、artifact、deploy key、身份会话和服务端隐藏 refs 不在普通 clone 的 Git 历史里。平台 API 导出和管理员日志必须单独采集，并记录产品版本、时区、查询条件、分页和权限。

### 4. 运行环境

进程、打开文件、挂载点、磁盘错误、网络连接、容器/虚拟机、环境变量和内存可能解释谁仍在写仓库。Git 不采集这些信息。疑似入侵现场应由取证人员使用可信工具处理，不能为了“看一下”把完整环境变量打印到普通日志。

## 冻结不是把目录 chmod 一次

先暂停自动化写入：CI 发布、机器人 push、镜像同步、IDE 后台 Git、定时 `git maintenance`、文件同步和备份回写。对远端事故，应在控制面冻结目标 refs 或仓库写入，同时记录冻结起点和例外身份。

真正的一致文件系统证据优先来自：

- 存储、虚拟机或文件系统的时间点快照；
- 已停写卷的受控镜像；
- 由备份系统产生、可验证恢复的一致副本。

对仍在变化的目录执行普通复制，可能把旧 index、新 refs 和半写 pack 拼成一个从未真实存在过的组合。复制命令成功不能证明时间点一致。快照前若必须 quiesce 应用，记录开始/结束时间、暂停组件、失败和回滚步骤。

下面的 Git 选项只能减少部分客户端写入：

~~~bash
git --no-optional-locks status --porcelain=v2 --branch
~~~

`--no-optional-locks` 让 Git 避免为性能刷新而取得可选锁，例如减少某些状态命令刷新 index 的机会。它不把仓库挂成只读，不阻止命令自身的必要写入，也不能约束其他进程。`git fetch`、`git reset`、`git gc` 等仍会改变状态；不要给所有命令加上该选项后就称“只读取证”。

## 先确认仓库实际分布在哪里

在可信 Shell、事故路径已经过人工核对且仓库所有权门禁允许读取的前提下：

~~~bash
incident_path=/absolute/path/to/incident-worktree

git --no-optional-locks -C "$incident_path" \
  rev-parse --path-format=absolute \
  --show-toplevel --git-dir --git-common-dir
git --no-optional-locks -C "$incident_path" worktree list --porcelain
~~~

第一条输出 worktree 根、当前 Git directory 和 common Git directory。普通仓库三者关系简单；linked worktree 的 `.git` 可能只是指向 common directory 管理项的文本文件。第二条列出已登记 worktrees，其路径、HEAD 和分支可能包含内部信息。

命令不移动 refs 或改文件。`--show-toplevel` 在 bare 仓库失败；此时使用已核对的 `--git-dir` 路径单独采集。若出现 dubious ownership，先按第十篇的 owner 调查，不要全局设置 `safe.directory=*` 绕过。

继续盘点外部对象来源：

~~~bash
git --no-optional-locks -C "$incident_path" \
  rev-parse --is-bare-repository --is-shallow-repository
git --no-optional-locks -C "$incident_path" \
  config --show-origin --show-scope --get-regexp \
  '^(extensions\.partialClone|remote\..*\.promisor|remote\..*\.partialclonefilter)$'
object_dir="$(
  git --no-optional-locks -C "$incident_path" \
    rev-parse --path-format=absolute --git-path objects
)"
test -f "$object_dir/info/alternates" &&
  sed -n '1,120p' "$object_dir/info/alternates"
~~~

配置查询没有匹配时返回非零，不一定是故障。Alternates 文件、`GIT_ALTERNATE_OBJECT_DIRECTORIES`、partial-clone promisor、submodule 和 LFS cache 都可能让当前目录依赖外部字节。输出可能暴露绝对路径和远端名，应进入受限证据。

## 建立采集目录，不写回事故仓库

采集目录应位于独立、访问受控、容量足够的存储，不能放进事故 worktree、Git directory 或其挂载点。下面只建立逻辑证据目录；原始文件系统快照由基础设施流程完成：

~~~bash
evidence_root=/absolute/restricted/evidence/INC-2026-001
install -d -m 0700 "$evidence_root"
evidence_dir="$evidence_root/git-logical-001"
install -d -m 0700 "$evidence_dir"
~~~

前提是两个绝对路径已经人工核对，不是符号链接，并且容量、加密、保留期和备份符合事件等级。`install -d` 创建目录并设置访问模式，不改变事故仓库。目录已存在或权限不足时停止，不要退回到仓库内或公共临时目录。

每条采集命令都要保存：

- 完整命令或采集器版本；
- 开始/结束时间和时区；
- stdout、stderr、退出码；
- Git/操作系统版本和执行主体；
- 输入仓库/快照的稳定标识；
- 输出文件摘要。

退出码非零也是证据，不能用空文件伪装成功。

## 第一组：身份、时间和布局

~~~bash
{
  date -u '+utc=%Y-%m-%dT%H:%M:%SZ'
  printf 'cwd=%s\n' "$incident_path"
  git --version
  uname -a
} > "$evidence_dir/environment.txt"

git --no-optional-locks -C "$incident_path" \
  rev-parse --path-format=absolute \
  --show-toplevel --git-dir --git-common-dir \
  > "$evidence_dir/layout.txt" \
  2> "$evidence_dir/layout.stderr"
~~~

这些输出不证明主机时钟可信。跨主机调查需要 NTP/平台事件时间和日志接收时间交叉核对。`uname` 可能暴露主机名；对外共享前生成脱敏副本，不能修改受控原件。

## 第二组：工作区、index 和进行中操作

机器可读输出使用 NUL 分隔，避免特殊路径破坏记录：

~~~bash
git --no-optional-locks -C "$incident_path" \
  status --porcelain=v2 --branch -z \
  > "$evidence_dir/status.porcelain-v2.nul"
git --no-optional-locks -C "$incident_path" \
  ls-files --stage -z \
  > "$evidence_dir/index-stage.nul"
git --no-optional-locks -C "$incident_path" \
  diff --binary --no-ext-diff --no-textconv -- \
  > "$evidence_dir/worktree.diff"
git --no-optional-locks -C "$incident_path" \
  diff --cached --binary --no-ext-diff --no-textconv -- \
  > "$evidence_dir/index.diff"
~~~

`status` 记录 tracked/untracked/conflict 与分支头，`ls-files --stage` 记录 index 中的 mode、OID、stage 和路径。两份 diff 分别保存 index 到工作区、HEAD 到 index 的差异。`--no-ext-diff --no-textconv` 避免运行仓库配置的外部 diff/textconv，但不能替代操作系统隔离。

Diff 不是原始字节备份：未跟踪文件内容不在其中，二进制补丁也不等于完整文件系统元数据。原始快照必须保存工作区字节、symlink、权限和扩展属性。若 diff 因缺失对象、filter 或损坏失败，保存 stderr/退出码，不要先 restore 文件“让它成功”。

进行中操作还需要保存 Git directory 中的状态：

~~~bash
for state_name in \
  MERGE_HEAD MERGE_MSG CHERRY_PICK_HEAD REVERT_HEAD REBASE_HEAD \
  rebase-merge rebase-apply sequencer
do
  state_path="$(
    git --no-optional-locks -C "$incident_path" \
      rev-parse --path-format=absolute --git-path "$state_name"
  )"
  if test -e "$state_path"; then
    printf '%s\t%s\n' "$state_name" "$state_path"
  fi
done > "$evidence_dir/operation-state.paths"
~~~

路径清单只是定位。实际目录和文件字节应由原始快照保留；直接 `cat` `MERGE_MSG` 可能把敏感提交说明写进公开终端。不要在采集前执行 `merge --abort`、`rebase --abort` 或删除锁文件。

## 第三组：HEAD、refs 与 reflog

~~~bash
git --no-optional-locks -C "$incident_path" \
  rev-parse --verify HEAD \
  > "$evidence_dir/head.oid"
git --no-optional-locks -C "$incident_path" \
  symbolic-ref -q HEAD \
  > "$evidence_dir/head.symbolic" \
  2> "$evidence_dir/head.symbolic.stderr" || :
git --no-optional-locks -C "$incident_path" \
  for-each-ref \
  --format='%(refname)%00%(objecttype)%00%(objectname)%00%(*objectname)%00' \
  > "$evidence_dir/refs.nul"
git --no-optional-locks -C "$incident_path" \
  reflog show --all --date=iso-strict \
  --format='%H%x00%gD%x00%gs%x00' \
  > "$evidence_dir/reflog.nul"
~~~

`head.oid` 固定当前提交；`head.symbolic` 区分分支附着与 detached HEAD；refs 记录直接对象和附注 tag 剥离目标；reflog 记录当前仓库可见的本地移动历史。符号 HEAD 查询在 detached 状态返回非零，因此示例保留空 stdout 和 stderr，而不是把它当总采集失败。

普通 `--all` 只覆盖当前仓库可见 refs/reflogs。平台隐藏 refs、另一个 clone 的 reflog、过期日志和已回收对象必须从其他来源取得。Ref snapshot 也不证明远端此刻值相同；网络查询应在本地现场保全后单独进行并记录认证主体与时间。

## 第四组：配置和执行入口

~~~bash
git --no-optional-locks -C "$incident_path" \
  config --show-origin --show-scope --null --list \
  > "$evidence_dir/config.nul"
git --no-optional-locks -C "$incident_path" \
  remote --verbose \
  > "$evidence_dir/remotes.txt"
~~~

配置输出能解释 hooks、filters、credential helper、remote URL、alternates 相关行为，却可能直接包含 token、Authorization header 和内部地址。证据目录要先具备正确权限；采集后生成脱敏工作副本，不覆盖原件。

读取配置与“用配置执行命令”是两件事。后续分析应在无生产凭据、禁网的可信环境中显式关闭外部 diff、textconv、fsmonitor 和可疑 hooks/filters；不能直接在原主机反复运行开发命令。

## 第五组：对象库和辅助文件

先做低成本盘点：

~~~bash
git --no-optional-locks -C "$incident_path" \
  count-objects -vH \
  > "$evidence_dir/count-objects.txt"
fsck_exit=0
git --no-optional-locks -C "$incident_path" \
  fsck --connectivity-only --no-progress \
  > "$evidence_dir/fsck-connectivity.stdout" \
  2> "$evidence_dir/fsck-connectivity.stderr" || fsck_exit="$?"
printf '%s\n' "$fsck_exit" > "$evidence_dir/fsck-connectivity.exit"
~~~

`count-objects` 输出 loose/pack 数量、大小、garbage 和 alternate 信息。`fsck --connectivity-only` 检查可达对象关系，比完整 blob 校验更轻，但仍可能非常耗时；partial clone、alternates 和损坏会改变结果。示例把非零状态保存到变量，避免 `set -e` 在写入退出码前终止；采集总状态仍必须标记失败，不能因为继续采集就把错误降级为成功。

完整 `git fsck --full`、`git verify-pack`、全对象哈希和大 pack 复制应在文件系统证据副本上运行。不要在原现场使用 `--lost-found`，它会向 `$GIT_DIR/lost-found` 写入引用文件；也不要运行 `repack`、`prune` 或 `gc`“修复”对象布局。

对象库证据还应包括：

- `objects/pack` 下 pack、idx、rev、keep、promisor 和 multi-pack-index 文件；
- commit-graph、shallow boundary、alternates 文件和 replace refs；
- 文件大小、时间、owner、权限及逐文件摘要；
- LFS cache/payload、submodule Git directory 和 linked worktree common directory；
- 存储/内核 I/O 错误与底层快照标识。

逻辑命令无法保留被后续覆盖的文件系统块；底层原始证据必须先于修复。

## 证据清单、摘要和保管链

在采集目录外层生成文件清单，并按字节摘要固定每个输出。以下命令只适用于已经完成写入且文件名由采集器控制的目录：

~~~bash
(
  cd "$evidence_dir"
  find . -type f ! -name 'SHA256SUMS' -print0 |
    sort -z |
    while IFS= read -r -d '' evidence_file; do
      if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$evidence_file"
      else
        sha256sum "$evidence_file"
      fi
    done
) > "$evidence_dir/SHA256SUMS"
~~~

SHA-256 证明之后拿到的文件是否与计算摘要时相同，不证明采集主体、时间或来源真实。保管记录还要写明事件 ID、采集者、原始来源、快照 ID、每次移交、访问、派生副本和销毁批准；高等级证据使用组织信任根签名或不可变日志。

清单本身可能泄漏路径和调查范围。原件与分享副本分开授权，脱敏、解密或格式转换都生成新的派生物和新摘要，不覆盖原文件。

## 为什么 clone、mirror 和 bundle 都不是完整现场

| 手段 | 通常保留 | 默认遗漏 | 合适用途 |
| --- | --- | --- | --- |
| 普通 clone | 服务器广告 refs 可达对象、默认工作区、远程配置 | 原工作区/index、未跟踪文件、本地 reflog/config/hooks、隐藏 refs、不可达对象 | 干净开发副本 |
| mirror clone | 服务器广告的更多 refs/对象与 mirror 映射 | 客户端现场、服务端隐藏状态、未广告对象、平台元数据 | 迁移/备份工作副本 |
| bundle | 指定 refs 可达 Git 对象和 prerequisites | 工作区/index/reflog/config/hooks、未选择 refs、不可达对象、LFS payload | 离线传输已选历史 |
| 文件系统快照 | 该时间点文件系统字节与元数据，取决于实现 | 平台 API、内存、外部对象存储、未纳入卷 | 原始现场与恢复基线 |

`git bundle create repository.bundle --all` 中的 `--all` 仍表示当前 Git refs 集合，不包含未暂存/暂存但未提交内容，也不自动包含 LFS payload。Bundle 可以是受控证据的派生交换格式，不能替代原始快照。

Mirror clone 从远端取得的是服务器愿意广告和授权读取的状态。若远端仍在变化，它也不是一致事故时间点；若来源被攻陷，它复制的是可疑来源提供的对象。迁移和恢复章节会给 mirror/bundle 配置独立验证门禁。

## 从证据派生恢复工作副本

原始快照设置只读、限制访问并保留摘要。恢复人员从它创建可销毁副本，在副本中：

1. 禁止网络和生产凭据；
2. 记录 Git/工具版本；
3. 先运行低成本对象和 refs 检查；
4. 为候选对象创建 `refs/recovery/...`，不修改原始 refs；
5. 比较 tree、提交图和业务测试；
6. 记录每次试验输入、命令、结果和副本销毁。

若恢复动作失败，删除的是可销毁副本，从同一原始快照重新派生。不要在原始证据上“撤销刚才的 reset”；第二次写入不能还原被覆盖的文件时间、reflog 和对象布局。

## 常见失败与处置

| 失败 | 判别证据 | 安全处置 |
| --- | --- | --- |
| 采集期间 refs 继续变化 | 开始/结束 ref 快照不同，平台仍有写事件 | 停止宣称一致，重新冻结并取得新快照；保留失败采集 |
| 输出写进事故仓库 | status 出现新文件，对象/磁盘统计变化 | 停止，记录污染；新建外部证据目录并从原始快照重采 |
| diff/status 触发可疑外部程序 | 子进程、审计日志、配置中的 driver | 隔离主机；在证据副本用可信配置和 `--no-ext-diff --no-textconv` 重做 |
| `fsck` 报 missing/corrupt | stderr、退出码、对象 OID、I/O 日志 | 不 repack；保存底层快照，从已验证备份/其他副本取候选对象 |
| 普通 clone 看起来正常 | clone 能 checkout，但现场有未提交或 reflog 证据 | 保留 clone 作为派生物，回到文件系统/平台证据 |
| 证据目录含秘密或个人数据 | 配置、diff、reflog、CI 导出 | 收紧访问，生成脱敏副本，执行保留/销毁规则 |
| SHA 清单不匹配 | 重新计算摘要不同 | 停止使用该副本，调查传输/存储；从受控原件重新派生 |

## 合成实验：采集前后状态不变

本书提供 `scripts/verify-forensic-acquisition.sh`。它在 `mktemp` 目录构造一个含分支、tag、notes、reflog、暂存变化、未跟踪文件和未完成 merge 的仓库，然后用受限只读命令采集逻辑证据。

在蓝皮书仓库根目录执行：

~~~bash
bash scripts/verify-forensic-acquisition.sh
~~~

实验验证：

1. 采集目录位于事故仓库外，尝试写到 worktree 内会被拒绝；
2. 状态、index stages、工作区/index diff、refs、reflog、config、操作状态和对象统计均有独立输出；
3. 采集前后 HEAD、refs、index 字节、冲突文件和 `MERGE_HEAD` 不变；
4. 普通 clone 不包含未完成 merge、index、未跟踪文件、local config、原仓库 reflog 和不可达 blob；
5. SHA-256 清单能发现人为修改的派生证据，随后从未改动采集重新生成；
6. 只有采集完成后，实验才在原 fixture 执行 `merge --abort`，证明恢复动作与原证据目录分离。

脚本只证明这些 Git 逻辑命令在合成 fixture 中的边界。它不创建法证磁盘镜像，不验证 APFS/ZFS/LVM/云盘崩溃一致性，不采集内存、平台审计、LFS 服务或恶意主机；真实安全事件必须使用组织批准的取证流程。

## 小结

恢复的第一步是维持选择空间。先冻结写入并取得文件系统/平台时间点，再从证据副本生成 Git 逻辑快照；工作区、index、refs、reflog、对象库和进行中操作缺一不可。`--no-optional-locks` 只能减少可选写入，clone、mirror 和 bundle 也各自只保存部分状态。

一个可恢复的组织不会把“某个工程师电脑上还有一个 clone”当备份。它会为原始证据、派生分析副本、恢复候选和重新上线分别建立摘要、权限、责任人和验收条件。下一章将在这个前提下处理 `fsck`、不可达对象、pack 和对象替代来源。

## 资料

- [git-rev-parse](https://git-scm.com/docs/git-rev-parse)
- [git-status](https://git-scm.com/docs/git-status)
- [git-ls-files](https://git-scm.com/docs/git-ls-files)
- [git-diff](https://git-scm.com/docs/git-diff)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-reflog](https://git-scm.com/docs/git-reflog)
- [git-count-objects](https://git-scm.com/docs/git-count-objects)
- [git-fsck](https://git-scm.com/docs/git-fsck)
- [gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)
- [git-worktree](https://git-scm.com/docs/git-worktree)
- [git-clone](https://git-scm.com/docs/git-clone)
- [git-bundle](https://git-scm.com/docs/git-bundle)
