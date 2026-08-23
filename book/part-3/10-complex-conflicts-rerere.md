# 复杂冲突不是“选一边”：ort、index 阶段与 rerere

文本标记只是冲突的一种外观。Git 真正保存的是共同祖先、当前一侧、合入一侧以及未完成的 index 状态；重命名、删除、目录迁移、submodule 和二进制文件可能根本没有可编辑的 `<<<<<<<`。处理复杂冲突要先读对象和路径状态，再形成业务上正确的最终 tree。

进入本章前，读者应理解三方合并、`ours`/`theirs` 的普通 merge 视角，以及基本的 `merge --abort`。读完后，应能解释 `ort` 在做什么，读取 index 三阶段，诊断 rename/delete 与目录重命名，并安全使用 `rerere` 复用仍需人工验证的解决结果。

本章以 Git 2.49.0 为实验环境。在该版本中，合并一个分支时默认策略是 `ort`，冲突时会写 `AUTO_MERGE`。本书最低基线 Git 2.28 使用较早的默认策略，不应期待 `AUTO_MERGE`；stage 1/2/3 和基本三方合并模型仍适用。实际操作前先运行 `git --version`，不要用新版本输出反推旧客户端状态。

## 策略负责生成候选 tree，不负责业务判断

对单个分支执行普通 merge 时，Git 2.49 默认使用 `ort`。它寻找最佳共同祖先；存在多个共同祖先时先合成参考 tree；再把当前头、合入头相对参考 tree 的变化组合起来。它能检测文件重命名，也能根据一组文件重命名推断目录迁移，但不检测复制来源。

自动合并成功只说明策略找到了一个没有机械冲突的 tree，不证明结果符合业务语义。两个分支可以分别修改互相关联的配置、锁顺序或 API 约束，文本完全不重叠却组合成错误行为。合并验证始终包括测试和运行证据。

### 策略与策略选项不是一回事

`-s ours` 选择 `ours` 合并策略，结果 tree 完全采用当前分支，忽略其他头的所有 tree 变化；它主要用于声明一段旧历史已经被当前历史取代。`-X ours` 是 `ort` 的冲突偏好，只在冲突 hunk 中偏向当前侧，另一侧不冲突的变化仍会进入结果。

二者都不是“安全解决所有冲突”的快捷方式。批量偏向一侧会隐藏被舍弃的约束，尤其不适合配置、schema、权限和协议变化。正文不提供可直接照抄的批量命令；只有先审计全部差异、明确舍弃理由并验证最终 tree 后，团队才可在专用场景采用。

`theirs` 是 `ort` 可用的相反冲突偏好，但没有一个与 `ours` 对称、忽略当前 tree 的 `theirs` 合并策略。看到旧教程时先分清它讨论的是 strategy 还是 strategy option。

## 冲突现场有四类可观察状态

普通 merge 停止后，至少检查：

```text
HEAD        当前分支在合并前的提交
MERGE_HEAD  正在合入的提交
index       已自动合并的 stage 0 与未合并的 stage 1/2/3
工作区      自动合并结果、冲突标记和人工编辑
```

不要一看到标记就启动编辑器。先在冲突仓库根目录采集只读证据：

```bash
git status --short --branch
git rev-parse HEAD
git rev-parse MERGE_HEAD
git show --no-patch --format='%H%n%P%n%T%n%s' HEAD MERGE_HEAD
git diff --name-status --diff-filter=U
git ls-files --unmerged
```

前提是仓库确有进行中的 merge；没有 `MERGE_HEAD` 时第三条会失败，这是“当前不是普通 merge 冲突”的证据，可能处于 rebase、cherry-pick 或普通脏工作区。命令只读取对象、index 和引用，不修改解决现场。

`status` 给出面向人的路径分类，`diff --diff-filter=U` 列出未合并路径，`ls-files --unmerged` 显示 mode、对象 ID、stage 和路径。对象 ID 与路径随事故变化，排障记录不要省略完整值，也不要把内部路径未经脱敏贴到公开渠道。

## Index 的三阶段是冲突权威输入

未冲突路径通常只有 stage 0，也就是下一次提交候选。未合并路径最多保存三个条目：

