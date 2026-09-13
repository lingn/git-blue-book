# Merge base 与三方合并：先固定共同历史，再计算两侧变化

两条工作线从共同历史分开后，Git 需要比较三棵 tree：共同祖先、当前接收方和被合入方。`merge-base` 从提交图中寻找最佳共同祖先，合并策略再根据三方路径和内容构造结果。没有固定这三个输入，只说“把 feature 合到 main”不足以复现一次合并。

`git merge topic` 的方向由当前 `HEAD` 决定。当前分支是结果接收方，参数只是被合入的提交入口；交换当前分支会改变第一父、ours/theirs 视角、最终更新的 ref，也可能改变冲突解决结果。

## 进入条件与完成标准

写入命令只在一次性仓库执行。真实项目在合并前保存：

~~~bash
git status --short --branch
ours_oid="$(git rev-parse 'HEAD^{commit}')"
theirs_oid="$(git rev-parse 'refs/heads/topic^{commit}')"
git merge-base --all "$ours_oid" "$theirs_oid"
git rev-parse --is-shallow-repository
~~~

工作区不必满足 Git 的绝对干净条件才能调用 merge，但团队合并流程应要求可解释、可恢复的 index 和工作区。未提交内容会让自动合并、冲突现场和 `--abort` 恢复更复杂。

读完本章后，应能确定接收方与被合入方，解释最佳共同祖先，区分一个、多个和不存在 merge base 的场景，从 base/ours/theirs tree 预测路径变化，并把 Git 自动合并成功与业务、评审、CI 和发布证据分开。

## 方向先于算法

假设当前位于 `main`：

~~~bash
git symbolic-ref --short HEAD
git merge topic
~~~

Git 尝试更新 `refs/heads/main`。普通二父合并提交的第一父通常是 merge 前的 main，第二父是 topic 尖端。Topic ref 不因被合入而移动。

如果当前位于 topic 再执行 `git merge main`，接收 ref 和父顺序相反。即使最终 tree 可以相同，commit OID 也会因为父顺序、说明或时间不同而变化。

合并前把角色命名为 OID：

~~~bash
receiver_ref="$(git symbolic-ref --quiet HEAD)"
receiver_oid="$(git rev-parse 'HEAD^{commit}')"
incoming_oid="$(git rev-parse 'refs/heads/topic^{commit}')"
printf 'receiver_ref=%s\nreceiver=%s\nincoming=%s\n' \
  "$receiver_ref" "$receiver_oid" "$incoming_oid"
~~~

分离 `HEAD` 也能执行部分合并操作，但结果不会由普通本地分支自动保留。日常整合先附着到明确目标分支；CI 构造临时候选时则显式记录分离 OID 和候选 ref。

## 最佳共同祖先不是“最近日期”

设提交图为：

~~~text
      L1 <- L  receiver
     /
B <-
     \
      R1 <- R  incoming
~~~

B 同时是 L 和 R 的祖先。若不存在另一个共同祖先是 B 的后代，B 是最佳共同祖先之一：

~~~bash
base_oid="$(git merge-base "$receiver_oid" "$incoming_oid")"
git merge-base --is-ancestor "$base_oid" "$receiver_oid"
git merge-base --is-ancestor "$base_oid" "$incoming_oid"
~~~

祖先判断都应退出 0。提交日期、分支创建时间和文件 mtime 不参与最佳共同祖先定义；父关系才决定拓扑。

不带 `--all` 的 `merge-base A B` 在有多个最佳共同祖先时只输出一个未指定候选。调查和工具应先使用：

~~~bash
git merge-base --all "$receiver_oid" "$incoming_oid"
~~~

Criss-cross 等图形可以产生多个互不为祖先的最佳 base。`ort` 可能先递归合并多个 base，形成虚拟共同祖先，再执行当前三方合并。单个 `merge-base` OID 不能完整解释这类结果。

## 三方输入是三棵 tree

固定一个 base 后读取：

~~~bash
base_tree="$(git rev-parse "$base_oid^{tree}")"
ours_tree="$(git rev-parse "$receiver_oid^{tree}")"
theirs_tree="$(git rev-parse "$incoming_oid^{tree}")"
printf 'base=%s\nours=%s\ntheirs=%s\n' \
  "$base_tree" "$ours_tree" "$theirs_tree"
