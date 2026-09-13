# Rerere：复用编辑结果，但每次重新验证语义

Rerere 是 reuse recorded resolution 的缩写。启用后，Git 为冲突记录规范化 preimage，并在操作者完成解决后保存 postimage；未来出现可匹配的冲突时，它可以把旧结果写回工作区。

缓存回答“上次怎样编辑”，不回答“这次业务约束是否相同”。依赖、schema、权限或生成器变化后，同样的文本冲突可能需要不同结果。默认保持 `rerere.autoupdate=false`，让复用停在工作区，由人审查后再写 stage 0。

## 进入条件与完成标准

配置与冲突实验只在临时仓库执行。真实仓库先检查来源：

~~~bash
git version
git config --show-origin --get rerere.enabled
git config --show-origin --get rerere.autoupdate
git rev-parse --path-format=absolute --git-path rr-cache
~~~

配置未设置时命令可能返回 1。不要因为 `.git/rr-cache` 存在就推断当前自动复用策略；读取有效配置和当前操作状态。

读完本章后，应能解释 preimage/postimage、记录与复用时点、autoupdate 风险、status/diff/remaining/forget、缓存保留与共享风险，并为每次复用重新验证三方对象和业务结果。

## 启用时先保留人工暂存

仓库级配置：

~~~bash
git config --local rerere.enabled true
git config --local rerere.autoupdate false
git config --show-origin --get-regexp '^rerere\.'
~~~

第一条允许记录与复用，第二条禁止复用后自动更新 index。配置写入当前仓库，不进入 commit，也不会随 clone 传输。

`autoupdate=false` 时，匹配的 postimage 会写到工作区，index 仍保留 stage 1/2/3。操作者可以比较三方对象与复用结果、运行本次测试，再执行 `git add`。这是初次采用和高风险仓库更稳妥的起点。

`rerere.autoupdate=true` 会让 Git 在复用结果后直接更新 index，减少操作步骤，也更容易把过期解决静默纳入候选。采用前需要受控缓存来源、强制 staged diff、测试和审计。

单次操作可用 `--no-rerere-autoupdate` 明确阻止自动暂存，但实际支持位置和命令形式要按当前 Git 帮助核对。

## 第一次冲突建立 preimage

Merge 停止后：

~~~bash
git rerere status
git rerere diff
git rerere remaining
~~~

`status` 列出 rerere 正跟踪的冲突路径，`diff` 显示当前工作区解决相对冲突 preimage 的变化，`remaining` 列出仍未自动解决或无法由 rerere 处理的路径。

Rerere 根据冲突内容建立缓存 key，不以分支名或 commit OID 作为唯一 key。工作区标记会规范化，使两侧顺序和标记标签等表面差异不阻止某些复用。这个设计提高命中率，也说明命中不等于相同业务上下文。

编辑后：

~~~bash
git add -- path/to/conflict
git rerere
git diff --staged -- path/to/conflict
~~~

Git 在正常 add/commit/continue 路径中会调用 rerere 记录已解决结果；显式 `git rerere` 适合观察或受控流程。Postimage 是解决内容，不包含测试、审批或外部数据状态。

## 再次遇到相似冲突时仍保留 stages

`autoupdate=false` 的复用路径：

~~~bash
git status --short --branch
git ls-files --unmerged -- path/to/conflict
git rerere diff
git rerere remaining
git diff -- path/to/conflict
~~~

工作区可能已经是上次 postimage，状态仍显示未合并，`ls-files -u` 仍有输入 stages。`remaining` 为空可以表示 rerere 已提供工作区结果，不表示 index 已解决，也不表示全部业务测试通过。

复核顺序：

1. 保存本次 base、ours、theirs OID 和路径类型；
2. 比较复用后的工作区与三方输入；
3. 检查依赖、schema、配置和生成器是否变化；
4. 运行绑定当前候选的测试；
5. 人工 `git add -- path`；
6. 审查 staged diff，再 continue。

缓存命中可以节省重复编辑，不能转借上次测试结果。

## 错误复用要按路径忘记

当前冲突中发现旧结果不适用：

~~~bash
git rerere diff
git rerere forget -- path/to/conflict
git ls-files --unmerged -- path/to/conflict
~~~

`forget` 根据当前冲突重新记录该路径的 preimage，让本次从未解决状态重新开始。执行前保存错误复用内容和缓存 key 证据，便于判断是否有其他分支受影响。

