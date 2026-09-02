# 定位引入问题的提交：bisect 的判定契约

bisect 用二分搜索缩小“已知正常”和“已知异常”之间的提交范围。它能找到满足判定规则的第一个坏提交，不能自动证明这个提交是业务根因，也不能替你处理环境、数据和外部依赖变化。

## 进入条件与完成标准

准备一个可以重复执行的失败测试，以及一条包含已知好提交和已知坏提交的历史。开始前在仓库根目录保存：

~~~bash
git status --short --branch
git rev-parse --verify HEAD^{commit}
git log --graph --decorate --oneline --all
~~~

工作区和 index 必须干净。bisect 会反复检出历史中的提交，未提交修改可能被覆盖或阻止检出。

读完本章后，你应能：

- 定义稳定的 good/bad 判定和边界；
- 手工或自动运行二分，并处理无法测试的提交；
- 记录每一步的候选、判定和环境；
- 处理 merge commit、浅克隆、生成物和 flaky 测试；
- 结束 bisect 并恢复原分支；
- 区分“第一个坏提交”与“最终根因”和“修复提交”。

## 先定义可重复判定

适合 bisect 的判定通常是：

- 固定测试命令退出码；
- 固定输入产生预期或错误输出；
- 不依赖网络、当前时间、随机数和未声明服务状态的回归脚本；
- 能在每个候选提交中完成构建，或明确返回 skip。

“页面感觉慢了”“偶尔超时”不能直接作为二分条件。先固定输入、数据集、工具版本、超时阈值和日志收集范围。若测试环境缺少依赖，判定应返回“无法测试”，不要把环境缺失标成坏提交。

## good 和 bad 是提交范围的边界

假设 A 已知正常，H 已知异常：

~~~text
A <- B <- C <- D <- E <- F <- G <- H
good                               bad
~~~

开始：

~~~bash
git bisect start
git bisect bad H
git bisect good A
~~~

Git 会选择中间提交并检出它。确认当前位置：

~~~bash
git bisect status
git bisect view
git rev-parse HEAD
git branch --show-current
~~~

bisect 期间 HEAD 通常处于分离状态，当前分支名可能为空。不要在这个状态提交修复，除非你明确要建立恢复引用并退出二分。

git bisect good 和 git bisect bad 不是对文件内容的评价，而是对当前提交和固定测试结果的分类。每次分类都会排除一半左右的候选，但提交图有分支和合并时不一定严格按一条线二分。

## 手工循环

每次候选提交检出后，先运行测试：

~~~bash
<project-test-command>
printf 'test_exit=%s\n' "$?"
~~~

如果结果符合已知正常条件：

~~~bash
git bisect good
~~~

如果结果符合坏条件：

~~~bash
git bisect bad
~~~

若当前提交无法构建、依赖缺失或测试输入不存在：

~~~bash
git bisect skip
~~~

skip 会移除当前候选，但可能让最终范围扩大或出现多个可能的坏提交。记录 skip 原因，不要把它当成 bad 的温和写法。

查看当前进度和已记录判定：

~~~bash
git bisect log
git bisect visualize
~~~

visualize 可能调用图形查看器或分页器，输出不是自动化协议。bisect log 是可以保存的判定轨迹。

## 自动运行和退出码

已有稳定脚本时：

~~~bash
git bisect run ./scripts/test-regression.sh
~~~

脚本以当前候选提交为工作目录，退出码按 Git 约定分类：

| 退出码 | 含义 |
| --- | --- |
| 0 | good |
| 1 至 127 中除 125 外 | bad |
| 125 | 当前提交无法测试，跳过 |

测试脚本必须自己清理生成文件、固定环境变量并避免修改仓库。脚本中不要调用 push、reset --hard、删除 refs、生产部署或改变共享服务。若脚本修改了工作区，下一次候选可能无法检出，bisect 会停止。

自动 bisect 完成后，读取 Git 报告的候选并保存：

~~~bash
git bisect log > bisect-session.log
git show --format=fuller --stat <first-bad-commit>
git bisect reset
~~~

