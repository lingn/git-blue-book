# 热修复如何在多个分支之间迁移：来源、目标与运行范围

热修复不是“把某个 commit 复制到 release 分支”这么简单。需要同时确认修复来源、目标分支、依赖闭包、生成的新 OID、制品和部署范围。Git 能证明提交和 tree 的关系，不能单独决定哪些服务需要重启或哪种数据库迁移可回退。

本章是本地分支操作入口。完整的事故到发布证据链见第八篇，cherry-pick 的冲突状态和来源记录见第四篇。

## 进入条件与完成标准

假设修复提交位于 develop，发布分支 release/1.x 只需要这个变化。开始前在目标仓库执行：

~~~bash
git status --short --branch
git rev-parse --verify develop^{commit}
git rev-parse --verify release/1.x^{commit}
git log --graph --decorate --oneline --all
~~~

工作区和 index 应干净，来源提交必须已取得且对象可读。不要只凭网页标题、短 OID 或提交说明判断修复独立。

读完本章后，你应能：

- 固定 source commit、target branch 和目标基线；
- 判断 cherry-pick 是否会生成新 OID、是否存在依赖；
- 处理目标分支冲突、空提交和中止；
- 用路径、对象和测试验证迁移结果；
- 计算受影响的构建模块、服务、配置和数据库；
- 写出可追溯的来源、目标、制品、部署记录。

## 先建立来源和目标清单

取得来源分支的最新本地观察点：

~~~bash
git fetch origin
source_commit=<完整修复提交 OID>
git cat-file -t "$source_commit"
git show --format=fuller --stat "$source_commit"
git rev-list --parents -n 1 "$source_commit"
~~~

然后查看目标分支：

~~~bash
git switch release/1.x
git status --short --branch
target_before="$(git rev-parse HEAD)"
git merge-base release/1.x "$source_commit"
~~~

把以下字段写入迁移清单：

~~~text
source_ref: <develop 或发布候选>
source_commit: <完整 OID>
target_branch: release/1.x
target_before: <目标分支迁移前 OID>
reason: <为什么维护线需要此修复>
dependencies: <接口、配置、迁移、共享库和外部对象>
verification: <目标版本测试和构建>
rollback: <revert 或其他回退方案>
~~~

如果 source_commit 不在本地对象库，先 fetch 对应 ref；不要使用一个可能解析到其他对象的短前缀。

## 检查修复是否真的独立

查看来源提交的变化和前序历史：

~~~bash
git show --format=fuller --name-status "$source_commit"
git show "$source_commit" -- path/to/fix
git log --oneline "$source_commit"^.."$source_commit"
git log --oneline --ancestry-path <source-base>.."$source_commit"
~~~

逐项判断：

- 是否依赖之前的 API、配置或数据模型；
- 是否假设某个数据库 schema 已迁移；
- 是否改变共享 SDK 或自动配置；
- 是否要求 LFS、submodule 或生成物；
- 是否只在 develop 的特定 feature flag 下生效；
- 是否带有与维护线不兼容的测试或脚本。

单个文件的 diff 不能证明运行时独立。依赖闭包应来自构建图、调用链、schema 版本和运行环境，而不是提交标题。

## 在目标分支应用修复

目标分支确认后：

~~~bash
git cherry-pick "$source_commit"
~~~

成功后保存新提交：

~~~bash
picked_commit="$(git rev-parse HEAD)"
git show --no-patch --format='%H%n%P%n%T%n%s' "$picked_commit"
git diff --stat "$target_before" "$picked_commit"
git status --short --branch
~~~

picked_commit 通常与 source_commit 不同，因为父提交、tree、提交者时间或说明上下文不同。source_commit 仍然保留在 develop；cherry-pick 不会移动来源分支。

如果只想先审查 index：

~~~bash
git cherry-pick --no-commit "$source_commit"
git diff --staged --check
git diff --staged
git commit -m "fix: backport payment correction"
~~~

no-commit 仍会修改工作区和 index，不能把它当成只读预览。发现结果不对时，按明确路径恢复并记录未采用原因。
## 冲突和中止

目标分支已有不同上下文时，cherry-pick 可能停止。先取证：

~~~bash
git status --short --branch
git rev-parse --verify CHERRY_PICK_HEAD
git cherry-pick --show-current-patch
git ls-files --unmerged
~~~

按目标版本的业务约束解决，逐路径 add 或 rm，再：

~~~bash
git diff --staged --check
git cherry-pick --continue
~~~

continue 可能运行 hook、打开编辑器或在下一条提交再次冲突。确认当前来源提交是否仍有独立价值，才决定 skip：

~~~bash
git cherry-pick --skip
~~~

