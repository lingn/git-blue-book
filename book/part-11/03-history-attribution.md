# 谁改了这一行：历史归因、搜索与证据边界

“是谁改了这一行？”通常不是一个 Git 命令能独立回答的问题。blame 可以指出当前文件行最近一次被某个提交写入，不能证明这个人设计了业务规则；pickaxe 可以找到某个字符串数量改变的提交，不能证明字符串就是逻辑边界；提交说明、评审、CI 和运行日志又分别属于不同证据系统。

本章把历史调查定义成一个可复核的过程：先固定调查问题、候选 refs、路径和时间范围；再从提交图、tree、diff、作者/提交者、提交说明和重命名证据缩小范围；最后把 Git 结果与测试、评审、发布和运行证据交叉验证。调查副本可以使用只读 Git 命令，原始现场仍遵循前两章的冻结和摘要规则。

本章以 Git 2.49.0、Bash 和 macOS 为验证基线。rename detection、相似度、编码、生成文件、浅/部分克隆和平台隐藏 refs 会改变结果。实验使用匿名角色和合成提交，不把作者名字或固定 OID 当成可推广结论。

进入本章前，读者应理解提交图、父关系、tree/blob、refs、merge、reflog 和现场证据。读完后，应能：

- 把“谁负责”拆成行级最后修改、逻辑引入、评审批准和运行变更四个问题；
- 选择 blame、log path、--follow、-S、-G、--grep、--first-parent 和 --all；
- 解释 rename detection、merge 简化、ignore-rev 和浅克隆造成的盲点；
- 用完整 OID、父提交、tree/diff、时间线和外部证据形成调查记录；
- 在调查结论不确定时明确写出未知、替代假设和下一份证据。

## 先把“归因”拆成四个问题

| 问题 | Git 能直接提供 | 还需要的证据 |
| --- | --- | --- |
| 当前这几行最后由哪个提交写入？ | blame 的 commit、作者/提交者、路径和行号 | 重构、复制、忽略提交后的语义复核 |
| 这条逻辑何时首次出现或被删除？ | -S/-G、path history、父子 diff | 变量改名、生成代码、合并分支和未取得历史 |
| 谁决定要这样改？ | commit message、作者、评审引用（若记录在平台） | 评审讨论、设计文档、审批和组织上下文 |
| 哪次变更造成线上结果？ | 候选提交、制品、部署和运行版本 | CI 输入、配置、数据迁移、遥测和回滚记录 |

作者是写入 commit 的身份，提交者是生成该 commit 的身份；两者都不是平台账号授权或业务责任的自动证明。邮箱可以伪造、历史可以改写、共享账号可以代写。调查文档应避免把“blame 显示某人”写成“某人造成事故”。

## 固定调查范围和时间线

调查副本中先保存 Git 版本、对象格式、根 refs 和候选时间范围：

~~~bash
git --no-optional-locks -C "$repo" version
git --no-optional-locks -C "$repo" \
  rev-parse --show-object-format --show-ref-format
git --no-optional-locks -C "$repo" \
  for-each-ref --format='%(refname)%00%(objectname)%00' > refs.nul
git --no-optional-locks -C "$repo" \
  log --all --date=iso-strict \
  --format='%H%x00%P%x00%aI%x00%cI%x00%an%x00%ae%x00%cn%x00%ce%x00%s%x00' \
  > commits.nul
~~~

命令读取本地 refs 和 commit header，输出应进入受限证据目录。--all 只覆盖当前仓库可见引用；平台隐藏 refs、另一个 clone 的历史、已过期 reflog 和外部评审对象需单独取得。日期是提交中记录的值，不等于服务器接收或部署时间。

把调查问题写成可检验句子，例如：

~~~text
在 release/2026.08 候选提交 C 的 src/payment/timeout.go 中，
timeout=60 首次进入哪条可见历史？它相对候选父提交改变了什么，
是否被合并/回滚/重写，最终制品和运行版本是否包含同一 tree？
~~~

没有候选 commit、路径、字符串或时间范围时，先采集，不要从当前工作树的第一行 blame 开始讲故事。

