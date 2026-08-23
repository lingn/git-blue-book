# 用显式租约更新允许改写的远程分支

远程历史改写是一项团队操作。适用场景通常是个人负责的评审分支已经推送，团队允许在合并前整理提交，而且没有发布流程或其他开发分支把旧提交当作稳定坐标。主线、发布分支和多人共同维护的分支发生错误时，优先使用 `revert` 保留共享历史。

本章假设改写已经获得授权，目标是防止操作期间出现的并发提交被覆盖。`--force-with-lease` 只能检查远程引用是否仍位于预期对象，不能代替授权、评审和测试。

## 租约是一次条件更新，不是锁

假设远程 `feature/search` 指向提交 O，Alice 在本地把 O 改写为 R：

```text
远程：A <- O                    refs/heads/feature/search

本地：A <- R                    feature/search
```

普通 push 会因为 R 不是 O 的后代而拒绝非快进更新。无条件 `--force` 请求服务器直接把引用从当前值改成 R。显式租约则表达一个条件：

```text
仅当 refs/heads/feature/search 仍等于 O，才把它更新为 R。
```

服务器在更新引用时比较实际值和 O。若 Bob 已经把远程分支推进到 B，条件不成立：

```text
远程：A <- O <- B

本地：A <- R
```

租约不会在 Alice 整理历史期间锁住分支，也不会阻止 Bob 推送。它只在最终更新发生时做比较，因此行为接近带前置条件的 compare-and-swap。

## 操作前要满足的条件

执行位置是拥有 `origin` 远程的本地克隆。开始前应确认：

- 团队规则明确允许改写该分支；
- 分支负责人和可能的协作者已经协调；
- 没有发布标签、部署记录或长期分支依赖旧提交 ID；
- 本地有目标分支的完整历史，并能运行规定的测试；
- 操作者有更新该远程引用的权限，平台规则没有禁止强制更新。

工作区是否干净不会直接决定 push 能否执行，但混杂的未提交修改会增加验证和恢复难度。先查看：

```bash
git status --short --branch
git remote -v
```

这两条命令只读取本地状态。远程地址中可能包含内部主机名或用户名，事故记录对外分享前需要脱敏。

## 记录服务器基线并建立恢复引用

先获取目标远程的最新状态：

```bash
git fetch origin
```

fetch 会下载对象并更新相应的远程跟踪引用，不会改写当前分支或工作区。随后把预期值保存到 shell 变量，并创建本地恢复分支：

```bash
expected_remote="$(git rev-parse refs/remotes/origin/feature/search)"
git branch recovery/feature-search-before-rewrite "$expected_remote"
printf '%s\n' "$expected_remote"
```

`expected_remote` 是本次操作的远程基线。输出是当前仓库对象格式下的完整对象 ID，具体值每次不同。恢复分支让旧提交保持可达；若该名称已经存在，`git branch` 会拒绝覆盖，应换一个带日期或事故编号的名称并记录下来。

检查基线的提交图和内容：

```bash
git log --graph --decorate --oneline --all --max-count=30
git show --stat "$expected_remote"
```

不要在只看过缩写 ID 的情况下继续。自动脚本和操作记录应保留完整 ID。

## 改写后验证新历史

变基、amend 或其他改写完成后，至少检查分支头、提交范围和最终差异：

```bash
git status --short --branch
git log --graph --decorate --oneline --all --max-count=30
git diff --stat "$expected_remote" HEAD
git diff "$expected_remote" HEAD
```

若改写只调整提交说明或拆分方式，最终 tree 应与改写前一致，可以增加严格检查：

```bash
test "$(git rev-parse "${expected_remote}^{tree}")" = "$(git rev-parse 'HEAD^{tree}')"
```

命令成功时没有输出；tree 不一致时返回非零状态。若改写同时把分支更新到新主线，最终 tree 可能合理变化，不能套用这条断言，应根据任务范围审查差异并运行构建、测试和静态检查。

## 使用明确的引用和预期值

推送前可以读取服务器当前值，确认人工记录没有抄错：

```bash
git ls-remote --exit-code --heads origin refs/heads/feature/search
```

输出第一列是服务器当前对象 ID，第二列是完整引用名。`ls-remote` 不更新本地远程跟踪引用，这次查询与随后 push 之间仍可能发生并发更新，最终保护由服务器处理租约条件。

推送时同时写明租约引用、预期值、来源和目标：

```bash
git push \
  --force-with-lease=refs/heads/feature/search:"$expected_remote" \
  origin \
  HEAD:refs/heads/feature/search
```

不要照抄未赋值的变量。当前 shell 中的 `expected_remote` 必须来自前面的 `rev-parse`，并在 push 前通过 `printf` 和操作记录再次核对。

成功后，服务器把 `refs/heads/feature/search` 从 `expected_remote` 更新为本地 `HEAD`，并接收新历史缺少的对象。协作者的本地分支不会自动迁移，他们仍需按团队约定重新获取和处理旧历史。

## 验证服务器接受了哪个对象

记录本地目标并直接查询服务器：

