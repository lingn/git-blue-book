# Index 内部结构：下一棵 tree、冲突候选与稀疏目录

工作区保存可编辑文件，commit 通过 tree 保存历史快照，index 位于两者之间。日常提交时，它按路径记录下一棵 tree 准备采用的对象；合并冲突时，同一路径可以临时保存 base、ours 和 theirs 三个候选。Sparse-index 还可以用一个目录条目代表整棵未展开子树。

把 index 只理解成“已暂存文件列表”，解释不了可执行位为何进入提交、`git add` 为什么会清掉冲突 stages、`write-tree` 为什么拒绝未合并路径，以及 sparse 工作区明明没有某个文件，提交 tree 却仍完整。

## 进入条件与完成标准

观察命令可在普通仓库执行。修改 index 格式、制造冲突、设置标志、切换 sparse-index 和使用替代 index 的命令只在一次性实验仓库执行。先固定当前工作树和实际 index 路径：

~~~bash
git status --short --branch
git rev-parse --path-format=absolute --git-path index
git update-index --show-index-version
git ls-files --stage --full-name | sed -n '1,20p'
~~~

`status` 通常可能刷新 index 的 stat 信息；需要减少可选写锁时可使用 `git --no-optional-locks status --porcelain=v1`。`update-index --show-index-version` 只报告当前磁盘格式；不要为了观察而附带 `--index-version`，后者会重写 index。

读完本章后，应能解释普通 stage 0 条目的 mode、OID、path 和 stat cache，区分 index 与 tree 对象，读取冲突 stage 1/2/3，判断缺失 stage 的路径冲突，说明 index 文件、锁、扩展和替代 index 的边界，并验证 sparse-directory 表示不会改变候选 tree。

## 普通 index 按路径指向对象

`git ls-files --stage` 的每条普通记录形状是：

~~~text
<mode> <object-id> <stage><TAB><path>
~~~

真实输出中的 OID 长度取决于仓库对象格式。Stage 0 表示该路径已经有唯一的下一次提交候选：

~~~bash
git ls-files --stage -- README.md
git cat-file -t "$(git rev-parse ':README.md')"
git show :README.md
~~~

第二条预期输出 `blob`，第三条读取 index 中的字节，不读取工作区。路径包含冒号、换行或其他特殊字节时，不要把 `:path` 拼进脚本；使用 `git ls-files -z --stage` 取得 mode、OID、stage 和 NUL 终止路径，再按 OID 调用 `cat-file`。

条目的主要逻辑字段包括：

| 字段 | 作用 | 不代表什么 |
| --- | --- | --- |
| path | 下一棵 tree 中的路径 | 工作区一定存在同名文件 |
| mode | Git 支持的文件类型与可执行位 | 完整 POSIX 权限、ACL 或所有者 |
| OID | blob 或 gitlink 等目标对象 | 工作区当前字节一定相同 |
| stage | 普通候选或冲突候选编号 | 业务已经批准该内容 |
| flags | intent-to-add、skip-worktree 等状态 | 忽略、安全或访问控制策略 |
| stat data | ctime、mtime、size、inode 等快速比较信息 | 内容身份或可信时间证据 |

Index 按 Git 的路径排序规则组织条目。文件名区分大小写和 Unicode 的实际行为还受文件系统、`core.ignoreCase`、平台规范化及远端约束影响；不能用当前机器能创建两个路径证明其他环境也能可靠检出。

## Mode 只保存 Git 需要的文件语义

常见 index mode：

| Mode | 含义 |
| --- | --- |
| `100644` | 普通非可执行文件 |
| `100755` | 普通可执行文件 |
| `120000` | 符号链接，blob 保存链接目标文本 |
| `160000` | submodule gitlink，OID 指向另一个仓库的 commit |
| `040000` | tree；普通完整 index 不用它表示文件，sparse-index 可用作 sparse-directory entry |

Git 不在 tree/index 中保存一般文件的读、写权限位、用户、组、ACL、扩展属性或创建时间。`core.fileMode` 会影响工作区可执行位变化是否被检测；它不改变历史中已有 mode，也不证明运行环境权限正确。

查看路径 mode 时使用 index/tree API：

~~~bash
git ls-files --stage -- path/to/file
git ls-tree HEAD -- path/to/file
~~~

符号链接在不支持或禁用 symlink 的工作区中可能表现为普通文件，submodule 工作区也可能缺失或停在另一个 commit。Index mode 与外部工作区状态要分别核对。

## `git add` 同时处理内容和路径条目

对普通文件执行：

~~~bash
git add -- path/to/file
~~~

Git 读取工作区字节，按当前 attributes 和 clean filter 生成 blob，需要时写入对象数据库，再用 blob OID、mode、stage 0 和 stat 信息更新 index。文件没有被“移动到暂存区”，工作区仍可继续编辑。

