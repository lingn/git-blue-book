# 补充最近一次本地提交：amend 会生成替代对象

刚提交后发现漏了同一任务的一份测试或文档，是 amend 最常见的使用场景。它不是在旧提交后追加附件，而是用当前 index 生成一个新的 commit，当前分支从旧 OID 移到新 OID。

## 进入条件与完成标准

在最近一次提交的本地分支根目录执行。只有在明确该提交尚未被协作者、评审、CI、制品或部署引用时，才按本章直接 amend。开始前保存：

~~~bash
git status --short --branch --untracked-files=all
git show --no-patch --format=fuller HEAD
git rev-parse HEAD
git reflog -1
~~~

如果最近提交已经共享，优先追加修正提交，或按团队批准使用新的历史治理流程。不要为了少一条提交而破坏共享坐标。

读完本章后，你应能：

- 判断遗漏内容是否属于最近提交的同一意图；
- 只把明确的 index 内容纳入 amend；
- 证明旧/新 OID、父提交和最终 tree 的变化；
- 处理提交 hook、空提交和身份错误；
- 在 amend 后用 recovery ref 或 reflog 找回旧提交；
- 区分私有历史整理与共享历史修正。

## amend 读取 index，不读取全部工作区

假设最近提交为 B，当前工作区有遗漏测试：

~~~text
A <- B
       ^
      HEAD
工作区：增加 tests/payment.txt
index：  未暂存
~~~

先完成遗漏内容并审查：

~~~bash
git add -- tests/payment.txt
git diff --staged --check
git diff --staged -- tests/payment.txt
git diff -- tests/payment.txt
~~~

工作区中其他未暂存修改不会自动进入 amend。确认 staged diff 只有本次补充后：

~~~bash
old_tip="$(git rev-parse HEAD)"
git commit --amend --no-edit
new_tip="$(git rev-parse HEAD)"
printf 'old=%s\nnew=%s\n' "$old_tip" "$new_tip"
~~~

--no-edit 保留原说明。成功后，当前分支指向 new_tip，old_tip 的父提交通常与 new_tip 相同，但 commit OID 因 tree、提交者时间、签名或其他字段变化而不同。

## 验证替代提交

~~~bash
git status --short --branch --untracked-files=all
git show --no-patch --format='%H%n%P%n%T%n%an%n%ae%n%cn%n%ce%n%s' HEAD
git diff-tree --no-commit-id --name-status -r HEAD
git show HEAD:tests/payment.txt
git reflog -2
~~~

验证：

- 工作区没有意外未暂存内容；
- new_tip 的父提交仍是原 B 的父提交；
- 漏掉的路径进入新 tree；
- 提交说明没有被意外改变；
- old_tip 仍能通过 recovery ref 或 reflog 解析。

只比较文件内容不够。作者、提交者、签名和时间字段也可能影响 OID，发布和评审系统若引用旧 OID，需要重新绑定。

## 先建立恢复引用

amend 前可以建立一个本地恢复入口：

~~~bash
old_tip="$(git rev-parse HEAD)"
git branch recovery/before-amend "$old_tip"
git show --no-patch --format=fuller recovery/before-amend
~~~

恢复分支只增加一个 ref，不复制对象。它让旧提交继续可达，即使当前工作分支已经移动。长期重要历史还应导出 bundle 或由团队备份系统保存。

如果 amend 之后发现遗漏内容不应进入，先不要再次 amend。比较：

~~~bash
git diff recovery/before-amend..HEAD
git show --stat recovery/before-amend
git show --stat HEAD
~~~

然后按私有/共享边界决定重建或追加修正。

## 说明也要修改时

如果遗漏内容正确，但提交说明需要更新：

~~~bash
git commit --amend -m "fix: add payment retry test"
~~~

这会同时改变提交说明和 OID。不要为了只改说明而重新暂存工作区全部文件。先确认：

~~~bash
git diff --staged --name-status
git status --short
~~~

如果只需改变 author，应先读身份配置和共享边界。--reset-author 不是把提交挂到任意他人名下的工具，详见身份和签名章节。

## hook、签名和空提交

amend 会再次运行适用的 hooks，并可能要求签名。失败时先保存：

~~~bash
git rev-parse HEAD
git diff --staged
git status --short
git config --show-origin --get-regexp '^(core\.hooksPath|commit\.|gpg\.|ssh\.)'
~~~

通常 hook 拒绝不会移动 HEAD，但 hook 可能写文件或外部日志。修复具体原因后重新审查。不要用 no-verify 绕过未知规则。

如果 index 与当前 HEAD 的 tree 没有变化，普通 amend 可能拒绝空提交。只有明确需要一个审计标记时才使用 allow-empty，并在说明中写清它不代表代码变化：

~~~bash
git commit --amend --allow-empty -m "chore: record approved marker"
~~~

空提交改变 OID，但不会改变文件快照。它不应被当作遗漏内容已补齐的证据。

## 共享后为什么不能直接 amend

旧 B 可能已经出现在：

- 其他人的本地分支或工作树；
- 评审评论、CI 结果和合并队列；
- 发布标签、制品清单和部署记录；
- 审计日志、备份和镜像。

amend 生成 B' 后，旧引用和新引用分叉。即使文件完全正确，协作者也要重新同步，外部证据会指向旧 OID。共享主线通常追加一个修正提交，必要时使用 revert；个人分支改写需明确协调和显式租约。

## 失败路径和恢复

| 现象 | 首先收集 | 处理 |
| --- | --- | --- |
| 遗漏内容属于另一意图 | staged diff、任务边界、测试 | 取消暂存并创建独立提交 |
| amend 后仍有未暂存修改 | status、工作区 diff | 保留，不能误认为已进入提交 |
| hook 拒绝 | hook 输出、HEAD、配置来源 | 修复门禁后重试 |
| 新提交 OID 与预期不同 | parent、tree、身份、签名、时间 | 这是正常内容寻址，记录字段 |
| 需要找回旧提交 | recovery ref、reflog、bundle | 先建立引用，不运行 gc/prune |
| 共享分支已经 amend | 旧/新 OID、使用者、外部记录 | 停止推送，通知并按历史治理恢复 |
| 提交变空 | 当前 tree 与 HEAD tree | 选择放弃、保留空提交或改用新提交 |

不要用 reset --hard 清理遗漏，也不要删除 recovery ref 来隐藏历史变化。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-5-local-history.sh
~~~

实验验证 amend 补充文件、再次修改说明会生成新 OID，最终文件和提交说明符合预期。它不验证真实 hook、签名、评审、CI、制品、部署或协作者同步。

## 小结

amend 用当前 index 创建替代 commit，旧对象不变，当前分支移动到新 OID。只有在提交明确私有、遗漏属于同一意图且 index 已审查时才直接使用；先建立恢复引用，提交后核对 parent、tree、说明和测试。共享历史的修正应保持旧坐标可追踪，不能把 amend 当作普通编辑。