skip 放弃整个当前来源提交，不只是跳过一个文件。发现目标版本不适合迁移时：

~~~bash
git cherry-pick --abort
git status --short --branch
git rev-parse HEAD
~~~

abort 尝试恢复到开始前状态。开始前已有未提交工作、autostash 或外部工具改动时，恢复可能不完整，必须与迁移清单和保存副本对照。

## 验证目标版本

Git 层至少验证：

~~~bash
git merge-base --is-ancestor "$target_before" HEAD
git show --format=fuller --stat HEAD
git diff "$target_before" HEAD -- path/to/changed-file
git status --short --branch
~~~

然后运行目标分支适用的测试、构建和静态检查。把结果绑定到 picked_commit，而不是 source_commit。若修复改变共享库、配置或数据库：

- 列出实际依赖服务；
- 检查旧版本与新版本的兼容矩阵；
- 确认 migration 是否可续跑和可回退；
- 保存制品摘要和运行版本；
- 写明金丝雀停止条件和回退目标。

Git 分支包含关系不能证明部署实例已经加载该代码。

## 哪些分支包含修复

对于原始 source_commit：

~~~bash
git branch --contains "$source_commit"
git branch -r --contains "$source_commit"
~~~

这只检查本地分支和本地远程跟踪 refs。picked_commit 不会被这些命令归入包含 source_commit 的分支，即使文件内容等价。需要比较等价补丁时，保存 source 和 picked 两个 OID，并查看：

~~~bash
git show "$source_commit" --format= --binary
git show "$picked_commit" --format= --binary
git log --cherry-mark --oneline "$source_commit"..."$picked_commit"
~~~

--cherry-mark 使用补丁等价启发式，仍不是业务证明。重复迁移或后续完整合并可能再次冲突，记录来源链可以避免误以为修复缺失。

## 计算部署范围

提交改了哪个文件，只是部署分析的起点。继续核对：

~~~bash
git diff-tree --no-commit-id --name-status -r "$picked_commit"
git diff-tree --no-commit-id --dirstat=files,0 -r "$target_before" "$picked_commit"
~~~

结合构建图和运行清单回答：

- 哪个组件编译并打包了变化；
- 哪些服务实际加载共享模块；
- 是否需要同步配置、schema、消息消费者和生产者；
- 是否有 LFS、submodule 或制品输入；
- 哪些实例需要滚动、金丝雀或重启；
- 如何证明全部实例已经运行新 digest。

不要从 commit message 直接推导“只发布 manager”或“只重启 worker”。第八篇的部署证据链要求把候选 OID、制品摘要和实例状态分开记录。
## 回退选择

如果 picked_commit 已进入共享发布线，优先使用追加的 revert 保留审计链：

~~~bash
git revert "$picked_commit"
~~~

如果只是未共享的目标分支且需要重新选择范围，可以 abort 后重新 cherry-pick 或在私有历史中整理。数据库不可逆迁移、异步消息和外部数据写入可能让代码回退无法恢复行为，必须按发布和迁移方案向前修复。

回退前保存 source_commit、picked_commit、制品、schema 和运行状态。Git revert 成功不等于数据库和数据已经回到旧状态。

## 失败路径和恢复

| 现象 | 首先收集 | 处理 |
| --- | --- | --- |
| source OID 无法解析 | refs、fetch 记录、对象类型 | 取得正确对象，不改目标分支 |
| cherry-pick 冲突 | CHERRY_PICK_HEAD、当前目标、stages | 按目标语义解决或 abort |
| 空 cherry-pick | 目标已有等价变化、来源依赖 | 明确 skip、保留空提交或不迁移 |
| 目标分支已共享 | 目标 OID、评审、制品、部署 | 追加修复或 revert，不重写共享历史 |
| 只改一个文件但多个服务受影响 | 构建图、调用链、运行清单 | 扩大验证和部署范围 |
| 迁移后测试失败 | picked OID、环境、schema、制品 | 停止提升，保留目标提交并调查 |
| 回退代码但数据未回退 | migration、消息、外部写入 | 采用向前修复或数据恢复流程 |

不要用 reset --hard、branch -D 或删除提交来掩盖迁移错误。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-6-engineering.sh
~~~

实验验证 hotfix 工作树中的修复提交可以被维护分支 cherry-pick，目标提交得到不同 OID 但文件变化保留。它不验证真实构建图、平台发布、数据库、消息、LFS、制品、部署或优雅停机。

## 小结

热修复迁移需要同时固定 source、target_before 和 picked OID，先检查依赖，再在目标分支应用并验证。Git 可以证明提交和文件快照，构建图、数据库、制品、实例和数据回退需要外部证据。修复进入共享历史后用追加 revert 保留因果链，未共享历史才考虑重新选择或改写。
