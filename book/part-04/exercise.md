# 综合练习：功能开发期间插入主线热修复

本练习从一条稳定基线创建功能分支。功能尚未合入时，主线先完成紧急修复并打附注标签，导致两端分叉；随后集成分支用 `--ff-only` 证明不能快进，普通 merge 进入内容冲突，操作者根据两侧意图形成第三种配置，验证二父提交后再让 main 快进到集成结果。

练习只在临时仓库运行，不连接远端，不模拟平台评审、CI 或真实发布。目标是把本篇对象和状态证据连成一条可执行路径，不是提供生产热修复脚本。

## 前置条件和安全边界

- Git 2.49.0 或兼容版本，Bash 与可写 `/private/tmp`；
- 当前位于本书仓库根目录，只执行提供的隔离脚本；
- 实验身份、配置和内容均为合成值；
- trap 只删除 `mktemp` 返回的实验目录；
- 真实事故不得照抄 `reset --hard`、删分支或标签操作。

完整自动实验：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-part-04-exercise.sh
~~~

下文解释脚本中的每个状态。手工练习应新建独立临时目录，不在蓝皮书或工作项目中重复初始化。

## 1. 建立基线并固定对象

基线包含服务文件和超时配置：

~~~bash
git init --initial-branch=main "$lab_repo"
git -C "$lab_repo" config user.name 'Part 04 Exercise'
git -C "$lab_repo" config user.email 'part04@example.invalid'
printf 'service baseline\n' > "$lab_repo/service.txt"
printf 'timeout=15\n' > "$lab_repo/runtime.conf"
git -C "$lab_repo" add service.txt runtime.conf
git -C "$lab_repo" commit -m 'build: create service baseline'
base_oid="$(git -C "$lab_repo" rev-parse HEAD)"
~~~

成功后 `base_oid` 是根 commit，index/工作区干净。失败时保存 stderr 和目录，不继续创建分支。

## 2. 功能分支独立前进

~~~bash
git -C "$lab_repo" switch -c feature/retry
printf 'retry feature\n' > "$lab_repo/retry.txt"
printf 'timeout=30\n' > "$lab_repo/runtime.conf"
git -C "$lab_repo" add retry.txt runtime.conf
git -C "$lab_repo" commit -m 'feat: add retry with extended timeout'
feature_oid="$(git -C "$lab_repo" rev-parse HEAD)"
~~~

`feature_oid` 的父提交是 base。Main 仍停在 base。功能分支同时新增重试能力并把超时调到 30。

## 3. 主线插入热修复并打标签

~~~bash
git -C "$lab_repo" switch main
printf 'hotfix guard\n' > "$lab_repo/hotfix.txt"
printf 'timeout=10\n' > "$lab_repo/runtime.conf"
git -C "$lab_repo" add hotfix.txt runtime.conf
git -C "$lab_repo" commit -m 'fix: cap runtime timeout during incident'
hotfix_oid="$(git -C "$lab_repo" rev-parse HEAD)"
git -C "$lab_repo" tag -a hotfix-20260914 "$hotfix_oid" \
  -m 'Incident timeout hotfix'
~~~

热修复把超时收紧到 10，与功能分支的 30 形成语义冲突。附注标签 target 必须等于 `hotfix_oid`：

~~~bash
git -C "$lab_repo" rev-parse 'hotfix-20260914^{tag}'
test "$(git -C "$lab_repo" rev-parse 'hotfix-20260914^{}')" = "$hotfix_oid"
~~~

该标签只是本地证据，不代表已推送、已构建或已部署。

## 4. 在集成分支证明不能快进

从 hotfix 创建集成分支，保留 main 作为条件更新基线：

~~~bash
git -C "$lab_repo" switch -c integration/retry "$hotfix_oid"
if git -C "$lab_repo" merge --ff-only "$feature_oid"; then
  printf 'expected divergent histories\n' >&2
  exit 1
fi
~~~

失败后 `HEAD`、index 和工作区应保持 hotfix 状态。`rev-list --left-right --count hotfix...feature` 预期两侧各有一个独有 commit。输出由真实 OID 决定，不匹配固定哈希。

## 5. 普通 merge 停在冲突现场

~~~bash
if git -C "$lab_repo" merge --no-ff "$feature_oid"; then
  printf 'expected runtime.conf conflict\n' >&2
  exit 1
fi

git -C "$lab_repo" status --short --branch
git -C "$lab_repo" rev-parse HEAD
git -C "$lab_repo" rev-parse MERGE_HEAD
git -C "$lab_repo" ls-files --unmerged -- runtime.conf
~~~

