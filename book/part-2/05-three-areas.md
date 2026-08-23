# 工作区、暂存区与提交：先判断差异在哪一层

很多 Git 误操作不是因为命令太难，而是因为操作者没有先回答一个问题：眼前的内容究竟在工作区、index，还是已经进入提交历史？文件名相同，不代表这三个位置保存的是同一份字节。

本章把三个位置建立成一个可观察、可恢复的操作模型。它只讲日常判断和状态变化。index 的磁盘格式、冲突 stage、稀疏索引和 pack 存储属于第三篇的底层解释；这里先让你能在命令前后说清楚“哪一份内容会被采用”。

## 进入条件与退出能力

进入本章前，你应能在 `git-first-lab` 中创建提交，并读懂 `git status` 的简短输出。练习仓库必须是一次性目录，不要把下面的恢复命令直接用于有未保存工作的真实项目。

读完本章后，你应能：

- 说出 `HEAD`、index 和工作区分别保存什么；
- 用 `git status`、`git diff`、`git diff --staged` 和 `git diff HEAD` 定位变化；
- 解释同一个路径为什么会同时出现在“已暂存”和“未暂存”两组；
- 在不丢失工作区内容的前提下取消暂存；
- 判断未跟踪文件和被忽略文件为什么没有出现在普通差异中；
- 在提交前证明真正会写入历史的内容，而不是只看编辑器里的最新版本。

## 三个位置，三份可能不同的内容

把当前仓库想成三列快照：

```text
HEAD       当前历史快照
  |
index      下一次提交准备采用的快照
  |
工作区      磁盘上当前可编辑的内容
```

这不是三个普通目录，而是三个比较边界：

| 位置 | 工作定义 | 主要读取方式 | 不代表什么 |
| --- | --- | --- | --- |
| `HEAD` | 当前分支或分离 `HEAD` 所指向的提交快照 | `git show HEAD:path`、`git ls-tree HEAD` | 不代表远程默认分支的最新状态 |
| index | 下一次提交准备采用的路径和内容 | `git diff --staged`、`git ls-files --stage` | 不是备份，也不是共享服务器上的暂存区 |
| 工作区 | 当前文件系统中的可编辑内容 | `git diff`、编辑器和文件系统工具 | 不等于下一次提交一定会写入的内容 |

首次提交前没有可解析的 `HEAD`，但 index 仍可以准备新文件。之后的命令若需要比较“相对当前提交”，必须先确认仓库已经有提交。

### 同一路径为什么会分叉

假设 `README.md` 已经在最近提交中。你先改了一行，再运行 `git add README.md`，然后又改了第二行：

```text
HEAD       原始版本
index      第一次修改后的版本
工作区      第一次修改 + 第二次修改
```

此时工作区不会因为 Git 已经暂存过就被冻结，index 也不会随着编辑器继续保存而自动更新。`git commit` 只读取 index，所以第二次修改不会进入这次提交。这正是 Git 允许你把不同意图拆成不同历史节点的基础。

## 用状态矩阵替代猜测

下面的矩阵以已跟踪路径为主。`Y` 表示存在差异，`N` 表示没有差异：

| 工作区相对 index | index 相对 `HEAD` | `git status --short` 的典型左/右位 | 含义 |
| --- | --- | --- | --- |
| N | N | 两个空格 | 工作区、index 和 `HEAD` 一致 |
| Y | N | ` M` | 只有工作区有未暂存修改 |
| N | Y | `M ` | 只有 index 有已暂存修改 |
| Y | Y | `MM` | index 有一份修改，工作区又继续修改 |
| N | N | `??` | 未跟踪路径，不属于任何提交快照 |
| N | N | `!!`（需 `--ignored`） | 被忽略的未跟踪路径，普通状态默认隐藏 |

短状态的左列描述 index 相对 `HEAD` 的变化，右列描述工作区相对 index 的变化。不要把 `M` 当作一个没有方向的“修改”标签；位置不同，恢复动作也不同。

## 四条只读命令，各自回答什么

以下命令在练习仓库根目录执行。它们只读取对象、index 和工作区，不连接远程，也不改变文件或引用。

### `git status --short`

```bash
git status --short
```

它给出路径级状态摘要。输出可能包含 ` M README.md`、`M  README.md`、`MM README.md` 或 `?? notes.txt`。路径名和排序会随实际状态变化，不能把示例行当成固定输出。

