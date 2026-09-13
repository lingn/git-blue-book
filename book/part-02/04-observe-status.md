# 先观察再操作：`git status` 的状态证据

Git 命令的风险取决于内容在哪一层。 `git status` 是日常工作循环的观察入口，但它不是一句“工作区有没有改动”的简单回答。它把当前 `HEAD`、index、工作区、未跟踪路径和上游引用的关系压缩成一份报告。

本章先建立状态报告的读法，再进入 `add` 和 `diff`。所有命令都在练习仓库根目录执行，除非特别说明。

## 进入条件与完成标准

准备好上一章创建的 `git-first-lab`，并确保仓库至少有一条提交且 `README.md` 已经被跟踪。若仓库只有初始化状态，请先创建一个最小基线提交；没有可解析的 `HEAD` 时，新增路径会显示为 `A`，不能直接演示已跟踪路径的 `MM`。如果你没有这个仓库，请新建一个空目录、初始化并先提交基线。不要在真实项目中为了制造状态而覆盖文件。

读完本章后，你应能：

- 解释短状态左列、右列分别比较哪两个区域；
- 区分已跟踪修改、未跟踪文件、忽略文件、冲突和重命名提示；
- 选择人读输出或机器读输出，并正确处理退出码与 NUL 分隔；
- 在状态异常时记录执行位置、分支、上游和仓库锁，而不是先做清理；
- 说明 `status` 通常不改工作区和引用，但可能刷新 index 的缓存元数据；
- 把“状态报告没有显示”与“内容不存在”明确分开。

## 状态报告回答的五个问题

在仓库根目录执行：

~~~bash
git status
~~~

一份完整报告通常回答：

1. 当前 `HEAD` 位于哪个分支，是否没有提交或处于分离状态；
2. index 相对 `HEAD` 准备了哪些内容；
3. 工作区相对 index 又产生了哪些变化；
4. 哪些路径还未进入 index；
5. 如果配置了上游，本地与上游引用是否有领先或落后。

报告中的提示文字、颜色、分页和路径格式会随 Git 版本、终端和配置改变。验收实验应检查状态关系和退出码，不应匹配整段人类提示。

`git status` 通常不会改文件内容、对象或分支引用。为了比较文件状态，Git 可能刷新 index 的 stat 缓存、untracked cache 或 fsmonitor 相关元数据。因此在取证现场，不能把它描述成绝对无写入命令；若必须保持原始 index 字节，应使用组织规定的只读采集方法，并记录命令副作用。

## 短状态的两列

快速扫描可以使用：

~~~bash
git status --short
~~~

短状态中，前两列分别表示：

~~~text
XY path
││
│└── 工作区相对 index 的状态
└─── index 相对 HEAD 的状态
~~~

常见组合如下：

| 短状态 | 比较结果 | 含义 |
| --- | --- | --- |
| `  ` | index 与 `HEAD` 一致，工作区与 index 一致 | 没有已跟踪变化 |
| ` M` | index 与 `HEAD` 一致，工作区不同 | 只有未暂存修改 |
| `M ` | index 与 `HEAD` 不同，工作区与 index 一致 | 只有已暂存修改 |
| `MM` | 两个比较都不同 | 暂存后又继续编辑了同一路径 |
| `A ` | index 新增路径 | 新文件已暂存 |
| `D ` 或 ` D` | index 或工作区删除了已跟踪路径 | 删除发生在不同层 |
| `??` | 路径没有 index 条目 | 未跟踪文件或目录 |
| `!!` | 未跟踪路径被忽略 | 只有使用 `--ignored` 才显示 |
| `UU` 等 | index 存在冲突阶段 | 合并或变基尚未完成 |

重命名和复制是 Git 根据相似度推断出的显示结果，不是 index 中保存了“重命名事件”。需要精确判断时，查看 `git diff --name-status` 或 tree 条目。

## 一个状态矩阵演练

以下步骤在练习仓库根目录执行。每一步都先观察后改变，输出中的路径和提交 ID 以本地实际值为准。

### 1. 只有未跟踪文件

创建一个新的未跟踪文件：

~~~bash
printf '个人草稿。\n' > notes.txt
git status --short
~~~

预期包含：

~~~text
?? notes.txt
~~~

文件只存在于工作区。`git diff` 不会自动展示它的完整内容，因为它还没有 index 基线。不要用“差异为空”判断它没有风险。

### 2. 只有已暂存变化

~~~bash
git add -- notes.txt
git status --short
git restore --staged -- notes.txt
~~~

状态会短暂显示 `A  notes.txt`，随后恢复为 `?? notes.txt`。左列非空说明 index 已经与当前 `HEAD` 不同。这里的新增路径不在历史中，下一步先取消暂存，避免它干扰已跟踪路径的状态演练。

### 3. 暂存后继续编辑

~~~bash
printf '\n第一处内容。\n' >> README.md
git add -- README.md
printf '第二处内容。\n' >> README.md
git status --short
~~~