暂存后再次修改会形成三份不同内容：

~~~bash
git show HEAD:path/to/file
git show :path/to/file
git hash-object --path=path/to/file path/to/file
~~~

第一条读取历史 tree，第二条读取 index，第三条按该路径的属性/filter 计算当前工作区内容将得到的 OID，但不带 `-w` 时不要求写对象。过滤器可能执行外部程序或失败；在不受信任仓库中先检查 attributes、filter 配置和执行边界。

`git add -N` 创建 intent-to-add 状态，让 diff 显示计划新增的路径，但还没有把工作区最终内容作为正常提交候选。脚本不能只看到 stage 0 路径就断言其 blob 已完成审查，应同时读取状态、flags、OID 和 staged diff。

未跟踪文件没有 index 条目。忽略规则只影响 Git 如何发现未跟踪路径，不会从 index 移除已跟踪路径，也不会阻止秘密被显式 `add -f`。

## Index 可以物化为 tree，但本身不是 tree 对象

在没有未合并条目的仓库中：

~~~bash
tree_oid="$(git write-tree)"
git cat-file -t "$tree_oid"
git ls-tree -r "$tree_oid"
~~~

`write-tree` 根据 index 路径、mode 和 OID 构造所需 tree 对象，成功输出根 tree OID。它可能向对象数据库写 tree，但不创建 commit、不移动 `HEAD`、不清理工作区。若 index 与 `HEAD` 完全一致，结果通常等于 `HEAD^{tree}`。

`git commit` 以这棵 tree 作为提交快照，再加入父提交、身份、时间和说明生成 commit 对象。工作区中未进入 index 的变化不在该 tree 中。

可以用替代 index 构造 tree，而不触碰当前工作树的主 index：

~~~bash
alternate_index="$(mktemp "${TMPDIR:-/tmp}/git-index.XXXXXX")"
rm -- "$alternate_index"
GIT_INDEX_FILE="$alternate_index" git read-tree HEAD
GIT_INDEX_FILE="$alternate_index" git write-tree
~~~

`mktemp` 先占用文件，而 `read-tree` 需要创建合法 index，所以示例在确认精确临时路径后删除空文件。`GIT_INDEX_FILE` 只影响该进程及子进程；路径应位于权限受控目录，完成后按证据策略清理。Hook、构建脚本或 CI 若继承了未知的 `GIT_INDEX_FILE`，可能审查一份 index 却提交另一棵 tree，运行前应记录和限制环境。

## Stat cache 是性能提示，不是内容身份

`git ls-files --debug` 可展示 entry 的 ctime、mtime、device、inode、size 和 flags。Git 用这些信息快速判断工作区文件是否可能没变；需要确认时仍会读取内容并计算 blob 身份。

~~~bash
git ls-files --debug -- path/to/file
git update-index --refresh
~~~

`--refresh` 重新匹配工作区 stat 信息，可能写 index 并取得锁，不把工作区新内容暂存成新的 blob。文件系统时间精度、时间倒退、复制工具和并发写入可能让 stat 信息可疑，Git 有 racy-clean 等保护路径；外部工具不能自行比较 mtime/size 后就宣布内容一致。

需要内容证据时比较 blob OID 或字节：

~~~bash
index_oid="$(git rev-parse ':path/to/file')"
worktree_oid="$(git hash-object --path=path/to/file path/to/file)"
printf 'index=%s\nworktree=%s\n' "$index_oid" "$worktree_oid"
~~~

执行位置、attributes 和 filter 配置会影响 `--path` 的解释。二者 OID 相等只证明规范 blob 输入相同，不证明路径 mode、外部 LFS payload 或业务行为相同。

## Index 格式与扩展可以重写

Git index 的磁盘格式包含头、按路径排列的 entries、可选扩展和尾部校验。当前常见格式版本为 2、3、4；版本 4 对路径前缀做压缩，版本 3 支持额外 flags。仓库对象格式也影响 OID 和校验长度。

查询当前版本：

~~~bash
git update-index --show-index-version
~~~

在可销毁仓库中可转换：

~~~bash
before_tree="$(git write-tree)"
git update-index --index-version 4
git update-index --show-index-version
test "$(git write-tree)" = "$before_tree"
~~~

转换属于写操作，只能在当前 Git 和所有消费工具都支持时采用。验收比较 tree、状态、特殊 mode、冲突能力和代表性工具，不以文件变小作为正确性证明。

常见扩展用于缓存 tree、保留 resolve-undo、拆分共享 index、untracked cache 或 fsmonitor 信息。扩展可能由普通 Git 命令自动增加、丢弃或重建。第三方工具应使用 Git 库或完整格式规范，不能按固定偏移手拆 `.git/index`。

