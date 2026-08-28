# 复制一个可协作仓库：clone 的初始状态

clone 不是下载一个压缩包。它创建一个新的本地仓库，获取来源仓库可见的对象和引用，记录远程地址，并把一个起点检出为工作区。克隆完成后的每一层状态都应被核对，尤其是默认分支和远程跟踪引用。

## 进入条件与完成标准

准备一个允许读取的 Git URL 或本地 bare 仓库。为了不把平台输出伪装成本地输出，本章的实验使用 file URL。真实 URL 还需要网络、服务器身份校验、认证和授权。

在执行前准备一个不存在或为空的目标目录。不要把 clone 目标指向已有项目目录。

读完本章后，你应能：

- 解释 clone 创建的仓库、refs、配置和工作区；
- 区分远程默认分支、远程跟踪分支和本地分支；
- 处理非空目标目录、权限、对象传输和认证失败；
- 认识浅克隆、部分克隆、镜像克隆和裸克隆的边界；
- 通过 OID、tree 和状态报告验收初始快照；
- 说明 clone 成功不等于具备写权限或平台协作权限。

## 目标目录必须先确认

在来源仓库 URL 已经过团队确认后：

~~~bash
destination=git-book-reading
test ! -e "$destination"
git clone <repository-url> "$destination"
~~~

尖括号占位符必须替换成已验证的 URL，不能连同尖括号执行。test 失败说明目标路径已存在，先换一个明确的新目录；不要用 rm -rf 清空不明目录。

若目标目录已存在且为空，Git 某些版本允许克隆到其中；团队脚本不应依赖这个细节，使用全新目录更容易证明结果。

## clone 实际完成哪些步骤

普通 clone 大致包含：

1. 连接来源并发现可见 refs；
2. 协商并下载需要的对象；
3. 初始化目标仓库；
4. 把来源地址写入 remote.origin.url；
5. 写入远程跟踪 refs；
6. 根据远端 HEAD 或指定分支创建本地分支；
7. 用目标 commit 的 tree 填充 index 和工作区。

检查结果：

~~~bash
cd "$destination"
git remote -v
git rev-parse --show-toplevel
git rev-parse --git-dir
git rev-parse --is-inside-work-tree
git status --short --branch
git symbolic-ref --short HEAD
git rev-parse HEAD^{commit}
git rev-parse origin/HEAD
~~~

远端可能没有名为 origin/HEAD 的本地符号引用，或者来源是没有设置 symbolic HEAD 的 bare 仓库。此时以 clone 输出、远端 refs 和明确的 branch 选择为准，不要把符号引用缺失当作对象传输失败。

初始验收至少保存当前本地 HEAD OID、origin/<branch> OID、根 tree OID 和 clone 时间。文件内容相同只能说明最终 tree 暂时相同，不足以证明历史和 refs 完整。

## 默认分支和指定分支

不指定分支时，clone 使用来源仓库的 symbolic HEAD 选择初始分支。这个默认分支是来源仓库控制面或 HEAD ref 的事实，不由本地用户的 init.defaultBranch 自动决定。

需要明确指定分支：

~~~bash
git clone --branch release/1.x <repository-url> release-reading
~~~

--branch 可以选择远端已有的分支或标签。选择标签时，工作区通常处于分离 HEAD；如果要继续开发，应明确创建本地分支：

~~~bash
git switch --create review/release-1.x
~~~

不要看到目录名或 origin/main 就假设它是来源仓库的默认分支。先用 git ls-remote --symref 或服务端资料核对。

## clone 不授予写权限

读取仓库与更新服务器引用是不同权限。公开仓库可能允许 clone，但 push 仍需仓库授权、分支规则和有效认证。clone 成功只能证明这次会话能读取某个可见范围。

提交中的 author/committer 字段也不会由 clone 自动变成远程登录主体。克隆后的本地身份配置要按本章第二篇的方式核对，不能从 URL 用户名猜测提交责任。

## ZIP、复制目录和 clone 的差异

