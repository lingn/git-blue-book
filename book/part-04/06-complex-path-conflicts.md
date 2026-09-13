# 复杂路径冲突：先还原每一侧做了什么，再决定最终布局

Content/content 冲突至少会在工作区留下文本标记，路径冲突却经常只出现在 status 和 index。Add/add 没有 base 条目，modify/delete 缺少被删除一侧，rename 冲突还可能把 stages 分散在不同路径；二进制、symlink、submodule 和文件/目录冲突也不能靠编辑标记解决。

复杂冲突的任务不是“消掉红色状态”，而是确定最终 tree 中每个路径的名称、mode、OID 和外部依赖，并说明舍弃了哪一侧的什么意图。

## 进入条件与完成标准

所有制造冲突和解决命令只在临时仓库执行。真实现场先保存：

~~~bash
git version
git status --short --branch
git rev-parse 'HEAD^{commit}'
git rev-parse 'MERGE_HEAD^{commit}'
git merge-base --all HEAD MERGE_HEAD
git ls-files -z --unmerged > /restricted/evidence/unmerged.z
git diff --name-status -z --diff-filter=U > /restricted/evidence/paths.z
~~~

证据目录必须预先创建并限制权限。NUL 输出不要放进 shell 变量。命令只适用于已确认的普通 merge；没有 `MERGE_HEAD` 时先识别操作类型。

读完本章后，应能按缺失 stage 识别 add/add 与 modify/delete，解释 rename/delete、rename/rename、目录重命名和 file/directory，处理 mode/symlink、binary/LFS 和 submodule，逐路径暂存最终布局，并识别工具与文件系统边界。

## Status 短码只是入口

常见未合并码：

| 短码 | 常见含义 | 需要继续读取 |
| --- | --- | --- |
| `UU` | 两侧都修改 | stage 1/2/3、标记和语义约束 |
| `AA` | 两侧都新增同名路径 | stage 2/3，没有 stage 1 |
| `DU` | ours 删除、theirs 修改 | stage 1/3，删除理由与修改内容 |
| `UD` | ours 修改、theirs 删除 | stage 1/2，修改价值与删除理由 |
| `AU`/`UA` | 一侧新增，另一侧存在路径级冲突 | 实际 stages、路径和 tree |
| `DD` | 两侧都删除但仍有未解决路径关系 | surrounding rename/file-directory 状态 |

同一个码不能完整描述 rename 来源、新旧路径和 mode。权威输入来自 `ls-files --unmerged` 的 mode/OID/stage/path，加上 base、两侧 tree 和 Git 的 rename 诊断。

## Add/add 没有共同祖先版本

Base 中不存在 `config/new.yml`，两侧都新增它，内容不同：

~~~bash
git ls-files --unmerged -- config/new.yml
git show :2:config/new.yml
git show :3:config/new.yml
~~~

通常只有 stage 2 和 3。`git show :1:...` 失败是结构事实，不是对象丢失。要判断两份新增是否代表同一概念：

- schema、用途和 owner 是否相同；
- 是否应合并字段、选择一份或拆成两个路径；
- 运行时是否只允许一个固定文件名；
- 默认值与安全边界是否兼容；
- 哪些调用方和部署清单需要同步。

形成最终文件后只 `git add -- config/new.yml`。若决定保留两个概念，先移动到经过评审的新路径，再显式 add/rm；不要把自动改名当成业务设计。

## Modify/delete 需要判断删除是否仍成立

Base 有 `legacy.conf`，ours 删除，theirs 修改时，常见 stages 为 1 和 3：

~~~bash
git show :1:legacy.conf
git show :3:legacy.conf
~~~

选择不是简单的“文件要或不要”。可能的业务结果包括：

- 删除仍正确，theirs 的新约束已由新系统实现；
- 文件要恢复，删除方遗漏了仍在使用的调用者；
- 内容应迁移到替代路径或数据库；
- 两侧方案都过期，需要第三种实现。

最终删除使用 `git rm -- legacy.conf`；迁移则 add 新路径并确认旧路径从 index 消失。验证调用方、生成规则、部署清单和回滚，不只验证 `ls-files -u` 为空。

## Rename/delete 的 stages 可能跨路径

