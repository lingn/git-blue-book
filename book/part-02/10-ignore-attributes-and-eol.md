# 忽略规则、属性与换行：仓库策略不等于安全边界

项目目录里经常出现不应进入版本控制的内容：构建产物、编辑器缓存、本地日志、临时文件，以及只适用于当前电脑的配置。Git 还需要另一类规则来描述已跟踪文件怎样处理，例如文本换行、差异展示和内容过滤。

`.gitignore` 和 `.gitattributes` 经常被放在一起，却回答不同问题：前者决定未跟踪路径是否作为候选显示，后者为路径提供属性，影响 checkout、diff、merge、archive 或外部 filter 的选择。两者都不是访问控制，也不是秘密清理工具。

## 进入条件与退出能力

进入本章前，你应能读懂 `git status` 的 `??`、` M` 和 `M ` 状态。实验必须在本篇的临时 `git-first-lab` 中完成，不要在真实项目里为了验证匹配规则而强制添加秘密或执行未知 filter。

读完本章后，你应能：

- 写出具有明确范围的 `.gitignore` 规则，并解释它为何命中；
- 区分未跟踪、已跟踪和被忽略路径；
- 用 `git check-ignore` 找到规则来源，并处理否定规则和目录边界；
- 用 `.gitattributes` 声明文本与换行策略，区分工作树版本和 index 中的属性；
- 识别 `filter=<name>` 只是选择器，真正的程序定义来自本机配置；
- 判断什么时候应当撤销暂存、停止执行 filter，或转入凭据撤销与历史清理流程。

## `.gitignore` 只管理未跟踪路径的发现

在仓库根目录创建：

```gitignore
# 本地日志
*.log

# 构建输出目录
/build/

# 个人笔记
/notes.txt
```

前置条件是当前目录属于目标仓库，且 `.gitignore` 本身准备作为团队规则审查。保存后运行：

```bash
git status --short --ignored
git check-ignore -v -- debug.log notes.txt
```

这些命令只读取工作区、规则文件和状态，不改变文件。成功时 `debug.log` 和 `notes.txt` 可能显示为 `!!`，`check-ignore -v` 会报告匹配的规则来源、行号和路径。不同 Git 版本对状态提示文本可能略有差异，验证应依赖退出码和规则来源，而不是复制示例行。

如果 `git check-ignore` 返回 1，通常表示没有匹配规则，不是 Git 崩溃。先检查执行目录、路径拼写、规则是否已经写入工作区，以及父目录是否被更宽的规则排除。不要为了让命令返回 0 而把规则改成通配所有文件。

### 规则范围和优先级

支持排除模式的 Git 命令会综合命令行排除、仓库级 `.gitignore`、嵌套目录中的 `.gitignore`、`.git/info/exclude` 和用户级 excludes 文件。越靠近路径的规则可以覆盖上层规则，否定模式 `!name` 可以重新包含一个路径，但不能穿过已经被排除的父目录。

常见模式的区别：

| 模式 | 典型含义 | 需要先确认的风险 |
| --- | --- | --- |
| `*.log` | 匹配任意层级的 `.log` 文件 | 可能隐藏团队真正需要提交的日志样例 |
| `/build/` | 只匹配仓库根目录的 `build` 目录 | 子目录中的同名目录不会自动匹配 |
| `cache/` | 匹配任意层级的 `cache` 目录 | 范围过宽，可能遮住源码或测试 fixture |
| `!keep.log` | 尝试重新包含名为 `keep.log` 的路径 | 父目录若已被忽略，单独否定不会生效 |

规则文件是代码。提交前应说明作用范围、例外和为什么不会掩盖应交付的文件。不要把 `.gitignore` 当作“只要加进去就安全”的批准记录。

### 被跟踪文件不会因新增规则消失

假设 `tracked.log` 已经提交，之后才加入 `*.log`：

```bash
git status --short --ignored
printf "新的记录。\n" >> tracked.log
git status --short --ignored
```

第二次状态仍应报告 `tracked.log` 的已跟踪修改，而不是把它隐藏成普通 `!!`。规则只影响未跟踪路径的发现，不会从 index、`HEAD` 或旧提交移除路径。

如果团队决定停止跟踪但保留本地文件，应先确认这不是共享配置，再执行：

```bash
git rm --cached -- local.env
git diff --staged -- local.env .gitignore
```

`git rm --cached` 会修改 index，保留工作区文件。成功后必须提交删除记录和忽略规则，并用 `git status` 确认本地文件仍在磁盘上。若该文件曾含真实凭据，先撤销和轮换凭据，再按第十篇的历史清理流程处置；取消跟踪不会擦除旧对象或旧 clone。

## `.gitattributes` 为路径声明属性

在仓库根目录创建：

```gitattributes
*.md text eol=lf
*.txt text eol=lf
*.generated filter=lab
```

`text`、`eol=lf` 和 `eol=crlf` 描述文本规范化与工作区呈现；`filter=lab` 只选择名为 `lab` 的 filter。属性文件中的名字不会自动安装程序，也不会赋予仓库代码执行权限。

在已经有提交的仓库中检查当前工作树属性：

```bash
git check-attr text eol filter -- README.md
git ls-files --eol -- README.md
```

