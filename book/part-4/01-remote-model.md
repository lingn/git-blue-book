# 远程仓库到底远在哪里：服务器引用、本地缓存和工作分支

第三篇里的所有分支、合并和标签都发生在一个本地仓库中。团队协作要让多个完整仓库交换对象和引用，再由每个仓库决定如何整合。理解远程模型的第一步，是把服务器上的引用、本地保存的远程跟踪引用和当前工作分支分开。

## 进入条件与完成标准

本章的概念可以在任意 Git 仓库阅读。实验使用本地 bare 仓库模拟远程接收端，不需要网络和平台账号。执行命令前先记录：

~~~bash
git --version
git status --short --branch
git remote -v
~~~

读完本章后，你应能：

- 说出一个远程名称、URL、远程跟踪分支和本地分支各自表示什么；
- 解释 clone、fetch、pull、push 分别读写哪些对象和引用；
- 区分本地对远程的最后一次观察与远端当前事实；
- 说明远程认证、仓库授权和 commit 作者字段不是一回事；
- 在同步失败时判断是传输阶段、引用更新阶段还是本地整合阶段；
- 把本地 Git 实验能证明的内容与平台控制面事实分开记录。

## 远程只是另一个 Git 仓库

远程仓库是当前仓库通过路径或网络地址访问的另一个 Git 仓库。它可以位于托管平台、公司服务器，也可以是同一台电脑上的 bare 目录：

~~~text
当前仓库                         另一个仓库
refs/heads/main                  refs/heads/main
对象库             <传输>        对象库
工作区和 index                    通常没有工作区
~~~

“远程”描述的是两个仓库的关系，不保证它跨越互联网，也不自动说明哪一份是权威。团队可以约定平台仓库作为主线入口，也可以使用多个写入端、镜像或灾备副本；权威关系属于治理规则，不能从 remote 名称推导。

远程 URL 是连接目标，不是对象库本身的副本。修改 URL 只改本地配置，不搬运服务器数据，也不改变已有 commit。

## 三层引用状态

以 main 为例：

~~~text
远程仓库中的 refs/heads/main
          |
          | fetch 或 push 通信
          v
本地 refs/remotes/origin/main
          |
          | merge、rebase 或其他整合
          v
本地 refs/heads/main
          |
          | switch 和 commit
          v
当前 HEAD、index、工作区
~~~

### 远端分支

服务器仓库里的真实引用。除非进行网络通信或读取一个受控副本，本地不能保证知道它此刻的 OID。

### 远程跟踪分支

origin/main 是本地的 remote-tracking ref，记录最近一次成功 fetch 或其他明确更新之后，本地认为 origin/main 指向哪里。它不是网络指针，也不会随服务器自动变化。

### 本地分支

main 是当前仓库自己可以提交和合并的 refs/heads/main。fetch 通常不会移动它，pull 的整合阶段和本地提交才会移动它。

## 四个动作各自改变什么

| 动作 | 主要读取 | 主要写入 | 是否自动整合当前分支 |
| --- | --- | --- | --- |
| clone | 远端对象和 refs | 新仓库、origin 配置、远程跟踪 refs、工作区 | 创建初始本地分支和检出 |
| fetch | 远端对象和 refs | 对象库、FETCH_HEAD、远程跟踪 refs | 否 |
| pull | fetch 结果 | fetch 写入，再写当前分支的 merge 或 rebase 结果 | 是 |
| push | 本地对象和待更新 refs | 远端对象和远端 refs（若被接受） | 不改本地工作区 |

具体 refspec、协议协商和受限克隆在第十三、十四章展开。本表只用于先判断动作边界。

fetch 可能写对象、remote-tracking refs 和 FETCH_HEAD，即使它不改工作区。push 可能被服务器拒绝，拒绝时本地提交通常仍保留。pull 失败时要分清 fetch 已经成功但整合失败，还是连接根本没有建立。