一侧把 `docs/guide.md` 移到 `manual/guide.md`，另一侧删除旧文件。Git 可能识别 rename/delete，并把候选放在旧、新路径的不同 stage。

先读取：

~~~bash
git status --short
git ls-files --unmerged
git diff --summary "$(git merge-base HEAD MERGE_HEAD)" HEAD
git diff --summary "$(git merge-base HEAD MERGE_HEAD)" MERGE_HEAD
~~~

保留 `manual/guide.md` 表示内容仍有价值且新位置正确；删除它表示整个概念已经淘汰。不要为了清空状态把工作区里恰好存在的文件全部 `add -A`。

最终选择新路径时，检查旧路径、链接、导航、构建输入和 owner 规则。选择删除时使用精确 `git rm`，并确认没有其他 rename 冲突仍引用相同源对象。

## Rename/rename 要确定唯一所有权

两侧把同一 base 文件分别移到不同目录时，Git 可能报告 rename/rename。最终路径不能由“哪个名字更像”决定，需要回答：

- 模块和运行 owner 属于哪里；
- import、include、路由和生成器引用哪个路径；
- 大小写、Unicode 与目标文件系统是否可表示；
- 两个新路径是否其实承载了不同概念；
- 历史追踪和发布包怎样继续发现文件。

若确实拆成两份，内容和名称都要独立审查，不能直接复制同一 blob 后声称冲突已解决。Git 后续 rename detection 仍只是相似度推断。

## 目录重命名是多条文件 rename 的推断

一侧把 `src/old/` 中已有文件移到 `src/new/`，另一侧在旧目录新增 `c.txt`。`ort` 可以推断目录迁移，并由 `merge.directoryRenames` 决定行为：

~~~bash
git config --show-origin --get merge.directoryRenames
~~~

Git 2.49.0 中可配置 `false`、`true` 或 `conflict`。当前默认与具体行为应按版本核对。`conflict` 会把新文件建议到迁移后位置并要求人工确认；这仍不是模块归属事实。

确认新文件也属于新模块后，暂存 `src/new/c.txt` 并检查 `src/old/c.txt` 不存在。若旧目录应继续存在，说明原因并检查构建图。Git 不保存空目录，也没有单独“移动目录”的对象事件。

## File/directory 冲突受路径结构约束

一侧新增文件 `docs`，另一侧新增 `docs/guide.md`，tree 不能在同一层同时让 `docs` 既是 blob 又是目录。Git 可能把一侧路径改名到临时唯一位置并留下冲突。

恢复时不要只把临时文件移回 `docs`。先决定最终结构，比如把文件改为 `docs.txt`，或把其内容合入目录内的 `docs/README.md`。检查所有调用方和跨平台大小写规则，再对最终路径 add/rm。

文件名仅大小写变化在大小写不敏感工作区可能表现不同。证据保留 tree entry 的原始字节、`core.ignoreCase`、文件系统和目标 runner；在大小写敏感的隔离环境验证最终 tree。

## Mode、symlink 与对象类型不能只比较文本

同一路径两侧可以分别成为普通文件、可执行文件或 symlink。使用：

~~~bash
git ls-files --unmerged -- path
git ls-tree HEAD -- path
git ls-tree MERGE_HEAD -- path
~~~

`100644`、`100755`、`120000` 的 mode 与 blob 内容一起决定 tree。Symlink blob 保存链接目标文本；平台禁用 symlink 时工作区可能展开为普通文件。验证目标操作系统、容器、归档和安全边界，不让链接逃出预期目录。

## 二进制和 LFS 需要选择 payload

Git 通常不能对二进制文件做有意义的行级三方合并。属性可能配置 custom merge driver，但 driver 退出 0 也只表示程序声称成功。保存两侧 blob OID、文件类型、工具版本和生成来源。

LFS 路径的 Git blob 是 pointer，真实 payload 在外部对象服务。解决指针冲突时同时验证：

~~~text
pointer blob OID
LFS oid sha256 / size
payload 实际可取性与摘要
lock/owner 状态
生成器或源文件
~~~

仅让 Git `fsck` 通过不能证明 LFS payload 存在。无法取得必要对象时状态应为 inconclusive，不提交一个手工拼出的 pointer。