## 先看提交图，再看一行

~~~bash
candidate="$(git -C "$repo" rev-parse --verify 'refs/heads/main^{commit}')"
git -C "$repo" log --graph --decorate --oneline --all --max-count=80
git -C "$repo" show --no-patch --format='%H%n%P%n%T%n%s' "$candidate"
git -C "$repo" diff-tree --no-commit-id --name-status -r -M -C "$candidate^" "$candidate"
~~~

第一条帮助发现分支、合并、孤立候选和标签；第二条固定候选的父列表与 tree；第三条在指定父与子之间展示路径变化，并尝试 rename/copy 检测。合并提交有多个父，不能用默认的单父直觉解释所有变化。没有父的根提交应单独处理。

--graph 和 --oneline 是人工浏览格式，不是证据的唯一机器格式。自动采集保存完整 OID、父列表、tree OID、pathspec 和 Git 版本。相似度阈值和 renameLimit 会影响第三条的 R/C 判断；“显示为 delete/add”不一定说明业务上没有重命名。

## git blame 是行的最后写入者，不是责任判决

### 默认 blame

~~~bash
git -C "$repo" blame "$candidate" --line-porcelain \
  -L 20,35 -- "$path" > blame.porcelain
~~~

前提是 path 在 candidate 的 tree 中存在，且 candidate 已经解析成完整 commit OID。省略 candidate 时，blame 默认使用当前 HEAD，调查期间可能随引用移动而漂移。--line-porcelain 为每行提供 commit OID、原始路径、原始行号和作者/提交者字段，适合后续按 OID 查询；-- 后的路径不会被当作选项。

blame 通常把当前行归给最近一次改变该行内容的提交。格式化、代码移动、复制、冲突解决、merge 选择和历史重写都可能让这个提交只是“最后写入者”。未提交工作树使用 --contents 可模拟另一个最终文件，但那是对比输入，不是已存在历史。

拿到 OID 后必须查看完整上下文：

~~~bash
line_commit=0123456789abcdef0123456789abcdef01234567
git -C "$repo" show --stat --summary "$line_commit"
git -C "$repo" show --format=fuller --find-renames --find-copies \
  "$line_commit" -- "$path"
git -C "$repo" log --graph --decorate --oneline \
  "$line_commit^..$line_commit"
~~~

如果命令失败，区分 path 不存在、OID 不在当前对象库、候选是 merge 但父写法不完整，不能把空 blame 当“没有作者”。

### 重命名、移动与复制

~~~bash
git -C "$repo" blame -M -C -C "$candidate" -- "$path"
git -C "$repo" log --follow --format='%H%x00%P%x00%s%x00' \
  "$candidate" -- "$path"
git -C "$repo" log --find-renames --find-copies --name-status \
  "$candidate" -- "$path"
~~~

-M 尝试在同一文件内追踪移动的行，-C 尝试跨文件追踪复制；阈值、文件规模和复制来源会影响结果。--follow 只针对单一路径，追踪一条线上的重命名，不会完整解决分裂、合并和多路径复制。log -- path 不加 --follow 时，路径边界可能从 rename 点截断。

这些选项会增加计算量，也会引入启发式判断。调查记录保存阈值、是否用了 -w、-M/-C 和实际 path 集合；不要把一次“识别到 rename”写成 Git 永久保存了 rename 操作。提交只保存前后 tree，rename 是 diff/merge 的推断。

### 忽略格式化提交

~~~bash
format_commit=0123456789abcdef0123456789abcdef01234567
git -C "$repo" blame --ignore-rev "$format_commit" -- "$path"
git -C "$repo" blame --ignore-revs-file blame-ignore-revs.txt -- "$path"
~~~

ignore-rev 让 blame 在展示时尝试跳过指定提交，适合纯格式化或机械迁移。它可能把行归给更早的提交，不能抹除格式化提交发生过的事实；如果被忽略提交同时包含逻辑变化，结果会误导。忽略列表是调查策略输入，必须随报告保存。

