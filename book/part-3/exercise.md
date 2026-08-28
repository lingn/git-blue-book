# 综合场景：功能开发中插入紧急修复

功能文档做到一半时，主线发现一个需要马上修正的说明错误。你要保存功能分支的可解释节点，先在 main 上完成修复并标记版本，再让功能分支获得修复，最后把功能合回主线。

本练习只组合第三篇的本地 Git 行为。它不模拟代码托管平台的合并请求、审批、CI、制品或部署。

## 练习边界

- 执行位置：新建的 git-branch-flow-lab 仓库根目录；
- 前置条件：Git 2.28 或更高版本、Bash、可写目录；
- 身份：只写当前仓库的合成身份，不改全局配置；
- 网络：不设置 remote，不执行 push；
- 安全：文件内容是文档字符串，不替换成真实配置、凭据或生产分支；
- 完成标准：main 最终包含紧急修复、功能文档和发布标签，提交图与父关系可解释。

如果目录已存在，换一个名字。不要通过删除未知仓库来重置练习。

## 1. 建立基线

~~~bash
mkdir git-branch-flow-lab
cd git-branch-flow-lab
git init --initial-branch=main
git config --local user.name "Git Blue Book Branch Lab"
git config --local user.email "branch@example.invalid"
printf '# Git Practice Lab\n\nSetup instructions are maintained here.\n' > README.md
git add -- README.md
git diff --staged --check
git commit -m "docs: initialize branch flow lab"
base="$(git rev-parse HEAD)"
git status --short --branch
~~~

预期当前分支为 main，工作区干净，base 是一个有提交的完整 OID。若身份、权限或 hook 导致提交失败，先记录错误和 status，修复当前仓库配置后重新审查，不使用 no-verify 绕过未知门禁。

## 2. 保存功能分支节点

创建功能分支并提交一份尚未完成但可解释的草稿：

~~~bash
git switch --create feature/search-help
printf '# Search help\n\nThis draft explains the search command.\n' > SEARCH.md
git add -- SEARCH.md
git diff --staged --check
git commit -m "docs: add search help draft"
feature_draft="$(git rev-parse HEAD)"
git merge-base --is-ancestor "$base" "$feature_draft"
~~~

feature_draft 应包含 base。这里的“可解释”意味着提交说明和文件内容能让同事知道当前意图，不代表功能已经通过完整评审。

## 3. 主线处理紧急修复

切回 main 前确认没有工作区变化：

~~~bash
git status --short --branch
git switch main
git rev-parse HEAD
~~~

修正 README 中的说明并提交：

~~~bash
printf '# Git Practice Lab\n\nRun setup checks before using the search command.\n' > README.md
git add -- README.md
git diff --staged --check
git commit -m "fix: correct setup instruction"
fix_tip="$(git rev-parse HEAD)"
~~~

确认修复提交只在 main 先出现：

~~~bash
test "$(git rev-parse main)" = "$fix_tip"
test "$(git rev-parse feature/search-help)" = "$feature_draft"
git merge-base --is-ancestor "$feature_draft" main
~~~

最后一条应以非零状态结束，因为功能分支没有包含紧急修复。脚本中不要用 set -e 直接吞掉这个预期的 1；交互练习只需记录它的含义。

## 4. 给修复节点命名

在确认候选提交、工作区和主线历史后创建附注标签：

~~~bash
git status --short --branch
git show --no-patch --format='%H%n%P%n%T%n%s' "$fix_tip"
git tag -a v0.1.1 -m "Correct setup instruction" "$fix_tip"
git cat-file -t v0.1.1
git rev-parse v0.1.1^{commit}
~~~

cat-file 应输出 tag，^{commit} 应解析为 fix_tip。标签只在本地，当前没有远端发布事实。不要把本地 tag 写成已发布版本，也不要在共享后用 tag -f 移动同名版本。

## 5. 让功能分支取得修复

切到功能分支，在接收方执行 merge：

~~~bash
git switch feature/search-help
git merge main
~~~

此时两边的差异在不同文件或不同位置，通常可以自动合并。验证：

