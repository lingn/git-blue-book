# 审查差异，而不是猜测：`git diff` 的三条比较边界

`git status` 告诉你哪些路径处于变化状态，`git diff` 负责回答“具体改变了什么”。但 `git diff` 没有唯一的默认含义：它比较哪两个快照，取决于是否指定 `--staged`、`HEAD`、提交范围和路径。

本章把差异当作提交前的证据。示例中的行号、对象 ID、颜色和重命名判断都可能随本地内容变化，验收时应关注比较边界和变化关系。

## 进入条件与完成标准

继续使用已经有至少一条提交的 `git-first-lab`。如果仓库没有 `HEAD`，先完成一条最小提交，或只练习“工作区与 index”的比较。所有命令在仓库根目录执行。

读完本章后，你应能：

- 说出 `git diff`、`git diff --staged` 和 `git diff HEAD` 各自比较什么；
- 在同一路径出现 `MM` 时分别审查两层变化；
- 使用 `--stat`、`--name-status`、`--check` 和 `--binary` 选择证据粒度；
- 处理未跟踪、二进制、子模块、LFS 和属性转换造成的“看不见差异”；
- 让脚本区分“存在差异”“没有差异”和“命令执行失败”；
- 在外部 diff、textconv 或重命名推断影响结论时，切换到可复核的字节级观察。

## 三种日常比较

把三个状态位置写成三列：

~~~text
HEAD  ←  index  ←  工作区
  A        B
~~~

三条命令回答的分别是：

| 命令 | 比较对象 | 回答的问题 | 默认是否包含未跟踪文件 |
| --- | --- | --- | --- |
| `git diff` | 工作区与 index | 暂存之后还改了什么 | 否 |
| `git diff --staged` | index 与 `HEAD` | 下一次提交准备写什么 | 否 |
| `git diff HEAD` | 工作区与 `HEAD`，合并已暂存和未暂存的已跟踪变化 | 相对最近提交总共改了什么 | 否 |

`--cached` 是 `--staged` 的同义写法。本书使用 `--staged`，因为它直接表达“检查已准备内容”。

在没有提交的仓库中，`git diff --staged` 没有默认的 `HEAD` 可比较，可能报错或需要显式的空树来源。不要把这种错误理解成 index 没有内容；先用 `git status` 和 `git ls-files --stage` 判断首次提交状态。

## 用同一文件观察三个结果

在 `README.md` 末尾添加一行，先不暂存：

~~~bash
printf '\n工作区修改。\n' >> README.md
git diff -- README.md
git diff --staged -- README.md
git diff HEAD -- README.md
~~~

预期是：第一条显示新增行，第二条为空，第三条在存在 `HEAD` 时也显示新增行。现在暂存，再继续编辑：

~~~bash
git add -- README.md
printf '暂存后继续修改。\n' >> README.md
git status --short
git diff -- README.md
git diff --staged -- README.md
git diff HEAD -- README.md
~~~

此时通常是 `MM README.md`。工作区差异只包含第二行，暂存差异只包含第一行，`HEAD` 差异包含两行。它们不是三份不同历史，而是同一个路径在三个边界上的比较。

若要取消暂存但保留两行内容：

~~~bash
git restore --staged -- README.md
git diff -- README.md
git diff --staged -- README.md
~~~

取消暂存后，两行都属于工作区差异。恢复动作改变 index，不会替你决定哪些内容最终应该提交。

## 先看范围，再看内容

长差异先用摘要缩小范围：

~~~bash
git diff --stat
git diff --name-status
git diff --numstat
git diff --summary
~~~

常见状态字母包括 `A`、`M`、`D`、`R` 和 `C`。重命名和复制由相似度算法推断，阈值变化可能让同一组对象在不同命令中显示为删除加新增。需要稳定的机器输入时，使用：

~~~bash
git diff --name-status -z
~~~

`-z` 让路径使用 NUL 分隔。不要按空格切分路径，也不要把“显示为 rename”当作历史事实，除非你同时保存旧、新路径和相似度阈值。

确定范围后再查看内容：

~~~bash
git diff -- README.md
git diff -- docs/
git diff -- '*.md'
~~~

最后一种是 Git pathspec，不是 shell glob。把它放在 `--` 后面，避免 shell 先展开成当前工作区文件列表。路径范围应写进审查记录，否则读者无法知道你是否漏看了兄弟目录。

## 空白、二进制和字节级证据

提交前至少运行一次：

~~~bash
git diff --check
git diff --staged --check
~~~

`--check` 检查尾随空格、空白错误和冲突标记等问题。发现非零状态时，先查看命中的文件和行，判断它是故意的格式、生成文件还是实际错误，再修改后重新运行。不要把 `--check` 的非零状态和“有普通差异”的 `--exit-code` 混为一谈。

如果需要脚本判断差异：

~~~bash
if git diff --quiet -- README.md; then
  printf '%s\n' 'no unstaged change'
else
  rc=$?
  if [ "$rc" -eq 1 ]; then
    printf '%s\n' 'unstaged change exists'
  else
    printf 'git diff failed with status %s\n' "$rc" >&2
    exit "$rc"
  fi
fi
~~~

使用 `--exit-code` 时，0 表示没有差异，1 表示有差异，其他非零值表示执行错误或选项问题。脚本应明确处理这三类结果。