## -S、-G 和提交说明搜索回答不同问题

### -S 搜索数量变化

~~~bash
git -C "$repo" log --all --full-history \
  -S'timeout=60' --format='%H%x00%P%x00%s%x00' -- "$path"
~~~

-S 找改变字符串出现次数的提交：加入、删除或从一处移动到另一处都可能命中。它不等于“搜索所有包含该字符串的 commit”，也不会理解运行时拼接、编码或生成文件。精确文本改变一个字符就可能不再命中。

### -G 搜索差异行

~~~bash
git -C "$repo" log --all --full-history \
  -G'timeout[[:space:]]*=[[:space:]]*[0-9]+' \
  --pickaxe-all --format='%H%x00%P%x00%s%x00' -- "$path"
~~~

-G 关注差异中新增/删除行是否匹配正则；--pickaxe-all 让命中的提交完整显示相关变更。正则由当前 Git/regex 实现解释，必须记录转义和 locale。二进制、重命名推断、merge 简化和浅历史都会影响召回。

### 提交说明和路径边界

~~~bash
git -C "$repo" log --all --grep='INC-2026-001' \
  --format='%H%x00%aI%x00%an%x00%s%x00'
git -C "$repo" log --all --name-status -- \
  ':(top)src/payment' ':(exclude,top)vendor'
~~~

--grep 只搜索 commit message；它不证明工单系统存在、内容未被改写或审批真实。pathspec 可以包含 top、exclude、glob、literal 等魔法，复杂调查应显式写出并保存。一个路径被排除后，命令成功只说明剩余集合，没有说明排除路径没有变化。

路径以 - 开头、包含换行或来自外部输入时，必须使用 --、NUL 输出和结构化参数；不要把不受信任 pathspec 拼进 Shell。历史搜索命令不能作为输入校验器。

## merge、first-parent 和历史简化会改变答案

~~~bash
git -C "$repo" log --first-parent --oneline --decorate "$candidate"
git -C "$repo" log --full-history --simplify-merges --oneline --all -- "$path"
git -C "$repo" log --ancestry-path --oneline \
  "$base_commit".."$candidate"
~~~

--first-parent 适合回答“主线何时合入了哪条分支”，会隐藏被合入分支内部的提交；不适合证明某行首次产生。--full-history 和 --simplify-merges 控制 path history 的图简化；--ancestry-path 限制在两个端点之间的祖先路径。默认 log 为了可读性可能简化 merge 图，空结果不代表没有相关变更。

对 merge commit 的具体归因，分别比较每个父：

~~~bash
for parent in $(git -C "$repo" show -s --format='%P' "$candidate"); do
  git -C "$repo" diff --find-renames --find-copies \
    "$parent" "$candidate" -- "$path"
done
~~~

循环只适用于没有特殊空白的变量 OID；OID 来自 Git 自身而不是用户文本。每个父得到的是“相对该父的变化”，不能把第一个父的 diff 当整个合并理由。最终业务结论还需审查冲突解决、评审和测试。

## 把 Git 输出串成可复核证据链

一个合格的归因记录至少包含：

1. 调查问题、候选 OID、refs 快照、路径/pathspec 和 Git 版本；
2. blame 的原始/机器格式输出、使用的 -M/-C/-w/ignore-rev；
3. 命中的 commit 的完整父列表、tree、作者/提交者、时间和 message；
4. 相对每个相关父的 diff、rename/copy 证据和 pickaxe 查询；
5. merge、rebase、cherry-pick、revert 或历史清理的上下文；
6. 评审、CI 候选、制品摘要、部署记录和运行版本的外部 ID；
7. 结论、反例、未知项、下一步采集和证据摘要。

时间线要区分 author time、committer time、服务端接收时间、CI 开始/结束时间、制品创建时间和部署/运行时间。Git 的提交时间可以被重写，不可单独证明先后。

### 一个可复用的调查表

