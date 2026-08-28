# 综合场景：同步主线，再准备一次可追溯评审

你在未共享的 feature/search-filter 分支上有两条提交，远程 main 已被同事更新。目标是先更新本地远程观察点，再选择不会覆盖他人历史的整合方式，最后固定评审候选并首次发布功能分支。

本练习需要一个实际可访问的远程仓库。若没有授权的测试远程，请只按“本地 bare 替代实验”运行，不要把示例 URL 或令牌换成生产值。

## 练习边界

- 执行位置：feature/search-filter 的本地 clone 根目录；
- 前置条件：Git 2.28 或更高版本、已配置 origin、分支工作区干净；
- 远端假设：origin/main 代表团队主线，但其 OID 必须通过本次 fetch 更新；
- 共享边界：feature/search-filter 从未推送，只有当前操作者使用；
- 安全边界：不使用 force，不删除远程引用，不修改他人分支；
- 完成标准：远程主线提交被保留，功能差异可重现，候选 OID 和验证记录完整，上游关系明确。

## 1. 保护当前工作和身份

~~~bash
pwd
git rev-parse --show-toplevel
git status --short --branch --untracked-files=all
git branch --show-current
git config --show-origin --show-scope --get-regexp '^remote\.origin\.|^branch\.'
~~~

如果状态不是干净，先保存工作区和 index 差异。不要为了演示 pull 而 reset --hard。确认当前分支确实是 feature/search-filter，避免把主线当成个人分支重写。

## 2. 获取远程最新观察点

~~~bash
old_origin="$(git rev-parse --verify origin/main^{commit})"
git fetch origin
new_origin="$(git rev-parse --verify origin/main^{commit})"
printf 'origin_before=%s origin_after=%s\n' "$old_origin" "$new_origin"
git rev-parse --verify FETCH_HEAD^{commit}
git log --graph --decorate --oneline --all
~~~

fetch 可能更新对象、origin/main 和 FETCH_HEAD，但不移动当前功能分支。即使 new_origin 与 old_origin 相同，也只能说明本次观察没有发现新的可见提交。

## 3. 固定共同祖先和两侧提交

~~~bash
base="$(git merge-base origin/main HEAD)"
candidate_before="$(git rev-parse HEAD)"
printf 'base=%s candidate_before=%s\n' "$base" "$candidate_before"
git log --oneline "$base"..HEAD
git log --oneline HEAD..origin/main
git diff --stat "$base"...HEAD
git diff "$base"...HEAD
~~~

两点 log 范围列出功能分支独有提交；三点 diff 从共同祖先比较到当前候选。保存 base、candidate_before 和范围，之后 rebase 会改变 candidate OID。

如果 origin/main 没有共同祖先，先检查远程 URL、仓库迁移、浅克隆和权限。不要强行合并两个独立根。

## 4. 选择整合方式

当前假设功能分支未共享，团队要求基于最新主线，因此执行：

~~~bash
git rebase origin/main
~~~

变基会按顺序重建功能分支提交。冲突时：

~~~bash
git status --short --branch
git rebase --show-current-patch
git ls-files --unmerged
~~~

按提交意图解决，逐路径 add，再执行 rebase --continue。发现起点或结果错误时使用：

~~~bash
git rebase --abort
~~~

abort 后确认 HEAD 回到 candidate_before，工作区和 index 恢复到开始前状态。不要把 rebase --skip 当作普通冲突解决，它会跳过整个来源提交。

如果该分支已经被同事、评审或 CI 使用，停止变基，改为协调后 merge 或追加修正。共享边界比“历史看起来线性”更重要。

## 5. 评审前重新固定候选

变基成功后：

~~~bash
candidate="$(git rev-parse HEAD)"
git status --short --branch
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
git diff --check
git diff --staged --check
git show --no-patch --format='%H%n%P%n%T%n%s' "$candidate"
~~~

候选 OID 应与 candidate_before 不同，这是重新生成提交的结果。功能差异仍应表达搜索过滤目标，且工作区没有额外未提交输入。

运行项目规定的测试、构建、静态检查和格式检查，记录真实命令、工具版本、结果、制品摘要和未覆盖范围。若涉及共享库、数据库或配置，补充部署顺序和回退边界。

## 6. 首次推送功能分支

确认目标和候选后：

~~~bash
git push --set-upstream origin HEAD:refs/heads/feature/search-filter
~~~

显式 refspec 把当前 HEAD 发布到远程功能分支，并建立 upstream。成功后核对：

~~~bash
git branch -vv
git rev-parse '@{upstream}'
git ls-remote origin refs/heads/feature/search-filter
~~~

远端返回的 OID 应等于 candidate。push 成功只证明远端 Git ref 更新，不证明评审、CI、制品和部署已完成。

## 7. 形成评审记录

至少保存：

~~~text
base: <origin/main 的完整 OID>
candidate: <变基后的完整 OID>
source history: <变基前提交 OID 列表>
range: origin/main...HEAD
tests: <命令和结果>
build: <构建输入和制品摘要>
deployment impact: <组件、迁移、回退>
remote ref: refs/heads/feature/search-filter
limitations: <平台、LFS、外部依赖或运行验证缺口>
~~~

平台合并请求的事件 ID、审批、必需检查和候选构造方式另行记录。不要只贴 git log 或网页截图。

## 失败路径和恢复

| 现象 | 先收集 | 恢复 |
| --- | --- | --- |
| fetch 失败 | URL、身份、原始 stderr、当前 refs | 修复传输层，不移动工作分支 |
| rebase 冲突 | HEAD、rebase patch、stages、工作区 | 逐提交解决或 abort |
| origin/main 仍过期 | fetch 时间、可见 refs、远端查询 | 核对权限和 refspec，不猜测 OID |
| 评审前发现无关文件 | status、staged diff、未跟踪扫描 | 按路径清理或追加明确提交 |
| push 无上游 | branch -vv、目标 ref | 显式 refspec 加 --set-upstream |
| push non-fast-forward | 远端 OID、merge-base、并发提交 | fetch 后重新审查，禁止无条件 force |
| 变基后同事引用旧 OID | 分支使用者、评审事件、旧/新 OID | 停止推送，通知协作者或恢复旧分支 |

## 本练习的验收边界

本练习能证明本地 Git 对象、refs、rebase 和 push 的关系。它不能单独证明：

- 托管平台的评审审批、CODEOWNERS、合并队列和保护规则；
- CI 是否使用同一个 candidate OID；
- 制品是否由同一输入构建并已提升；
- 数据库、配置、LFS、子模块和运行实例是否兼容；
- 远程审计、权限主体和组织留存是否完整。

这些事实必须从平台、构建、制品、运行和审计系统分别取证。

## 小结

一次可追溯的评审准备先固定远程观察点和共同祖先，再根据共享边界选择 rebase 或 merge，最后用 candidate OID、三点 diff、测试和推送结果形成证据链。pull、rebase 和 push 都会改变不同层，拆开观察比把它们当成一个“同步动作”更容易恢复和审查。