如果命令失败，先确认执行位置是仓库内，并保留完整错误。不要为了让状态命令成功而删除 `.git`、清理工作区或设置全局通配例外。恢复通常是回到正确的仓库目录，或修复仓库发现/所有权问题后重新读取。

### `git diff`

```bash
git diff -- README.md
```

它比较工作区和 index，回答“自上次暂存后，磁盘文件又变了什么”。输出为空只表示两者一致，不表示文件与 `HEAD` 一致，也不表示没有未跟踪文件。`--` 把后面的字符串解释为路径，避免路径名与选项混淆。

如果需要让脚本只根据差异判断，可使用退出码：

```bash
git diff --quiet -- README.md
```

退出码为 0 表示没有未暂存差异，1 表示有差异，其他非零值可能表示参数或仓库错误。脚本应把 1 与真正的执行失败分开处理。

### `git diff --staged`

```bash
git diff --staged -- README.md
```

它比较 index 和 `HEAD`，回答“已经准备进入下一次提交的内容是什么”。`--cached` 是同一语义的别名。本书主线使用 `--staged`，因为它直接表达了操作意图。

如果仓库还没有提交，`HEAD` 无法解析，命令可能以非零状态结束。此时用 `git diff --staged` 观察首次提交的新增路径，不能把“没有可比较的 `HEAD`”解释成“index 为空”。

### `git diff HEAD`

```bash
git diff HEAD -- README.md
```

在 `HEAD` 存在时，它比较当前工作区和 index 合并后的结果与 `HEAD`。因此它能一次看见已暂存和未暂存的已跟踪变化，但默认仍不会替你展示未跟踪文件。自动化或审阅记录应同时保存 `git status --short`，否则读者无法知道某个路径是否根本还未被纳入 Git。

## 一个可复现的状态演练

下面的演练继续使用本篇的 `git-first-lab`。如果状态不同，先保存 `git status --short`，不要用破坏性命令强行对齐。

### 1. 只改变工作区

在 `README.md` 末尾追加一行，然后在仓库根目录执行：

```bash
printf "\n工作区中的第一处修改。\n" >> README.md
git status --short
git diff -- README.md
git diff --staged -- README.md
```

预期是状态出现 ` M README.md`，`git diff` 显示新增行，而 `git diff --staged` 为空。文件内容已经改变，但 index 仍然等于 `HEAD`。

如果状态没有出现修改，检查你是否写入了另一个目录，或文件本身被过滤器转换。先用 `pwd`、`git rev-parse --show-toplevel` 和 `git status --short` 记录位置，不要立即重复追加内容。

### 2. 把当前版本写入 index

```bash
git add -- README.md
git status --short
git diff -- README.md
git diff --staged -- README.md
```

`git add` 读取当前工作区内容并更新 index 中的路径。预期状态变成 `M  README.md`，未暂存差异为空，暂存差异显示刚才那一行。工作区文件仍在原位置，没有被移动。

如果 `git add` 报路径不存在、权限不足或 filter 失败，先看 `git status` 和文件实际路径。不要用 `git add .` 扩大范围来绕过失败；修复路径或 filter 后，重新检查暂存差异。

### 3. 暂存后再次编辑，制造 `MM`

再次追加一行，但这次不要执行 `git add`：

```bash
printf "暂存之后的第二处修改。\n" >> README.md
git status --short
git diff -- README.md
git diff --staged -- README.md
git diff HEAD -- README.md
```

预期状态是 `MM README.md`。前一条新增行只出现在 `git diff --staged`，后一条新增行只出现在 `git diff`，`git diff HEAD` 则同时看到两条。三条输出的提交 ID、时间和上下文可能不同，但它们应该共同解释同一个状态。

### 4. 取消暂存而不丢工作区内容

如果发现第一次修改也不该进入这次提交，可以把 index 恢复到 `HEAD`，保留工作区当前内容：

```bash
git restore --staged -- README.md
git status --short
git diff -- README.md
git diff --staged -- README.md
```

预期状态是 ` M README.md`，两处修改仍在工作区，暂存差异为空。这里的 `--staged` 指定恢复 index；它不是删除文件，也不会把工作区改回旧版本。

如果仓库处于无提交状态，`git restore --staged` 没有可用的 `HEAD` 作为默认恢复来源，可能失败。此时先保留文件副本，重新选择首次提交路径，不要假设 index 可以替代备份。

### 5. 重新审查并提交

```bash
git add -- README.md
git diff --staged -- README.md
git commit -m "docs: explain the practice repository"
git status --short
```