| 字段 | 示例含义 |
| --- | --- |
| 结论 | “当前 line 最后由 C 写入；逻辑首次出现候选为 A” |
| Git 证据 | C/A 的完整 OID、父、tree、diff、blame 行和命令 |
| 外部证据 | 评审 ID、CI run、制品 digest、部署事件 |
| 反例 | 复制代码、生成文件、未获取分支、revert 后再次引入 |
| 置信度 | 已验证、部分验证、推断或未知 |
| 保留动作 | 原始快照、查询输出、工具版本和摘要 |

写“某某负责”前，明确它属于哪一列。若历史被强制改写，使用改写前后的 OID 映射和平台审计，不把新提交作者当原始事件的唯一身份。

## 常见失败与恢复

| 症状 | 可能原因 | 安全动作 |
| --- | --- | --- |
| blame 只显示重构提交 | 行移动/复制、格式化或相似度不足 | 保存默认结果，隔离尝试 -M/-C/-w 和 ignore-rev；不覆盖原报告 |
| -S 没找到已知逻辑 | 字符串改名、生成代码、浅历史或 pathspec 排除 | 用 -G、旧路径集合、全 refs 和外部制品交叉查 |
| rename 显示 delete/add | 相似度阈值、renameLimit、内容差异太大 | 保存两个 tree，调整单次检测参数并人工审查 |
| merge 的 first-parent 没有命中 | 变更在被合入分支内部 | 先用 first-parent 看主线，再对每个父和全图搜索 |
| 当前 clone 没有目标提交 | ref 未 fetch、浅边界、平台隐藏 ref 或 GC | 从现场记录、CI/评审、mirror/bundle/备份取得候选 |
| 提交说明指向工单但无法证明决定 | message 可改写、平台数据未导出 | 标为线索，采集评审/审计，不把 message 当审批 |

任何历史查询失败都先保存命令、退出码和 stderr。不要为了让 blame/log “查到”而 fetch、替换 refs 或编辑对象库；需要扩大范围时从可复现调查副本重新派生。

## 合成实验：从行到逻辑的调查链

本书提供 scripts/verify-history-attribution.sh。实验在 mktemp 仓库创建功能提交、格式化提交、分支合并、重命名和复制路径，不连接远端或平台。

在仓库根目录执行：

~~~bash
bash scripts/verify-history-attribution.sh
~~~

脚本验证：

1. line-porcelain blame 返回完整 commit OID、原始路径和行号，随后用 show 核对父与 diff；
2. 纯格式化提交会改变默认 blame，ignore-rev 能把显示归因退回候选旧提交，但调查记录仍保留格式化提交；
3. -M/-C 与 --follow 能在合成 rename/copy 中扩大搜索，默认单路径历史存在截断边界；
4. -S 只命中字符串数量改变，-G 命中差异正则，--grep 只命中提交说明；
5. --first-parent 与全图结果不同，merge commit 对每个父有不同 diff；
6. --all 能看到未合入分支，普通 main 历史不能代表所有本地 refs；
7. 最终生成一份包含 OID、父、tree、命令和摘要的调查 manifest，并验证篡改会被发现。

脚本只验证 Git 历史搜索机制，不验证真实平台评审、工单、CI、制品、部署或运行数据；实验作者和提交时间是合成值，不能用于责任判断。

## 小结

blame 是定位入口，pickaxe 是缩小范围的工具，commit graph/diff 是机械证据，评审、构建和运行记录才可能补齐“为什么”和“是否造成影响”。Rename、merge、格式化、历史改写和受限 clone 都会改变可见答案。

调查完成的标志不是找到一个名字，而是能复现查询范围、解释每个选项、比较相关父提交、列出未知项，并把 Git 证据与外部时间线绑定。下一章将把这些对象和历史证据用于 bundle、mirror、备份与恢复演练。

## 资料

- [git-blame](https://git-scm.com/docs/git-blame)
- [git-log](https://git-scm.com/docs/git-log)
- [git-show](https://git-scm.com/docs/git-show)
- [git-diff-tree](https://git-scm.com/docs/git-diff-tree)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
- [gitdiffcore](https://git-scm.com/docs/gitdiffcore)
