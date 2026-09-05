# 常用命令地图

这不是从零学习入口。第一次阅读请按正文顺序；遇到工作问题时，可从这里回到命令首次解释和风险边界。

## 建立仓库和记录

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 确认版本 | `git --version` | [安装与版本](../part-2/01-install.md) |
| 配置身份 | `git config` | [身份配置](../part-2/02-identity.md) |
| 查看配置来源和最终身份 | `git config --show-origin --show-scope`、`git var` | [身份配置](../part-2/02-identity.md) |
| 初始化仓库 | `git init` | [创建仓库](../part-2/03-init.md) |
| 查看状态 | `git status` | [状态](../part-2/04-status.md) |
| 准备内容 | `git add` | [暂存](../part-2/06-add.md) |
| 创建提交 | `git commit` | [提交](../part-2/07-commit.md) |
| 检查暂存差异或创建受控空提交 | `git diff --staged --check`、`git commit --allow-empty` | [提交](../part-2/07-commit.md) |
| 比较内容 | `git diff` | [差异](../part-2/08-diff.md) |
| 查看历史 | `git log`、`git show` | [历史](../part-2/09-history.md) |

## 分支与整合

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 查看或创建分支 | `git branch` | [分支模型](../part-3/02-branch-as-reference.md) |
| 切换分支 | `git switch` | [切换分支](../part-3/04-switch-branch.md) |
| 合并历史 | `git merge` | [合并](../part-3/05-first-merge.md) |
| 标记版本 | `git tag` | [标签](../part-3/09-tags.md) |
| 重建功能提交 | `git rebase` | [安全变基](../part-4/11-rebase-workflow.md) |
| 迁移独立提交 | `git cherry-pick` | [挑选提交](../part-07/07-cherry-pick.md) |

## 远程协作

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 复制仓库 | `git clone` | [克隆](../part-4/02-clone.md) |
| 管理远程地址 | `git remote` | [远程配置](../part-4/03-remote.md) |
| 只获取远程历史 | `git fetch` | [获取](../part-4/04-fetch.md) |
| 获取并整合 | `git pull` | [拉取](../part-4/06-pull.md) |
| 发布提交或标签 | `git push` | [推送](../part-4/07-push.md) |
| 计算本地与上游各自独有的提交数 | `git rev-list --left-right --count` | [远端历史改写](../part-5/14-remote-history-rewrite.md) |
| 判断本地提交是否有上游补丁等价项 | `git cherry -v`、`git range-diff` | [远端历史改写](../part-5/14-remote-history-rewrite.md) |

## 撤销与恢复

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 丢弃未暂存修改 | `git restore <路径>` | [恢复工作区](../part-07/02-restore-worktree.md) |
| 取消暂存 | `git restore --staged` | [取消暂存](../part-07/03-unstage.md) |
| 替换最近本地提交 | `git commit --amend` | [amend 一条提交](../part-07/04-amend-one-commit.md) |
| 重置最近提交署名 | `git commit --amend --reset-author` | [amend 一条提交](../part-07/04-amend-one-commit.md) |
| 变基时逐条执行命令 | `git rebase --exec` | [逐条执行](../part-07/05-interactive-rebase.md) |
| 对提交改名、合并、拆分或删除 | `git rebase -i` 的 `reword`、`fixup`、`squash`、`edit`、`drop` | [amend 一条提交](../part-07/04-amend-one-commit.md) |
| 撤销已公开提交 | `git revert` | [公开回滚](../part-5/07-revert.md) |
| 有条件更新个人远程分支 | `git push --force-with-lease` | [租约保护](../part-5/09-force-with-lease.md) |
| 移动分支并选择区域更新范围 | `git reset` | [reset 三模式](../part-5/10-reset.md) |
| 查找引用旧位置 | `git reflog` | [引用日志](../part-5/11-reflog.md) |
| 证明 fetch 非快进更新及 rebase abort 返回位置 | `git reflog show origin/<branch>`、`git reflog show HEAD` | [远端历史改写](../part-5/14-remote-history-rewrite.md) |

## 工程调查

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 临时收纳修改 | `git stash` | [stash](../part-02/11-stash.md) |
| 多个工作目录 | `git worktree` | [worktree](../part-02/12-multiple-worktrees.md) |
| 二分定位缺陷 | `git bisect` | [历史归因中的 bisect](../part-11/03-history-attribution.md) |
| 查询当前行的最后写入提交 | `git blame --line-porcelain` | [历史归因](../part-11/03-history-attribution.md) |
| 搜索字符串数量或差异行演变 | `git log -S`、`git log -G` | [历史归因](../part-11/03-history-attribution.md) |