预期为 `MM README.md`。第一处内容已进入 index，第二处只在工作区。不要重新执行 `git add .` 来“消除 MM”，除非你已经审查并确认两处变化属于同一次提交。

### 4. 观察未跟踪和忽略路径

~~~bash
printf '个人草稿。\n' > notes.txt
printf 'notes.txt\n' > .gitignore
git status --short
git status --short --ignored
git check-ignore -v -- notes.txt
~~~

普通状态会列出 `.gitignore` 的变化和 `README.md` 的变化，但不会列出 `notes.txt`。带 `--ignored` 时，`notes.txt` 以 `!!` 出现。`check-ignore -v` 给出命中的规则和文件来源。忽略只影响未跟踪路径的发现，不会隐藏已提交内容，也不是权限控制。

## 适合脚本的状态格式

人读的短状态不适合直接作为自动化协议。路径可能包含空格、换行或引号，重命名还可能有两个路径。脚本可以使用：

~~~bash
git status --porcelain=v2 -z
~~~

`porcelain=v2` 提供稳定得多的字段格式，`-z` 使用 NUL 分隔路径，避免换行路径破坏解析。脚本必须按 NUL 读取，不能把输出交给普通的逐行 `read` 或按空格切分。若只需要判断是否干净：

~~~bash
if git status --porcelain=v1 --untracked-files=all | grep -q .; then
  printf '%s\n' 'repository has changes'
fi
~~~

这里的 `grep` 只用于演示人读格式。生产脚本应明确处理 `git status` 的执行失败与“有变化”两种不同结果，不要让管道的最后一个命令掩盖仓库错误。

## 未跟踪文件、目录和忽略规则

默认情况下，状态会把未跟踪目录折叠成一行。需要看到目录内每个文件时：

~~~bash
git status --short --untracked-files=all
~~~

`-uno` 或 `--untracked-files=no` 可以在大仓库中暂时关闭未跟踪扫描，但它也会让你看不见新文件。使用它时必须把“未扫描未跟踪路径”写进记录，不能把空报告当作干净证明。

在共享脚本或排障快照中，建议同时保存：

~~~bash
git status --short --branch --untracked-files=all
git status --short --ignored
git rev-parse --show-toplevel --git-dir --is-inside-work-tree
~~~

第二条可能暴露本地构建路径和规则文件名，上传前按组织要求脱敏。

## 分支、上游和远程状态

使用 `--branch` 查看当前分支及上游摘要：

~~~bash
git status --short --branch
~~~

如果没有上游，报告不会替你查询服务器；如果有上游，领先或落后数值依赖本地远程跟踪引用。它不一定反映远端此刻的真实状态，因为本地缓存可能过期。要更新缓存需要执行 `fetch`，而 `fetch` 会写本地 refs 和对象，属于下一篇的有副作用动作。

因此，看到“领先 1”只能证明相对于当前本地上游缓存领先 1，不能直接证明远端没有并发更新。推送前的租约和远端核对见第四、第五篇。

## 状态命令失败时的分流

| 现象 | 先确认 | 不要做的事 | 低风险下一步 |
| --- | --- | --- | --- |
| `not a git repository` | `pwd`、仓库根目录发现 | 在父目录盲目 `git init` | 回到已确认的项目目录 |
| `detected dubious ownership` | 路径所有权和 `safe.directory` 来源 | 用 `safe.directory=*` 全局绕过 | 让所有者或管理员按单仓库确认 |
| `index.lock` 已存在 | 进程列表、锁文件时间和团队并发情况 | 直接删除锁文件 | 确认没有 Git 进程后按仓库流程处置残留锁 |
| 状态很慢 | 未跟踪数量、文件系统、fsmonitor/untracked cache | 用 `-uno` 后宣称干净 | 记录扫描范围，再测量性能 |
| 文件明明存在却不显示 | `git check-ignore -v`、sparse 配置、子模块状态 | 直接 `git add .` | 先判定 ignore、sparse、子模块或路径错误 |
| 出现冲突状态 | `git status` 的进行中操作提示、index stages | 用 reset 或删除 `.git` 清场 | 保留现场，按合并或变基章节完成或 abort |

状态异常时，先保存原始输出和执行位置。`status` 是导航工具，不是“清理按钮”。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-2.sh
~~~

实验会在临时仓库中验证未跟踪、已暂存、`MM` 双层修改、忽略路径和最终干净状态。断言只检查状态字段、差异内容和提交关系，不匹配版本相关的整段提示。实验不会连接远程，也不会改变本书工作区。

它不能证明真实文件系统监控、网络挂载、平台上游计数、子模块服务或冲突工具的行为。对生产排障，必须把 Git 状态和外部平台状态分别取证。

## 小结

`git status` 的核心不是“有没有改动”，而是“变化位于哪一层、是否被扫描、相对于哪个引用”。先确认仓库根目录，再读两列状态；需要自动化时用 porcelain 和 NUL 格式；需要远程新鲜度时明确区分本地跟踪缓存和服务器事实。观察清楚之后，`add`、`diff` 和 `commit` 才有可验证的输入。
