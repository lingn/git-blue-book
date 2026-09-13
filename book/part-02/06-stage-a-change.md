# 选择并准备内容：`git add` 的路径边界

`git add` 不是“保存文件”，也不是“提交文件”。它把指定路径在某个时刻的工作区内容写入 index，成为下一次提交的候选快照。一次可靠的 `add` 操作，必须同时回答两个问题：选择了哪些路径，选择的是哪一版内容。

## 进入条件与完成标准

继续使用 `git-first-lab`，并在仓库根目录执行命令。若仓库存在未确认的修改，先保存 `git status --short` 和 `git diff`，不要用 `git add .` 把现场扩大。

读完本章后，你应能：

- 区分 `git add` 修改的是 index，不是当前分支引用；
- 用显式路径、`-u`、`-A` 和交互式 patch 控制选择范围；
- 解释 `git add .` 为什么受执行目录影响；
- 处理新增、修改、删除和重命名路径；
- 识别 clean filter、换行属性、权限和 index 锁导致的失败；
- 用 `git diff --staged`、`--check` 和 `git ls-files --stage` 证明准备结果；
- 在误暂存时只恢复 index，保留工作区内容。

## `add` 改变哪一层

对已跟踪文件执行：

~~~bash
git add -- README.md
~~~

Git 读取工作区中 `README.md` 的当前字节，按照属性和 clean filter 处理，并更新 index 中该路径的对象 ID 与模式。对象可能已经写入对象数据库，但分支和 `HEAD` 不会移动，工作区文件也不会被删除或提交。

状态变化可以表示为：

~~~text
执行前：HEAD = H，index = H，工作区 = W1
git add：HEAD = H，index = W1，工作区 = W1
~~~

如果随后再次编辑：

~~~text
HEAD = H，index = W1，工作区 = W2
~~~

这就是 `MM` 状态的来源。`git commit` 只读取 index 中的 W1，不会自动采用工作区的 W2。

首次提交前没有可解析的 `HEAD`，但 index 仍可以有新增条目。此时 `git add` 成功并不意味着已经创建历史，必须用 `git diff --staged` 检查候选快照，再执行 `commit`。

## 显式路径是默认安全选择

在仓库根目录准备两个文件：

~~~bash
printf 'public documentation\n' > README.md
printf 'local draft\n' > notes.txt
git add -- README.md
git status --short
~~~

预期只有 `README.md` 被暂存，`notes.txt` 仍是 `??`。单独的 `--` 告诉 Git 后面的参数是路径，即使文件名以短横线开头，也不会被当成选项。文件名来自变量时，仍应使用数组或安全的参数传递方式，避免 shell 展开。

提交前检查：

~~~bash
git diff --staged -- README.md
git diff --staged --check
git ls-files --stage -- README.md
~~~

第一条看内容，第二条报告空白错误，第三条看 index 条目的模式、对象 ID 和 stage。它们共同证明“选择了什么”和“准备了什么”，不能用 `git add` 的无输出替代。

## `.`、`-u` 和 `-A` 不是同一个范围

下面三个写法都常见，但选择集合不同：

| 写法 | 主要选择 | 受什么影响 | 典型用途 |
| --- | --- | --- | --- |
| `git add .` | 当前目录及其下方路径的新增、修改和删除 | 执行位置与路径规则 | 小范围明确审查后使用 |
| `git add -u` | 所有已跟踪路径的修改和删除 | 仓库范围，默认不含新文件 | 只更新已有文件 |
| `git add -A` | 工作区范围内的新增、修改和删除 | 从当前 Git 版本和路径位置解释 | 明确要同步整个工作区时使用 |

在子目录执行 `git add .`，不会把兄弟目录的变化纳入 index。旧版本 Git 对 `git add -A` 在子目录的行为曾有差异；团队脚本应写清 Git 版本基线，并尽量在仓库根目录使用显式路径或明确的 pathspec。`-A` 也会暂存删除，风险比“只添加新文件”更大。

用下面的顺序观察范围差异：

~~~bash
git status --short
git add -u
git status --short
git restore --staged -- .
git add -A
git status --short
~~~

最后一条会把练习目录内的所有可见变化加入 index。恢复命令只适合你已经确认这是一次性练习仓库并且 `HEAD` 可解析的情况。真实项目不要用它覆盖别人已经准备好的 index，先按路径逐个核对。

## 只暂存文件的一部分

一个文件可能包含两个不同意图。交互式 patch 可以逐块选择：

~~~bash
git add -p -- README.md
~~~

Git 会显示一个 hunk，并询问是否加入 index。常用响应包括 `y` 接受、`n` 跳过、`s` 尝试拆分、`q` 退出。不同版本的提示略有差异，退出不会自动提交。

交互式暂存的验收仍然是：

~~~bash
git status --short
git diff --staged -- README.md
git diff -- README.md
~~~

只看 `git status` 不够，因为一个文件可能仍然是 `MM`。如果 hunk 无法拆分，先用编辑器把变化分成更小的逻辑块，或在隔离分支中采用临时提交，再通过后续历史整理解决。不要为了得到“干净状态”而接受不理解的 hunk。