## Submodule 冲突处理的是 gitlink commit

Submodule 在父仓库 index 中使用 mode `160000`，OID 指向子仓库 commit。冲突 stages 保存的是不同 gitlink OID，不包含子仓库文件。

选择前在可信子仓库验证：

- 两个候选 commit 是否可取得；
- 一方是否为另一方祖先；
- 是否需要在子仓库先合并并发布第三个 commit；
- 父仓库 CI 能否按最终 gitlink 递归检出；
- `.gitmodules` URL 和权限是否同步变化。

先发布子仓库 commit，再更新父仓库 gitlink。父仓库 `git add submodule-path` 只记录当前子仓库 `HEAD`，不会自动发布对象。

## 逐路径解决，不扩大暂存范围

每个冲突建立记录：base、ours、theirs 的 mode/OID/path，双方意图，最终路径与对象，验证者和测试。形成结果后使用精确动作：

~~~bash
git add -- final/path
git rm -- obsolete/path
git ls-files --unmerged
git diff --staged --check
git diff --staged
~~~

`git add -A` 会同时纳入无关修改和未跟踪文件，不适合作为真实复杂冲突的默认收尾。所有 unmerged entries 消失只满足结构条件；还要核对最终 tree、两父 diff、构建输入和业务测试。

生成文件冲突优先在确定源文件与生成器版本后重新生成。不要手工拼接压缩、lockfile 或机器输出；生成命令、依赖摘要和可重复性属于验证证据。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| 某路径少于三个 stage | add/delete/rename/type 语义 | 按真实 entries 解释，不制造缺失 base |
| Rename 未被识别 | 两侧 tree、相似度、候选规模和配置 | 在副本调整检测并审查，不全局强制 |
| 目录新文件被建议移动 | directoryRenames、模块归属和构建图 | 人工确认最终路径，不盲目接受 |
| 大小写路径在本机消失 | tree entries、文件系统和 `core.ignoreCase` | 在兼容环境重建工作区，不改 tree 猜测 |
| Binary driver 返回成功但文件损坏 | driver 来源、两侧 OID、结果摘要和格式校验 | 阻止提交，恢复 payload 后重新生成 |
| LFS pointer 存在但 payload 缺失 | pointer、oid/size、LFS 服务和权限 | 取得并校验 payload，不能只看 Git 状态 |
| Submodule 无法检出最终 OID | gitlink、子仓 refs、发布顺序和 URL | 先发布依赖 commit，再更新父仓 |
| `add -A` 带入无关文件 | staged diff、未跟踪清单和秘密扫描 | 不提交，按路径恢复 index 并重新选择 |

无法判断业务归属时保留 merge 状态或在证据完整后 abort，不用 `ours`/`theirs` 消除等待。已共享错误结果按恢复流程追加修复或 revert。

## 隔离实验

运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-ort-path-conflicts.sh
TMPDIR=/private/tmp ./scripts/verify-complex-conflicts-rerere.sh
~~~

第一组验证 add/add 只有 stage 2/3，ours 删除/theirs 修改只有 stage 1/3，并保留两侧真实 blob。第二组验证 rename/delete 与目录重命名建议，形成最终路径后检查 tree。

实验使用普通 ASCII 路径和本地 Git 2.49.0，不模拟大小写/Unicode 文件系统、真实 binary driver、LFS API、submodule 远端、IDE 合并工具或大规模 rename 性能。

## 小结

复杂路径冲突要从 mode、OID、stage 和 path 还原三方事实。缺失 stage 通常来自 add/delete 语义，rename 与目录迁移来自推断；二进制、LFS 和 submodule 还跨出普通 blob。最终验收对象是完整 tree、外部 payload、调用方和业务行为，不是状态颜色消失。

## 资料

- [git-merge](https://git-scm.com/docs/git-merge)
- [merge strategies](https://git-scm.com/docs/merge-strategies)
- [git-ls-files](https://git-scm.com/docs/git-ls-files)
- [git-diff](https://git-scm.com/docs/git-diff)
- [git-config](https://git-scm.com/docs/git-config)
- [gitattributes](https://git-scm.com/docs/gitattributes)
- [git-submodule](https://git-scm.com/docs/git-submodule)