~~~

对每条路径，策略需要判断 base 到两侧发生了什么。常见机械情形：

| Base 到 ours | Base 到 theirs | 常见结果 |
| --- | --- | --- |
| 未变 | 修改 | 采用 theirs 变化 |
| 修改 | 未变 | 保留 ours 变化 |
| 同样修改 | 同样修改 | 采用共同结果 |
| 不同路径修改 | 不同路径修改 | 通常自动组合 |
| 同一路径不兼容修改 | 同一路径不兼容修改 | 留下冲突候选 |
| 删除 | 修改或重命名 | 需要路径与业务决策 |

这张表只提供第一层模型。重命名检测基于 tree 差异和相似度，不是 commit 中的“rename 事件”；目录重命名、文件/目录冲突、symlink、submodule 和二进制内容还需要策略专门处理。

查看三段变化：

~~~bash
git diff --name-status -z "$base_oid" "$receiver_oid" > ours.paths.z
git diff --name-status -z "$base_oid" "$incoming_oid" > theirs.paths.z
git diff --stat "$receiver_oid" "$incoming_oid"
~~~

前两条输出 NUL 路径，适合结构化解析；写入的证据文件可能含内部路径，应存放在受控目录。最后一条只比较两侧 tree，不等于三方合并结果。

## 自动合并也会创建新的结果 tree

两侧修改不同路径时，`ort` 通常可以自动组合。结果 tree 同时包含 ours 和 theirs 的变化，可能不等于任一输入 tree。

在分叉历史上执行：

~~~bash
git merge --no-ff --no-commit "$incoming_oid"
git rev-parse HEAD
git rev-parse MERGE_HEAD
git write-tree
git diff --staged --check
~~~

`--no-commit` 在需要合并提交且没有冲突时停在提交前：`HEAD` 仍是 receiver OID，`MERGE_HEAD` 保存 incoming OID，index 已是候选结果 tree，工作区展开自动合并内容。`write-tree` 会在无未合并 stage 时输出结果 tree OID。

此时仍需验证构建、测试、生成文件、配置和数据库约束。`git diff --staged` 只展示结果相对当前 `HEAD`，不会自动解释相对 incoming 的差异；合并完成后分别比较两个父视角。

若不继续：

~~~bash
git merge --abort
git rev-parse HEAD
git status --short --branch
~~~

`--abort` 尝试恢复合并前状态。合并前有本地修改时不保证每一份字节都能无损复原，所以严格流程在开始前保存或清空本地变化。

## 冲突表示“还没有唯一结果”

两侧对同一路径作不兼容修改时，Git 通常不移动当前分支，写入 `MERGE_HEAD`，并在 index 保存非零 stages。工作区可能含冲突标记，也可能只有路径级状态。

~~~bash
git status --short --branch
git rev-parse 'HEAD^{commit}'
git rev-parse 'MERGE_HEAD^{commit}'
git ls-files --unmerged
git diff --name-status --diff-filter=U
~~~

Index stage 1/2/3 的数据模型见[Index 内部结构](../part-03/05-index-internals.md)。Stage 1 是 base 候选，stage 2/3 在普通 merge 中对应当前 `HEAD` 和 `MERGE_HEAD`。并非每类路径冲突都拥有三条记录。

冲突不表示对象库损坏，也不授权机械选择 ours/theirs。最终内容可能是任一侧、两侧组合、迁移到新路径或重新设计。后续 `ort` 和复杂路径章节负责策略语义，解决章负责取证、继续、中止和业务验收。

## 没有共同祖先时不能伪造 base

两个独立初始化的仓库历史可能没有共同祖先：

~~~bash
git merge-base "$receiver_oid" "$incoming_oid"
~~~

命令无输出并返回非零。浅克隆缺少边界外父对象时也可能得到相同表象，先检查 `--is-shallow-repository`、对象可用性、replace refs 和导入来源。

`git merge --allow-unrelated-histories` 可以显式允许无共同祖先的历史进入一次合并，但它不是“修复 merge-base”的开关。采用前应核对：