只有 `git diff --staged` 符合本次意图时才提交。成功后状态应为空。提交只改变本地对象和当前引用，不会上传远程；需要共享时，进入远程协作篇再讨论认证、权限和非快进边界。

## 未跟踪与忽略路径不在这三份快照里

未跟踪文件存在于工作区，但没有 index 条目，也没有被 `HEAD` 的 tree 记录。普通 `git diff` 不会展示它的完整内容。先用状态确认，再决定是否显式加入：

```bash
git status --short
git add -- notes.txt
git diff --staged -- notes.txt
```

如果它是个人草稿或本地产物，应当删除暂存选择并建立经过审查的 `.gitignore` 规则，而不是误以为“diff 没显示，所以安全”。忽略规则只影响未跟踪路径的发现，不提供访问控制、加密或历史清理。

要解释某个路径为何被隐藏，在仓库根目录执行：

```bash
git status --short --ignored
git check-ignore -v -- notes.txt
```

`--ignored` 会把被忽略路径以 `!!` 形式显示，`check-ignore -v` 会报告匹配的规则来源。命令只读；输出可能包含内部路径和规则文件，提交到公开工单前要脱敏。

## 恢复动作的范围和风险

| 动作 | 修改位置 | 保留什么 | 主要风险 |
| --- | --- | --- | --- |
| `git restore --staged -- path` | index | 工作区当前内容 | 没有可解析 `HEAD` 时无法按默认来源恢复 |
| `git restore --worktree -- path` | 工作区 | index 内容 | 会覆盖未暂存修改，执行前必须保存或审查 |
| `git restore --staged --worktree -- path` | index 与工作区 | 默认回到 `HEAD` | 可能丢失两处本地变化，不能当作清理状态 |
| `git add path` | index | 工作区当前内容 | 路径过宽会把秘密、生成物或无关改动纳入候选 |
| `git commit` | 对象和当前引用 | index 中的内容 | 提交后 OID 固定，共享后再改写会影响协作者 |

执行任何恢复动作前，先保存：

```bash
git status --short
git diff --binary > /tmp/git-first-lab.worktree.patch
git diff --staged --binary > /tmp/git-first-lab.index.patch
```

这些 patch 只覆盖已跟踪的差异，未跟踪文件仍需单独复制或登记。`/tmp` 路径只是示例，真实项目应使用权限受控的临时目录；不要把可能含秘密的 patch 上传到公开位置。恢复后重新运行状态和差异命令，确认实际保留的内容。

## 三个容易混淆的结论

1. **文件保存了，不等于已经准备提交。** 编辑器只改变工作区，index 仍需显式更新。
2. **状态干净，不等于仓库完整或远程一致。** 它只说明工作区和 index 与当前 `HEAD` 没有已跟踪差异。
3. **进入 index，不等于已经备份。** index 是本地下一次提交的输入，提交、备份、远程推送和平台保留是不同层次。

## 隔离实验验证了什么

在仓库根目录运行：

```bash
./scripts/verify-part-2.sh
```

前置条件是 Bash、Git 2.28 或兼容版本、`mktemp` 和可写临时目录。脚本在临时目录创建全新的仓库，隔离用户配置，使用合成身份，不连接网络、不读取本机凭据，也不修改蓝皮书仓库。退出时删除实验目录。

实验依次断言：初始提交后工作区单独变化；`git add` 后 index 单独变化；再次编辑后同一文件同时拥有 staged 和 unstaged 差异；`git diff HEAD` 能覆盖两者；取消暂存会保留工作区字节；重新暂存并提交后状态回到干净。它还验证 `.gitignore` 只隐藏合成日志，不把忽略路径误当成已跟踪内容，并检查混合改动按路径拆成两个意图明确的提交。

成功时只输出：

```text
Part 2 worktree/index/HEAD state matrix and recovery experiment passed.
```

实验没有验证 IDE 的状态缓存、文件系统恢复、Git LFS、远程平台、协作者并发、服务端 hooks 或未跟踪文件的磁盘取证。真实项目发生误操作时，应先保留工作区和证据，再根据本章的三层状态选择恢复动作。

## 小结

`HEAD` 是当前历史快照，index 是下一次提交的候选快照，工作区是当前磁盘内容。`git status` 说明三者关系，`git diff` 读工作区与 index 的差异，`git diff --staged` 读 index 与 `HEAD` 的差异，`git diff HEAD` 汇总已跟踪变化。只要先定位变化所在层，`add`、取消暂存、审查和提交就不再是试一条命令看看。