Split index 会把共享主体放入 `sharedindex.<hash>`，当前 index 只保存差异；linked worktree 则各自拥有不同 index 路径。清理 `.git/index` 或 `sharedindex.*` 可能丢失已暂存但未提交的选择，不能当作通用修复。

## 写入通过 lockfile 和替换完成

Git 更新 index 时通常创建实际 index 路径旁的 `index.lock`，写完并校验后原子替换目标。查询真实路径：

~~~bash
git rev-parse --path-format=absolute --git-path index
git rev-parse --path-format=absolute --git-path index.lock
~~~

出现 `index.lock` 错误时，先确认活跃 writer、进程命令、工作树、锁路径、时间和底层文件系统。直接删除锁可能让两个 writer 同时覆盖，也可能毁掉事故证据。只有证明 owner 已退出、精确锁文件属于残留且已保存 index/工作区后，才按[仓库损坏、锁文件与并发操作](../part-13/08-repository-corruption-locks-concurrency.md)处理。

Index 不是备份。它通常只有当前候选和有限冲突/恢复辅助信息，没有分支历史，也不传输到远端。需要保留复杂暂存选择时，先保存工作区字节、`git diff --staged --binary`、未暂存 diff、未跟踪文件清单和 index 副本，再做恢复操作。

## 冲突时同一路径可以有多个 stage

普通状态下路径只有 stage 0。三方合并无法形成唯一结果时，index 用非零 stage 保存候选：

| Stage | 普通 `git merge topic` 中的输入 | 常用读取 |
| --- | --- | --- |
| 1 | merge base 中的路径 | `git show :1:path` |
| 2 | `HEAD`，当前接收分支中的路径 | `git show :2:path` |
| 3 | `MERGE_HEAD`，被合入提交中的路径 | `git show :3:path` |

机器采集使用：

~~~bash
git ls-files -z --unmerged > /restricted/evidence/unmerged.index.z
git diff --name-status --diff-filter=U
git status --short
~~~

输出文件含内部路径和 OID，应写入权限受控的证据目录。`ls-files --unmerged` 只列非零 stages，不修改现场。工作区冲突标记是由这些输入生成的编辑视图，不是权威备份；二进制、modify/delete、rename 或目录冲突可能没有文本标记。

并非每个冲突路径都有三条记录：

- add/add 在 base 中没有路径，通常只有 stage 2 和 3；
- modify/delete 会缺少删除一侧的 stage；
- rename 冲突可能让候选分布在旧路径和新路径；
- submodule 冲突的 `160000` 条目保存 gitlink commit，不保存子仓库文件。

`write-tree` 和普通 commit 会拒绝仍含非零 stage 的 index。形成最终工作区内容后，`git add -- path` 会删除该路径的 stage 1/2/3 并写入唯一 stage 0；选择删除时使用经过审查的 `git rm -- path`。这只表示结构上已经选择结果，仍需检查 staged diff、mode、attributes、测试和业务约束。

Rebase 会把待重放 commit 应用到已经检出的新基线上，冲突命令中的 ours/theirs 常与“我的功能分支”直觉相反。记录 `HEAD`、rebase 状态和正在重放的 commit，按 OID 读取 stage，不凭标签选择整边。

`git update-index --index-info`、`--cacheinfo` 能直接构造 entries，适合受控 plumbing 和测试。它们可以绕过工作区读取并指向已有对象，误用会制造与磁盘内容完全不同的提交候选；日常冲突解决使用 `add`、`rm` 和对应的 continue/abort 状态机。

## Sparse-index 用 tree 条目压缩未展开目录

Sparse-checkout 决定哪些 tracked paths 出现在工作区。完整 index 即使带 skip-worktree 标志，仍可逐文件记录整个候选 tree；sparse-index 则把完全位于稀疏范围外的目录折叠为一个 stage 0、mode `040000`、OID 指向 tree 的 sparse-directory entry。

在已启用 cone-mode sparse-checkout 的可恢复副本中：

~~~bash
git sparse-checkout reapply --sparse-index
git config --get index.sparse
git ls-files --sparse --stage
~~~

`ls-files --sparse` 显示折叠目录；不带该选项的命令可能为兼容性展开显示。Sparse-directory 不是准备提交一个“目录文件”，它代表候选 tree 中一整棵已有子树。范围外文件没有出现在工作区，不表示从 commit 或 index 语义中删除。

关闭表示优化：

~~~bash
before_tree="$(git write-tree)"
git sparse-checkout reapply --no-sparse-index
test "$(git write-tree)" = "$before_tree"
~~~

