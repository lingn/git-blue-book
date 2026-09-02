# 提交信息、粒度与可审查历史：把一次变化变成协作契约

一条提交是未来排障、回滚、发布和归因的坐标。它至少要让读者知道：为什么改、改变了哪个边界、依赖什么、怎样验证、能否单独撤销。提交数量和图形是否线性只是表面属性，不能替代这些信息。

## 进入条件与完成标准

在准备提交的本地仓库根目录执行。开始前保存：

~~~bash
git status --short --branch --untracked-files=all
git diff --no-ext-diff --no-textconv
git diff --no-ext-diff --no-textconv --staged
git rev-parse --verify HEAD^{commit}
~~~

如果仓库正在 merge、rebase、cherry-pick 或 revert，先处理对应状态。不要在一段未完成操作中用普通 commit 掩盖状态。

读完本章后，你应能：

- 用意图、依赖、验证和回滚判断提交边界；
- 区分提交主题、正文、trailers、作者和提交者；
- 发现格式化、生成物、凭据和无关重构污染；
- 设计可审查的多提交序列；
- 选择 amend、交互式 rebase 或追加修正的共享边界；
- 用 OID、tree、差异、测试和签名记录提交证据。

## 提交的四个问题

审查一条提交时，按顺序问：

1. 它解决了哪个明确问题，影响范围是什么；
2. 它依赖哪些代码、配置、schema、消息、子模块或外部对象；
3. 它怎样被验证，测试覆盖了什么、没覆盖什么；
4. 如果结果错误，怎样单独撤销、修正或向前修复。

“改了一个文件”不代表边界小，一个共享库的单行变化可能影响多个服务。反过来，一个功能需要同时修改接口、实现、测试和迁移时，把每个文件拆成单独提交会让中间状态不可运行。

## 原子性不是文件数量

适合放在同一提交的变化，通常满足：

- 具有一个可以说清的行为或文档意图；
- 依赖关系在提交内部闭合，或前序提交明确提供依赖；
- 评审者可以用一个 diff 理解；
- 测试和构建边界清楚；
- 出问题时有明确回滚或向前修复动作。

通常应拆开的变化包括：

- 无关格式化与业务修复；
- 两个可以独立发布的功能；
- 大规模重命名与行为变化；
- 生成物更新与源码修复；
- 凭据、权限策略与普通文档；
- 数据迁移与不兼容的应用切换。

拆分时不要只按目录或文件数判断。数据库迁移、应用兼容层、测试和运行配置可能必须作为一个可验证单元；但多个不相关的迁移也不应塞进同一提交。

## 提交前审查 index

提交读取 index，不读取编辑器当前尚未暂存的版本。按固定顺序审查：

~~~bash
git status --short --branch --untracked-files=all
git diff --no-ext-diff --no-textconv
git diff --no-ext-diff --no-textconv --staged
git diff --staged --check
git ls-files --stage
~~~

确认：

- index 中只有本次意图的路径；
- 暂存版本与工作区最新版本没有意外分叉；
- 没有凭据、调试输出、构建缓存或个人草稿；
- 属性、换行、filter 和文件模式符合项目规则；
- 删除、重命名和子模块 gitlink 是有意的。

空的普通 diff 不等于没有变化。未跟踪文件、忽略路径、LFS payload、子模块内部变化和 sparse 路径要分别取证。

## 主题和正文

主题行应具体、稳定、可搜索。可以使用团队约定的前缀，但前缀不能代替动机：

~~~text
fix: prevent duplicate settlement on retry
docs: explain detached HEAD recovery
refactor: separate token validation from transport
~~~

正文回答背景、方案、风险和验证，不要逐行复述 diff：

~~~text
fix: prevent duplicate settlement on retry

Persist the provider request key before the first external call so a
worker retry reuses the same operation. The schema change remains
compatible with the previous worker during the rollout.

Tests: unit retry case, integration provider stub.
Rollback: deploy the previous artifact; schema column is additive.
~~~

中文团队可以使用中文正文，技术关键词保留项目实际使用的名称。主题和正文不要承诺没有执行过的测试、部署或审批。提交说明是声明，不是自动事实来源。

## Trailers、签名和身份

trailers 可以记录 Reviewed-by、Co-authored-by、Fixes、Refs、Tested-by 等结构化信息。它们改善检索和关联，但不能自动验证对应的人、工单或测试：

~~~bash
git show --format=fuller --format='%(trailers:unfold)' <commit>
~~~

author 表示 commit 元数据中的原始作者，committer 表示创建当前对象的人。签名字段证明某个密钥对特定对象签名，不能自动证明有权合并、发布或部署。提交质量审查仍要同时查看远程认证、评审事件、CI 和运行记录。

不要通过伪造 Co-authored-by、修改邮箱或使用他人密钥来补齐“看起来完整”的历史。身份不确定时如实标记并走组织流程。

## 可验证的多提交序列

一个功能可能需要这样的顺序：

