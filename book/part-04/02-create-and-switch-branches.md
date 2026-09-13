# 创建和切换分支：先证明本地内容不会被覆盖

`git branch` 只创建或管理引用，`git switch` 改变当前工作树的历史入口。成功切换时，Git 更新 `HEAD`，把 index 调整到目标 tree，并更新需要变化的工作区路径；当前分支 ref 本身不会因为“切到它”而前进。

Git 可以携带不会被目标 tree 覆盖的未提交修改，因此“切换前工作区必须干净”是更严格、也更容易审计的团队规范，不是客户端每次强制执行的条件。真正的停止线是：操作者不能解释本地内容，或切换可能覆盖 index、工作区和未跟踪路径。

## 进入条件与完成标准

写操作只在一次性练习仓库执行。真实项目先保存：

~~~bash
git status --short --branch
git diff --binary
git diff --staged --binary
git ls-files --others --exclude-standard -z
git worktree list --porcelain
~~~

命令可能输出内部路径和源码，证据文件应位于权限受控目录。Shell 变量不能保存 NUL；自动化把最后一条直接写入文件并按字节解析。

读完本章后，应能区分只创建、创建并切换、切到已有分支和分离检出，选择明确起点与 upstream，预测工作区修改何时被携带或拒绝，处理未跟踪覆盖与 worktree 占用，并在分离提交离开前建立恢复引用。

## 只创建分支不会切换

在已提交仓库中：

~~~bash
start_oid="$(git rev-parse 'HEAD^{commit}')"
git branch feature/payment-retry "$start_oid"
git rev-parse 'refs/heads/feature/payment-retry^{commit}'
git branch --show-current
git rev-parse HEAD
~~~

新分支和 `start_oid` 相等，当前 `HEAD`、index 和工作区不应变化。显式保存起点比依赖命令执行时瞬间解析的 `HEAD` 更适合审计。

同名分支已存在时创建失败。先读取其 OID、worktree 占用和用途，不直接 `-f` 覆盖：

~~~bash
git show-ref --verify refs/heads/feature/payment-retry
git worktree list --porcelain
git show --no-patch --format='%H%n%P%n%T%n%s' \
  refs/heads/feature/payment-retry
~~~

## 创建并立即切换

从明确起点建立工作线：

~~~bash
base_oid="$(git rev-parse 'refs/heads/main^{commit}')"
git switch --create feature/invoice-retry "$base_oid"
git symbolic-ref --short HEAD
git rev-parse HEAD
git status --short --branch
~~~

成功后新建 `refs/heads/feature/invoice-retry`，`HEAD` 附着到它，index 和工作区对应 `base_oid` 的 tree。命令不创建新 commit，也不发布远端分支。

如果起点是 `origin/main`，它是本地 remote-tracking ref：

~~~bash
git fetch --prune origin
base_oid="$(git rev-parse 'refs/remotes/origin/main^{commit}')"
git switch --create feature/invoice-retry "$base_oid"
~~~

`fetch` 会访问远端并写对象、远程跟踪 refs 和 `FETCH_HEAD`。保存执行时间、远端 URL、refspec 和结果 OID；不能把未 fetch 的 `origin/main` 当成服务器实时状态。

分支名先验证：

~~~bash
git check-ref-format --branch feature/invoice-retry
~~~

不要把工单标题或用户名未经校验直接作为分支名。外部系统还需单独处理 URL、路径、日志和长度限制。

## 切换已有分支改变三个本地层次

~~~bash
target="refs/heads/feature/invoice-retry"
target_oid="$(git rev-parse --verify "$target^{commit}")"
git switch feature/invoice-retry
git symbolic-ref --quiet HEAD
git rev-parse HEAD
git write-tree
~~~

成功后：

1. `HEAD` 保存目标本地分支名；
2. index 代表目标 commit 的候选 tree，除非有被允许携带的本地变化；
3. 工作区中受影响的 tracked paths 更新为目标内容，同时保护不会安全合并的本地修改。

目标分支 ref 仍指向 `target_oid`。切换不是 merge，不产生父提交或合并提交。工作区 filters、LFS、submodule、sparse-checkout、文件权限和未跟踪冲突会影响实际展开结果，不能只比较 `HEAD` 就宣布检出完整。

## 未提交修改可能被携带

假设 `notes.txt` 在当前与目标 tree 中相同，你在工作区修改它，再切换到目标分支。若 Git 能保留这份修改而不覆盖目标内容，切换可能成功，修改继续留在工作区。

这类成功不代表修改属于新分支。它只说明 Git 找到一个可保留的三层状态。切换后立即运行：