命令只读取属性和 index。`check-attr` 会报告 `set`、`unset` 或 `unspecified`，`ls-files --eol` 会把 index、工作树和属性推断出来的换行状态放在一行中。路径和换行结果取决于实际文件，不能把示例状态当作跨平台固定输出。

### 工作树属性和 index 属性可能不同

在仓库中已经提交一份 `.gitattributes` 后，临时把工作区中的 `eol=lf` 改为 `eol=crlf`，再分别执行：

```bash
git check-attr text eol -- README.md
git check-attr --cached text eol -- README.md
git diff -- .gitattributes
```

默认查询使用当前工作树能看到的属性，`--cached` 只使用 index 中的 `.gitattributes`。如果两者不同，构建或审查工具可能得到不同选择。先审查差异，再决定是否 `git add .gitattributes`；恢复临时实验可用：

```bash
git restore --worktree -- .gitattributes
```

该命令会覆盖这个文件的未暂存修改，执行前应确认只包含可丢弃的实验变化。真实项目先保存 patch，不要用它清理未知工作。

### 换行策略不是“统一改一下就结束”

`text` 属性允许 Git 在对象和工作区之间进行文本换行处理，`eol=lf` 或 `eol=crlf` 规定工作区期望形式。`core.autocrlf`、`core.eol`、编辑器设置和操作系统也会影响结果，不能只看一个配置键就宣称团队已经统一。

批量规范化前，先在隔离分支检查：

```bash
git ls-files --eol
git diff --check
git add --renormalize .
git diff --cached --stat
git diff --cached -- .gitattributes
```

`git add --renormalize .` 会重新按当前属性处理已跟踪路径并更新 index，可能产生大量变化。它不上传远程，也不修改 `HEAD`，但提交后会改变很多文件的对象内容。若 diff 中出现不预期的二进制、生成物或全仓库换行变化，先恢复 index 并修订属性，不要为了让门禁变绿而提交噪声。

## filter 是执行入口，不是格式说明

属性文件可以写：

```gitattributes
*.generated filter=lab
```

真正的 clean、smudge 或 process 命令来自本机配置，例如 `filter.lab.clean`。仓库中的属性可以随提交到达，但普通 clone 不会把源仓库的 local config 和 hooks 一起复制给目标；一旦目标机已经配置了同名 filter，checkout、add 或 restore 就可能启动外部程序。

在允许访问的仓库中只读盘点：

```bash
git show HEAD:.gitattributes
git config --show-origin --show-scope --get-regexp '^filter\.'
git check-attr filter -- README.generated
```

第一条读取提交中的属性，第二条读取当前配置来源，第三条只回答路径选择了哪个 filter，不主动执行它。配置输出可能包含内部路径、命令和秘密，不能原样复制到公开日志。

如果 checkout 或 `git add` 因 filter 失败，先停止构建并保存 `git status`、配置来源和错误输出。不要直接删除 `.git`、关闭 `filter.<name>.required` 或用 `git add -f` 掩盖问题。第十篇会把不受信任仓库、attributes、filter 和 hooks 放进完整的执行链边界。

## 安全判断和恢复顺序

以下结论必须分开：

- 被忽略，只说明某个未跟踪路径默认不显示；
- 属性命中，只说明路径获得了某个 Git 行为选择；
- filter 运行成功，只说明当前本机程序完成了一次转换；
- 扫描没有发现秘密，不说明旧历史、LFS、日志或旧 clone 没有秘密。

出现疑似凭据时，顺序应是停止传播、撤销/轮换、保存证据、再决定是否改写历史。不要先把真实值复制到 `git check-ignore`、日志或新的测试 fixture 中。

## 隔离实验验证了什么

在仓库根目录运行：

```bash
./scripts/verify-part-2.sh
```

前置条件是 Bash、Git 2.28 或兼容版本、`mktemp`、`grep` 和可写临时目录。脚本在临时仓库中使用合成日志、属性和路径，不连接网络、不读取真实凭据、不执行外部 filter，退出时删除临时目录。

实验除了验证工作区/index/`HEAD` 状态矩阵和取消暂存恢复，还验证：被忽略的 `debug.log` 不出现在普通候选中；使用 `git add --force` 后，已跟踪的 `tracked.log` 即使命中忽略规则仍会报告修改；`.gitattributes` 的 `eol=lf` 在 index 查询和工作树查询中可以区分；临时工作树属性改为 `crlf` 时，`--cached` 仍读取已提交的 `lf`；恢复属性文件后混合文档改动仍能拆成独立提交。

成功时只输出：

```text
Part 2 worktree/index/HEAD state matrix, ignore rules, attributes, and recovery experiment passed.
```

实验没有验证真实操作系统的编辑器换行策略、Git LFS、第三方 filter、远程平台规则、CI runner 或历史清理服务。它只证明本地 Git 可观察到的选择器和状态边界；生产属性与 filter 必须在代表性平台和受控执行环境中单独验收。

## 小结

`.gitignore` 决定未跟踪路径是否被发现，`.gitattributes` 为路径声明 Git 行为，`filter=<name>` 还需要本机配置提供执行程序。已跟踪文件不会因为忽略规则消失，工作树属性也可能与 index 属性不同。把规则、属性和执行入口分别审查，才能避免“看不见”被误解为“没有”或“安全”。
