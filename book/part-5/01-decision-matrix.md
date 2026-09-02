# 先别急着撤销：用状态矩阵判断位置

“回滚代码”不是一个足够明确的操作目标。撤销工作区修改、取消暂存、替换最近提交、在共享历史中追加反向提交，以及找回误移动的引用，改变的对象和风险都不同。第一步永远是说明要保留什么、要改变什么、这段历史是否已经被别人拿到。

## 进入条件与完成标准

在需要处理的工作树根目录执行，只做状态采集。开始前不要运行 reset、clean、gc、prune 或强制推送。

~~~bash
pwd
git --version
git rev-parse --show-toplevel
git status --short --branch --untracked-files=all
git branch --show-current
git log --graph --decorate --oneline --all -20
~~~

如果仓库正在进行 merge、rebase、cherry-pick 或 revert，先识别当前状态机。不要用另一个命令的 abort、continue 或 reset 介入。

读完本章后，你应能：

- 将“撤销”拆成位置、目标、共享边界和恢复来源；
- 区分工作区、index、当前引用和远端引用；
- 选择 restore、unstage、amend、rebase、revert、reset 或 reflog；
- 判断动作是否创建新提交、移动引用或覆盖文件；
- 识别没有 HEAD、浅克隆、锁文件和未跟踪内容的边界；
- 在执行高风险动作前建立恢复引用或其他可回退入口。

## 第一问：变化在哪一层

先看三组证据：

~~~bash
git diff --no-ext-diff --no-textconv
git diff --no-ext-diff --no-textconv --staged
git ls-files --stage
git ls-files --others --exclude-standard
~~~

可以把状态简化为：

| 变化位置 | 典型证据 | 你要做的事 |
| --- | --- | --- |
| 只在工作区 | git diff 有输出，staged diff 为空 | 丢弃或保留未暂存修改 |
| 只在 index | staged diff 有输出，工作区与 index 一致 | 取消暂存或提交 |
| index 和工作区都有 | 同一路径出现两层差异，状态常为 MM | 分别审查两版，决定拆分 |
| 未跟踪文件 | status 为 ??，没有 index 条目 | 显式加入、备份或按文件系统规则移除 |
| 冲突状态 | ls-files --unmerged 有 stage 1/2/3 | 继续解决或使用对应 abort |
| 当前引用误移动 | reflog 显示旧 OID，工作区可能正常 | 先建立 recovery ref，再评估 |

“差异为空”不能证明没有变化。未跟踪、忽略、sparse、子模块、LFS payload 和外部制品需要另取证。

## 第二问：历史是否共享

用以下字段定义共享边界：

~~~text
local_only: <只有当前操作者的本地对象>
pushed: <是否已推送到任意远端>
fetched_by_others: <是否可能被同事或 CI 获取>
reviewed: <评审/审批是否引用该 OID>
built_or_deployed: <制品或运行实例是否绑定该 OID>
tagged: <是否有共享标签指向它>
worktrees: <是否被其他工作树检出>
~~~

不能只看当前分支是不是 main。个人功能分支可能已被评审和 CI 使用，远端发布分支也可能尚未被任何人获取。历史一旦成为评审、制品、部署或审计的坐标，就不应为了整洁随意改写。

## 默认决策矩阵

| 现场和目标 | 首选动作 | 是否创建新提交/移动引用 | 关键风险 |
| --- | --- | --- | --- |
| 已跟踪工作区修改不要了 | restore 指定路径 | 覆盖工作区 | 未保存内容通常无法由 Git 找回 |
| 已暂存但想保留文件修改 | restore --staged 或 rm --cached | 修改 index | 没有 HEAD 时默认来源可能不可用 |
| 最近私有提交漏文件 | amend | 新 OID，当前分支移动 | 已共享提交会分叉协作者历史 |
| 多条私有提交需重排/拆分 | interactive rebase | 多个新 OID | 范围或 skip 错误会丢变化 |
| 共享提交效果不对 | revert | 新反向提交 | 数据、消息和外部副作用不会自动回退 |
| 本地分支误移动 | reflog + recovery branch | 增加恢复引用 | reflog 和不可达对象会过期 |
| 个人远程分支获批改写 | 显式 force-with-lease | 远端引用条件更新 | 不是备份，也不是绝对并发锁 |
| 当前操作停在冲突 | 对应 merge/rebase/cherry-pick/revert abort | 恢复操作前状态 | 开始前已有脏工作时可能不完整 |
| 远端引用被错误更新 | 远端 OID、备份、权限证据 | 先冻结和协调 | 强推可能覆盖并发提交 |

表格只是默认分流。任何动作前仍要读实际 OID、状态、路径和恢复来源。

## 第三问：是否有进行中的状态机

检查操作标记：

~~~bash
git status
git rev-parse --verify MERGE_HEAD
git rev-parse --verify REBASE_HEAD
git rev-parse --verify CHERRY_PICK_HEAD
git rev-parse --verify REVERT_HEAD
~~~

