# reset 会移动引用，并按模式重置另外两个区域

`git reset` 有两组不同语义。指定提交而不指定路径时，它移动当前检出位置，并按模式决定是否重置 index 和工作区；指定路径时，它只把选中路径从某个 tree 复制到 index，不移动分支。把两组语义混在一起，是许多误操作的起点。

本章先讨论提交形式的 `--soft`、`--mixed` 和 `--hard`。所有改写实验都应在临时仓库运行。真实事故现场先保存状态和对象 ID，不要边试参数边观察结果。

## 操作前记录三个快照和两个引用

假设当前历史是：

```text
A <- B <- C  main, HEAD
```

工作区和 index 可能还有 C 之后的修改。执行 reset 前先读取状态：

```bash
git status --short --branch
git log --graph --decorate --oneline --all --max-count=20
git diff
git diff --staged
```

这些命令分别展示当前引用、工作区与 index 的差异，不修改仓库。记录当前提交的完整 ID，并创建恢复引用：

```bash
before_reset="$(git rev-parse HEAD)"
git branch recovery/before-reset "$before_reset"
printf '%s\n' "$before_reset"
```

如果恢复分支已存在，`git branch` 会拒绝覆盖。换一个带日期或事故编号的名称，不要使用 `-f` 替换旧证据。若当前处于分离 `HEAD`，创建恢复分支仍然有效。

从 Git 2.49.0 的行为看，提交形式 reset 在执行前还会把原分支头写入 `ORIG_HEAD`。它是一个方便的单值引用，后续 merge、pull、reset 等操作可能再次覆盖，不能替代命名恢复分支。

## 提交形式改变什么

先把 B 的完整 ID 固定下来，后面三种模式各自使用这个变量：

```bash
target_commit="$(git rev-parse HEAD~1)"
printf '%s\n' "$target_commit"
```

三种模式不能为了比较而连续在真实现场执行。每次都应从同一份隔离仓库状态开始；本章后面的代码块是互斥选择，不是连续步骤。

在普通分支上，提交形式 reset 把当前分支引用移到目标提交；分离 `HEAD` 时，它直接更新 `HEAD`，没有分支随之移动。远程跟踪引用和服务器端分支不会因本地 reset 自动变化。

## soft 只移动当前检出位置

```bash
git reset --soft "$target_commit"
```

以 C 重置到 B 后：

```text
main, HEAD -> B
index      -> 保持操作前内容
工作区      -> 保持操作前内容
ORIG_HEAD  -> C
```

若 reset 前 index 和工作区都等于 C，C 相对 B 的变化会显示为已暂存。若 reset 前本来就有部分暂存和未暂存修改，它们仍保持原层次，不能简单理解成“最后一次提交全部回到暂存区”。

`--soft` 适合已经确认历史未分享、需要重新组合最近提交的场景。只补充最近提交内容时，`git commit --amend` 通常表达得更直接。

## mixed 同时把 index 重置为目标 tree

```bash
git reset --mixed "$target_commit"
```

`--mixed` 是提交形式的默认模式。以 C 重置到 B 后：

```text
main, HEAD -> B
index      -> B 的 tree
工作区      -> 保持操作前内容
ORIG_HEAD  -> C
```

原来属于 C 的文件变化留在工作区，通常显示为未暂存。reset 前的暂存选择会被 B 的 tree 取代，所以不要在没有检查 `git diff --staged` 的情况下运行默认 `git reset <目标>`。

`--mixed -N` 会把目标中删除、工作区仍存在的路径标为 intent-to-add，常用于随后用 `git add -p` 重新拆分变化。本书主线不依赖该选项，看到它时需要把 intent-to-add 状态纳入 `status` 和 diff 判断。

## hard 同时覆盖 index 和工作区

```bash
git reset --hard "$target_commit"
```

以 C 重置到 B 后：

```text
main, HEAD -> B
index      -> B 的 tree
工作区      -> 检出 B 的 tree
ORIG_HEAD  -> C
```

目标 tree 与当前文件之间的已跟踪修改会被覆盖，包括未暂存修改和已暂存但未提交的内容。普通无关未跟踪文件通常保留，但如果未跟踪文件或目录挡住目标提交需要写入的路径，`--hard` 会删除障碍后检出目标内容。它不是“只清理 Git 已跟踪文件”的安全命令。

`--hard` 不会像 `git clean` 那样遍历删除全部未跟踪文件。两者不能互相类推，也不应组合成通用的“恢复干净状态”命令。

## 三种模式的状态矩阵