`--no-sparse-index` 把折叠目录展开为逐路径 entries，通常不会把范围外文件写回工作区；`sparse-checkout disable` 才会尝试展开全部 tracked paths。两者都可能写 index 并触发大量工作，低磁盘、LFS/filter、未提交修改或冲突现场需要先停下评估。

Git 命令可能按需展开 sparse-index，第三方 IDE、语言服务器、归档器和自写解析器未必兼容。生产采用要验证候选 tree、路径 diff、构建输入闭包、工具版本、失败回退和性能收益。第九篇的[稀疏与部分工作流](../part-09/04-sparse-partial-workflows.md)负责工作流决策，本章只定义 index 表示。

## `assume-unchanged` 和 `skip-worktree` 不是忽略规则

`assume-unchanged` 是工作区文件预计不变化的性能提示。Git 仍可在某些操作中检查或覆盖该路径，不应依赖它隐藏本地配置修改。`skip-worktree` 表示工作区内容可以缺席，主要服务 sparse-checkout；用户在范围外创建/修改路径时，Git 可能清除标志或拒绝稀疏操作以保护内容。

观察标志可使用：

~~~bash
git ls-files -v -- path/to/file
git ls-files -t -- path/to/file
git sparse-checkout list
~~~

字母标签会受选项与 Git 版本影响，脚本应同时记录配置和 index 语义。不要用：

~~~bash
git update-index --assume-unchanged local.conf
~~~

代替 `.gitignore`、模板配置、加密或秘密管理。已跟踪的 `local.conf` 仍在 commit tree 中，也可能被 merge、checkout 和 reset 更新。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| staged diff 与工作区不同 | stage 0 OID、工作区 hash、attributes/filter | 明确要提交哪一版，再按路径 `add` 或恢复 |
| `write-tree` 报 unmerged | `ls-files -u -z`、操作状态、冲突类型 | 继续逐路径解决或执行对应 abort，不手改 index |
| 某冲突路径少于三个 stage | add/delete/rename/submodule 语义、各 stage mode/OID/path | 按实际候选解释，不能生成假的 base |
| `index.lock` 已存在 | writer、真实 index 路径、worktree 和文件系统 | 先排除活跃写入，再按残留锁流程处理 |
| 删除 index 后暂存选择消失 | index 副本、staged diff、工作区和对象 | 从证据重建，不用 `add -A` 猜原选择 |
| sparse-index 工具报未知 entry | Git/工具版本、`index.sparse`、sparse rules | 在副本展开 index，验证 tree 与工作流不变 |
| sparse 范围外文件意外出现 | skip-worktree 标志、本地修改、规则和 reapply 输出 | 保护字节，决定扩大范围或恢复规则，不强删 |
| 替代 index 生成了错误 tree | `GIT_INDEX_FILE`、主/替代 index 摘要和 tree OID | 停止 commit，保留两份 index 并重新构造 |
| mode 在平台间变化 | `core.fileMode`、symlink 支持、tree/index mode | 以候选 tree 验证，修正平台配置后重新暂存 |

Index 损坏、对象缺失和工作区丢失是三类问题。先复制现场并验证对象可读性；不要把 `git reset --hard`、删除 index 或重新 clone 当作统一修复。

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-index-internals.sh
~~~

实验验证普通 stage 0 的 mode/OID/path、可执行文件与 symlink、index version 4 转换前后 tree 不变、暂存后继续编辑形成不同 blob、替代 index 与主 index 隔离。随后制造 content/content 和 add/add 冲突，断言 stage 1/2/3 的对象内容、缺失 base、`write-tree` 拒绝和 `git add` 收束为 stage 0。

最后启用 cone-mode sparse-index，检查 `040000` sparse-directory entries，展开为完整 index 后继续得到同一候选 tree，工作区仍保持稀疏。实验只操作临时目录，不测试大型仓库性能、IDE 兼容、LFS 服务、恶意 filter、真实文件系统故障或生产锁恢复。

## 小结

Index 按路径保存下一棵 tree 的 mode、OID 和 stage，并用 stat cache 与扩展加速工作区操作。普通路径只有 stage 0，冲突路径可暂存多个输入，sparse-index 还能用 tree OID 折叠未展开目录。所有表示都要以最终 `write-tree`、对象和工作流结果验收；直接解析、删除或无条件重建 index 会绕过它承担的候选与恢复信息。

## 资料

- [gitformat-index](https://git-scm.com/docs/gitformat-index)
- [git-ls-files](https://git-scm.com/docs/git-ls-files)
- [git-update-index](https://git-scm.com/docs/git-update-index)
- [git-read-tree](https://git-scm.com/docs/git-read-tree)
- [git-write-tree](https://git-scm.com/docs/git-write-tree)
- [git-add](https://git-scm.com/docs/git-add)
- [git-sparse-checkout](https://git-scm.com/docs/git-sparse-checkout)
- [gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)