不要直接删除整个 `.git/rr-cache`。这会同时丢弃其他仍有效记录，也破坏事故调查。`git rerere clear`、`gc` 和手工清理有不同作用域与保留语义，使用前查看当前版本文档并备份需要的缓存。

## Rerere 适用于多种冲突状态机

Merge、rebase、cherry-pick 和 revert 都可能产生 index stages，rerere 可以在可识别的内容冲突中记录/复用。Ours/theirs 在 rebase 中的含义与普通 merge 不同，但 rerere 处理的是规范化冲突内容，不替调用者解释分支角色。

每次记录操作类型、`HEAD`、正在应用的 commit 和状态目录。复用结果相同，不表示最终 commit 父关系、作者、签名或共享边界相同。

路径冲突、submodule 和某些二进制冲突可能无法由 rerere 完整跟踪。`rerere remaining` 仍有输出时逐条处理，不尝试通过空文件或 add 全部路径制造命中。

## 缓存是本地可变状态

Rerere 缓存通常位于当前仓库 common directory 的 `rr-cache`。Linked worktree 共享 common directory，因此可能共享 rerere 记录；不同 clone 默认不共享。

Git 2.49.0 文档中的默认清理窗口通常为：未解决记录 15 天，已解决记录 60 天，可由以下配置调整：

~~~bash
git config --show-origin --get gc.rerereUnresolved
git config --show-origin --get gc.rerereResolved
~~~

未显式设置时命令返回 1，仍使用版本默认。保留期限不是备份承诺；GC 调度、配置和缓存损坏都会影响实际可用性。

跨机器共享 `rr-cache` 会把可执行源码或配置写入他人工作区，必须像构建缓存一样治理来源、摘要、权限、租户隔离、版本和撤销。不要从未知仓库复制缓存，也不要把它当成不需评审的“团队冲突知识库”。

## 命中率不是质量指标

高命中率可能来自长期分支反复解决同一冲突，也可能说明架构、生成文件或集成频率有问题。团队应观察：

- 每类冲突的重复原因和等待时间；
- 复用后被人工修改或 forget 的比例；
- 复用候选的测试失败和回滚；
- 生成文件、锁文件、schema 等高风险路径；
- 缓存来源、过期与 Git 版本。

Rerere 适合降低确定性机械编辑，不应掩盖长期分叉或缺少接口兼容设计。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| 相同冲突没有命中 | preimage、marker style、路径、缓存和 Git 版本 | 正常人工解决，不篡改 stages 追求命中 |
| 工作区已变但仍显示 `UU` | autoupdate 配置、stages、rerere remaining | 审查复用结果后手工 add |
| 复用结果业务错误 | 本次三方 OID、旧 postimage、依赖与测试 | 保存证据、forget 当前路径、重新解决 |
| Autoupdate 静默暂存 | 配置来源、staged diff、缓存 provenance | 停止 continue，恢复 index 后人工复核 |
| 缓存突然消失 | GC 配置、common dir、清理任务和备份 | 人工解决；不要从不可信来源补缓存 |
| Linked worktree 结果互相影响 | common dir、并发操作和 rr-cache | 暂停并发，按候选与路径分流 |
| 共享缓存写入恶意内容 | 来源、摘要、权限和受影响工作区 | 隔离缓存与仓库，按安全事件处理 |

Rerere 错误不会修改已有 commit，但可能改变工作区或 index。未提交时先阻止 continue 并保存现场；已共享错误合并按第七篇追加修复或 revert，不能清理缓存后声称事故消失。

## 隔离实验

运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-complex-conflicts-rerere.sh
~~~

实验第一次人工解决 content/content 并记录 postimage；从同一两个尖端重建冲突时，Git 把结果写入工作区。由于 `autoupdate=false`，index 仍有 stage 1/2/3，脚本在检查后人工 add。第三次复现验证 `rerere forget` 让路径重新进入未解决状态。

脚本使用临时 common directory 和虚构身份，不共享缓存、不测试 autoupdate=true、真实 GC、恶意缓存、平台合并、业务测试或大仓库性能。

## 小结

Rerere 缓存冲突 preimage 到解决 postimage 的映射，减少重复编辑。它不保存业务理由、测试和审批，也不保证相似文本仍应使用旧结果。保持人工暂存、记录缓存来源，每次按本次三方对象重新验证，错误命中按路径 forget。

## 资料

- [git-rerere](https://git-scm.com/docs/git-rerere)
- [git-config](https://git-scm.com/docs/git-config)
- [git-merge](https://git-scm.com/docs/git-merge)
- [git-rebase](https://git-scm.com/docs/git-rebase)
- [gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)
