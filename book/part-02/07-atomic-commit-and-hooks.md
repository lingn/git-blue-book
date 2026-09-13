# 生成提交：把已审查的 index 写进本地历史

`git commit` 不是“把当前目录保存一下”的快捷键。它读取 index 中已经准备好的路径，创建 tree 和 commit 对象，然后移动当前分支或 `HEAD` 所在的引用。工作区的未暂存变化通常保留，远程仓库、制品和部署环境完全不会因此改变。

## 进入条件与退出能力

进入本章前，你应能用 `git status` 和 `git diff --staged` 判断候选内容，并理解 `HEAD`、index 和工作区的差异。请继续在 `git-first-lab` 或隔离脚本中操作。

读完本章后，你应能：

- 在提交前证明 index 中只有本次意图的内容；
- 解释一次成功提交会改变哪些本地状态；
- 处理身份缺失、没有暂存内容、钩子拒绝和提交说明错误；
- 区分普通提交、故意的空提交和绕过本地钩子；
- 知道本地 hook 不是服务端保护，也不能把提交成功当作远程发布成功。

## 一次提交的状态变化

可以把提交抽象成四个动作：

```text
index
  -> 创建根 tree
  -> 创建 commit（父对象、author、committer、说明）
  -> 移动当前分支引用
工作区保留未暂存变化
```

| 状态 | 成功提交后 | 失败时通常怎样 |
| --- | --- | --- |
| index | 内容被新 commit 的 tree 采用 | 原 index 保留，便于修复后重试 |
| 对象库 | 新增 tree/commit，OID 由完整内容决定 | 可能已经写入临时对象，不能把对象数当作提交成功证明 |
| 当前引用 | 指向新 commit | 通常不移动；用 old/new OID 核对 |
| 工作区 | 未暂存内容通常不变 | 不应因为提交说明或 hook 失败而被自动清空 |
| 远程/平台 | 不发生变化 | 仍需单独 push、评审或发布 |

提交是本地对象和引用的一次操作，不是跨系统事务。它不会自动更新 GitHub/GitLab 的评审状态、CI、制品库、数据库或运行实例。

## 提交前的可复现检查

在仓库根目录执行：

```bash
git status --short
git diff --staged --check
git diff --staged
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
```

这些命令只读工作区、index、配置和对象，不移动引用。`git diff --staged --check` 返回 0 表示没有检测到空白错误；非零时先修复或明确记录原因。身份命令返回的是当前进程最终值，不等于远程认证主体。

如果 `git diff --staged` 为空，说明没有准备好的已跟踪变化。不要为了消除提示而直接执行 `git add .`，先回到工作区/index 状态模型选择具体路径。未跟踪文件也不会自动进入提交。

## 创建普通提交

当暂存差异已审查，执行：

```bash
git commit -m "docs: explain project purpose"
```

命令在当前仓库执行，`-m` 给出提交说明。成功时输出中的分支名、OID、文件数量和行数会随实际内容变化，例如：

```text
[main 1a2b3c4] docs: explain project purpose
 1 file changed, 2 insertions(+)
```

成功后用以下命令确认引用和工作区：

```bash
git rev-parse --verify HEAD^{commit}
git show --no-patch --format='%H%n%P%n%s' HEAD
git status --short
```

第一条读取当前 `HEAD` 的完整 commit OID，第二条读取对象字段，第三条确认是否还有未提交变化。不要只复制终端中显示的短 OID；自动化和跨系统证据应保存完整值。提交仍只存在本地，分享历史需要后续的 fetch/push 和服务器授权。

## 提交说明是审计入口，不是装饰

说明应表达变化意图，而不是只描述编辑器动作：

```text
docs: explain project purpose
fix: reject negative quantity
refactor: isolate rounding policy
```

前缀不是 Git 强制语法。团队可以规定类型、范围、关联工单或破坏性变更标记，但规则必须在评审和 CI 中明确执行，不能把某种约定写成 Git 核心行为。提交说明中不要放 token、密码、私钥和未脱敏的事故数据。

