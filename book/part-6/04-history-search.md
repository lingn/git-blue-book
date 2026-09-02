# 查找一行代码和一段逻辑的演变：从线索到证据

历史查询适合回答“哪里开始出现”“哪次提交触及它”“某一行最后由哪个提交写入”。它不能单独回答“谁应该负责”“为什么线上故障发生”或“哪条提交一定是根因”。这些结论需要评审、CI、制品、部署和运行证据。

## 进入条件与完成标准

在包含目标路径和足够历史的仓库根目录执行。开始前保存：

~~~bash
git status --short --branch
git rev-parse --verify HEAD^{commit}
git log --graph --decorate --oneline --all
~~~

如果仓库是浅克隆、部分克隆或存在替代对象库，先记录限制。查询输出可能包含姓名、邮箱、内部路径和客户数据，外发前要脱敏。

读完本章后，你应能：

- 用 blame 定位一行的最后写入提交，并知道它的误差来源；
- 用 log、follow、pickaxe 和 grep 逐步缩小历史范围；
- 在重命名、复制、格式化提交和合并提交中保持证据边界；
- 固定提交 OID、父列表、路径和查询条件；
- 区分本地 Git 归因与平台责任、部署因果和业务根因；
- 把线索交给第十一篇的历史取证流程，而不是直接下结论。

## 先固定调查对象

调查开始先记录路径、候选提交和版本：

~~~bash
target_path=src/payment/service.conf
candidate="$(git rev-parse HEAD)"
git rev-parse --verify "$candidate^{commit}"
git check-ignore -v -- "$target_path" || true
git ls-files -- "$target_path"
~~~

ls-files 没有输出时，路径可能未跟踪、被 sparse 排除、位于子模块中或拼写错误。不要因为 blame 报错就修改 index 或恢复文件。

保存查询上下文：

~~~text
repository: <脱敏后的仓库标识>
candidate: <完整 commit OID>
path: <精确路径>
refs: <查询使用的 refs>
git_version: <版本>
query_time: <UTC 时间>
limitations: <浅克隆、替代对象库、过滤器或缺失路径>
~~~

相同命令在不同 refs、不同浅边界或不同 Git 版本上可能得到不同结果。没有上下文的截图不能作为历史证据。

## blame 只表示最后写入

查看当前文件指定行：

~~~bash
git blame -L 20,35 -- src/payment/service.conf
~~~

输出把每行映射到一个提交、作者和路径。它通常回答“当前这行最后一次由哪个提交写入”，不等于“谁最初设计了这段逻辑”或“谁对线上结果负责”。

更适合保存的机器格式：

~~~bash
git blame --line-porcelain -L 20,35 -- src/payment/service.conf
~~~

保存后对每个提交执行：

~~~bash
git show --format=fuller --stat <blame-commit>
git show <blame-commit> -- src/payment/service.conf
git rev-list --parents -n 1 <blame-commit>
~~~

注意这些情况：

- 后续格式化提交可能接管整段行的 blame；
- 移动代码会让最后写入者与逻辑作者不同；
- 合并提交和路径简化可能隐藏另一侧来源；
- 工作区的未提交修改不会改变 commit 中的历史；
- 文件被删除或路径不在当前 tree 时，当前 blame 无法直接回答。

## ignore-revs 只能改变显示路径

大规模格式化提交可以在 blame 中忽略：

~~~bash
git blame --ignore-rev <format-commit> -- src/payment/service.conf
git blame --ignore-revs-file .git-blame-ignore-revs -- src/payment/service.conf
~~~

这改变的是 blame 遍历规则，不会改变 commit、tree 或 author 字段。忽略文件本身是团队规则，应审核、版本化并记录来源。错误或不存在的 ignore revision 应该使查询失败，不要静默忽略拼写错误。

即使忽略格式化提交，行归因也只是启发式结果。还要查看被忽略提交前后的差异、测试和评审说明。

## log 先看路径，再看内容

路径历史：

~~~bash
git log --oneline --follow -- src/payment/service.conf
git log --oneline --all --full-history -- src/payment/service.conf
git log -p --all -- src/payment/service.conf
~~~

follow 只对单一路径工作，并通过相似度启发式追踪重命名。它可能漏掉复制、拆分、合并和大规模目录迁移。full-history 可以减少路径历史简化，但输出仍受 pathspec、父提交和 Git 版本影响。

目录和多个路径查询：

~~~bash
git log --oneline --all -- src/payment/
git log --oneline --all -- src/payment/service.conf docs/payment.md
~~~

最后命令中的 -- 很重要，它把后面的字符串解释为路径。路径中含空格、通配符或换行时，脚本必须安全传参，不能把输出按空格拆分。