## 规模与仓库组合

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 采集对象、引用和历史规模 | `git count-objects`、`git rev-list`、`git for-each-ref` | [性能与维护基线](../part-09/01-measure-before-optimizing.md) |
| 验证辅助索引与维护 | `git commit-graph`、`git multi-pack-index`、`git maintenance` | [性能与维护基线](../part-09/01-measure-before-optimizing.md) |
| 排查慢命令和容量分层 | `git status`、`git rev-list`、`git count-objects`、Trace2 | [性能和容量故障](../part-13/04-performance-and-capacity-failures.md) |
| 排查 LFS、子模块和 CI clone 外部依赖 | `git cat-file`、`git ls-tree`、`git lfs fetch/checkout/fsck`、`git submodule status/update` | [LFS、子模块与 CI clone 异常](../part-13/05-lfs-submodule-ci-failures.md) |
| 排查签名、信任策略和 tag 目标 | `git show`、`git verify-commit`、`git verify-tag`、`git cat-file` | [签名无法验证与密钥状态异常](../part-13/06-signature-verification-failures.md) |
| 对账远端 refs、默认分支、分支重命名和标签 OID | `git ls-remote --symref`、`git fetch`、`git remote set-head`、`git update-ref` | [远程引用漂移](../part-13/07-remote-ref-drift-failures.md) |
| 分流锁文件、引用并发和对象/pack 损坏 | `git rev-parse --git-common-dir`、`git update-ref <ref> <new> <expected-old>`、`git fsck`、`git verify-pack` | [仓库损坏、锁与并发](../part-13/08-repository-corruption-locks-concurrency.md) |
| 核对 CI 触发事件、实际 checkout 和路径输入 | `git rev-parse`、`git status --porcelain=v1`、`git diff --name-status -z` | [触发与 checkout](../part-08/01-triggers-and-checkout.md) |
| 固定 candidate、比较 merge-base/target 并判断结果是否过期 | `git cat-file -e`、`git show`、`git merge-base`、`git update-ref <ref> <new> <expected-old>` | [候选提交](../part-08/02-candidate-commits.md) |
| 固定流水线 blob、发布 tag、源码归档和制品目标 | `git rev-parse <commit>:<path>`、`git cat-file -t`、`git archive`、`sha256sum`/`shasum` | [制品与部署证据链](../part-08/03-source-artifact-deployment-evidence.md) |
| 比较两次源码归档、固定构建环境并核对 manifest | `git archive --mtime`、`git cat-file -e`、`sha256sum`/`shasum` | [可重复构建](../part-08/04-reproducible-builds.md) |
| 创建、推送并核对附注发布 tag，验证制品提升和同名竞态 | `git tag -a`、`git push <refspec>`、`git ls-remote --tags`、`git update-ref`、`sha256sum`/`shasum` | [发布引用与制品提升](../part-08/05-release-refs-and-artifact-promotion.md) |
| 核对部署输入、实例实际 digest、rollout 状态和回退目标 | `git cat-file -e`、`git archive --mtime`、`sha256sum`/`shasum`、状态清单核对 | [部署与回退](../part-08/06-deploy-and-rollback.md) |
| 固定迁移代码、schema 版本、回填 checkpoint 和不可逆回退边界 | `git rev-parse`、`git archive --mtime`、`sha256sum`/`shasum`、迁移清单核对 | [数据库迁移](../part-08/07-database-migrations.md) |
| 从事故基线定位候选、迁移修复到发布并核对关闭条件 | `git bisect`、`git cherry-pick`、`git tag -a`、`git archive --mtime`、`sha256sum`/`shasum` | [从事故到发布](../part-08/08-incident-to-release.md) |
| 管理 LFS 路径与 payload | `git lfs track`、`git lfs fetch`、`git lfs checkout` | [二进制与 Git LFS](../part-09/02-binary-and-lfs.md) |
| 初始化或更新固定 submodule | `git submodule update --init --recursive` | [Submodule 与 subtree](../part-09/03-submodule-and-subtree.md) |
| 检查外部 commit 是否已发布 | `git push --recurse-submodules=check` | [Submodule 与 subtree](../part-09/03-submodule-and-subtree.md) |
| 导入、同步或抽取 subtree | `git subtree add`、`pull`、`split` | [Submodule 与 subtree](../part-09/03-submodule-and-subtree.md) |
| 组合 refspec、shallow、partial clone 和 sparse-checkout，并核对受限输入 | `git fetch`、`git clone --depth/--filter`、`git sparse-checkout`、`git rev-list --boundary`、`git rev-parse` | [稀疏与部分工作流](../part-09/04-sparse-partial-workflows.md) |
| 核对 monorepo 变更闭包、原子候选、构建图和所有权审批 | `git diff-tree`、`git rev-parse`、`git archive --mtime`、`sha256sum`/`shasum` | [Monorepo 拓扑治理](../part-09/05-monorepo-topology-and-ownership.md) |