| 模式 | 更新当前分支或分离 HEAD | 把 index 重置为目标 tree | 把工作区重置为目标 tree | 主要数据风险 |
| --- | --- | --- | --- | --- |
| `--soft` | 是 | 否 | 否 | 历史位置改变 |
| `--mixed` | 是 | 是 | 否 | 暂存选择丢失 |
| `--hard` | 是 | 是 | 是 | 未提交的已跟踪内容及阻挡路径丢失 |

这张表只描述提交形式。每种模式都会改变引用可达关系；即使文件仍在工作区，原提交也可能从普通 `git log` 中消失。

## 路径形式不移动 HEAD

指定路径时，reset 从给定 tree 复制这些路径到 index：

```bash
git reset HEAD -- README.md
```

状态变化是：

```text
当前分支、HEAD -> 不变
README 的 index 条目 -> HEAD 中的版本
README 的工作区内容 -> 不变
其他 index 路径 -> 不变
```

`--` 明确结束修订参数，避免路径名被解析成提交或选项。现代 Git 中，取消暂存更推荐职责清楚的等价写法：

```bash
git restore --source=HEAD --staged -- README.md
```

路径形式还可以指定其他 tree，把选中路径的 index 恢复到那个版本。它不会移动分支，也没有 `--soft`、`--mixed`、`--hard` 的模式选择。

## merge 与 keep 是有条件的工作区更新

提交形式还支持 `--merge` 和 `--keep`。它们试图在移动引用时保留部分本地修改，并在会覆盖这些修改时中止。两者判断 index、工作区、当前 `HEAD` 和目标提交差异的条件不同，不能把它们当作“安全版 hard”。

合并、变基、cherry-pick 或 revert 正在进行时，优先使用对应的 `--abort`。只有在理解当前 index 冲突阶段和本地修改来源时，才考虑用 reset 的高级模式处理特殊现场。

## 子模块需要单独确认

reset 默认处理超级项目记录的 gitlink，不等于递归重置每个子模块工作区。显式使用 `--recurse-submodules` 时，Git 会递归更新活动子模块，并把它们的 `HEAD` 置于超级项目记录的提交，可能覆盖子模块中的本地修改或改变其检出位置。

包含子模块的仓库执行提交形式 reset 前，应分别记录超级项目和每个活动子模块的状态。第九篇会完整讨论子模块的所有权和恢复边界。

## 已共享历史不能靠本地 reset 消失

在已推送分支执行 reset 只移动本地引用。服务器仍指向原提交，普通 push 通常因非快进而拒绝。随后使用强推会改写共享坐标，必须先按公开历史章节判断授权和协作者依赖。

主线或发布分支上的错误提交通常使用 `revert`。个人私有历史可以 reset 后重新组织。判断标准是提交是否已被其他人和系统引用，不是分支名称看起来像不像个人分支。

## 发生误 reset 后先固定候选提交

如果没有提前创建恢复分支，先停止继续 reset、提交和清理。读取 `ORIG_HEAD` 和 reflog：

```bash
git show --no-patch --decorate ORIG_HEAD
git reflog show --date=iso HEAD
```

`ORIG_HEAD` 可能正好是操作前位置，也可能已被后续命令覆盖。reflog 序号会随新操作变化。找到候选后先检查，再创建新引用：

```bash
candidate="replace-with-the-verified-full-object-id"
git cat-file -e "${candidate}^{commit}"
git show --stat "$candidate"
git branch recovery/reset-candidate "$candidate"
```

不要把占位符原样输入。`cat-file -e` 成功时没有输出，候选不是可解析提交时返回非零状态。创建恢复分支不会移动当前分支、index 或工作区，比立即再次 `reset --hard` 更适合保护现场。

## 隔离实验验证状态和恢复

**前置条件**：Git 2.28 或更高版本、Bash、`mktemp` 和本书工作区。在仓库根目录执行：

```bash
./scripts/verify-reset-reflog.sh
```

脚本创建临时仓库，分别从同一提交验证 soft、mixed、hard 的引用、index 和工作区状态；验证路径形式不移动 `HEAD`；验证 `--hard` 保留无关未跟踪文件，却会替换阻挡目标路径的未跟踪文件；最后通过 `ORIG_HEAD` 和 reflog 为误重置提交建立恢复分支。

成功时输出：

```text
Reset modes, path reset, reflog evidence, and recovery passed.
```

对象 ID 和临时目录每次不同。断言失败时脚本返回非零状态并删除实验目录。它不会连接远程，也不证明平台、子模块或共享历史上的 reset 安全。