## “远程已更新”到底是哪一个事实

下面三句话含义不同：

- “服务器 main 当前是 C”，需要本次远端查询或服务器审计证据；
- “本地 origin/main 是 C”，只需要读取本地 ref；
- “我的 main 已经包含 C”，需要本地祖先关系或整合记录。

如果没有 fetch，origin/main 可能已经过期。如果 fetch 受权限影响只能看到部分 refs，本地仍不能把缺失的引用写成服务器不存在。平台可能隐藏 refs、评审 refs 或限制不同主体的可见范围，Git 命令的空结果也需要带范围解释。

## 认证、授权和提交身份

一次远程操作至少有三层主体：

| 层 | 证据 | 回答什么 |
| --- | --- | --- |
| 传输身份 | SSH key、TLS 客户端凭据、令牌或其他会话 | 谁向哪个 endpoint 发起连接 |
| 仓库授权 | 服务端对仓库、ref 和操作的判断 | 这个主体能否读、写或更新目标引用 |
| 提交元数据 | commit 的 author、committer、gpgsig 等字段 | 对象中记录了谁和哪些签名字段 |

本地 user.name、user.email 不会授予 push 权限。能 clone 也不代表能 push。签名验证通过也不自动表示该主体有权合并或发布。第十篇会把这些证据和信任策略分层。

## 远程实验的安全边界

本书的基础远程实验用 file URL 和本地 bare 仓库：

~~~bash
git clone --bare seed server.git
git clone server.git alice
git clone server.git bob
~~~

这种实验能真实验证 Git 对象传输、remote-tracking refs、非快进拒绝、快进更新和本地 upstream。它不能证明：

- SSH 主机密钥和 agent 的行为；
- HTTPS TLS、代理、令牌或凭据助手的真实存储；
- 托管平台的组织成员、分支保护、评审、合并队列和审计；
- 服务器端隐藏 refs、限流、配额、镜像复制和故障域；
- LFS、制品、CI 或平台控制面数据是否同步。

实验输出中的 file 路径不能冒充 GitHub、GitLab 或公司平台输出。正文把平台能力写成抽象模型，需要平台事实时另行登记版本、权限、套餐和核对日期。

## 失败分流

| 现象 | 更可能在哪一层 | 先取证 |
| --- | --- | --- |
| URL 无法解析或连接超时 | endpoint/网络/传输 | remote get-url、主机、代理和原始 stderr |
| host key 或证书错误 | 服务器身份/TLS | 客户端信任配置和证书链，不重试绕过 |
| authentication failed | 客户端凭据 | 凭据来源、过期、helper/agent 状态 |
| repository not found | URL 或可见性/授权 | 脱敏后的 URL、主体权限和仓库存在性 |
| fetch 成功但本地 main 没变 | 正常数据面边界 | origin/main、FETCH_HEAD、本地 main OID |
| push non-fast-forward | 引用更新规则 | 远端新 OID、共同祖先、并发写入 |
| pull 冲突 | 本地整合阶段 | fetch 结果、HEAD、MERGE_HEAD 或 rebase 状态 |

失败时不要删除本地仓库、重置工作分支或修改作者邮箱来解决传输问题。保留原始错误和本地提交，先判断失败层。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-4-remotes.sh
~~~

实验在临时目录创建 seed、bare server、Alice 和 Bob 三份仓库，验证 clone 建立 origin，fetch 更新远程跟踪引用但不移动本地分支，pull 快进本地分支，push 新分支并建立 upstream，以及显式推送标签。实验不连接外网，不使用真实凭据，也不模拟平台控制面。

## 小结

远程协作由多个完整仓库通过对象和 refs 交换组成。服务器分支、本地 remote-tracking ref 和本地工作分支是三种不同事实；clone、fetch、pull、push 的写入范围也不同。把 URL、传输身份、仓库授权和 commit 元数据分开，才能在同步失败时找到正确的证据入口。