- 两套根目录是否会发生同名路径覆盖；
- licenses、身份、秘密、LFS、submodule 和大对象是否允许组合；
- 哪条历史作为第一父，发布与回滚怎样解释；
- 导入映射、审计和后续所有权如何保存；
- 是否更适合 subtree、迁移工具或保留独立仓库。

不要把 shallow 边界误判为真正无关历史后强制合并。先补齐必要父对象，再重新计算。

## Merge base 取决于本地可见图

`merge-base` 只读取当前仓库可见的 commit 和父关系。以下状态会改变或限制观察：

| 状态 | 影响 |
| --- | --- |
| shallow boundary | 边界外父对象不可遍历，可能找不到真实 base |
| replace refs | 默认遍历可能看到替换后的父图 |
| 对象 missing/corrupt | 一侧或父链无法读取 |
| 远程跟踪 ref 过期 | 输入 OID 不是服务器当前尖端 |
| 隐藏/未 fetch refs | 不改变已知两 OID 父图，但会遗漏其他候选入口 |

调查原始对象图时记录 replace refs，并在受控副本使用 `git --no-replace-objects` 对照。需要远端新鲜度时先按授权 fetch 或 `ls-remote`，保存新旧 OID 和查询时间；网络操作会改变本地状态。

## 合并前后的证据清单

合并前至少保存：

~~~text
repository_id / object_format / Git_version
receiver_ref / receiver_oid / receiver_tree
incoming_ref_or_oid / incoming_oid / incoming_tree
all_merge_bases / shallow_replace_promisor_state
index_tree / worktree_and_untracked_state
selected_merge_options / config_origins
~~

完成后保存结果 commit、父列表、tree、冲突解决记录、测试、评审候选和引用更新事件。只有本地 Git 实验时，外部字段标记为“未验证”，不能用合成文本填成成功。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| `not something we can merge` | 输入 ref、对象类型和 shell 参数 | 解析完整 commit OID，不创建假分支 |
| `merge-base` 无结果 | 独立根、shallow/partial、replace 和对象错误 | 补齐证据或确认无关历史，不猜 base |
| 多个 merge base | `--all` 输出、Git 版本、策略 | 保存全集和最终结果，不固定第一个输出 |
| 自动合并结果不符合业务 | 三方 tree、staged diff、测试 | 不提交；中止或修正候选并重新验证 |
| 合并冲突 | `HEAD`、`MERGE_HEAD`、unmerged stages | 按路径决策或 `merge --abort`，不删状态文件 |
| Abort 后本地修改异常 | 合并前 diff/副本、autostash、index | 停止覆盖，从已保存现场恢复 |
| 站错接收分支 | 当前 ref、合并是否进行中/已完成 | 进行中先 abort；已完成按共享边界恢复，不硬改 |

合并开始后不要用 `reset --hard` 或删除 `MERGE_HEAD` 伪造干净状态。已共享错误合并需按第七篇创建可审计恢复提交，不能重写协作者已使用的历史。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-merge-shapes.sh
~~~

实验构造快进和分叉图，验证唯一 merge base、两侧独有计数、三方无冲突组合的候选 tree、`HEAD`/`MERGE_HEAD` 状态和 abort 恢复。它还验证冲突场景保留当前 `HEAD` 并产生 stage 1/2/3。

同一脚本覆盖快进、`--ff-only`、`--no-ff` 与 `--no-commit` 的历史形状，由下一章解释。实验不模拟多个 merge base、无关历史、平台候选、评审或业务测试。

## 小结

三方合并从 receiver、incoming 和最佳共同祖先的 tree 计算结果。当前分支决定接收 ref、第一父和 ours 视角；多个 base、浅边界与 replace refs 会改变诊断要求。自动组合只证明 Git 形成了候选 tree，提交、评审、测试和发布仍需各自证据。

## 资料

- [git-merge-base](https://git-scm.com/docs/git-merge-base)
- [git-merge](https://git-scm.com/docs/git-merge)
- [git-merge-tree](https://git-scm.com/docs/git-merge-tree)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
- [git-diff](https://git-scm.com/docs/git-diff)
- [shallow](https://git-scm.com/docs/shallow)