| Stage | 普通 merge 中的含义 | 常用读取方式 |
| --- | --- | --- |
| 1 | merge-base 的共同祖先版本 | `git show :1:path` |
| 2 | `HEAD`，即当前/目标分支版本 | `git show :2:path` |
| 3 | `MERGE_HEAD`，即正在合入的版本 | `git show :3:path` |

这三个版本比工作区标记更稳定。假设冲突路径已经安全赋值：

```bash
conflict_path=service.conf
git show ":1:$conflict_path"
git show ":2:$conflict_path"
git show ":3:$conflict_path"
```

命令读取 index 中的 blob，不改变文件。路径包含冒号、换行或其他特殊字节时，不要把这种 revision 语法拼字符串处理；使用支持 `git ls-files -u -z` 和对象 ID 的脚本逐项读取。本章实验使用普通路径以突出阶段语义。

并非每类冲突都有三个 stage。add/add 没有共同祖先条目；modify/delete 会缺少删除一侧；rename 冲突可能把不同 stage 放在旧路径和新路径。不能写死“每个冲突必有三行”，应按 `ls-files -u` 的真实输出判断。

执行 `git add` 或 `git rm` 解决路径时，Git 用最终 stage 0 替换该路径的未合并 stages。这一步表示“这个路径的候选结果已经决定”，不是证明结果正确。所有未合并条目消失后才具备完成 merge 的结构条件。

### Rebase 中的 ours/theirs 会换视角

上表只描述普通 `git merge`。Rebase 会把待重放提交应用到已经检出的新基线上，命令文案中的 ours/theirs 视角因此常与开发者直觉相反。处理 rebase 冲突时应记录当前 `HEAD`、正在重放的提交和 rebase 状态目录，不把普通 merge 的“当前分支/合入分支”标签直接套用。

## Diff3 让共同祖先进入工作区标记

默认 `merge` 冲突样式只展示两侧。`diff3` 增加 base 段；`zdiff3` 也显示 base，同时压缩三方共同上下文，较容易看出双方各自从什么内容出发。

在 Git 2.49 的目标仓库中启用仅对本仓库生效的样式：

```bash
git config --local merge.conflictStyle zdiff3
git config --local --get merge.conflictStyle
```

第一条修改 `.git/config`，不会重写已经存在的冲突文件；它影响之后生成的文本冲突标记。第二条预期输出 `zdiff3`。旧客户端不支持该值时 merge 可能报配置错误，可使用 `diff3` 或升级经过验证的 Git。

回退自己添加的本地值：

```bash
git config --local --unset merge.conflictStyle
```

这恢复默认配置来源，不修改已解决内容。若值来自 include、系统或组织配置，先用 `git config --show-origin --get merge.conflictStyle` 确认，不要删除错误作用域。

Base 段仍只是文本上下文，不能替代 stage 对象和业务历史。生成文件、压缩格式和二进制内容不会因此变得可人工三方合并。

## AUTO_MERGE 是解决过程的临时 tree 基线

`ort` 遇到冲突时会写一个名为 `AUTO_MERGE` 的引用，指向与自动合并后工作区受跟踪内容对应的 tree；文本冲突标记也在这个 tree 中。先验证类型：

```bash
git cat-file -t AUTO_MERGE
git diff AUTO_MERGE
```

在 Git 2.49 的 `ort` 冲突现场，第一条预期输出 `tree`。刚产生冲突且尚未编辑时，第二条通常没有差异；开始人工解决后，它显示工作区相对初始自动合并结果改变了什么。这比只看 `git diff` 更容易区分 Git 生成的标记与人工决策。

`AUTO_MERGE` 不是发布引用、永久审计日志或恢复备份。后续 merge 可以覆盖它，其他策略和旧 Git 可能不创建它，未跟踪文件也不在 tree 证据中。需要事故留存时记录对象 ID、index stages 和人工说明，不能只写“当时存在 AUTO_MERGE”。

## 冲突类型决定要做的业务选择