## pickaxe 查找内容变化

查找字符串出现次数变化：

~~~bash
git log --all --full-history -S'legacyDiscount' --oneline -- src/payment/service.conf
~~~

S 关注字符串在文件中的数量变化，适合找加入、删除或替换某个标识的提交。

查找新增或删除行匹配正则：

~~~bash
git log --all --full-history -G'discount[[:space:]]*=[[:space:]]*[0-9]+' --oneline -- src/payment/service.conf
~~~

G 关注差异行是否匹配表达式。二者都可能受重命名、二进制、生成文件和历史简化影响。结果为空只能说明当前查询范围没有匹配，不能证明代码从未存在。

查看提交说明：

~~~bash
git log --all --grep='INC-2026-001' --format='%H%x09%s'
~~~

提交说明是作者提供的索引，不是系统自动验证的工单关系。需要责任链时，另存工单、评审、CI、发布和部署事件。

## rename 和 copy 是推断

Git commit 保存 tree，不保存“这条路径被重命名”的操作记录。diff、log 和 blame 会根据相似度推断 rename/copy：

~~~bash
git diff-tree --find-renames --find-copies --name-status -r <parent> <commit>
git log --follow -- path/to/file
git blame -M -C -- path/to/file
~~~

阈值、renameLimit、内容变化和候选规模都会影响结果。不同选项或 Git 版本可能给出不同路径链。调查记录应保存选项、相似度阈值和旧/新路径，不把推断写成提交对象中的事实。

复制代码的归因尤其容易误导。C 可能把相似内容归到另一个文件，但它不证明设计来源、依赖关系或责任转移。

## merge 历史要看父提交

普通 show 的差异视角可能隐藏对某个父提交不独特的变化。对合并提交先固定父列表：

~~~bash
git rev-list --parents -n 1 <merge-commit>
git show -m --format=fuller <merge-commit>
git diff <merge-commit>^1 <merge-commit>
git diff <merge-commit>^2 <merge-commit>
~~~

first-parent 适合回答主线何时合入分支：

~~~bash
git log --first-parent --oneline main
~~~

它不等于完整归因历史。主线事件、功能分支提交、合并解决和部署记录要放在同一时间线上比较，不能只看一个视角。

## 从线索走到根因

一个可复核的调查链可以这样展开：

1. 固定当前候选和路径；
2. 用 blame 或 pickaxe 找到少量候选提交；
3. 阅读候选完整 diff、父提交和相关配置；
4. 检查是否存在格式化、重命名、复制或合并简化；
5. 用 bisect 或回归测试验证候选是否改变可观察行为；
6. 关联 CI、制品、部署和运行时间线；
7. 记录支持、反驳和未知证据，不把作者显示名当作责任结论。

log 和 blame 只提供本地对象层线索。服务端接收时间、评审决定、构建输入、部署实例和业务指标属于外部系统，必须独立取得。

## 失败路径和恢复

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| blame 指向格式化提交 | ignore-revs、前后 diff、提交范围 | 重新运行并对照原始提交，不直接换责任人 |
| follow 路径断开 | rename/copy 选项、旧路径、合并图 | 保存多种视角，必要时进入取证章 |
| pickaxe 没找到 | 字符串、正则、pathspec、浅边界 | 固定输入并扩大范围，不写成“从未存在” |
| merge 中的来源不清 | parent 列表、first-parent、逐父 diff | 分别比较父提交和最终 tree |
| 查询输出很大 | refs、时间、路径和格式 | 缩小范围，保留完整查询参数 |
| 历史显示与平台责任冲突 | OID、接收事件、评审和部署记录 | 分开记录本地线索和外部事实 |
| 对象或路径缺失 | refs、浅状态、对象统计 | 停止清理，检查备份、bundle 和其他 clone |

历史查询是只读入口，但某些配置、filters、替代对象库和外部命令可能影响输出。高风险现场先按第十一篇采集，再做解释性查询。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-history-attribution.sh
~~~

该实验验证 blame 的 line-porcelain、ignore-revs、路径重命名、copy 推断、pickaxe、提交说明搜索、first-parent、合并父比较和调查清单完整性。它不证明平台评审、服务端接收时间、CI、制品、部署或业务责任。

## 小结

历史查询要从可观察线索开始，不要从作者名字开始下结论。blame 看最后写入，log 看可达提交，pickaxe 找内容变化，rename/copy 是启发式，合并提交必须逐父比较。固定 OID、路径、范围和 Git 版本，再把本地证据与评审、构建、部署和运行事实串起来，调查结果才可复核。