```bash
pushed_commit="$(git rev-parse HEAD)"
remote_after="$(
  git ls-remote --exit-code --heads origin refs/heads/feature/search |
    awk '{print $1}'
)"
test "$remote_after" = "$pushed_commit"
```

`test` 成功时没有输出，不一致时返回非零状态。这里使用 `awk` 读取 Git 的制表符分隔输出，需要 POSIX `awk`。若远程引用不存在、认证失败或网络不可用，`git ls-remote --exit-code` 会返回非零状态，不能把空结果当作验证成功。

验证记录还应包含测试命令、平台评审状态和通知范围。对象 ID 相同只能证明远程引用位于预期提交，不能证明构建、部署或业务行为正确。

## 为什么无参数租约仍有竞态

下面这种简写很常见：

```bash
git push --force-with-lease origin feature/search
```

没有显式预期值时，Git 通常用本地远程跟踪引用作为“服务器应该还在这里”的依据。编辑器、IDE、定时任务或用户自己执行的后台 fetch 可能悄悄推进 `origin/feature/search`。本地工作分支尚未整合 Bob 的提交，租约依据却已经更新，简写形式可能允许覆盖 Bob 的工作。

Git 2.49.0 的 `git-push` 文档把除 `--force-with-lease=<refname>:<expect>` 之外的租约形式标为实验性语义。本书对高风险操作只采用完整引用加显式预期值的形式。`--force-if-includes` 可以为部分简写场景增加包含性检查，但它不替代明确记录服务器基线的流程。

## 租约拒绝后先保留现场

陈旧租约通常以非零状态结束，远程引用保持不变。错误文字会随 Git 版本、传输协议和托管平台变化，判断依据是退出状态和服务器引用，而不是匹配某一句固定文案。

停止重试，先读取服务器实际位置：

```bash
remote_now="$(
  git ls-remote --exit-code --heads origin refs/heads/feature/search |
    awk '{print $1}'
)"
printf 'expected=%s\nactual=%s\n' "$expected_remote" "$remote_now"
git fetch origin
git log --left-right --graph --oneline HEAD...origin/feature/search
```

`<` 和 `>` 标出两侧独有提交。找到新增提交的来源和意图，再决定把它们整合进改写后的历史、放弃改写，或由分支负责人重新安排迁移。租约拒绝证明前置条件已经变化，不能通过改用 `--force` 消除这个事实。

认证失败、网络错误、服务端 hooks 和平台分支保护也会让 push 失败。显式租约不会绕过这些控制。排障时分别记录“比较条件不成立”“无权更新”“策略拒绝”和“传输失败”，恢复动作并不相同。

## 已经错误更新时怎样恢复

如果租约条件本身记录错了，push 仍可能成功覆盖不该覆盖的历史。发现后先暂停该分支的其他更新，记录服务器当前 ID，并确认操作前的恢复引用仍存在：

```bash
bad_remote="$(
  git ls-remote --exit-code --heads origin refs/heads/feature/search |
    awk '{print $1}'
)"
git show --stat recovery/feature-search-before-rewrite
```

团队确认需要把远程恢复到旧位置后，用新的显式租约保护这次反向更新：

```bash
git push \
  --force-with-lease=refs/heads/feature/search:"$bad_remote" \
  origin \
  recovery/feature-search-before-rewrite:refs/heads/feature/search
```

若事故期间又有人推送，新的租约会拒绝恢复操作，此时不能继续覆盖。先保存各方提交并协调新的目标历史。恢复分支不存在时，可以从其他克隆、评审记录、CI 日志或服务端管理员保留的引用寻找旧对象 ID；服务器是否保存 reflog 和不可达对象取决于实现与维护策略，不能把它当作必然存在的恢复来源。

恢复远程引用后，仍要通知已经获取错误历史的协作者，并处理评审、CI、制品和部署系统中的旧坐标。远程分支回到旧对象不表示外部系统自动回滚。

## 隔离实验覆盖三种结果

**前置条件**：Git 2.28 或更高版本、Bash、`mktemp` 和本书工作区。在仓库根目录执行：

```bash
./scripts/verify-force-with-lease.sh
```

脚本只使用系统临时目录和本地 bare 远程，不连接托管平台。它创建 Alice、Bob 两个克隆，验证陈旧显式租约拒绝且不改变远程；Alice 获取并保留 Bob 的提交后，使用新基线成功更新远程；随后以当前远程 ID 为新租约，把服务器恢复到更新前的已知位置。

成功时输出：

```text
Explicit lease rejection, coordinated update, and recovery passed.
```

对象 ID 和临时路径由运行环境决定。任何关系断言失败时脚本返回非零状态，退出时删除实验目录。实验只证明 Git 引用更新语义，不模拟平台权限、分支保护、代码评审或 CI 行为。

## 安全边界

显式租约减少的是并发覆盖风险。它不知道目标分支是否允许改写，不知道预期值是否记录正确，也不判断新历史是否包含所有必要变化。标签和发布分支的对象 ID 可能已经进入制品、审计和部署记录，即使只有一个维护者，也不应按个人评审分支的流程改写。

操作结束后保留恢复引用，直到评审、CI 和协作者完成迁移。确认不再需要时再按团队保留策略删除，不要在 push 成功后立即清理唯一恢复坐标。