## 删除、重命名和未跟踪路径

删除已跟踪文件后：

~~~bash
rm path/to/old.txt
git status --short
git add -u -- path/to/old.txt
git status --short
git diff --staged --name-status
~~~

index 此时记录删除，工作区中没有该路径。若只执行 `git add path/to/old.txt`，路径已经不存在，结果可能不是你期望的删除动作，因此 `-u` 或显式 `git rm` 更能表达意图。 `git rm` 同时修改 index 和工作区，属于更强的动作，执行前必须确认路径和备份边界。

重命名通常是删除旧路径、添加新路径。Git 在 diff 显示阶段根据相似度推断 rename，而不是在 `add` 时写入一条不可变的重命名对象。审查时使用：

~~~bash
git diff --staged --name-status -M
~~~

新文件默认不受 `.gitignore` 规则影响时，才能被普通 `add` 选中。对被忽略路径使用：

~~~bash
git add -f -- generated/output.bin
~~~

这会显式绕过忽略规则，只影响本次路径选择。使用前要确认文件不是凭据、构建产物或有版权限制的二进制；`-f` 不是权限绕过，也不会从已经提交的历史中清除秘密。

## `-N` 只建立意图，不写入完整内容

有时想让未跟踪文件出现在 diff 中，但还不准备把其内容放进 index：

~~~bash
git add -N -- notes.txt
git status --short
git diff -- notes.txt
git diff --staged -- notes.txt
~~~

`-N` 或 `--intent-to-add` 为路径建立意图条目，通常让工作区内容可以被普通 diff 看到，但不等于已经准备了可提交的完整 blob。提交前必须再次执行普通 `git add`，并检查暂存差异。它适合协作审阅或先登记路径，不适合用来证明秘密已经安全处理。

## 属性、过滤器和换行边界

`git add` 可能执行 `.gitattributes` 定义的 clean filter，并根据 `text`、`eol` 等属性规范化内容。出现“编辑器看到的字节”和“暂存差异中的字节”不同，先检查：

~~~bash
git check-attr --all -- path/to/file
git check-attr --cached --all -- path/to/file
git diff --no-ext-diff --no-textconv --staged -- path/to/file
~~~

工作树属性和 index 属性可能来自不同版本的 `.gitattributes`。不要为了让 diff 看起来干净而关闭 filter 或强制转换；先确认团队规定的规范化结果，再决定是否重新暂存。过滤器执行外部程序时还会引入可执行代码和失败依赖，详见安全篇的不受信任仓库边界。

## `add` 失败时会发生什么

`git add` 通常先创建或更新对象，再在 index 上持有锁，最后替换 index 文件。错误可能来自路径、权限、属性过滤器、磁盘空间、对象库损坏或并发的 index 锁。失败不等于“什么都没有写入”：临时对象可能已经存在，但只要 index 没有更新，它们不会自动进入当前提交的可达历史。

遇到失败，先记录：

~~~bash
git status --short
git diff -- path/to/file
git diff --staged -- path/to/file
git rev-parse --git-path index
git rev-parse --git-path index.lock
~~~

不要直接删除 `index.lock`。确认没有另一个 Git 进程、IDE 或 CI 正在使用该仓库后，再按仓库运维规则处理残留锁。过滤器失败时，修复过滤器或属性配置后重新执行，不要用 `-f` 绕过一个未知的内容转换错误。

## 误暂存后的恢复

只想取消暂存、保留工作区当前内容：

~~~bash
git restore --staged -- path/to/file
~~~

该命令把 index 恢复到默认来源，通常是 `HEAD`，不覆盖工作区。执行后核对：

~~~bash
git status --short
git diff -- path/to/file
git diff --staged -- path/to/file
~~~

若仓库还没有提交，`HEAD` 不存在，默认恢复来源可能不可用。此时先复制或保存文件，再决定如何重建首次提交的 index。不要把 `git restore --staged` 当成文件备份。

如果要把某个路径从工作区也恢复为 index 版本：

~~~bash
git restore --worktree -- path/to/file
~~~

这会覆盖未暂存修改，风险更高。执行前应把要保留的字节复制到仓库外的受控位置，并在命令后重新运行状态和 diff。恢复 index 与恢复工作区是两个动作，不要因为选项名称相似而混用。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-2.sh
~~~

共享实验覆盖显式路径选择、暂存后继续编辑、取消暂存、删除和属性变化。脚本还把一个混合场景拆成两个提交，证明 index 是“下一份快照”的选择器，而不是提交按钮。

实验不会验证真实 IDE 的自动暂存、网络文件系统锁、企业 filter、LFS 服务、平台权限或大文件性能。生产环境中如果 `add` 报错，应保存原始 index 和对象统计，再交给仓库维护流程处理。

## 小结

`git add` 的含义是“把某些路径当前的内容准备进 index”。路径范围由参数和执行目录决定，内容版本由执行时的工作区状态决定。用显式路径或交互式 patch 缩小选择，用 `status` 和 `diff --staged` 证明结果，误选时只恢复 index。提交前不审查 index，就没有真正审查提交输入。