其中某些 rev-parse 失败是正常的，表示对应操作不存在。status 的提示决定下一步：

- merge 冲突使用 merge --continue 或 merge --abort；
- rebase 冲突使用 rebase --continue、skip 或 abort；
- cherry-pick 冲突使用 cherry-pick --continue、skip 或 abort；
- revert 冲突使用 revert --continue 或 abort。

不要在进行中的状态机上执行 reset --hard 或删除 .git 状态文件。它们可能让工作区看似干净，却丢失当前操作的恢复线索。

## 第四问：恢复来源是什么

每个恢复动作都要写出来源和目标：

~~~text
source: <HEAD、index、指定 commit、reflog OID 或备份>
target: <worktree、index、local ref、remote ref>
paths: <精确路径或 refs>
preserve: <必须保留的内容>
shared: <是否已共享>
verify: <动作后不变量>
~~~

例如 restore --staged 的来源通常是 HEAD，目标是 index，工作区应保留；restore --worktree 的来源通常是 index，目标是工作区，未暂存内容可能被覆盖。写清这四项，比记住命令名称更安全。

## 高风险动作前建立恢复入口

准备移动当前分支或改写历史时：

~~~bash
current_tip="$(git rev-parse HEAD)"
git branch recovery/before-rewrite "$current_tip"
git reflog -1
git bundle create before-rewrite.bundle HEAD
~~~

bundle、recovery branch 和 reflog 的保留范围不同。恢复引用能让当前对象继续可达，bundle 可搬到另一个仓库，reflog 记录本地引用移动但会过期。不要只依赖其中一项。

如果现场涉及安全事件、对象损坏或合规调查，先进入第十、十一篇的冻结和取证流程，不要执行可能触发清理的动作。

## 观察与改变的边界

以下命令通常是观察入口，但仍应记录副作用：

~~~bash
git status --porcelain=v2 -z
git diff --no-ext-diff --no-textconv
git show --no-patch HEAD
git log --graph --decorate --oneline --all
git for-each-ref --format='%(refname) %(objectname)'
~~~

status 可能刷新 index 缓存；log 和 show 读取对象；for-each-ref 读取引用。fetch 会写对象、FETCH_HEAD 和 remote-tracking refs，不能在取证记录中称为完全只读。restore、reset、clean、stash、merge、rebase、revert、push 和维护命令都应明确列为有副作用。

## 常见错误判断

| 误判 | 为什么不成立 | 应补的证据 |
| --- | --- | --- |
| 文件不在 diff，所以没改 | 可能是未跟踪、忽略或 sparse | status、check-ignore、sparse、ls-files |
| 提交不在 log，所以丢了 | log 只遍历当前 refs | reflog、fsck、其他 refs、bundle |
| push 被拒绝就是权限 | 可能是 non-fast-forward 或保护规则 | endpoint、认证、授权、old/new OID |
| reset 后状态干净，所以恢复成功 | hard reset 可能覆盖字节 | 原始 diff、目标 tree、备份和测试 |
| revert 后线上恢复 | 数据、消息和实例可能仍是新状态 | 制品、schema、运行和数据证据 |
| 强推前先 fetch 就安全 | fetch 后仍可有并发更新 | 显式 expected-old、租约、远端审计 |

## 失败路径和恢复

| 现象 | 先收集 | 恢复 |
| --- | --- | --- |
| 不知道该用哪条命令 | status、三层 diff、共享字段 | 暂停改变，写出 source/target |
| restore 后找不到修改 | 原始文件副本、编辑器历史、文件系统快照 | Git 通常无法恢复从未提交的字节 |
| abort 后状态不一致 | 操作前状态、autostash、外部进程 | 从副本和 recovery ref 逐项重建 |
| reflog 没有候选 | refs、对象统计、其他 clone/bundle | 进入对象取证，不先 gc/prune |
| 远端已经变化 | 远端查询时间、old/new OID、事件 | 冻结并协调，不升级为无条件 force |
| 规则或安全风险不明 | 现场权限、凭据、命令日志 | 转安全/取证/组织负责人处理 |

## 隔离实验验证了什么

可运行：

~~~bash
./scripts/verify-part-5-local-history.sh
./scripts/verify-reset-reflog.sh
./scripts/verify-revert.sh
./scripts/verify-troubleshooting-snapshot.sh
~~~

实验验证 restore、取消暂存、amend、reset、reflog、revert 和证据采集的本地状态变化。它们不证明文件系统恢复、远端服务、平台权限、数据库、LFS、CI 或组织级 RPO/RTO。

## 小结

撤销的安全顺序是：先描述目标，定位工作区/index/提交/引用，确认共享边界和进行中状态，写出恢复来源，再选择最小动作。restore 解决工作区，unstage 解决 index，amend/rebase 重建私有对象，revert 保留共享坐标，reflog 负责寻找引用旧位置。没有证据时不改变状态，才能保住下一步的恢复机会。