~~~bash
git status --short --branch
git diff -- notes.txt
git diff --staged -- notes.txt
~~~

团队若要求工作线之间不携带未提交内容，可以在切换前强制干净状态，并把 stash、临时提交或 worktree 作为明确交接动作。该规范减少归属不清，但仍要保护未跟踪文件和外部生成物。

## 会覆盖修改时必须拒绝

当前工作区修改了 `config.yml`，目标分支也在当前基线之后修改了同一路径，切换通常拒绝。捕获失败前后状态：

~~~bash
before_head="$(git rev-parse HEAD)"
before_worktree_oid="$(git hash-object -- config.yml)"

if git switch target-branch 2>switch.err; then
  printf 'unexpected switch success\n' >&2
  exit 1
fi

test "$(git rev-parse HEAD)" = "$before_head"
test "$(git hash-object -- config.yml)" = "$before_worktree_oid"
git status --short --branch
~~~

失败的原始 stderr 是证据。不要看到拒绝后立即使用 `switch --discard-changes`、`switch -f` 或 `checkout -f`；这些选项会放弃 Git 原本保护的工作区/index 内容。

已暂存修改同样需要检查。目标切换若会覆盖 index 候选，Git 会拒绝或要求更明确处理。先保存 staged diff 和 index 副本，再选择提交、取消暂存、stash 或独立 worktree。

## 未跟踪路径也能阻止切换

当前分支没有 `generated/report.json`，目标分支跟踪该路径，而工作区存在同名未跟踪文件时，切换通常拒绝覆盖。普通 `git diff` 不展示未跟踪文件内容，必须单独盘点：

~~~bash
git status --short --untracked-files=all
git ls-files --others --exclude-standard -z
~~~

确认文件来源后，把它移动到权限受控的仓库外路径、纳入正确提交，或在证明可重新生成后删除。不要用 `git clean -fd` 处理单个冲突，它会扩大删除范围；被忽略文件还需要 `--ignored` 和 `check-ignore -v` 单独观察。

目录/文件冲突、大小写折叠、symlink 和 sparse 范围也可能让目标无法展开。保留目标 tree、当前路径类型、文件系统和错误原文，不通过手工复制文件冒充成功 checkout。

## Upstream 需要显式确认

从唯一匹配的 remote-tracking branch 执行 `git switch topic` 时，Git 的 guess 行为可能自动创建本地分支并设置 upstream。多个远端都有同名分支或配置关闭 guess 时，结果不同。可审计流程使用完整起点：

~~~bash
git switch --create topic --track origin/topic
git for-each-ref refs/heads/topic \
  --format='%(refname) %(objectname) %(upstream) %(upstream:track)'
git config --get-regexp '^branch\.topic\.(remote|merge)$'
~~~

`--track` 写本地分支配置，不验证平台评审、push 权限或远端保护规则。设置错误时先记录当前配置，再修正：

~~~bash
git branch --set-upstream-to=origin/topic topic
~~~

这条命令不移动本地/远程分支，不 fetch，也不 push。Upstream 删除或重命名后，本地配置可能继续指向失效名称，第十三篇的远程引用漂移章负责完整排障。

## 分离检出适合固定候选

~~~bash
candidate="$(git rev-parse --verify 'refs/remotes/origin/main^{commit}')"
git switch --detach "$candidate"
git rev-parse HEAD
git branch --show-current
git status --short --branch
~~~

成功后 `HEAD` 直接保存候选 OID，短分支名为空。CI 使用分离 `HEAD` 可以避免本地分支意外前进，但仍需记录候选如何生成、对象是否完整和工作区是否与候选 tree 一致。

若在此状态产生需要保留的 commit：

~~~bash
detached_oid="$(git rev-parse 'HEAD^{commit}')"
git branch recovery/detached-work "$detached_oid"
git switch recovery/detached-work
~~~

先创建名字，再离开。直接 `switch main` 后提交通常仍可从 `HEAD` reflog 找到一段时间，但日志不是备份。

`git switch -` 使用上一次 checkout/switch 位置，也可写为 `@{-1}`。它依赖本地 checkout 日志，自动化不要用它代替明确 ref/OID；新动作会改变其含义。

## Worktree 占用是另一条停止线

若 `topic` 已在 linked worktree 检出：

~~~bash
git worktree list --porcelain
git switch topic
~~~

Git 通常拒绝第二个工作树检出同一分支。到原 worktree 检查状态和运行任务，或从同一 OID 创建不同本地分支。强行忽略占用会让两个 index 竞争移动同一 `refs/heads/topic`，无法靠工作目录分离保证顺序。