| 类型 | 典型 index/工作区现象 | 必须回答的问题 |
| --- | --- | --- |
| content/content | 同一路径常有 stage 1/2/3 和标记 | 两侧语义怎样组合，base 中哪些约束仍有效 |
| add/add | 没有 stage 1，两侧新增同名路径 | 是同一概念的两种实现，还是应该拆成两个路径 |
| modify/delete | 一侧有 blob，另一侧删除 | 删除理由是否仍成立，修改是否要迁到替代位置 |
| rename/delete | 新旧路径分布不同 stage | 文件被淘汰还是应在新位置保留 |
| rename/rename | 两侧把同一来源移到不同位置 | 最终所有权、导入路径和调用方怎样统一 |
| file/directory | 一侧文件名占用另一侧目录位置 | 目标布局与跨平台文件系统约束是什么 |
| directory rename | 新文件落在另一侧已移动的旧目录 | 新文件是否也属于迁移后的目录 |
| mode/symlink | 内容可能相同但模式或对象类型不同 | 可执行位、链接目标和部署平台是否允许 |
| submodule | gitlink 指向不同子仓库提交 | 哪个子模块提交包含双方需要的历史并可获取 |
| binary/LFS pointer | 无可用行级合并或指针文本冲突 | 选择哪个原始二进制，是否能重新生成，LFS 对象是否存在 |

`git status` 的短码（例如 `UU`、`DU`、`UA`）从 index/工作区两列描述状态，适合定位但不承担最终决策。对路径冲突，先用 `ls-files -u`、两侧提交 tree 和 rename 检测结果还原因果。

## Rename 是推断，不是历史中的动作记录

Git commit 保存旧 tree 和新 tree，不保存一条“把 A 重命名为 B”的操作。Diff 和 merge 根据删除/新增内容的相似度推断 rename；阈值、候选规模和配置会影响结论。大规模生成文件变更可能超过 rename 检测的穷举限制。

诊断当前配置：

```bash
git config --show-origin --get merge.renames
git config --show-origin --get merge.renameLimit
git config --show-origin --get merge.directoryRenames
```

无输出表示使用内置或其他默认来源，不等于功能关闭。在 Git 2.49 中，`merge.directoryRenames` 可取 `false`、`true` 或 `conflict`；默认 `conflict` 会对“另一侧在被重命名目录中新增路径”要求人工确认。关闭 `merge.renames` 时目录重命名推断也失效。

不要为了让某一次 merge“通过”就全局提高阈值或把目录策略改成自动移动。先在隔离分支记录 Git 版本、提交对、候选路径数和当前配置，验证结果 tree 与构建工具。配置变化本身也应进入团队评审。

### Rename/delete 的解决不是恢复旧路径

假设当前分支删除 `docs/guide.md`，合入分支将它重命名为 `manual/guide.md`。保留新路径意味着接受“内容仍需要，但位置改变”；删除新路径则接受“整个概念已淘汰”。选择不能只基于文件是否还在工作区。

形成结果后显式暂存相关路径：

```bash
git add -- manual/guide.md
git status --short
git ls-files --unmerged
```

若最终决定删除，应使用 `git rm --` 处理 Git 正在跟踪的对应路径。命令的具体路径来自现场 `ls-files -u`，不要把本书示例当作真实仓库结构。`ls-files --unmerged` 对该冲突应不再列出条目；其他冲突仍会保留。

### 目录重命名需要确认新文件归属

一侧把 `src/old/` 中已有文件移动到 `src/new/`，另一侧在 `src/old/` 新增 `c.txt`。`ort` 可以从多条文件 rename 推断目录迁移，并在默认 `conflict` 策略下建议把新文件放入 `src/new/c.txt`，但“建议”不是业务事实。

确认新文件属于迁移后的模块后，再暂存新路径并确认旧路径不存在。若新文件刻意留在旧目录，则要检查旧目录是否仍应存在、构建与所有权规则怎样处理。目录只是 tree 路径，Git 不保存空目录，也没有单独的目录对象移动记录。

## 一套不会遗漏 index 状态的解决循环

对每个冲突批次执行：

1. 记录 HEAD、MERGE_HEAD、merge-base、Git 版本和 merge 配置；
2. 用 `git ls-files -u` 保存各 stage 对象，而不是只截屏标记；
3. 阅读双方提交、调用方、测试和删除/重命名理由；
4. 编辑、移动或删除为最终路径布局；
5. 对明确路径执行 `git add --` 或 `git rm --`，避免无意暂存其他文件；
6. 再次运行 `git ls-files --unmerged`，直到没有输出；
7. 检查 `git diff --staged`、`git diff AUTO_MERGE` 和项目测试；
8. 使用 `git merge --continue` 或提交完成 merge；
9. 记录冲突范围、双方意图、舍弃内容和验证证据。