## 失败路径和恢复

### 身份缺失

如果 Git 无法组成 author 或 committer 身份，提交命令会返回非零。先运行 `git var GIT_AUTHOR_IDENT` 和 `git config --show-origin --show-scope --get-regexp '^user\.'`，修复正确作用域后重试。失败尝试不应被解释为生成了一条“半提交”；恢复前仍应检查 `git rev-parse HEAD`、index 和工作区。

### 没有暂存内容

没有已暂存变化时，普通 `git commit` 会拒绝。保留当前工作区，用 `git status` 和路径级 `git add` 重新选择。不要用 reset 或删除文件来让状态看起来干净。

### hook 拒绝

`pre-commit` 或 `commit-msg` 可能在本地阻止提交。先保存完整错误、hook 路径和当前 OID，确认 index 和工作区没有被覆盖；修复代码或 hook 后重新运行同一提交命令。`post-commit` 在引用移动后运行，失败不能自动回滚已经创建的 commit。

本地 hook 来自 `.git/hooks`、`core.hooksPath` 或受控模板，普通 clone 不会把源仓库的 hooks 自动当作服务端规则。`--no-verify` 只能绕过部分客户端 hook：

```bash
git commit --no-verify -m "..."
```

这会削弱本地检查，只能作为已记录的例外；它不绕过远程保护、必需检查、签名策略或平台权限。不要在不理解 hook 来源时用它强行通过。

### 提交说明写错

如果提交尚未共享，可以在后续章节学习 `git commit --amend`。已经共享的 commit 改写会改变 OID、签名和评审链接，不能把 amend 当作无成本编辑。当前先保存完整 OID 和传播范围，再决定是否进入历史治理流程。

## 空提交必须有明确目的

没有 index 变化时，Git 默认拒绝创建提交。自动化有时需要用空提交触发一个受控流程，可以显式写出意图：

```bash
git commit --allow-empty -m "ci: request verification"
```

它会创建新的 commit 和 OID，但不改变 tree。空提交不能伪造代码变化，也不应成为绕过评审或重复触发高权限部署的暗门。团队要记录谁允许、哪个流程消费以及如何防止重复触发。

## 原子性和边界

一次 `git commit` 只把 index 的一个快照写入一个本地 commit。它不会替你保证：

- 工作区中的所有改动都已包含；
- 测试、构建、依赖下载或数据库迁移成功；
- 提交者有权代表 author；
- 远端接受了该 OID；
- 这个对象经过签名、评审或发布审批。

如果提交关联了源码、配置和迁移，原子性只覆盖 Git tree。跨仓库、制品、数据库和运行实例的一致性要在第八篇的证据链中单独设计。

## 隔离实验验证了什么

本章复用第二篇共享实验：

```bash
./scripts/verify-part-2.sh
```

前置条件是 Bash、Git 2.28 或兼容版本、`mktemp`、`grep` 和可写临时目录。实验会在临时仓库中验证 local identity 覆盖、暂存内容提交、hook 拒绝后的 index 保留、移除 hook 后恢复，以及无变化提交和 `--allow-empty` 的区别。hook 只在临时 `.git/hooks` 中创建，退出时删除。

成功输出中的 OID、提交数量和路径都由 fixture 产生。实验只证明本地 Git 对象、引用、index、工作区和客户端 hook 的状态变化，不模拟远程接收、托管平台规则、CI、签名服务、数据库或部署审批。

## 小结

提交是从 index 创建 tree 和 commit 并移动本地引用的动作。先审查 `git diff --staged`，再执行 commit；失败时保留 index 和工作区，按身份、暂存内容和 hook 来源分流。普通提交、空提交和 `--no-verify` 都是有明确边界的动作，不能把其中任何一个当作远程发布或组织授权的替代品。
