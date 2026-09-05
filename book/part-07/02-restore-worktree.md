# 丢弃工作区修改：restore 的来源与覆盖边界

本章是 v2 第七篇的工作区恢复章节。它只处理已明确选择的路径，历史改写和共享引用更新留给后续章节。

restore 解决的是“某个路径当前工作区版本不需要了”或“某个路径需要从明确来源重新取出”。它可以只改工作区，也可以只改 index，甚至同时改两者。默认来源和目标不同，数据后果也不同。

## 进入条件与完成标准

在包含至少一条提交的仓库根目录执行。开始前查看：

~~~bash
git status --short --branch --untracked-files=all
git diff --no-ext-diff --no-textconv
git diff --no-ext-diff --no-textconv --staged
git rev-parse --verify HEAD^{commit}
~~~

本章命令会覆盖文件内容。执行前必须读完将要丢失的差异，并确保路径是本次明确要处理的对象。

读完本章后，你应能：

- 说明 restore 默认从哪里读、写到哪里；
- 区分工作区恢复和 index 恢复；
- 在已暂存后继续编辑的文件上选择正确来源；
- 用 pathspec 和 patch 缩小影响范围；
- 处理未跟踪、忽略、属性、子模块和冲突路径；
- 判断 Git 无法恢复哪些从未进入对象的字节。

## 三层内容不是一份文件

同一路径可能同时有三份不同内容：

~~~text
HEAD       提交历史中的版本 A
index      下一次提交准备的版本 B
工作区      磁盘当前版本 C
~~~

不带来源的 restore 只在这些层之间复制，不创建新 commit，也不移动分支引用。先看状态：

~~~bash
git status --short
git diff -- path/to/file
git diff --staged -- path/to/file
~~~

如果状态为 MM，必须分别决定工作区的 C 和 index 的 B；不能因为文件名相同就把它们视为同一个版本。

## 默认 restore 只覆盖工作区

对已跟踪路径执行：

~~~bash
git restore -- path/to/file
~~~

默认从 index 读取，覆盖工作区。状态从“工作区相对 index 有变化”回到工作区与 index 一致，index 和 HEAD 的差异保持不变。

验证：

~~~bash
git status --short -- path/to/file
git diff -- path/to/file
git diff --staged -- path/to/file
git ls-files --stage -- path/to/file
~~~

如果 index 已经暂存了版本 B，默认 restore 会把工作区从 C 恢复成 B，而不是最近提交 A。这个行为是为了配合“先暂存，再继续编辑”的工作流。

## 明确从 HEAD 恢复工作区

如果目标是丢弃工作区修改，并让文件回到当前提交：

~~~bash
git restore --source=HEAD --worktree -- path/to/file
~~~

source 指定读取来源，worktree 指定只写工作区。index 如果原来是 B，仍然保持 B，可能继续显示暂存差异。执行后要分别检查：

~~~bash
git diff -- path/to/file
git diff --staged -- path/to/file
git show HEAD:path/to/file
~~~

source 可以是任何已验证的提交、标签或树对象。使用远端跟踪引用前先确认它没有过期；使用任意短 ID 前先验证唯一性。

## 同时恢复 index 和工作区

要让路径同时回到某个提交版本：

~~~bash
git restore --source=<full-commit-id> --staged --worktree -- path/to/file
~~~

这会覆盖 index 和工作区，可能丢弃两层未提交内容。执行前把当前文件复制到受控位置，保存 index 条目和两组 diff。恢复后核对：

~~~bash
git status --short -- path/to/file
git diff -- path/to/file
git diff --staged -- path/to/file
git show <full-commit-id>:path/to/file
~~~

不要对整个仓库使用这条命令，除非目标快照、影响范围和恢复副本都已经明确。

## 只恢复部分 hunk

一个文件里同时有要保留和要丢弃的变化时：

~~~bash
git restore --patch -- path/to/file
~~~

Git 会逐块询问。先读每个 hunk 的上下文，使用 y、n、s、q 等实际提示支持的选项；不确定时退出。完成后重新运行工作区和暂存差异，不能只看交互过程中的屏幕。

patch 选择依赖 diff 算法、上下文和属性。无法合理拆分时，先用编辑器把变化分开，或创建临时提交后再整理，不要连续输入 y 直到状态看起来干净。

## 未跟踪和忽略路径

restore 主要作用于 Git 已知路径。未跟踪文件没有 index 版本，默认 restore 不会替你删除或恢复它：

~~~bash
git status --short --untracked-files=all
git check-ignore -v -- path/to/file || true
~~~

对于重要未跟踪文件，先复制到仓库外的受控位置。确定无用后再使用操作系统文件工具移除。Git 无法找回从未写入对象库的未跟踪字节。

被忽略的路径不代表安全。忽略规则只改变发现范围，不提供权限、加密或历史清理。

## 属性、换行和过滤器

restore 可能触发 clean/smudge filter、换行转换和文件模式处理。发现恢复后的工作区字节与预期不同，先检查：

~~~bash
git check-attr --all -- path/to/file
git check-attr --cached --all -- path/to/file
git ls-files --eol -- path/to/file
git diff --no-ext-diff --no-textconv -- path/to/file
~~~

工作区的属性文件和 index 中的属性文件可能不同。先审查属性变化，再决定是否恢复。不要关闭 filter 或强制跳过转换来掩盖结果。

## 冲突和子模块路径

冲突路径存在 stage 1/2/3 时，普通 restore 可能不能按预期工作。先用：

~~~bash
git ls-files --unmerged
git status
~~~

按照 merge、rebase 或 cherry-pick 的状态机解决或 abort。不要用 restore 清除冲突现场。

对子模块路径，父仓库保存的是 gitlink，不是子模块内部文件。恢复 gitlink 后还要在子模块目录验证 commit 是否存在、是否已发布和工作区是否干净。LFS pointer 的工作区水合也需要外部 payload 证据。

## 失败和恢复

| 现象 | 先收集 | 恢复 |
| --- | --- | --- |
| pathspec 不匹配 | status、实际路径、大小写 | 修正路径，不扩大到整个仓库 |
| bad revision/source | rev-parse、show-ref、对象类型 | 换完整 OID 或已确认 ref |
| 工作区恢复后内容不见 | 执行前 diff、副本、编辑器历史 | Git 通常无法找回未提交对象 |
| index 与工作区仍不同 | 两层 diff、属性和 filter | 分别选择 source 与 target |
| restore 遇到冲突 | operation state、unmerged stages | 使用对应 continue/abort |
| 子模块或 LFS 恢复失败 | gitlink/pointer、外部对象 | 补齐依赖，不用父仓库状态代替 |
| 恢复范围过大 | 执行前 manifest、受影响路径 | 从副本和 recovery ref 重建 |

恢复命令本身也要记录 source、target、pathspec、执行时间和后置验证。不要用全仓库 hard reset 代替窄范围 restore。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-5-local-history.sh
./scripts/verify-missing-files-and-commits.sh
~~~

实验验证工作区从 HEAD/index 恢复、取消暂存和路径级状态变化。它不证明文件系统快照、编辑器历史、LFS payload、子模块服务或真实数据恢复。

## 小结

restore 的安全关键是明确 source 和 target。默认 restore 从 index 覆盖工作区，source=HEAD 可以指定历史版本，staged/worktree 决定写入哪一层。执行前读差异、限制路径、保留副本，执行后分别检查工作区和 index；未跟踪字节、外部 payload 和冲突状态不能靠一条 restore 命令解决。
