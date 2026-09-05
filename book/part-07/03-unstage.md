# 取消暂存，但保留文件修改：把选择退回工作区

本章是 v2 第七篇的 index 恢复章节。取消暂存不会替工作区决定内容，也不会移动共享引用。

取消暂存的目标是改变 index 的候选快照，不是撤销编辑器里的内容。它适合发现误加文件、需要重新拆分提交，或暂存版本还没有通过审查的情况。

## 进入条件与完成标准

在已经有至少一条提交、且目标路径已被 Git 识别的仓库根目录执行。开始前：

~~~bash
git status --short --branch --untracked-files=all
git diff --no-ext-diff --no-textconv
git diff --no-ext-diff --no-textconv --staged
git rev-parse --verify HEAD^{commit}
~~~

如果 index 中有冲突 stages，先使用 merge、rebase、cherry-pick 或 revert 的状态机。不要把普通取消暂存命令当成冲突解决。

读完本章后，你应能：

- 说明 restore --staged 修改的是 index；
- 处理已跟踪、未跟踪和首次提交前的不同路径；
- 取消一部分路径而不扩大影响；
- 检查取消暂存后工作区内容是否保留；
- 识别属性、子模块、LFS 和冲突状态的特殊边界；
- 在误选后恢复到明确的 index 快照。

## 取消暂存的状态变化

假设同一路径有三份版本：

~~~text
HEAD       A
index      B
工作区      C
~~~

执行：

~~~bash
git restore --staged -- path/to/file
~~~

通常把 index 从 B 恢复到 HEAD 的 A，工作区仍保留 C。状态从 MM 变为工作区单独修改，或从 M 空格变为未暂存修改。验证：

~~~bash
git status --short -- path/to/file
git diff --no-ext-diff --no-textconv -- path/to/file
git diff --no-ext-diff --no-textconv --staged -- path/to/file
git show HEAD:path/to/file
~~~

工作区 C 是否等于 B，不由 restore --staged 保证。该命令只改变 index，不能把工作区内容自动回到某个版本。

## 新文件取消暂存

在已有提交的仓库中，首次暂存新文件：

~~~bash
git add -- new-file.txt
git status --short -- new-file.txt
git restore --staged -- new-file.txt
git status --short --untracked-files=all -- new-file.txt
test -f new-file.txt
~~~

新文件会从 index 条目回到未跟踪状态，磁盘文件仍在。普通 diff 不会显示它的完整内容，因为它又没有 index 基线。需要审查内容时可以：

~~~bash
git diff --no-index -- /dev/null new-file.txt
~~~

--no-index 发现差异时退出码 1 是预期结果，不是仓库错误。

## 首次提交前的特殊边界

仓库初始化但还没有 HEAD 时，restore --staged 默认没有可用的提交来源。新文件已暂存后，可以使用：

~~~bash
git rm --cached -- new-file.txt
~~~

cached 只从 index 移除，不删除工作区文件。执行后用 status 和文件测试确认。

这不是通用恢复命令。路径已经是已跟踪文件、或者仓库有 HEAD 时，先使用 restore --staged 并核对来源。首次提交前若需要保留当前 index，先复制文件和保存 ls-files --stage 输出。

## 只取消部分路径

明确列出路径：

~~~bash
git restore --staged -- README.md docs/guide.md
~~~

脚本处理用户输入时用安全的参数传递和 -- 分隔，不能把路径拼成未经校验的 shell 代码。对于大量路径，先生成审查清单，再执行；不要在不理解范围时使用：

~~~bash
git restore --staged -- .
~~~

点号会扩大到当前目录及其子路径，且行为受执行位置影响。真实项目中先保存 status、staged name-status 和路径清单。

## 取消暂存后重新拆分提交

误把两个意图一起暂存时：

~~~bash
git diff --staged --name-status
git restore --staged -- path/to/unrelated
git status --short
git diff --staged
git diff
~~~

确认 index 只剩当前提交意图后，再按路径重新 add 或交互式选择：

~~~bash
git add -- path/to/required
git add --patch -- path/to/mixed-file
git diff --staged --check
~~~

取消暂存不会自动判断“相关”与“不相关”。它只是把路径恢复到某个 index 来源，提交边界仍由操作者负责。

## 删除和重命名

已跟踪文件在工作区删除后，若删除已经暂存：

~~~bash
git status --short
git diff --staged --name-status
git restore --staged -- path/to/deleted-file
git status --short
~~~

取消暂存会让删除回到工作区修改，文件是否重新出现取决于 index 与工作区的实际状态。需要恢复文件本体时，还要明确执行 worktree restore，并先保存未暂存字节。

重命名通常表现为 index 中删除旧路径、添加新路径。取消暂存其中一边可能产生删除加新增，Git 的 rename 推断会在后续 diff 阶段重新计算。不要把 rename 显示当成不可变事件。

## 属性、子模块和 LFS

取消暂存属性文件后，Git 对其他路径的 clean/smudge 和换行解释可能变化。重新 add 前检查：

~~~bash
git check-attr --all -- path/to/file
git check-attr --cached --all -- path/to/file
git ls-files --eol -- path/to/file
~~~

子模块路径的 index 条目是 gitlink，取消暂存父仓库中的 gitlink 不会撤销子模块内部提交。LFS pointer 的 index 内容和外部 payload 也要分开验证。父仓库状态干净不代表外部对象可取。

## 冲突 index 不能普通取消暂存

有 unmerged stages 时：

~~~bash
git ls-files --unmerged
git status
~~~

stage 1、2、3 是 merge-base、ours、theirs 等候选，不是普通的单一 index 版本。此时先决定完成合并、逐路径解决或对应 abort。不要用 restore --staged 或 rm --cached 擦掉冲突证据。

## 失败路径和恢复

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| pathspec 不匹配 | 实际路径、大小写、status | 修正精确路径，不扩大范围 |
| restore 找不到 HEAD | symbolic HEAD、是否首次提交 | 首次提交前用 rm --cached 或保留副本 |
| 工作区内容消失 | 执行前 diff、副本、编辑器历史 | restore --staged 本身不应覆盖工作区，调查其他命令 |
| index 仍有变化 | staged diff、属性、过滤器 | 重新审查 index 来源和规则 |
| 出现 unmerged stages | status、操作状态、stage 清单 | 用对应状态机，不普通取消暂存 |
| 误取消了整个目录 | 操作前清单、reflog、工作区 | 逐路径重新 add，必要时从保存的 index 恢复 |
| 子模块/LFS 看似干净 | gitlink、pointer、payload | 分开核对外部对象和依赖 |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-2.sh
./scripts/verify-part-5-local-history.sh
~~~

实验验证已跟踪修改和新增文件的取消暂存、工作区保留和后续提交。它不证明真实编辑器历史、LFS 服务、子模块发布、文件系统恢复或外部备份。

## 小结

取消暂存只把 index 的候选退回默认来源，通常是 HEAD，工作区文件应保留。新文件、首次提交前、删除、属性、子模块、LFS 和冲突路径的边界不同。执行前保存 staged diff，按精确路径操作，之后同时检查工作区和 index；不要把“没有 staged diff”误解成文件已经恢复或秘密已经安全。
