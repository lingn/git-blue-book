# 代码评审前整理什么：把候选、范围和验证绑定起来

代码评审的输入不是某个分支名，也不是一张 diff 截图，而是一组可以复核的候选提交、比较范围、测试结果和未包含内容。整理历史的目的，是让评审者知道变化来自哪里、会影响什么，以及怎样重新验证。

## 进入条件与完成标准

假设当前在未共享的功能分支，远程主线保存在 origin/main。开始前：

~~~bash
git status --short --branch
git branch --show-current
git rev-parse --verify HEAD^{commit}
git rev-parse --verify origin/main^{commit}
~~~

如果当前分支已经被别人使用，或评审已经关联旧 OID，先确认团队是否允许改写。不要为让提交数量变少而自动 rebase、reset 或 amend。

读完本章后，你应能：

- 确定评审候选提交和共同祖先；
- 区分工作区、index、当前分支和远程主线的变化；
- 用两点和三点范围避免漏看或误看；
- 检查提交粒度、路径范围、凭据和生成物；
- 记录测试、构建、迁移和回退证据；
- 在共享边界清晰后再决定是否重写历史。

## 第一层：先保护工作区

评审准备不是清空状态。先保存所有变化：

~~~bash
git status --short --branch --untracked-files=all
git diff --no-ext-diff --no-textconv
git diff --no-ext-diff --no-textconv --staged
git diff --check
git diff --staged --check
~~~

确认：

- 当前分支是预期功能分支；
- 未跟踪文件已经逐项判断；
- index 没有把凭据、调试日志、构建产物或其他任务变化混入；
- 工作区差异是本次任务的一部分，或已被明确保存。

若需要中途切换分支，先提交临时节点、stash 或使用独立 worktree。不要用 reset --hard 追求“干净”。

## 第二层：固定评审候选

先获取主线最新远程观察点：

~~~bash
git fetch origin
base="$(git merge-base origin/main HEAD)"
candidate="$(git rev-parse HEAD)"
printf 'base=%s candidate=%s\n' "$base" "$candidate"
~~~

fetch 可能更新 origin/main、对象库和 FETCH_HEAD，但不移动当前功能分支。候选是当前 HEAD 的完整 OID，不是短分支名。

如果功能分支只包含自己的提交：

~~~bash
git log --oneline "$base"..HEAD
git diff --stat "$base"...HEAD
git diff "$base"...HEAD
~~~

对 diff 使用三点范围表示从共同祖先比较到 HEAD。对 log 使用两点范围列出 HEAD 可达但 base 不可达的提交。不要把两个范围的语义混写。

如果候选是 merge commit 或合并队列生成的临时提交，另外保存 parent 列表、构造事件和目标分支：

~~~bash
git show --no-patch --format='%H%n%P%n%T%n%s' "$candidate"
~~~

评审平台上的候选、检查和审批可能指向一个之后已过期的 OID。平台控制面需要单独取证，不能由本地 log 代替。

## 第三层：检查提交粒度

逐条查看：

~~~bash
git log --format='%H%x09%P%x09%an%x09%ae%x09%s' "$base"..HEAD
git show --stat --format=fuller <commit-id>
git show --name-status <commit-id>
~~~

评审者应能回答：

- 每条提交是否有独立意图；
- 提交顺序是否让中间状态可理解；
- 是否混入纯格式化、无关重构或生成文件；
- 是否包含之后完全撤销的实验噪音；
- 提交说明是否写清动机、约束和验证。

粒度不是“每个文件一个提交”，也不是“提交越少越好”。当一个功能需要一起修改接口、实现和测试时，拆得过细反而会让中间提交无法验证。重点是每条提交的边界能否解释和审查。

## 第四层：检查路径和外部输入

按任务清单核对：

~~~bash
git diff --name-status "$base"...HEAD
git diff --submodule=log "$base"...HEAD
git ls-files --others --exclude-standard
git check-ignore -v -- path/to/suspect
~~~

额外关注：

