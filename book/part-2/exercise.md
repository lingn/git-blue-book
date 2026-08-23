# 综合练习：把一次混合修改拆成可复核历史

本练习把第二篇的本地循环连在一起：确认仓库、观察状态、选择路径、审查三层差异、提交单一意图、阅读历史，并在误暂存时恢复。目标不是让终端最后“看起来干净”，而是让每个提交都能回答“为什么存在、包含哪些字节、怎样证明”。

## 练习边界

- **执行位置**：新建的 `git-first-lab-exercise` 根目录；
- **前置条件**：Git 2.28 或更高版本、Bash 或等价终端、可写临时目录；
- **身份**：使用练习专用的虚构邮箱，不改全局配置；
- **网络**：全程不设置 remote，不访问 GitHub、GitLab 或 CI；
- **安全**：所有文件都是合成内容，任何命令都不要替换成真实密钥、生产路径或团队仓库；
- **完成标准**：历史包含互相独立的文档提交和忽略规则提交，个人草稿仍在磁盘但未被跟踪，工作区可解释且最终干净。

如果目录已经存在，换一个新名字。不要为了重跑练习删除一个不确定来源的目录。

## 1. 创建并确认仓库

在父目录执行：

~~~bash
mkdir git-first-lab-exercise
cd git-first-lab-exercise
pwd
git rev-parse --show-toplevel
~~~

最后一条在初始化前应失败。如果它输出了另一个项目的根目录，立即停止并换目录。

初始化并设置仅当前仓库有效的身份：

~~~bash
git init --initial-branch=main
git config --local user.name "Git Blue Book Exercise"
git config --local user.email "exercise@example.invalid"
git rev-parse --show-toplevel
git symbolic-ref --short HEAD
git status --short --branch
~~~

预期是不含提交的 `main`，状态报告会提示尚无提交或没有可提交内容。初始化只创建本地 Git 数据目录，不会创建 remote。

## 2. 建立可比较的基线提交

创建一份最小项目说明：

~~~bash
printf '# Practice repository\n\nThis file is the baseline.\n' > README.md
git status --short
git add -- README.md
git diff --staged --check
git diff --staged -- README.md
git commit -m "docs: add practice baseline"
git rev-parse --verify HEAD^{commit}
~~~

状态变化是：`?? README.md`，然后 `A  README.md`，最后工作区和 index 都相对新 `HEAD` 一致。完整 OID 由内容、身份、时间和父提交决定，不要匹配固定示例。

如果提交因身份配置失败，先执行：

~~~bash
git config --show-origin --show-scope --get-regexp '^user\.'
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
~~~

只修正当前练习仓库的 local 配置。不要为了通过练习修改全局身份，也不要把真实邮箱或凭据粘贴到公开记录。

## 3. 制造三种不同意图

继续在仓库根目录执行：

~~~bash
mkdir -p docs
printf '# Contributing\n\nRun tests before opening a review.\n' > docs/CONTRIBUTING.md
printf '\nSee docs/CONTRIBUTING.md for contribution rules.\n' >> README.md
printf 'personal draft: add branch examples later\n' > notes.txt
printf 'local debug output\n' > debug.log
git status --short --untracked-files=all
git diff -- README.md
git diff --no-index -- /dev/null docs/CONTRIBUTING.md
~~~

预期：

- `README.md` 是已跟踪的工作区修改；
- `docs/CONTRIBUTING.md`、`notes.txt` 和 `debug.log` 是未跟踪路径；
- 普通 `git diff` 只显示 `README.md`；
- `--no-index` 发现未跟踪文档与空文件有差异时返回 1，这是预期的“有差异”，不是 Git 仓库错误。

这四个文件的意图不同：前两个是团队文档，`notes.txt` 是个人草稿，`debug.log` 是本地产物。此时不要执行 `git add .`。

## 4. 只提交团队文档

先选择路径，再审查 index：

~~~bash
git add -- README.md docs/CONTRIBUTING.md
git status --short
git diff --staged --check
git diff --staged --name-status
git diff --staged
~~~

检查点：

- `README.md` 和 `docs/CONTRIBUTING.md` 位于已暂存区域；
- `notes.txt` 和 `debug.log` 仍未跟踪；
- 暂存差异没有个人草稿或调试输出；
- `--check` 没有报告空白错误。

确认后创建文档提交：

~~~bash
git commit -m "docs: add contribution guide"
git status --short --untracked-files=all
~~~

提交只改变本地对象和 `main` 引用，不会上传远程。若 hook 拒绝提交，保存 hook 的错误输出和 `git status`，修复明确原因后重新审查。不要用 `--no-verify` 绕过未知门禁。

## 5. 明确忽略本地产物

项目规则决定不跟踪个人草稿和调试日志。创建规则并验证命中来源：

~~~bash
printf 'notes.txt\n*.log\n' > .gitignore
git check-ignore -v -- notes.txt debug.log
git status --short --ignored
~~~

预期 `check-ignore` 为每个路径报告 `.gitignore` 的规则行，状态中以 `!!` 显示两个被忽略的未跟踪文件。规则文件本身仍是未跟踪的，必须显式加入：

