# 完整处理一次冲突：从现场记录到可验证提交

这一章用同一个文档标题制造两次冲突。第一次只观察并中止，第二次根据双方意图形成新的最终标题。重点不是记住冲突标记，而是练习一套可以在代码、配置和数据库迁移中复用的流程。

## 练习边界

- 执行位置：临时练习仓库根目录；
- 前置条件：Git 2.28 或更高版本、Bash、可写临时目录；
- 身份：仅在仓库 local 配置合成姓名和邮箱；
- 网络：不设置 remote，不访问平台；
- 状态：每次 merge 前保持工作区和 index 干净；
- 安全：只用文档字符串，不放真实密钥或生产配置。

如果沿用已有仓库，先确认其中没有需要保留的未提交工作。更稳妥的做法是创建新目录，不要把下列命令直接复制到生产项目。

## 1. 创建共同祖先和功能分支

先建立最小基线：

~~~bash
mkdir git-conflict-lab
cd git-conflict-lab
git init --initial-branch=main
git config --local user.name "Git Blue Book Conflict Lab"
git config --local user.email "conflict@example.invalid"
printf '# Git Practice Lab\n' > README.md
git add -- README.md
git commit -m "docs: initialize conflict lab"
git rev-parse --verify HEAD^{commit}
~~~

成功后当前分支是 main，README.md 已进入第一条提交。保存基线 OID：

~~~bash
base="$(git rev-parse HEAD)"
~~~

创建功能分支并改标题：

~~~bash
git switch --create feature/title
printf '# Git Quick Start Lab\n' > README.md
git add -- README.md
git diff --staged --check
git commit -m "docs: rename guide for quick start"
feature_tip="$(git rev-parse HEAD)"
~~~

此时 feature/title 包含 base，README.md 的第一行是 Quick Start。

切回 main，做另一种改动：

~~~bash
git switch main
printf '# Git Practice Handbook\n' > README.md
git add -- README.md
git commit -m "docs: rename guide as handbook"
main_tip="$(git rev-parse HEAD)"
git merge-base main feature/title
~~~

main 和 feature/title 从 base 分叉，两个尖端互不为祖先。先保存这三个 OID，后面用于验证 abort 没有改变历史。

## 2. 第一次合并，只取证然后中止

站在 main 上执行：

~~~bash
if git merge feature/title; then
  printf '%s\n' 'Expected a conflict, but merge succeeded.' >&2
  exit 1
fi
~~~

输出中的 CONFLICT 和文件名可能随版本变化，验收不要匹配整段文本。立即保存现场：

~~~bash
git status --short --branch
git rev-parse HEAD
git rev-parse MERGE_HEAD
git diff --name-status --diff-filter=U
git ls-files --unmerged
git diff -- README.md
~~~

预期 README.md 处于 UU，MERGE_HEAD 指向 feature_tip，index 中存在未合并候选。工作区可能包含：

~~~text
&lt;&lt;&lt;&lt;&lt;&lt;&lt; HEAD
# Git Practice Handbook
&#61;&#61;&#61;&#61;&#61;&#61;&#61;
# Git Quick Start Lab
&gt;&gt;&gt;&gt;&gt;&gt;&gt; feature/title
~~~

如果 Git 版本使用不同冲突样式，标记周围的上下文可能不同，但两侧内容应来自 main_tip 和 feature_tip。不要在这一步编辑文件，先保存原始冲突文本和命令错误。

现在判断这次合并是否应该继续。本练习选择中止：

~~~bash
git merge --abort
test "$(git rev-parse HEAD)" = "$main_tip"
test -z "$(git status --short)"
test ! -e .git/MERGE_HEAD
~~~

abort 会尝试恢复 merge 开始前的 HEAD、index、工作区和状态文件。它不是“选择 ours”，也不是把两个提交删除。feature/title 和 main 的提交仍可达：

~~~bash
git merge-base --is-ancestor "$base" main
git merge-base --is-ancestor "$base" feature/title
~~~

若 abort 后状态不干净，先比较合并前的保存记录和当前 diff。合并前已有未提交内容、自动暂存或外部程序修改时，Git 不保证能无损重建现场；此时从保存副本或独立 worktree 恢复，不要继续执行强制切换。

## 3. 第二次合并，先理解两侧再编辑

再次执行：

~~~bash
git merge feature/title
~~~

仍应进入冲突状态。对冲突路径，先回答：

| 输入 | 本练习的事实 |
| --- | --- |
| merge-base | base 中的标题是 Git Practice Lab |
| ours | main_tip 把标题改成 Git Practice Handbook |
| theirs | feature_tip 把标题改成 Git Quick Start Lab |
| 最终目标 | 同时表达练习用途和快速开始入口 |

