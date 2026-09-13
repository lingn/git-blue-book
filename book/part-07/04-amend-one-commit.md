# amend 一条提交：先判断有没有共享，再决定改写还是追加

本章合并原第五篇的“补充提交内容”和“修改提交说明”两条入口，也承接提交改写操作手册。amend 只适合明确拥有的最近提交；更早提交要重放后续序列，已经共享的提交默认追加修正或 revert。

提交不是可以原地编辑的文档。补一个文件、改一句提交说明、合并两条提交或删除一条提交，都会创建新的 commit，或者让分支改指向别的 commit。真正决定操作方式的，不是“改动大不大”，而是旧提交是否已经成为别人使用的坐标。

本章只处理最新一条提交的内容和说明。更早提交的重建、共享历史撤销和远端条件更新分别由后续章节承担。

## 先回答三个问题

动手前执行：

```bash
git status --short --branch
git branch -vv
git log --graph --decorate --oneline --all --max-count=30
git diff
git diff --staged
```

然后回答：

1. 要改的是最新一条提交，还是更早的提交？
2. 旧提交是否已经推送、进入评审、被 CI 检查、被别人拉取，或者用于制品和部署？
3. 工作区与 index 是否还混有其他任务的修改？

“已推送”是最容易观察的共享信号，但不是唯一信号。本地提交也可能已经被另一个 worktree、bundle、CI 或同事的临时远端使用。无法确认时，按已共享处理。

| 现场 | 默认动作 | 原因 |
| --- | --- | --- |
| 最新提交未共享，补充内容属于同一意图 | `git commit --amend --no-edit` | 用新的完整提交替换旧提交 |
| 最新提交未共享，只改说明 | `git commit --amend` | 说明属于 commit 内容，修改后 OID 会变化 |
| 更早的未共享提交要改名、合并、拆分或删除 | `git rebase -i` | 从目标提交起重建后续序列 |
| 个人远程分支允许改写 | 本地改写后使用显式 `--force-with-lease` | 条件更新远端，避免覆盖查询后出现的新提交 |
| 主线、发布分支或多人共享分支 | 追加修正或 `git revert` | 保留已经公开的提交坐标 |

## 刚提交但还没推送，又补了一段代码

假设最新提交刚完成，后来发现漏了同一功能的一份测试。先只暂存这份补充：

```bash
git status --short
git diff -- tests/search_test.java
git add -- tests/search_test.java
git diff --staged --check
git diff --staged
```

确认 index 里只有应当并入原提交的内容后，保存旧位置并改写：

```bash
old_tip="$(git rev-parse HEAD)"
git branch recovery/before-amend "$old_tip"
git commit --amend --no-edit
new_tip="$(git rev-parse HEAD)"

test "$new_tip" != "$old_tip"
git show --stat --format=fuller HEAD
git status --short
```

`--no-edit` 只表示沿用原说明，不表示修改旧对象。Git 使用当前 index 生成新 tree，再创建一个新 commit。旧 OID 仍由恢复分支指向，新 OID 成为当前分支头。

如果补充内容是另一个需求，不要为了“一条提交看起来整齐”而 amend。直接创建下一条提交，意图边界比提交数量更重要。

## 已经推送，又要补代码并保持一条提交

这只适合明确允许改写的个人评审分支。主线、发布分支和多人共同开发分支默认追加修正或 revert。确认允许改写后，先按本章审查 index 并完成 amend，再按[显式租约](10-explicit-force-lease.md)记录服务器基线、条件更新远端。租约被拒绝时停止推送，不升级为无条件 `--force`。

## 修改提交说明

### 最新提交尚未共享

```bash
git branch recovery/before-message-amend HEAD
git commit --amend -m "fix: handle empty matcher id"
git show --no-patch --format=fuller HEAD
```

即使 tree 完全相同，说明变化也会生成新 OID，因为提交说明是 commit 对象内容的一部分。

更早提交的说明修改会重建后续序列，进入[交互式 rebase](05-interactive-rebase.md)。提交已经共享时，按[共享历史改写政策](09-public-history-policy.md)处理；主线通常不为文字美化改写历史，真实审计歧义应在评审或事故记录中关联原 OID 并追加说明。

## Hook、签名和空提交仍需单独核对

amend 会再次经过适用的 hook，也可能要求签名。失败时先保存状态和配置来源：

~~~bash
git status --short --branch
git diff --staged
git rev-parse HEAD
git config --show-origin --get-regexp '^(core\.hooksPath|commit\.|gpg\.|ssh\.)'
~~~

通常 hook 拒绝不会移动 `HEAD`，但 hook 可能已经写文件、改 index 或记录外部日志。修复具体门禁后重新审查 index，不要用 `--no-verify` 绕过未知规则。提交签名只证明新对象被某个密钥签过，不会把旧对象的签名自动转移到新 OID。

如果 index 与当前 `HEAD` 的 tree 没有变化，普通 amend 可能拒绝空提交。只有明确要记录审计节点时才使用 `--allow-empty`，并在说明中写清它不代表代码变化：

~~~bash
git commit --amend --allow-empty -m "chore: record approved marker"
~~~

空提交同样会创建新 OID，不能拿来证明遗漏内容已经补齐。

## 超出 amend 边界时转到对应章节

| 目标 | 权威章节 |
| --- | --- |
| 修改、合并、拆分或删除更早的未共享提交 | [交互式 rebase](05-interactive-rebase.md) |
| 把提交迁移到正确分支 | [cherry-pick](07-cherry-pick.md) |
| 撤销共享历史中的变化 | [revert 共享历史](08-revert-shared-history.md) |
| 条件更新允许改写的个人远程分支 | [显式租约](10-explicit-force-lease.md) |
| 分支头误移动或需要重新选择本地历史 | [reset](11-reset.md)与[恢复案例](13-local-and-remote-recovery.md) |
| fetch 后同时 ahead/behind，怀疑远端被改写 | [远端历史事故](14-remote-history-rewrite.md) |
| 提交含凭据 | [凭据泄漏与历史清理](../part-10/01-credential-leak-history-cleanup.md) |

## 完成一次改写后的验收

至少检查：

```bash
git status --short --branch
git log --graph --decorate --oneline --all --max-count=30
git show --stat --format=fuller HEAD
git diff 'recovery/before-amend^{tree}' 'HEAD^{tree}'
git reflog --date=iso -20
```

根据实际任务替换恢复分支名。还要运行项目测试，并核对评审、CI、标签、制品和部署是否仍指向有效 OID。Git 只能证明对象和引用变化，不能替你证明业务行为正确。

## 小结

提交一旦创建就不可原地修改。amend 用当前 index、原父提交和新元数据创建替代 commit，适合明确拥有的最近提交。更早提交、共享历史和远端改写由后续章节分别处理。