`HEAD` 仍是 `hotfix_oid`，`MERGE_HEAD` 是 `feature_oid`。Runtime.conf 有 stage 1/2/3，内容分别为 15、10、30。Retry.txt 与 hotfix.txt 已自动形成 stage 0。

此时可以 abort 回到热修复，也可以继续。练习选择继续，但生产事故要由服务 owner 判断。

## 6. 根据两侧意图形成第三种配置

练习假设重试功能需要延长单次处理，而事故修复要求总时限不能回到 30，最终选择 20：

~~~bash
printf 'timeout=20\n' > "$lab_repo/runtime.conf"
git -C "$lab_repo" add runtime.conf
test -z "$(git -C "$lab_repo" ls-files --unmerged)"
git -C "$lab_repo" diff --staged --check
result_tree="$(git -C "$lab_repo" write-tree)"
~~~

Stage 清空只表示结构可提交。脚本进一步断言 result tree 同时包含 `retry.txt`、`hotfix.txt` 和 `timeout=20`。

## 7. 完成二父提交并验证

~~~bash
GIT_EDITOR=true git -C "$lab_repo" merge --continue
integration_oid="$(git -C "$lab_repo" rev-parse HEAD)"
git -C "$lab_repo" show --no-patch \
  --format='%H%n%P%n%T%n%s' "$integration_oid"
~~~

第一父必须是 `hotfix_oid`，第二父是 `feature_oid`，tree 等于 `result_tree`。还要确认状态干净、没有 unmerged stages，并运行代表性测试。本地脚本只能验证合成文本，不提供业务测试证明。

## 8. 条件推进 main，再清理工作分支

~~~bash
git -C "$lab_repo" switch main
test "$(git -C "$lab_repo" rev-parse HEAD)" = "$hotfix_oid"
git -C "$lab_repo" merge --ff-only integration/retry
test "$(git -C "$lab_repo" rev-parse HEAD)" = "$integration_oid"
~~~

Main 只有在仍位于 hotfix 基线且 integration 是其后代时才能快进。真实远端还需 expected-old、保护规则和合并队列。

为最终候选创建附注标签：

~~~bash
git -C "$lab_repo" tag -a candidate-2.0.0 "$integration_oid" \
  -m 'Candidate 2.0.0'
~~~

确认 main 已可达 feature 后，删除本地工作分支：

~~~bash
git -C "$lab_repo" branch -d feature/retry integration/retry
~~~

标签仍保留两个关键 OID。删除分支不删除 commit，但真实项目先核对评审、远端、制品和恢复来源。

## 失败方式与恢复

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| ff-only 意外成功 | 两端 OID、main 是否真的前进 | 接受真实图形，不制造假冲突 |
| Merge 没有冲突 | 三方 runtime.conf blob、attributes/driver | 审查自动结果并运行测试 |
| Stage 内容不是 15/10/30 | 起点、分支、工作区和 filter | Abort，重建隔离仓库，不继续猜 |
| Continue 被 hook 拒绝 | stderr、`MERGE_HEAD`、index tree | 修复门禁后重试或 abort |
| Main 无法 ff 到 integration | main current、integration 父关系 | 停止更新，调查并发或错误基线 |
| `branch -d` 拒绝 | 最终 main、祖先关系和 worktree 占用 | 保留分支，不用 `-D` 绕过 |
| 标签同名已存在 | 当前/期望 tag object 与 target | 新版本或审批处置，不强制覆盖 |

## 验收清单

实验只有同时满足以下条件才通过：

1. Base、feature、hotfix 和 integration OID 互相符合父关系；
2. ff-only 在分叉时拒绝且没有改变现场；
3. 冲突 stages 精确对应 15/10/30；
4. 最终 tree 包含功能、热修复和第三种配置；
5. Merge commit 父顺序正确；
6. Main 通过快进指向同一 integration commit；
7. 两个附注标签分别剥离到 hotfix 和最终候选；
8. 删除已合入本地分支后提交仍从 main 可达；
9. `fsck --full --strict` 和工作区状态通过。

自动检查通过仍不代表出版或生产验收。真实流程还要绑定平台评审、CI 候选、制品、数据库、部署和运行指标。

## 资料

- [git-switch](https://git-scm.com/docs/git-switch)
- [git-merge](https://git-scm.com/docs/git-merge)
- [git-ls-files](https://git-scm.com/docs/git-ls-files)
- [git-tag](https://git-scm.com/docs/git-tag)
- [git-fsck](https://git-scm.com/docs/git-fsck)