~~~text
1. 建立接口或数据结构
2. 实现行为和错误处理
3. 添加测试和观测
4. 更新文档或迁移说明
~~~

每一步是否能独立构建，要看项目约定。如果中间提交暂时不能部署，应在提交说明和评审规则中明确，而不是假装它是可独立发布的单元。评审者需要知道哪些提交只用于阅读，哪些提交可以单独回滚。

查看序列：

~~~bash
git log --format='%H%x09%P%x09%s' <base>..HEAD
git show --stat --format=fuller <commit>
git diff <base>..<commit> --check
~~~

提交顺序错误、前序依赖缺失或测试落在后续提交中时，先调整提交边界，再开始评审。

## 格式化和生成物

格式化有时是必要变更，但大规模格式化会降低归因和审查质量。建议：

- 将纯格式化与行为变化拆开；
- 在提交说明中写清工具和范围；
- 提供 blame ignore-revs 文件，并经过评审；
- 固定生成工具和版本；
- 对生成物保存源码、输入清单和摘要；
- 不把生成文件当作“测试通过”的证据。

如果格式化和行为变化必须同一提交，正文要说明原因和影响，评审中使用不含格式噪声的辅助 diff。历史查询时不要把最后写入者直接当作逻辑作者。

## 提交钩子和自动化

pre-commit、commit-msg、签名和其他 hook 可能拒绝提交或修改输入。提交失败后先查看：

~~~bash
git status --short --branch
git diff --staged
git rev-parse HEAD
git config --show-origin --get-regexp '^(core\.hooksPath|commit\.|gpg\.|ssh\.)'
~~~

失败通常不会移动 HEAD，但 hook 可能已经生成文件、修改 index 或写入外部日志。修复具体问题后重新审查。不要用 no-verify 绕过未知门禁；若确有例外，应记录原因、批准人和补做的检查。

CI 生成提交时还要记录工作负载身份、输入候选 OID、工具版本和生成方式。提交作者字段不能替代自动化身份证据。

## amend、rebase 与追加修正

最近一次提交尚未共享时，可以使用 amend 修正遗漏内容或说明：

~~~bash
git commit --amend
~~~

这会创建新 commit，旧 OID 仍可能由 reflog、标签或其他引用保留。多条提交的顺序、拆分和合并应使用交互式 rebase，并先建立恢复引用。

已经推送、被评审、被其他 worktree 或 CI 引用的提交，默认追加修正或 revert。若团队明确允许改写，保存旧远程 OID、通知使用者并使用显式租约。不要把提交数量少当成共享历史改写的理由。

## 提交后验收

提交成功后执行：

~~~bash
commit="$(git rev-parse HEAD)"
git status --short --branch --untracked-files=all
git show --no-patch --format='%H%n%P%n%T%n%an%n%ae%n%cn%n%ce%n%s' "$commit"
git show --stat --format=fuller "$commit"
git diff-tree --no-commit-id --name-status -r "$commit"
git fsck --connectivity-only
~~~

根据项目规则补充测试、构建、静态检查、签名验证和制品摘要。不要把 fsck 通过解释成代码正确；它只检查对象连接性范围。

如果提交进入发布流程，关联：

~~~text
commit: <完整 OID>
source/input: <依赖和构建清单>
tests: <实际命令和结果>
artifact: <摘要>
review: <评审和审批事件>
deployment: <实例或 rollout 证据>
rollback: <代码、制品、schema 和数据动作>
~~~

## 失败路径和恢复

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| 提交混入无关文件 | status、staged name-status、属性 | 逐路径取消暂存并重新审查 |
| 主题准确但行为不完整 | diff、依赖、测试和运行记录 | 追加修正或拆分提交，不只改说明 |
| hook 拒绝提交 | hook 输出、HEAD、index、配置来源 | 修复门禁，保留失败证据 |
| amend 后找不到旧提交 | reflog、标签、恢复分支 | 建立恢复引用，不立即 gc |
| 共享提交需要重写 | 旧/新 OID、协作者、评审和 CI | 默认追加修正，获批后才用租约 |
| 生成物无法复现 | 工具版本、输入清单、缓存 | 固定输入并重新构建，不提交猜测产物 |
| 提交后测试失败 | candidate、制品、部署和数据状态 | 按共享边界 revert 或向前修复 |

## 隔离实验验证了什么

结合以下实验验证本章的本地边界：

~~~bash
./scripts/verify-part-2.sh
./scripts/verify-interactive-rebase.sh
./scripts/verify-signatures-trust.sh
~~~

实验能证明 index 审查、hook 拒绝、提交对象变化、交互式重建和签名对象的本地关系。它不能证明提交说明中的工单、评审、CI、制品、部署和责任声明真实有效。

## 小结

可审查提交不是格式漂亮的提交，而是意图、依赖、验证和回滚边界都能被复核的提交。先审查 index，再写准确说明，提交后固定完整 OID、tree、测试和外部证据。私有历史可以整理，共享历史要保持坐标稳定；任何自动生成的声明都不能替代真实系统证据。