~~~bash
git add -- .gitignore
git diff --staged --check
git diff --staged -- .gitignore
git commit -m "chore: ignore local drafts and logs"
~~~

再次运行：

~~~bash
git status --short --ignored
git log --oneline --decorate --all
~~~

工作区应没有已跟踪变化，两个本地文件仍在磁盘上但不会被普通状态报告列出。忽略规则不会保护已经提交的秘密，也不会删除远程副本。

## 6. 模拟误暂存并恢复

为了练习恢复，不使用真实秘密。创建一个明确的合成文件：

~~~bash
printf 'API_KEY=fixture-only\n' > secrets.env
git add -- secrets.env
git diff --staged -- secrets.env
git status --short
~~~

发现它不应进入历史后，只取消暂存并保留文件：

~~~bash
git restore --staged -- secrets.env
git status --short
test -f secrets.env
rm -- secrets.env
git status --short
~~~

如果文件曾经被提交或推送，恢复动作必须升级为凭据撤销、轮换、全 refs 调查和外部副本处置。这里只是验证 index 的选择边界，不能替代泄漏响应。

## 7. 制造并解释 `MM`

最后做一次只属于工作区的修改：

~~~bash
printf '\nReview the staged diff before committing.\n' >> README.md
git add -- README.md
printf 'This line is intentionally left unstaged.\n' >> README.md
git status --short
git diff -- README.md
git diff --staged -- README.md
git diff HEAD -- README.md
~~~

预期 `README.md` 为 `MM`。暂存差异只有第一行，工作区差异只有第二行，`HEAD` 差异合并显示两行。选择一种意图：

- 如果两行属于同一个文档改动，重新 `git add -- README.md`，审查后提交；
- 如果第二行属于下一项工作，先用 `git restore --staged -- README.md` 取消暂存，再分别处理；
- 如果发现第一行也不应保留，复制需要的内容后再按明确来源恢复，不能使用 `reset --hard` 清空整个仓库。

本练习选择第一种：

~~~bash
git add -- README.md
git diff --staged --check
git diff --staged -- README.md
git commit -m "docs: clarify review expectations"
~~~

## 8. 阅读并验收历史

用多个视角证明结果：

~~~bash
git status --short --branch --untracked-files=all
git log --graph --decorate --oneline --all
git log --format='%H %s' --all
git show --stat --format=fuller HEAD
git log HEAD~2..HEAD --oneline
~~~

应能证明：

1. `main` 至少有四条提交，且文档、忽略规则和最后一项说明分别可识别；
2. 忽略规则提交没有把 `notes.txt` 或 `debug.log` 变成历史文件；
3. `secrets.env` 没有出现在任何提交，工作区中也已按明确路径删除；
4. `git status` 没有把“未扫描未跟踪”误报成干净；
5. 本地没有 remote，也没有任何命令连接远程或 CI。

检查某个文件是否进入历史：

~~~bash
git log --all --oneline -- notes.txt
git log --all --oneline -- .gitignore
~~~

第一条应没有输出，第二条应列出忽略规则提交。空输出只能在“查询范围和路径都已确认”的前提下解释为未找到，不能直接推断平台和其他 clone 中也不存在该文件。

## 失败路径和恢复清单

| 失败或误操作 | 证据 | 恢复 |
| --- | --- | --- |
| 误执行 `git add .` | `git status`、`git diff --staged --name-status` | 在有可解析 `HEAD` 时按路径执行 `git restore --staged --`，再逐项加入 |
| 提交前发现暂存内容不完整 | `git diff --staged` 与目标清单 | 取消暂存或补充明确路径后重新审查 |
| hook 拒绝提交 | hook 输出、`HEAD` 是否移动、index 是否保留 | 修复 hook 报告的问题，再重新运行检查 |
| 文档已提交但说明不准确 | `git show`、是否已共享 | 本地未共享时进入历史整理章节；已共享时优先追加修正提交 |
| 忽略文件仍被跟踪 | `git ls-files -- notes.txt`、`git check-ignore -v` | 规则不能取消跟踪，按审查后的 `git rm --cached` 处理 |
| 历史与预期不同 | `git log --all`、完整 OID、执行位置 | 先建立恢复引用，暂缓 reset、强推和清理 |

## 本练习的验收边界

完成本练习只证明本地 Git 的仓库发现、index 选择、三层 diff、忽略和历史阅读。它不证明：

- 远程平台上是否允许推送、合并或删除引用；
- CI 是否检出了同一个 OID；
- LFS payload、制品、数据库和运行实例是否一致；
- 提交作者、签名者和远程认证主体是否是同一人；
- 任何真实凭据已经被安全处置。

这些问题分别属于远程、供应链、发布、安全和事故章节。不要把本地练习的绿色状态当成组织级发布证据。

## 小结

一次可靠提交不是“把所有变化都 add 后 commit”。先确认目录，再把不同意图分开，使用 `status` 确认范围，用 `diff --staged` 审查真正的输入，最后用 `log` 和 `show` 证明历史结果。发生误选时保留工作区和对象，优先恢复 index；不要用破坏性清理换取表面干净。
