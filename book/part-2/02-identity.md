# 配置身份与 Git 配置：记录者不是登录者

提交对象里有 author 和 committer 字段，但 Git 不会从网页账号、SSH key 或操作系统登录名自动推断它们。配置身份解决的是“对象写什么元数据”，远程认证和平台授权解决的是“谁能访问或更新什么”。把两者混为一谈，会让历史看似有名字，却没有可靠的权限证据。

## 进入条件与退出能力

进入本章前，你应能在练习仓库中执行 `git init` 和 `git status`。所有配置演练都应使用 `git-first-lab` 或脚本创建的临时仓库，不要把示例值写入真实项目的全局配置。

读完本章后，你应能：

- 解释 system、global、local、worktree 和命令级配置的作用范围；
- 查看一个生效值来自哪个文件，而不是只看最终字符串；
- 用条件 include 为不同目录选择不同的提交身份；
- 用 `git var` 判断最终 author/committer 身份是否被环境覆盖；
- 区分作者、提交者、签名者和远程认证主体；
- 在不暴露凭据的前提下修改、撤销和审查配置。

## 身份字段不等于认证主体

一次提交至少涉及这些身份：

| 身份 | 保存或出现在哪里 | 能回答什么 | 不能回答什么 |
| --- | --- | --- | --- |
| author | commit 对象 | 谁被记录为变化的原始作者 | 这个人是否登录或获准推送 |
| committer | commit 对象 | 谁创建了当前这个 commit 对象 | 这个对象是否经过评审或签名 |
| transport principal | SSH/HTTPS/其他传输会话 | 谁在远端请求读写 | 不自动改变 commit 中的邮箱 |
| signature principal | commit/tag 签名与验证策略 | 哪个 key 对精确对象签名 | 不自动表示有权合并或发布 |

直接提交时 author 和 committer 通常相同。代他人应用补丁、合并或重写历史时，两者可能不同。`user.name` 和 `user.email` 只影响 Git 生成的新对象，不会追溯修改已经存在的提交。

## 配置的作用域和优先级

Git 会从多个配置来源读取值。常见范围从宽到窄如下：

| 范围 | 典型位置 | 影响范围 | 适合放什么 |
| --- | --- | --- | --- |
| system | `/etc/gitconfig` 或系统管理位置 | 主机上的所有用户 | 组织基线和受管策略 |
| global | 用户配置目录 | 当前系统用户 | 默认姓名、邮箱和通用偏好 |
| local | 仓库的 `.git/config` | 当前仓库 | 项目专用身份和远程设置 |
| worktree | 启用 worktree config 后的工作树配置 | 当前 linked worktree | 工作树独有的行为 |
| command/environment | `git -c`、`GIT_CONFIG_*`、身份环境变量 | 当前进程或当前命令 | 受控自动化和一次性诊断 |

更具体的配置通常覆盖更宽的来源，但 command/environment 可以改变 Git 读取哪些配置文件，author/committer 环境变量还可以直接覆盖提交身份。不要只打开 `.git/config` 就声称知道最终值。

先在练习仓库根目录只读检查：

```bash
git config --show-origin --show-scope --get-regexp '^user\.(name|email)$'
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
```

前三条都只读取当前生效配置或 Git 计算出的身份，不改变仓库、index、工作区或提交。没有输出通常表示该作用域没有配置；`git var` 失败说明 Git 无法组成有效身份，应先修复配置再提交。输出可能含个人邮箱和内部路径，不能原样贴到公开工单。

## 设置默认身份，再为仓库覆盖

在确认目标是当前用户配置后，设置默认身份：

```bash
git config --global user.name "你的名字"
git config --global user.email "you@example.com"
git config --global --show-origin --get-regexp '^user\.'
```

这些命令修改当前用户的 global 配置，不创建 commit，也不连接远程。若文件由设备管理或组织策略维护，命令可能被拒绝，或后续更宽/更窄的来源覆盖它；用 `--show-origin` 记录实际结果。

公司项目可以在仓库内设置 local 覆盖：

```bash
git config --local user.name "Work Maintainer"
git config --local user.email "work@example.invalid"
git config --show-origin --show-scope --get-regexp '^user\.'
```

执行位置必须是目标仓库。成功后只影响该仓库的新提交，不改变全局默认值和已有历史。若命令提示不是 Git 仓库，先回到正确目录，不要把 `--global` 作为无条件修复。

## 用条件 include 管理多种工作身份

当工作项目和个人项目位于稳定的目录边界时，可以让 Git 根据仓库路径加载不同片段：

```ini
[includeIf "gitdir:~/work/"]
    path = ~/.config/git/work.inc
```