为并行热修复创建新 worktree 时明确路径、分支和起点：

~~~bash
git worktree add ../project-hotfix -b hotfix/payment "$base_oid"
~~~

它会创建目录、worktree 元数据和分支 ref，属于多层写操作。完整创建、锁定、移动与移除边界见[多个工作树](../part-02/12-multiple-worktrees.md)。

## Stash、临时提交与 worktree 怎样选

| 当前状态 | 更合适的动作 | 验收 |
| --- | --- | --- |
| 几分钟后返回，修改范围清楚 | 带说明的 stash | 核对 stash tree、未跟踪边界和恢复目标 |
| 内容已形成可审查意图 | 当前分支临时/正式提交 | 保存 OID，后续按共享边界整理 |
| 两条工作线都要持续运行 | 新分支加 linked worktree | 核对独立 HEAD/index 与共享 refs |
| 内容来源不明或可能含秘密 | 停止切换，先采集与分类 | 不把未知字节写入 stash/commit 后误发布 |

Stash 可能遗漏未跟踪或忽略文件，worktree 不隔离外部数据库和端口，临时提交也会进入对象与 reflog。选择动作时说明保留范围和清理条件。

## 旧式 checkout 不能机械替换

~~~bash
git checkout -b topic base
git checkout topic
git checkout -- path/to/file
~~~

前两条分别接近 `switch -c` 和 `switch`，第三条是路径恢复，应迁移为明确来源/目标的 `restore`。`checkout` 还支持路径、overlay、ours/theirs 等语义；批量替换脚本前按每个调用的参数形状分类。

新文档使用 `switch` 表达分支意图，使用 `restore` 表达路径恢复。旧 Git 版本不支持时保留经过测试的 checkout 写法，并记录最低版本，不能让文档命令与实际 runner 脱节。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| `invalid reference` | 完整 ref、对象类型、shallow/partial 状态 | 修正或取得对象，不创建同名空分支掩盖缺口 |
| `would be overwritten by checkout` | 工作区/index diff、目标 tree、路径来源 | 提交、stash、worktree 或保护副本后重试 |
| 未跟踪文件会被覆盖 | NUL 路径清单、目标 tree、生成来源 | 精确移动/保留路径，不运行宽泛 clean |
| 切换成功却携带修改 | 切换前后 status/diff、内容归属 | 决定移回原工作线、提交或 stash，不继续混改 |
| `branch already exists` | 现有 OID、worktree、评审/自动化用途 | 使用现有分支或新名字，不强制重置 |
| `already checked out at` | worktree 清单、运行任务和 owner | 到原路径处理或创建不同分支 |
| 分离提交在切回后消失 | `HEAD` reflog、完整 OID、对象保留 | 验证并立即建立 recovery ref，不运行清理 |
| Upstream ahead/behind 异常 | branch config、remote-tracking OID、fetch 时间 | 先修配置/缓存，再重新计算，不 pull 猜测 |

切换失败时保存前后 `HEAD`、index tree、工作区 hash 和 stderr。失败通常是保护结果，不是授权执行强制覆盖。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-branch-switching.sh
~~~

实验创建本地与 bare 仓库，验证只创建分支不切换、功能提交只移动当前 ref、不会冲突的工作区修改可以被携带、目标也修改同一路径时切换被拒绝且状态保持。它还验证未跟踪路径阻止覆盖、显式 `--track` 配置 upstream、分离提交用 recovery ref 保留，以及 linked worktree 阻止同分支重复检出。

所有路径和身份都是合成值，退出时删除临时目录。实验不验证网络认证、平台权限、LFS/filter、大小写文件系统、IDE 状态、进程级并发或未提交文件的真实恢复。

## 小结

创建分支只写引用，切换分支会协调 `HEAD`、index 和工作区。Git 有时能携带本地修改，只有覆盖风险出现才拒绝；工程流程仍应在切换前明确修改归属、未跟踪路径和 worktree 占用。起点、upstream 和分离候选都使用完整 OID 验收，失败后保留保护现场，不用强制选项把拒绝变成数据丢失。

## 资料

- [git-switch](https://git-scm.com/docs/git-switch)
- [git-branch](https://git-scm.com/docs/git-branch)
- [git-checkout](https://git-scm.com/docs/git-checkout)
- [git-status](https://git-scm.com/docs/git-status)
- [git-worktree](https://git-scm.com/docs/git-worktree)
- [git-stash](https://git-scm.com/docs/git-stash)