## 安全与事故处置

| 目标 | 命令 | 详解 |
| --- | --- | --- |
| 盘点含泄漏 commit 的 refs | `git for-each-ref --contains` | [凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md) |
| 在 fresh clone 重写敏感路径或文本 | `git filter-repo` | [凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md) |
| 审计凭据助手、Authorization header 与 remote URL 来源 | `git config --show-origin --show-scope`、`git remote get-url` | [最小权限机器身份](../part-10/02-machine-identities.md) |
| 通知凭据助手删除精确旧记录 | `git credential reject` | [最小权限机器身份](../part-10/02-machine-identities.md) |
| 从候选对象初筛 CI 依赖入口 | `git grep <commit> -- <CI 路径>` | [第三方 CI 依赖](../part-10/03-ci-dependency-supply-chain.md) |
| 解析 Git 型依赖并比较 old/new 对象 | `git fetch`、`git rev-parse FETCH_HEAD^{commit}`、`git diff` | [第三方 CI 依赖](../part-10/03-ci-dependency-supply-chain.md) |
| 验证 commit/tag 对象签名 | `git verify-commit`、`git verify-tag` | [签名与信任策略](../part-10/04-signatures.md) |
| 审计不受信任仓库配置来源 | `git config --show-origin --show-scope` | [不受信任仓库](../part-10/05-untrusted-repositories.md) |
| 固定 refs 并枚举可达对象 | `git for-each-ref`、`git rev-list --objects --all` | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| 保留 reflog、不可达对象与对象统计 | `git reflog --all`、`git fsck --unreachable`、`git count-objects` | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| 检查 tree mode、属性与归档 | `git ls-tree`、`git check-attr`、`git archive` | [秘密扫描与归档导出](../part-10/06-secret-scanning-and-exports.md) |
| 定位 worktree、Git directory 与 common directory | `git rev-parse --path-format=absolute`、`git worktree list --porcelain` | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 以机器可读格式采集工作区和 index | `git status --porcelain=v2 -z`、`git ls-files --stage -z`、`git diff --binary` | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 采集 refs、reflog、配置与对象统计 | `git for-each-ref`、`git reflog --all`、`git config --show-origin`、`git count-objects` | [事故现场保护与采集](../part-11/01-preserve-and-acquire.md) |
| 区分可达、不可达、缺失和损坏对象 | `git fsck --connectivity-only`、`git fsck --full --strict` | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| 读取候选对象并核对原始解释 | `git cat-file`、`git ls-tree`、`GIT_NO_REPLACE_OBJECTS=1` | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| 在恢复副本定位 dangling 对象 | `git fsck --no-reflogs --lost-found`、`git update-ref` | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| 检查 pack/idx 并从 donor 恢复 blob | `git verify-pack`、`git cat-file blob`、`git hash-object -w` | [对象取证与恢复](../part-11/02-object-forensics-and-recovery.md) |
| 固定 refs、父列表与归因时间线 | `git for-each-ref`、`git log --all`、`git show --format=fuller` | [历史归因](../part-11/03-history-attribution.md) |
| 跨重命名、移动和复制追踪行与路径 | `git blame -M -C`、`git log --follow`、`git diff-tree -M -C` | [历史归因](../part-11/03-history-attribution.md) |
| 比较主线合入史、完整图和 merge 各父提交 | `git log --first-parent`、`git log --full-history`、`git diff <parent> <merge>` | [历史归因](../part-11/03-history-attribution.md) |
| 创建并验证完整或增量逻辑备份 | `git bundle create`、`git bundle verify`、`git bundle list-heads` | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| 在空 bare 仓库恢复并核对全 refs | `git fetch <bundle> '+refs/*:refs/*'`、`git symbolic-ref`、`git fsck` | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| 建立传输镜像并审查删除传播 | `git clone --mirror`、`git remote update --prune` | [bundle 与恢复演练](../part-11/04-bundle-mirror-backup.md) |
| 盘点迁移身份可见的远端 refs 与默认分支 | `git ls-remote --symref`、`git for-each-ref` | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| 向确认为空的迁移目标传输全 refs | `git push --mirror` | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| 比较原始与规范化作者显示 | `git log --format='%an <%ae>'`、`git log --use-mailmap` | [仓库与平台迁移](../part-11/05-repository-platform-migration.md) |
| 比较主备 refs 与复制滞后 | `git ls-remote --symref`、`git for-each-ref`、`git fsck --full --strict` | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| 把 donor 后继提交放入恢复命名空间 | `git bundle create`、`git bundle verify`、`git fetch <bundle> '+refs/recovery/*'` | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| 使用期望旧值条件提升引用 | `git update-ref <ref> <new> <expected-old>` | [故障转移与安全回切](../part-11/06-disaster-failover-and-failback.md) |
| 对账登记默认分支与仓库实际 HEAD | `git symbolic-ref HEAD`、`git show-ref --verify` | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 固定归档 refs、HEAD 与逻辑恢复点 | `git for-each-ref`、`git symbolic-ref`、`git bundle create` | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 从归档恢复后验证对象闭包和引用 | `git fetch <bundle> '+refs/*:refs/*'`、`git fsck --full --strict` | [仓库生命周期](../part-12/01-repository-lifecycle.md) |
| 只读探测一个会话能否读取指定远端 ref | `git ls-remote --exit-code <url> refs/heads/main` | [权限生命周期](../part-12/02-access-lifecycle.md) |
| 在接收端按已认证主体与目标 ref 实施本地拒写策略 | `pre-receive` hook、`git receive-pack` | [权限生命周期](../part-12/02-access-lifecycle.md) |
| 判断 proposed commit 是否为 old ref 的快进后继 | `git merge-base --is-ancestor <old> <new>` | [规则与例外治理](../part-12/03-policy-rules-and-exceptions.md) |
| 区分 commit 对象声明时间与本地 ref 移动记录 | `git show --format=fuller`、`git reflog --date=iso-strict` | [审计日志与证据留存](../part-12/04-audit-logs-and-evidence-retention.md) |
| 采集组织健康快照中的 Git 对象、refs 与提交规模 | `git count-objects -v`、`git for-each-ref`、`git rev-list --count --all` | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| 在门禁通过的维护窗口更新并验证辅助提交图 | `git maintenance run --task=commit-graph`、`git commit-graph verify` | [健康、容量与维护窗口](../part-12/05-repository-health-capacity-maintenance.md) |
| 为组织恢复事件固定主备 refs 与候选恢复点 | `git for-each-ref`、`git bundle create`、`git bundle verify` | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 在隔离候选验证批准 OID 与自包含对象闭包 | `git rev-parse`、`git fsck --full --strict` | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 以拒写探针验证旧权威围栏并开放新权威 canary | `pre-receive` hook、`git push`、`git ls-remote` | [组织级故障手册与演练](../part-12/06-incident-playbooks-and-drills.md) |
| 定位报障发生的 worktree、Git directory 与 common directory | `git rev-parse --path-format=absolute` | [最小排障证据集](../part-13/01-evidence-first.md) |
| 无网络采集 HEAD、porcelain 状态、index stages 与本地 refs | `git status --porcelain=v2`、`git symbolic-ref`、`git ls-files --stage`、`git for-each-ref` | [最小排障证据集](../part-13/01-evidence-first.md) |
| 采集不调用 external diff/textconv 的工作区与暂存补丁 | `git diff --no-ext-diff --no-textconv --binary`、`git diff --staged` | [最小排障证据集](../part-13/01-evidence-first.md) |
| 受控探测远端 ref 并区分 fetch 的本地写入 | `git ls-remote --exit-code`、`git fetch` | [最小排障证据集](../part-13/01-evidence-first.md) |
| 区分目标路径在工作区、index 与当前 tree 的存在性 | `git status --porcelain=v2`、`git ls-files --stage`、`git ls-tree`、`git cat-file` | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 从明确 index/tree 来源窄范围恢复工作区或暂存路径 | `git restore --worktree`、`git restore --source=<OID> --staged --worktree` | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 判断文件是被 ignore 还是被 sparse-checkout 留在 tree 外 | `git check-ignore -v`、`git sparse-checkout list`、`git ls-files -v` | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 验证 reflog 候选并建立不切换工作区的恢复引用 | `git reflog`、`git cat-file`、`git for-each-ref --contains`、`git branch recovery/...` | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 识别并按授权补全浅克隆祖先 | `git rev-parse --is-shallow-repository`、`git fetch --deepen`、`git fetch --unshallow` | [文件与提交消失](../part-13/02-missing-files-and-commits.md) |
| 区分 endpoint 可达、远端 ref 可见与本地 refs 未改变 | `git ls-remote --exit-code`、`git remote get-url` | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| 保存非快进拒绝前后 OID 并判断远端是否为祖先 | `git fetch`、`git merge-base --is-ancestor`、`git log --left-right` | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| 在专用 ref 验证接收端规则并保留本地提交 | `pre-receive` hook、`git push HEAD:refs/heads/review/...` | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
| 修改并回滚本地远程 URL 而不改对象和工作区 | `git remote set-url`、`git remote get-url` | [Push、认证与权限失败](../part-13/03-push-auth-and-permission-failures.md) |