`~/.config/git/work.inc` 可以只保存工作身份：

```ini
[user]
    name = Work Maintainer
    email = work@example.invalid
```

这是配置文件示例，不应直接覆盖现有配置。部署前要确认目录匹配语义、大小写、符号链接和公司目录迁移；先用一个临时仓库执行 `git config --show-origin --show-scope --get-regexp '^user\.'` 验证来源。条件 include 只决定 Git 读取哪份设置，不提供身份认证，也不能替代平台的组织成员关系。

如果一个仓库同时匹配多个 include，最终值可能由文件顺序决定。审查时保存完整来源链和最终值，不要只比较显示姓名。身份规则变更也属于团队协作规则，应经过代码审查或配置管理流程。

## `git var` 才能看到提交时的最终身份

配置值可能被环境覆盖。自动化或脚本调用前，先在同一个进程环境读取：

```bash
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
```

若需要诊断一次性覆盖，可在隔离命令中显式设置并立即清理：

```bash
GIT_AUTHOR_NAME="Fixture Author" \
GIT_AUTHOR_EMAIL="author@example.invalid" \
GIT_COMMITTER_NAME="Fixture Committer" \
GIT_COMMITTER_EMAIL="committer@example.invalid" \
git var GIT_AUTHOR_IDENT
```

这条命令只影响当前进程的身份计算，不修改配置文件。不要把真实 token、密码或 SSH key 放进这些变量。若自动化生成提交，审计还要保存运行主体、候选 OID 和流水线版本，不能只保存 `user.name`。

## 作者和提交者什么时候不同

`git commit --author` 可以为新提交指定作者，提交者仍由当前 Git 进程计算。应用补丁、合并机器人和历史重写可能产生这种分离。它适合有明确授权和审计记录的代提交场景，不适合用来冒充其他人。

发现历史中的姓名或邮箱不正确时，先判断提交是否已经共享。改配置只影响未来对象；改写已有对象会改变 OID、签名、评审链接和协作者同步成本。相关操作放在历史治理篇，不要在本章为修正显示文字而直接重写公共历史。

## 修改和撤销配置的安全动作

在修改前先保存来源和值：

```bash
git config --local --show-origin --show-scope --get-regexp '^user\.'
```

确认值来自当前仓库后，撤销某个 local 覆盖：

```bash
git config --local --unset user.email
git config --show-origin --show-scope --get-regexp '^user\.'
```

第一条只删除当前仓库的 `user.email`，不会删除全局值、密钥或旧提交。若键不存在，命令可能返回非零，这是“没有该 local 覆盖”的证据，不要连续执行更宽范围的删除。来源来自 system 或受管 include 时，应由相应管理面处理。

## 常见错误与恢复

| 现象 | 首要证据 | 恢复动作 |
| --- | --- | --- |
| 提交提示缺少身份 | `git var GIT_AUTHOR_IDENT`、配置来源 | 在正确作用域设置姓名/邮箱，再确认最终值 |
| 配置已改但提交仍用旧邮箱 | `--show-origin --show-scope`、环境变量 | 找到更具体来源或环境覆盖，不要盲目重复写 global |
| 工作与个人仓库身份混用 | 仓库路径、条件 include、最终来源 | 修正路径规则，重新核对新提交；旧历史另行评估 |
| 输出中出现凭据 | 配置来源、helper、环境和 remote URL | 立即停止传播，按凭据撤销/轮换流程处理，不要只删除显示行 |
| 误删全局配置 | 备份文件、来源和当前生效值 | 从受控备份恢复；不要在不明来源时执行递归删除 |

## 隔离实验验证了什么

本章使用第二篇共享实验：

```bash
./scripts/verify-part-2.sh
```

前置条件是 Bash、Git 2.28 或兼容版本、`mktemp` 和可写临时目录。脚本把 global 配置和条件 include 放在临时目录，先验证路径条件能选择实验身份，再设置 local 身份覆盖并用 `git var` 读取最终结果。它还使用虚构邮箱，不连接网络、不读取本机凭据，退出时删除配置和仓库。

实验验证的是 Git 配置来源和身份计算边界，不是平台认证、隐私邮箱可用性、SSO、签名、组织授权或提交责任证明。生产团队应在真实目录规则和受管配置环境中另外核对权限、审计和迁移影响。

## 小结

姓名和邮箱是 commit 元数据，不是登录凭据。先用 `--show-origin --show-scope` 找到配置来源，再用 `git var` 观察提交时的最终身份；用 local 或条件 include 隔离项目身份，避免把全局设置当作万能答案。作者、提交者、签名者和远程认证主体各自需要不同证据，不能用一个字符串替代整条信任链。