~~~bash
git status --short --branch
git merge-base --is-ancestor "$fix_tip" feature/search-help
git show --no-patch --format='%H%n%P%n%T%n%s' HEAD
~~~

如果出现冲突，不要跳过解决流程。先记录 HEAD、MERGE_HEAD、merge-base 和 unmerged paths，再逐路径决定、add、测试或 merge --abort。冲突处理以第七、八章为准。

继续完善 SEARCH.md：

~~~bash
printf '\nAdd examples for empty and quoted queries.\n' >> SEARCH.md
git add -- SEARCH.md
git diff --staged --check
git commit -m "docs: complete search help"
feature_tip="$(git rev-parse HEAD)"
~~~

feature/search-help 现在包含 base、fix_tip 和最终功能提交，顺序要通过祖先关系而不是提交日期验证。

## 6. 合回 main

站在接收方 main：

~~~bash
git switch main
git status --short --branch
git merge --ff-only feature/search-help
~~~

因为 feature/search-help 已经包含当前 main，且 main 没有继续独立前进，这次应快进。验证：

~~~bash
git rev-parse main
git rev-parse feature/search-help
git rev-list --parents -n 1 main
git status --short --branch
git show v0.1.1 --no-patch
~~~

main 和 feature/search-help 应指向同一提交。最终 main 的最新提交通常是功能提交，v0.1.1 仍稳定指向修复提交，而不会随着分支合并移动。

## 7. 从提交图验收

保存引用、父关系和路径证据：

~~~bash
git log --graph --decorate --oneline --all
git for-each-ref --format='%(refname) %(objectname) %(objecttype)'
git merge-base --is-ancestor "$fix_tip" main
git merge-base --is-ancestor "$feature_draft" main
git show "$fix_tip":README.md
git show main:SEARCH.md
~~~

应能证明：

1. fix_tip 是 main 上独立的紧急修复提交；
2. v0.1.1 的 target commit 是 fix_tip；
3. 功能分支获取了 fix_tip 后才完成最终文档；
4. main 最终可达修复和功能提交；
5. 标签引用没有因后续提交自动移动。

如果只看当前文件，无法证明第 1、2、3 项。若只看 log，又无法证明最终 tree 中的具体内容。

## 8. 处理失败和恢复

| 现象 | 先收集 | 恢复 |
| --- | --- | --- |
| switch 被拒绝 | status、工作区/index diff、目标 tree | 提交、stash 或独立 worktree 后重试 |
| merge 方向错了 | branch --show-current、两端 OID | 若仍进行中则 abort，重新站到接收方 |
| ff-only 拒绝 | main、功能分支、merge-base | 先把主线同步到功能分支，或按团队策略创建 merge commit |
| 标签已存在 | tag object、target commit、发布清单 | 停止覆盖，确认是否应创建新版本号 |
| 功能分支仍不包含修复 | merge-base --is-ancestor、log --graph | 在功能分支合入 main，再重新审查 |
| 合并后测试失败 | merge tip、父提交、最终 tree、测试 | 追加修正或按共享边界 revert，不移动已共享标签 |

不要使用 switch -f、branch -D、tag -f 或 reset --hard 来让练习“通过”。这些命令会减少恢复入口，真实项目中还可能破坏协作者的引用。

## 本练习的验收边界

本练习只证明本地分支、HEAD、快进、祖先关系和标签对象。它不证明：

- 远程平台已创建或接受合并请求；
- 审批、必需检查和合并队列已经通过；
- v0.1.1 制品已构建或部署；
- 任何作者、签名者和远程认证主体已被验证；
- 删除功能分支后外部平台数据仍按组织制度保留。

需要这些事实时，保存 Git OID 后到对应远程、CI、制品和运行系统取证。

## 小结

紧急修复插入功能开发的关键是保存每一个接收方和候选 OID：先让功能草稿成为可追踪节点，再在 main 上修复和标记，接着把修复合入功能分支，最后在 main 上快进合回。提交图、父列表、标签 target 和最终 tree 一起构成验收证据。