| 方式 | Git 对象与 refs | 远程配置 | 能否提交和 fetch |
| --- | --- | --- | --- |
| ZIP/归档 | 通常没有 | 没有 | 不能直接作为完整 Git 工作副本 |
| 复制工作区 | 不确定，可能没有或带错 .git | 可能带错 | 风险很高 |
| 普通 clone | 来源可见对象和 refs 的本地副本 | 有 origin | 可以在本地提交和显式同步 |
| mirror clone | 几乎所有 refs，通常无工作区 | mirror refspec | 用于镜像/备份，不是日常编辑目录 |

不要手工复制另一个项目的 .git。它可能带入错误的 remote、hooks、alternates、工作树路径和安全配置。需要复制仓库时使用 Git 的 clone、bundle 或受控文件系统快照。

## 受限 clone 的初步提醒

下列选项会改变本地历史或对象范围：

~~~bash
git clone --depth 20 <repository-url> shallow-reading
git clone --filter=blob:none <repository-url> partial-reading
git clone --sparse <repository-url> sparse-reading
git clone --mirror <repository-url> mirror.git
git clone --bare <repository-url> server.git
~~~

浅克隆限制祖先深度，部分克隆可延迟取得对象，sparse 只改变工作区路径，mirror/bare 改变仓库用途。它们不能互相替代。第十四章和第九篇会说明组合和恢复顺序。

不要把受限 clone 中“log 看不到”写成“来源没有这段历史”，也不要在 mirror 仓库里直接当工作区编辑。

## 传输失败时的状态

clone 可能在初始化、对象传输、校验或检出阶段失败。失败目录可能已经包含部分 Git 数据，不能假设“目录为空”或“对象一定不完整”。先保留目录并检查：

~~~bash
git -C "$destination" rev-parse --git-dir
git -C "$destination" count-objects -v
git -C "$destination" for-each-ref
git -C "$destination" fsck --connectivity-only
~~~

如果目标目录没有 Git 数据，再换一个新路径重试。如果已经存在对象或 refs，先按失败日志和临时目录流程保存或清理；不要把未知目录直接交给递归删除。

常见失败分流：

| 现象 | 层级 | 首要证据 |
| --- | --- | --- |
| destination path already exists | 目标路径 | 目录清单、所有权、是否为空 |
| repository not found | URL/可见性/授权 | 脱敏 URL、主体和来源仓库存在性 |
| host key/证书错误 | 服务器身份/TLS | 信任配置和原始 stderr |
| authentication failed | 客户端凭据 | helper、agent、令牌有效期 |
| early EOF/pack error | 传输或对象校验 | 网络日志、对象统计、fsck |
| checkout failed | 工作区覆盖/文件系统 | HEAD、index、冲突路径、权限 |

不要用浅克隆或关闭校验来掩盖传输损坏，也不要把真实令牌写入命令历史或公开报告。

## 远程地址和验证范围

克隆后查看配置来源：

~~~bash
git config --show-origin --show-scope --get-regexp '^remote\.origin\.'
git remote get-url origin
git remote get-url --push origin
~~~

fetch URL 和 push URL 可以不同。一个只读镜像可能故意没有可写 push URL。修改 remote URL 只是本地配置动作，不会迁移仓库，也不会授予权限。

如果需要验证来源可见 refs：

~~~bash
git ls-remote --symref <repository-url>
~~~

这是网络查询，会受到认证、隐藏 refs、代理和平台控制面影响。本地 clone 实验不替代服务器审计。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-remotes.sh
~~~

实验在临时目录创建 seed、bare server、Alice 和 Bob，验证普通 clone 的 origin、初始 OID、fetch 后远程跟踪引用、pull 后本地分支和显式 tag 推送。它使用本地 file 传输，不验证 SSH 主机密钥、HTTPS TLS、真实令牌、平台默认分支控制面、LFS 或 CI。

## 小结

clone 建立的是一个新的 Git 仓库和一组本地远程观察点。验收时要核对来源、初始分支、HEAD、tree、远程跟踪 refs 和工作区，不要把它当作下载 ZIP。能读取不等于能写入，受限克隆也不能把有限视图当成完整历史。