`git add -A` 在隔离实验里便于断言路径布局，真实工作区可能同时包含无关修改和未跟踪文件，不应作为复杂冲突的默认收尾命令。

搜索 `<<<<<<<` 只能发现残留文本标记。合法文档可能本来就含标记，二进制和路径冲突也没有标记；权威完成条件是 index 不再有 unmerged stages、最终 diff 符合意图、测试通过。

## Abort 与 quit 的后果不同

`git merge --abort` 尝试恢复 merge 前状态。合并前工作区干净时最可靠：

```bash
git merge --abort
git status --short --branch
git rev-parse HEAD
```

第一条改变 index、工作区和 merge 状态文件；成功后 HEAD 回到合并前提交，状态应与合并前一致。合并开始时已有非平凡未提交修改，尤其冲突后继续修改同一文件时，Git 可能无法完整重建原状态。因此开始 merge 前先提交、stash 或使用独立 worktree，不把 abort 当备份。

若 merge 使用 autostash，`merge --abort` 会尝试把临时 stash 应用回工作区，这一步本身可能冲突。恢复时检查 `MERGE_AUTOSTASH`、stash 列表和工作区，不只看 MERGE_HEAD 是否消失。

`git merge --quit` 只忘记“正在 merge”的元数据，保留当前 index 和工作区；若有 autostash，会把它保存到 stash 列表。它不恢复合并前状态。只有明确要保留当前文件并自行接管后续处理时才使用，且先记录 stages；日常“取消合并”应优先 abort。

## rerere 复用结果，不替你重新判断

`rerere` 是 reuse recorded resolution 的缩写。它记录冲突自动合并的 preimage 与人工解决的 postimage；以后遇到可匹配冲突时，把已记录结果应用到工作区。

按仓库启用，并保持不自动暂存：

```bash
git config --local rerere.enabled true
git config --local rerere.autoupdate false
git config --show-origin --get-regexp '^rerere\.'
```

配置只修改当前仓库 `.git/config`。`autoUpdate=false` 意味着复用结果写入工作区后，index 仍保留 unmerged stages，给操作者检查机会；这是团队初次采用时更安全的默认。`--no-rerere-autoupdate` 也可用于单次 merge 明确阻止自动更新 index。

解决过程中观察：

```bash
git rerere status
git rerere diff
git rerere remaining
```

`status` 列出将被记录的冲突路径，`diff` 展示当前解决相对记录 preimage 的变化，`remaining` 列出尚未自动解决或无法追踪的冲突，例如部分 submodule 冲突。命令会读取 `.git/rr-cache` 和工作区；普通 merge、commit、rebase 会在启用后自动调用 rerere 的记录/复用逻辑。

复用成功时仍要：

1. 比较 stage 1/2/3 与复用后的工作区；
2. 运行本次提交图对应的测试，而不是引用上次结果；
3. 人工 `git add` 后检查 staged diff；
4. 在提交说明中说明复用了哪类冲突解决及复核结果。

相似冲突不保证业务上下文相同。缓存中的解决内容也可能在依赖和策略变化后过时。发现复用错误时，可在当前冲突中用 `git rerere forget -- "$conflict_path"` 忘记相应记录，再重新解决；执行前保存错误复用证据。不要直接删除整个 `.git/rr-cache` 掩盖来源。

Rerere 缓存默认只在本地 `.git/rr-cache`，不会进入提交。Git 2.49 文档中的默认 GC 窗口是：未解决记录 15 天、已解决记录 60 天，可由 `gc.rerereUnresolved` 和 `gc.rerereResolved` 调整。共享缓存会把他人的解决内容带入工作区，应像构建缓存一样定义来源、完整性、权限、审查和失效机制，而不是无条件同步。

回退自己添加的配置：

```bash
git config --local --unset rerere.enabled
git config --local --unset rerere.autoupdate
```

这只关闭后续自动记录/复用，不删除已有缓存。是否清理历史记录要按保留和取证需要另行决定。

## 合并提交不保存“曾经冲突”的清单