这里没有一个由 Git 自动推导的“正确字符串”。本练习决定写成：

~~~markdown
# Git Quick Start Practice
~~~

这个结果是一个新的业务选择，不等于自动选择上半段或下半段。真实代码冲突时，最终选择应来自接口契约、数据兼容、运行指标和责任人确认。

## 4. 写入最终结果并标记路径

只编辑冲突文件 README.md，删除冲突标记，写入决定后的内容：

~~~bash
printf '# Git Quick Start Practice\n' > README.md
git diff -- README.md
git add -- README.md
git status --short --branch
git ls-files --unmerged
~~~

git add 在冲突路径上的作用有两层：把最终工作区内容写入 index，并移除该路径的 stages 1/2/3，建立 stage 0。它不等于业务审批，也不等于测试通过。

确认暂存内容：

~~~bash
git diff --staged --check
git diff --staged -- README.md
~~~

如果仍有其他冲突路径，ls-files --unmerged 仍会输出它们。不能只因为 README.md 已经变成 stage 0 就完成整个 merge。

## 5. 完成合并和验证

所有冲突路径都解决后，可以提交：

~~~bash
git commit -m "merge: reconcile guide title"
~~~

某些环境也支持：

~~~bash
git merge --continue
~~~

对普通 merge，continue 可能调用编辑器或提示使用默认说明；commit 允许你明确写出本次合并意图。无论选哪一个，都要保存最终 commit 的完整字段：

~~~bash
git status --short --branch
git show --no-patch --format='%H%n%P%n%T%n%s' HEAD
git ls-files --unmerged
git diff --check
git grep -n -e '<<<<<<<' -e '=======' -e '>>>>>>>'
~~~

预期：

- status 没有未提交变化；
- ls-files --unmerged 没有输出；
- HEAD 有两个父提交，第一父为 main_tip，第二父为 feature_tip；
- README.md 的 tree 内容是 Quick Start Practice；
- grep 没有命中残留标记。

grep 的空结果不是全部验收。合法文档可以包含这些字符串，二进制、submodule 和 LFS 指针也没有普通标记。最终 tree、自动化测试和运行验证才是业务条件。

## 6. 向同事报告一次冲突

使用具体证据写报告：

~~~text
冲突路径：README.md 第一行
共同祖先：<base 的完整 OID>
当前分支：main，原标题为 Git Practice Handbook
合入分支：feature/title，原标题为 Git Quick Start Lab
最终选择：Git Quick Start Practice
验证：index 无 unmerged stages，暂存差异无空白错误，合并提交有两个父提交
~~~

如果是代码或配置，报告还应包含测试命令、数据迁移状态、部署候选和未采用方案。不要只写“已解决”。

## 7. 处理另一类冲突时不要套模板

本章是 content/content 冲突。遇到下列情况先改用复杂冲突章节：

- 一边删除、另一边修改；
- 同一文件分别重命名；
- 文件名与目录名冲突；
- 模式、符号链接、submodule 或 LFS pointer 冲突；
- index 里没有 stage 1，或工作区没有冲突标记；
- rebase/cherry-pick 进行中，操作上下文不是 MERGE_HEAD。

这些情况仍然遵循“先取证、逐路径决定、暂存、验收”，但输入和恢复动作不同。

## 失败路径和恢复

| 现象 | 首要证据 | 处理 |
| --- | --- | --- |
| merge 竟然成功 | 两端 OID、是否真正分叉、最终 parent | 记录自动结果并做业务测试，不强行制造冲突 |
| abort 后工作区有差异 | merge 前 status/diff、autostash、外部编辑 | 从保存副本恢复，避免覆盖现状 |
| git add 后仍不能提交 | ls-files --unmerged、status | 找出剩余路径逐个解决 |
| 标记删了但测试失败 | 双方提交、base、最终 tree、测试日志 | 追加修正或按共享边界 revert |
| merge --continue 失败 | hooks、提交说明、index | 修复具体错误后重试，不删除状态文件 |
| 不知道该选哪边 | 业务约束和责任人 | 暂停合并，保留现场，不用 ours/theirs 猜答案 |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-3-conflicts.sh
~~~

现有实验自动完成与本章等价的流程：创建分叉、验证合并提交、触发冲突、检查 UU 和 MERGE_HEAD、abort、重新合并、写入最终内容、创建提交并验证附注标签。它不验证真实项目业务语义、平台评审、CI 或生产回退。

## 小结

一次可恢复的冲突处理有固定顺序：确认当前分支和共同祖先，保存 HEAD、MERGE_HEAD、index stages 与差异，先决定是否继续，再按路径写入最终结果，最后同时验收结构、内容和测试。merge --abort 保留历史并取消本次尝试，git add 只表示路径选择完成，两者都不替代业务判断。
