# 为什么已公开历史不应随意改写：共享坐标比图形整洁更重要

历史一旦被其他人、评审、CI、制品或部署系统引用，就不再只是当前操作者的本地草稿。改写提交会生成新的 OID 和父关系，旧坐标可能仍在其他 clone 和记录中。文件内容看起来相同，也不能消除同步和审计成本。

## 进入条件与完成标准

在评估 amend、rebase、reset 或强制推送前执行：

~~~bash
git status --short --branch
git log --graph --decorate --oneline --all -20
git for-each-ref --format='%(refname) %(objectname)'
git reflog --all -5
git remote -v
~~~

如果目标分支、标签或候选已被发布，先停止改写。保存旧 OID、相关 refs、评审事件和制品/部署记录，再讨论恢复或前向修复。

读完本章后，你应能：

- 定义“公开历史”而不是只看是否在 main；
- 解释改写如何制造分叉和证据断裂；
- 判断 revert、追加修正、merge、rebase 和 force-with-lease 的边界；
- 处理协作者、CI、评审、制品和标签对旧 OID 的依赖；
- 在获批的个人分支改写后保留恢复和通知记录；
- 说明 Git 无法撤回哪些外部副本。

## 什么叫已公开

以下任一情况都可能构成共享：

- 提交已经推送到任意远程；
- 其他人已经 fetch、clone、检出或基于它提交；
- 评审评论、审批、CI 检查或合并队列引用该 OID；
- 标签、制品清单、部署请求或运行记录绑定该提交；
- 其他 worktree、镜像、bundle 或备份保存了该对象；
- 组织审计或外部工具已经记录了它。

“分支不是 main”不能证明它私有，“还没有同事抱怨”也不能证明没有人获取。共享判断要结合服务器日志、平台事件、CI 和部署记录；本地 Git 只能提供部分线索。

## 改写前后的提交图

Alice 已获取 B，并从 B 创建 C。Bob 把 B 改成 B' 后强制更新远程：

~~~text
远程：A <- B'
Alice：A <- B <- C
~~~

B 与 B' 即使 tree 只有一处字符差异，也是不同对象。Alice 的本地分支不能自动把 B 替换成 B'，后续 fetch、merge 或 rebase 可能出现分叉和重复补丁。

amend、rebase、reset 后分支可以指向新节点：

~~~text
旧：A <- B <- C
新：A <- B' <- C'
~~~

旧对象可能仍由 reflog、恢复分支、标签、备份或其他 clone 找到，但这些入口有各自的保留期限。改写不是删除旧对象的瞬间动作，也不是让所有副本同步的机制。

## 为什么共享主线优先 revert

共享提交的效果有问题时，通常追加反向提交：

~~~bash
git fetch origin
git show --format=fuller --stat <bad-commit>
git revert <bad-commit>
git diff --staged --check
git commit -m "revert: disable broken settlement path"
~~~

revert 保留旧提交和后续历史，新的提交说明“曾经引入、后来撤销”这条事实。它只能撤销 Git tree 中的变化，数据库、消息、外部 API 和已运行实例要单独处理。

如果坏提交是 merge commit，需要选择 mainline。若回退会破坏已经写入的数据或消息，可能应采用向前修复，而不是简单 revert。决定必须基于发布和数据证据。

## 什么时候可以改写

个人分支、未共享提交或明确批准的维护窗口可能允许 rebase、amend 或 reset。最低条件包括：

1. 分支所有权和使用者明确；
2. 没有其他人、CI、制品或部署依赖旧 OID；
3. 已保存旧远端 ref、恢复分支或 bundle；
4. 已通知评审者和自动化所有者；
5. 已核对远端没有新的并发提交；
6. 平台规则和审计允许条件更新；
7. 新历史的测试、签名和发布记录会重新生成。

推送时使用显式 expected-old 租约：

~~~bash
expected_remote=<改写前远端完整 OID>
git push --force-with-lease=refs/heads/feature/search:"$expected_remote" \
  origin HEAD:refs/heads/feature/search
~~~

租约只防止远端 ref 已经偏离 expected value。它不证明没有其他副本、不提供备份，也不能替代通知和平台授权。

## 协作者如何恢复

发现共享分支被改写后，先保存旧 OID 和当前 refs：

~~~bash
git fetch origin
git branch recovery/old-shared <old-commit-id>
git log --graph --decorate --oneline --all
git log --left-right --oneline recovery/old-shared...origin/feature/search
~~~

然后按团队决定：

- 把本地未发布工作 rebase 到新的远端；
- 从旧恢复分支 cherry-pick 尚未包含的提交；
- 对比补丁等价性，避免重复应用；
- 如果远端改写未经授权，冻结写入并启动事件响应。

不要直接 reset --hard 到 origin/feature/search，除非已备份本地工作并确认旧提交无须保留。重新 clone 是最后的同步方式之一，不是第一反应。

## 标签、制品和评审不会自动迁移

改写提交后，以下内容可能仍指向旧 OID：

- 附注或签名标签；
- 评审链接、审批和检查结果；
- 构建制品、SBOM 和 provenance；
- 部署请求、实例 digest 和回退清单；
- 审计事件、bundle、镜像和备份。

不要移动标签、覆盖制品或删除评审来掩盖 OID 变化。为新对象重新生成签名、检查、制品和部署记录，旧记录保留为历史证据。

## 版本和恢复窗口

reflog 和不可达对象的保留受仓库配置、维护、对象过期和备份策略影响。查看配置和候选：

~~~bash
git config --show-origin --get-regexp '^(gc|core\.logAllRefUpdates)'
git reflog --all --date=iso-strict
git fsck --no-reflogs --unreachable
git count-objects -v
~~~

这些命令可能显示内部路径和对象，外发前脱敏。事故响应期间暂停自动清理，先建立恢复 refs 和独立备份。窗口过去后，Git 本地可能无法恢复，需依赖其他 clone、镜像或对象库。

## 失败路径和恢复

| 现象 | 首先收集 | 处理 |
| --- | --- | --- |
| 不知道分支是否共享 | refs、远端日志、评审、CI、制品 | 按“已共享”处理，暂缓改写 |
| 改写后普通 push 被拒绝 | 远端 old OID、新 OID、协作者 | fetch、通知、获批后使用租约 |
| 协作者本地仍在旧历史 | 旧/新 refs、未发布提交 | recovery ref 后 rebase/cherry-pick |
| 标签或制品仍指向旧对象 | tag target、制品摘要、部署记录 | 新对象重新签名/构建/发布，保留旧证据 |
| 强推覆盖了并发提交 | ref 更新时间、服务端事件、reflog | 冻结写入，从备份或旧 clone 恢复 |
| reflog 已过期 | 对象统计、bundle、镜像、其他 clone | 进入对象取证，不能假设本地可恢复 |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-force-with-lease.sh
./scripts/verify-sensitive-history-boundaries.sh
./scripts/verify-reset-reflog.sh
~~~

实验验证显式租约拒绝并发更新、恢复引用和历史对象边界。它不证明真实平台的保护分支、审计、标签不可变、制品库、备份保留或协作者已获取范围。

## 小结

共享历史是团队共同坐标，不能为了少一条提交或修正说明而随意改写。先判断 OID 是否被人和系统引用，再选择 revert、追加修正或获批的重建；改写后重新生成签名、评审、CI、制品和部署证据。保持旧坐标可追踪，才能让恢复和调查继续进行。