- 子模块 gitlink 指向的提交是否已发布；
- LFS pointer 对应 payload 是否在目标环境可取；
- 构建脚本、CI 配置和第三方依赖是否改变执行权限；
- .gitattributes、filter、换行和文件模式是否改变实际输入；
- 生成文件是否与源码候选和构建清单一致；
- 敏感文件是否只在工作区、reflog 或旧提交中出现。

Git diff 不会自动展示所有外部状态。评审清单应把未跟踪、忽略、LFS、子模块、制品和部署输入列成独立证据。

## 第五层：验证候选行为

至少运行仓库规定的测试、构建、静态检查和格式检查，并记录：

~~~text
candidate: <完整 OID>
environment: <工具链和版本>
commands: <实际命令>
result: pass/fail
artifacts: <摘要或位置>
limitations: <未覆盖范围>
~~~

如果改动涉及数据库、消息、配置或多个服务，还要说明：

- expand/contract 顺序和混合版本兼容；
- 回填、锁和事务边界；
- 受影响服务和部署顺序；
- 已知良好制品和回退目标；
- 运行指标和关闭条件。

“本地测试通过”不能证明 CI 用了同一 OID，也不能证明制品、数据库和运行实例一致。

## 是否需要重写历史

在未共享功能分支上，可以根据团队约定使用交互式 rebase 整理提交。但先保存：

~~~bash
git branch --contains HEAD
git reflog -1
git log --oneline --decorate --all
~~~

如果分支已经推送、评审、被其他工作树检出或被自动化引用，重写会改变 OID 和评审关联。此时优先追加修正提交，或明确通知所有依赖者后再操作。整理后的推送需要显式租约，不用无条件 force。

合并、squash、rebase merge 都会留下不同的提交图。评审者应看到最终候选 OID、原始提交范围和平台合并结果，而不是只看提交数量。

## 评审前检查清单

| 证据 | 要证明的事实 | 缺失时的动作 |
| --- | --- | --- |
| 当前 branch/HEAD OID | 评审对象明确 | 停止，不共享模糊分支名 |
| base 和 candidate | diff 范围可重现 | fetch 并记录共同祖先 |
| status 与 untracked | 没有遗漏路径 | 逐项处理或说明未纳入 |
| staged diff | 真实提交输入 | 先清理 index，再审查 |
| commit log/show | 意图和粒度可理解 | 调整提交或解释依赖 |
| 测试/构建结果 | 行为有验证 | 补运行或标注缺口 |
| LFS/submodule/CI 输入 | 外部依赖已固定 | 取得 payload、发布依赖或阻塞评审 |
| 回退与部署证据 | 运行风险可控 | 交给发布流程，不在评审中猜测 |

## 失败路径

| 现象 | 先收集 | 恢复 |
| --- | --- | --- |
| diff 范围为空 | base、candidate、merge-base、路径 | 确认是否确实没有变化或 ref 过期 |
| 发现无关文件 | status、staged name-status | 按路径取消暂存或追加明确提交 |
| 本地和平台候选不同 | OID、fetch 时间、事件 ID | 以平台候选为准重新取证 |
| 测试只在工作区通过 | candidate、构建清单、未暂存变化 | 在干净检出中重跑 |
| 评审后需要改写 | 分支所有权、依赖者、旧 OID | 协调后使用租约，或追加修正 |
| 子模块/LFS 缺对象 | gitlink/pointer OID、外部服务状态 | 先发布或补齐外部对象，不把 Git diff 当完整证明 |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-history.sh
~~~

该实验验证本地 clone、fetch、非快进拒绝、rebase、维护分支 cherry-pick 和提交 OID 变化。它不模拟真实评审平台的候选、审批、CODEOWNERS、CI、制品或部署控制面。

## 小结

评审准备的核心是固定 base、candidate 和实际差异，再把提交意图、路径范围、测试结果和外部输入一起记录。工作区、index、远程跟踪 ref、平台候选和运行版本各有边界；整理历史可以改善可读性，但不能改变共享边界和证据要求。