二进制文件通常不会显示可读的行补丁：

~~~bash
git diff --stat -- path/to/image.png
git diff --binary -- path/to/image.png
~~~

`--binary` 允许生成可以被补丁工具使用的二进制差异，但输出不等于人类可读的图片内容。审查二进制应结合文件类型、大小、摘要和来源，不要因为终端只显示“Binary files differ”就认为变化无法审查。

## 未跟踪文件不在普通 diff 里

普通 `git diff` 只比较已有 index 条目的路径。未跟踪文件没有 index 基线，所以不会出现。可以先明确查看它与空文件的差异：

~~~bash
git diff --no-index -- /dev/null notes.txt
~~~

`--no-index` 不依赖仓库，发现差异时返回 1 是预期结果。更稳定的提交前流程仍然是先用 `git status` 发现路径，再决定是否 `git add`，最后审查 `git diff --staged`。不要把 `--no-index` 的输出直接当成 Git 提交内容，属性、过滤器和路径选择仍要通过 index 验证。

被忽略的未跟踪文件也不会出现。用：

~~~bash
git check-ignore -v -- notes.txt
git status --short --ignored
~~~

确认它是被规则排除，还是根本位于另一个目录。

## 属性、外部 diff 和 textconv

`git diff` 可能受 `.gitattributes`、外部 diff 驱动或 textconv 影响。为了得到更接近 Git 对象字节的审计证据：

~~~bash
git diff --no-ext-diff --no-textconv -- README.md
git diff --no-ext-diff --no-textconv --staged -- README.md
~~~

这不会自动取消换行规范化，index 中已经存储的内容仍可能是 clean filter 的结果。要同时确认属性：

~~~bash
git check-attr --all -- README.md
git check-attr --cached --all -- README.md
git ls-files --stage -- README.md
~~~

如果工作区属性和 index 属性来自不同版本的 `.gitattributes`，先把属性文件本身纳入审查。不要为了让两条 diff 相同而关闭 textconv，关闭可能只会隐藏二进制或文档格式的真实变化。

## 差异不是完整的系统变更

以下内容需要额外证据：

- 子模块的 gitlink 只显示外部提交 ID，不显示嵌套仓库的文件差异；
- Git LFS 默认跟踪的是 pointer，实际 payload 在外部服务；
- 生成文件、构建缓存和被忽略目录不会自动进入差异；
- sparse-checkout 可能让 tree 中存在的路径不在工作区；
- 外部服务上的评审、CI、制品和部署状态不属于 Git diff；
- 工作区文件权限、换行和过滤器转换可能让字节和显示内容不同。

一次代码评审至少应记录候选提交、暂存差异、未跟踪与忽略扫描范围。不能用“diff 没有输出”证明远程环境、制品或运行版本没有变化。

## 失败和恢复

| 现象 | 先记录 | 恢复方式 | 风险边界 |
| --- | --- | --- | --- |
| `fatal: bad revision 'HEAD'` | `git status`、是否已有提交 | 首次提交用状态和 index 证据，或显式指定空树 | 不要创建假提交来掩盖范围问题 |
| diff 结果与编辑器不同 | 属性、filter、textconv、换行 | 用 `--no-ext-diff --no-textconv` 和 `check-attr` 复核 | 不要盲目关闭规范化 |
| 只看到删除加新增 | 相似度阈值、路径状态 | 用 `-M`、`--summary` 和内容审查 | rename 是推断，不是对象字段 |
| 二进制无行差异 | 类型、大小、摘要和来源 | 结合专用比较器或制品清单 | Git diff 不能证明二进制语义安全 |
| `--check` 失败 | 命中路径和行、属性规则 | 修复或记录有意空白，再重跑 | 不要用 `--no-warn-embedded-repo` 等无关选项掩盖 |
| 命令退出 1 | 使用的选项和脚本上下文 | 区分“存在差异”和执行错误 | 管道不能吞掉真实 Git 错误 |

如果差异审查中发现不应提交的内容，先取消暂存或恢复工作区的明确路径。不要用 `reset --hard` 清除整个仓库来获得空输出。

## 一个可复核的提交前顺序

在提交前保存以下结果：

~~~bash
git status --short --branch --untracked-files=all
git diff --no-ext-diff --no-textconv
git diff --no-ext-diff --no-textconv --staged
git diff --check
git diff --staged --check
~~~

审查顺序是：先确认路径范围，再读工作区变化，最后读真正会写入 commit 的 index 变化。若需要把未跟踪文件纳入，先显式 `add`，再重跑整组命令。把输出和候选提交的完整 OID 绑定到评审记录，不能只贴一段孤立补丁。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-2.sh
~~~

实验验证工作区与 index、index 与 `HEAD`、合并两层变化的三种比较，检查暂存差异和最终提交统计。它使用合成文本和临时仓库，不伪造平台评审、CI、LFS payload 或二进制语义。

实验成功只证明本地 Git 的比较关系和退出边界。真实团队还要把属性、外部 diff、生成文件、制品和部署证据纳入评审流程。

## 小结

`git diff` 的价值在于明确比较边界。先看 `status`，再分别审查工作区、index 和 `HEAD`；用摘要缩小范围，用 `--check` 检查质量，用不调用外部转换的模式复核字节证据。未跟踪文件、LFS payload 和远程运行状态不在普通 diff 中，必须另取证。