合并完成后，commit 保存父提交和最终 tree，不保存一份机械冲突路径列表。可以从父提交重建输入并审查结果：

```bash
merge_commit="$(git rev-parse HEAD)"
git show --no-patch --format='%H%n%P%n%T%n%s' "$merge_commit"
git show --cc "$merge_commit"
git diff "$merge_commit^1" "$merge_commit"
git diff "$merge_commit^2" "$merge_commit"
```

前提是 HEAD 确为预期合并提交；先确认 `%P` 至少有两个父对象。组合 diff 突出相对父提交的结果，但不能完整证明哪些路径当时触发冲突、谁做了决定或运行了哪些测试。因此在解决现场保留结构化说明，格式可参考本篇的[冲突解决报告](../part-6/07-conflict-report.md)。

## 常见失败怎样恢复

| 症状 | 首要证据 | 安全动作 |
| --- | --- | --- |
| 文件有标记但 `MERGE_HEAD` 不存在 | status、rebase/cherry-pick 状态目录、标记来源 | 先识别操作类型，不运行错误的 `merge --continue` |
| `ls-files -u` 某路径少于三条 | 冲突类型、各 stage 路径 | 按 add/delete/rename 语义读取，不能假定对象丢失 |
| Git 没识别预期 rename | 两个 tree、相似度、候选规模和 rename 配置 | 隔离调整检测参数并审查结果，不全局强制 |
| 目录新文件被建议移动 | directoryRenames 配置、双方路径意图 | 人工确认模块归属后暂存最终路径 |
| abort 无法恢复未提交修改 | 合并前状态、autostash、工作区和 stash | 停止覆盖，从备份/worktree/stash/编辑器历史恢复 |
| rerere 复用了错误内容 | rr-cache、stage 对象、`rerere diff` | 保存证据、forget 当前路径、重新解决和测试 |
| index 已干净但行为错误 | staged/combined diff、测试和运行证据 | 不提交；回到双方意图修正最终 tree |

如果已经创建并共享错误合并提交，不能靠再次“解决冲突”改变该对象。按共享历史策略创建修复或 revert，并重新构建、评审和部署。若合并尚未共享，可在保留恢复引用后重新执行，但仍要保留第一次错误的原因供复盘。

## 隔离实验验证了什么

在本书仓库根目录运行：

```bash
./scripts/verify-complex-conflicts-rerere.sh
```

脚本要求 Bash、Git 2.49 或兼容的 `ort`/`AUTO_MERGE` 实现、`awk`、`sed` 和可写临时目录。它创建三个隔离仓库，不读取用户级 Git 配置、不连接网络，也不修改蓝皮书仓库。

内容冲突实验验证 stage 1/2/3 分别对应 base、HEAD 和 MERGE_HEAD；`AUTO_MERGE` 初始等于带标记的工作区 tree，人工追加内容后能显示进度；第一次 abort 恢复合并前提交与干净状态。第二次人工解决被 rerere 记录，第三次相同冲突自动写入已记录结果，但由于 `autoupdate=false`，index 仍保持未合并，必须人工检查并 add。

第二个仓库制造 rename/delete，选择把仍需保留的内容放在新路径。第三个仓库让一侧移动整个目录、另一侧向旧目录增加新文件，在 `merge.directoryRenames=conflict` 下确认 `ort` 把建议的新路径留给人工决策，解决后最终 tree 的三个文件都位于新目录。

成功时最后输出：

```text
Index stages, AUTO_MERGE, rerere, rename/delete, and directory rename passed.
```

实验只能证明当前 Git 版本对这些小型提交图的语义，不能外推大型仓库 rename 性能，也不能验证 IDE 合并工具、submodule 服务器、LFS 对象或真实业务测试。输出不冒充托管平台冲突页面。

## 小结

复杂冲突的权威输入在提交和 index stages，不在冲突标记。`ort` 能组合 tree、推断 rename 并生成 `AUTO_MERGE` 基线，但最终语义仍由人和测试负责。

路径冲突先判断保留、删除和归属；abort 与 quit 区分恢复和接管；rerere 只复用过去的编辑结果，并应保持人工暂存与重新验证。用这套模型，团队才能把“冲突解决了”升级为一条可审查、可复现的工程结论。