reset 在这里是 bisect 子命令，结束二分并回到开始前的分支，不是普通 git reset 的任意模式。
## 第一个坏提交的证据

候选提交只是“在给定测试和范围里，第一个使判定变坏的节点”。调查还要检查：

~~~bash
git show --format=fuller <first-bad-commit>
git show <first-bad-commit>^..<first-bad-commit>
git diff <first-bad-commit>^ <first-bad-commit>
git log --ancestry-path --oneline <known-good>..<first-bad-commit>
~~~

询问：

- 失败是否由该提交直接改变；
- 提交是否依赖另一个先前变化；
- 测试是否真正覆盖用户症状；
- 环境或依赖是否在该提交同时变化；
- 后续提交是否只是暴露、放大或修复旧问题。

bisect 找到的是定位线索，不是责任判决。将候选 OID 与测试版本、输入摘要和运行日志一起保存。

## merge commit 和路径边界

默认 bisect 会在提交图中选择候选，合并提交的父方向可能影响解释。需要只沿主线调查时，可以先用：

~~~bash
git log --first-parent --oneline main
~~~

然后明确选择 good/bad 范围。不要在一个含大量合并提交的仓库里把第一个坏合并提交直接等同于具体功能提交。

如果问题只涉及一个子目录，bisect 仍然是在提交级别运行。测试脚本可以检查路径变化，但不能假设未触及该目录的提交一定安全，构建图、生成物和共享依赖可能跨目录影响结果。

## 浅克隆、子模块和外部依赖

浅克隆可能没有足够的祖先，bisect 会在边界停止。先检查：

~~~bash
git rev-parse --is-shallow-repository
git log --boundary --oneline HEAD
~~~

需要更多历史时，在有权限和网络的环境中执行 deepen 或 unshallow，并记录对象量和时间。

子模块、LFS、依赖缓存、数据库和远程服务也可能让同一个提交在不同环境中得到不同结果。自动脚本应固定子模块提交、补齐 LFS payload、清理缓存并把外部服务版本写入证据。无法固定时返回 125 或停止调查，不要制造确定性结论。

## 结束和恢复

无论手工还是自动二分，结束后都执行：

~~~bash
git bisect log
git bisect reset
git status --short --branch
git branch --show-current
git rev-parse HEAD
~~~

如果 bisect 期间误创建了提交或修改了引用，先保存 OID 和 reflog，再决定是否建立 recovery 分支。不要用 reset --hard 让状态“恢复正常”，除非你已经保存要保留的工作区字节和引用。

## 失败路径和恢复

| 现象 | 首先收集 | 处理 |
| --- | --- | --- |
| 没有 good/bad 边界 | 当前 HEAD、已知版本、测试定义 | 先证明两端，再开始 |
| 测试随机失败 | 输入、环境、重复运行结果 | 固定环境或返回 skip |
| 候选无法构建 | stderr、依赖、提交 OID | 返回 125/skip，记录原因 |
| bisect 找到多个候选 | skip 数量、merge 图、测试覆盖 | 扩大测试和历史证据，不强行选一个 |
| 浅克隆无共同祖先 | shallow 状态、边界提交 | 补历史后重试 |
| reset 后仍在分离 HEAD | bisect 状态、reflog、分支 | 先执行 bisect reset，再建立恢复引用 |
| 第一个坏提交不是根因 | show、依赖、运行日志 | 追加回归测试和因果调查 |

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-6-engineering.sh
~~~

实验创建一个固定数值回归，使用自动 bisect 找到第一个坏提交，随后结束 bisect 并验证工作区恢复。它不模拟真实编译器差异、网络服务、数据库、缓存、子模块/LFS 或业务责任认定。

## 小结

bisect 的可靠性取决于判定契约，而不是二分命令本身。先建立已知好坏边界，保持工作区干净，让测试明确返回 good、bad 或 skip，保存判定轨迹和候选 OID，结束后执行 bisect reset。第一个坏提交需要结合提交差异、依赖和运行证据继续调查，不能直接当作最终根因。
