# 迁移不是换一个 remote：代码、身份、平台数据与切换

把 `origin` 从旧地址改成新地址，只完成了客户端寻址。一次完整迁移还要决定哪些 refs 和对象进入目标、旧身份如何解释、默认分支和标签是否保持、LFS/submodule 是否可取、issue/评审关系如何落地、权限和 CI 如何重建，以及切换期间哪一端允许写入。

迁移最危险的状态不是命令报错，而是两个看似可用的系统同时接受不同写入。此时两个平台都能继续产生提交、评审、标签、制品和审计事件，任何“最后再同步一次”都可能覆盖另一端的合法变化。

本章以 Git 2.49.0、Bash 和本地 bare 仓库验证 Git 到 Git 的数据面迁移。本地没有安装 SVN 或 `git-svn`，也不连接托管平台，因此不提供伪造的 SVN、GitHub、GitLab 或 CI 输出。SVN 导入和平台元数据迁移只定义可验收的工具契约；实际命令、API 版本、权限、分页、套餐和限制必须在目标环境按核对日期验证。

进入本章前，读者应理解对象 ID、refs/refspec、annotated tag、notes、LFS pointer、submodule gitlink、签名、受保护引用、CI 候选和备份恢复点。读完后，应能：

- 判断迁移是否应保持 OID，还是会生成新的 commit/tag；
- 为 Git、SVN 和托管平台分别盘点数据面、控制面与外部对象；
- 建立作者/提交者、平台账号与审批身份的分层映射；
- 用 staging mirror、refs manifest、源端冻结和 acceptance clone 完成 Git 到 Git 切换；
- 为 LFS、submodule、issue/评审、权限、CI、制品和审计建立单独迁移路径；
- 在切换失败或目标已产生新写入时选择安全回退方向。

## 先判断迁移是否允许保持对象 ID

| 迁移类型 | commit/tag OID | 主要原因 |
| --- | --- | --- |
| 同对象格式的 Git 到 Git，原样传输对象 | 可以保持 | Commit/tag 原始字节不变 |
| 只改变 remote URL、托管服务或 ref 所在服务器 | 可以保持 | 地址和平台元数据不进入 commit payload |
| 用 `.mailmap` 规范日志显示 | 可以保持 | Mailmap 是读取时映射，不修改对象 |
| SVN/CVS/其他模型导入 Git | 必然新建 Git 对象 | 源系统没有同一 Git commit payload/OID |
| 改作者/提交者、时间、message、parent 或 tree | 必然改变 | 任一 commit payload 字节变化都会重算 OID |
| LFS 历史迁移、秘密清理、目录拆分/合并 | 通常改变 | Blob/tree/parent 链被重写 |
| 从 SHA-1 仓库重建为 SHA-256 对象格式 | OID 改变 | 对象寻址算法与格式不同 |

“文件内容一样”不足以证明迁移保持历史。Commit 还包含 tree、parent、author、committer、时间和 message；annotated tag 也有独立对象和可选签名。若目标是 OID 保持，迁移过程不得顺手改邮箱、统一时间、重写说明或重新创建 tag。

OID 改变并不自动意味着迁移失败，但必须生成可审计映射：旧 commit/tag、目标对象、转换规则、无法映射项和验证结果。外部评审链接、发布清单、submodule gitlink、签名、CI cache 和制品 provenance 都可能仍引用旧 OID。

## 迁移范围要覆盖三个平面

### Git 数据面

- branches、tags、notes、自定义 refs 和平台可导出的评审 refs；
- refs 可达的 commit/tree/blob/tag 对象；
- 默认分支 symbolic HEAD 和对象格式；
- Git LFS pointer 与独立 payload；
- submodule gitlink 指向的外部仓库 commit；
- 签名对象，以及迁移后仍可用的外部信任策略。

### 平台控制面

- 仓库可见性、默认分支、保护规则和允许的合并方式；
- 用户、团队、外部协作者、机器人和 deploy key；
- 必需检查、审批规则、所有权规则和例外流程；
- webhook、应用安装、runner、环境、OIDC trust 和审计设置；
- 仓库归档、保留、删除、fork 与镜像关系。

### 协作与交付数据

- issue、合并请求、评论、审批、review thread、标签和 milestone；
- 附件、wiki、release、package、CI log/artifact 和部署记录；
- 原系统数字 ID、URL、状态、作者、时间和目标 commit；
- 不能导入目标平台的数据应保留在哪里、如何检索和多久删除。

Secrets 不应作为普通迁移导出物复制。目标平台的 CI 变量、webhook secret、机器人 token 和云身份信任应重新签发/绑定，验证后撤销旧值；迁移清单只保存 secret ID、owner、scope、轮换状态和审计证据。

## 盘点源端：可见 refs 不等于服务端全部状态

从迁移 staging 主机读取源端广告：

~~~bash
git ls-remote --symref "$source_url" \
  > source-advertised-refs.txt
~~~

命令只读，不创建本地对象；预期包含服务端允许当前身份看到的 refs 和 `HEAD` symref。认证失败、权限不足或 namespace 被隐藏时，空结果不能解释为“源端没有数据”。平台内部评审 refs、保留对象、fork 和软删除数据可能不通过普通协议广告。

对有完整读取权限、对象格式兼容的 Git 源端，可以建立 staging mirror：

~~~bash
git clone --mirror "$source_url" migration-stage.git
git -C migration-stage.git remote update --prune
~~~

`clone --mirror` 写入本地 bare 仓库，并配置广泛的强制 ref 映射。`remote update --prune` 会把源端 force update 和删除同步到 staging；它不是保留点。同步前后都应生成不可变 bundle/快照和 refs manifest，避免源端误删在迁移期间覆盖唯一副本。

在 staging 中记录：

~~~bash
git -C migration-stage.git version
git -C migration-stage.git rev-parse \
  --show-object-format --show-ref-format
git -C migration-stage.git symbolic-ref -q HEAD
git -C migration-stage.git for-each-ref \
  --format='%(refname)%00%(objecttype)%00%(objectname)%00%(*objectname)%00' \
  > source-refs.nul
git -C migration-stage.git fsck --full --strict --no-progress
~~~

Manifest 中还要记录采集身份、权限范围、源平台导出任务、Git/LFS/submodule 边界和任何排除项。`fsck` 通过只证明当前 Git 对象闭包，不证明隐藏 refs、LFS 或平台数据完整。

## 身份映射不是改一列邮箱

迁移至少涉及四种身份：

| 身份 | 来源 | 能否由 Git 单独证明 |
| --- | --- | --- |
| Commit author | Commit header | 只能证明对象记录了该字符串 |
| Commit committer | Commit header | 只能证明谁被记录为生成该 commit |
| 平台账号 | 身份目录/平台数据库 | 需要平台导出和账号映射 |
| 评审/审批者 | 评审与审计系统 | 需要不可变评审/审计证据 |

同一邮箱可能对应多人，员工也可能有多个历史邮箱；共享账号、导入机器人和被删除账号都需要显式状态。映射表至少包含源 identity、目标 principal、映射依据、冲突处理、是否已验证和未知项，不能默认为“邮箱相同就是同一个人”。

### `.mailmap` 只规范显示

~~~text
Canonical Engineer <canonical@example.com> Legacy User <legacy@example.org>
~~~

~~~bash
git log --format='%an <%ae>' --all
git log --use-mailmap --format='%aN <%aE>' --all
~~~

前一条显示 commit 原始 author 字段，后一条按当前 mailmap 显示规范身份。Mailmap 不修改 commit、OID 或签名，也不会自动把平台账号、评审作者和权限映射到目标系统。若合规要求保留原始历史又希望统一展示，mailmap 是可选层；若必须改写对象，进入单独的历史重写项目并保留 old/new OID map。

### SVN 导入时身份映射会参与创建新提交

SVN revision 是仓库范围内的修订序号，branch/tag 通常由目录和 copy history 表达；Git 则用 refs 指向 commit DAG。导入工具必须把 SVN author、revision time、log message、changed paths 和 copy ancestry 转换成新的 Git commit。作者表缺失、时区误读或 copy 追踪错误会直接改变生成的历史。

在运行导入器前，先穷举全部源 author，并为每个值给出目标名称/邮箱或明确的 unmapped 占位；导入器遇到未知身份应失败，而不是静默使用当前操作员。保留工具版本、完整命令、布局规则、作者表摘要和每次导入日志。

本地未安装 SVN/`git-svn`，所以本章不展示未经验证的输出。若选用 `git svn` 或其他导入器，应在冻结的 SVN dump/只读副本上演练，并以源 revision/path 与目标 commit/tree 的可复核映射验收，而不是以“命令完成”验收。

## SVN 的 branch、tag、property 和空目录需要显式策略

`trunk/branches/tags` 只是常见 SVN 布局，不是所有仓库的硬规则。迁移前盘点：

- 多项目是否共享一个 repository，branch/tag 目录是否嵌套或改名；
- branch/tag 是否由 copy 创建，是否存在后续修改、删除和重建；
- 哪些历史路径应成为 Git repository、branch、tag 或归档 ref；
- `svn:ignore`、`svn:externals`、`svn:eol-style`、`svn:keywords`、可执行与特殊文件属性如何转换；
- 空目录是否由占位文件、构建脚本或部署系统重新创建；
- 大二进制是否保留为 Git blob、迁入 LFS，还是移到制品/对象存储。

SVN tag 目录可能在创建后继续变化，不能一律转换成 Git annotated tag 并丢掉后续提交。`svn:externals` 也不是 submodule 的自动同义词：它可能跟踪路径、revision 或外部 URL，迁移前必须确定固定性、认证、发布顺序和灾难恢复边界。

迁移验收应按抽样与全量指标结合：源 revision 数、路径集合、branch/tag 映射、关键 revision tree、删除/复制历史、属性转换和最终 checkout 字节。单独比较“提交条数差不多”没有证明力。

## Git 到 Git 的切换流程

### 1. 先做可重复的演练迁移

目标使用隔离测试实例或新建空仓库。恢复源备份到 staging，迁移 Git refs/LFS/平台元数据，运行完整验收，再销毁目标重做。手工修补如果不能进入脚本、manifest 或 runbook，下一次正式迁移仍会失败。

### 2. 初始同步后保持单一写入源

迁移窗口前可以多次从旧源读取增量，但新目标保持只读或不可发现。不要让用户同时向两端提交；若业务要求长时间并行，需要真正的双向冲突协调协议，而不是两个 cron mirror。

### 3. 冻结旧源并记录切换点

冻结至少覆盖 Git push、平台评审合并、tag/release 创建、issue/评论、LFS 上传、CI 触发和自动化机器人。记录每个控制面的最后事件 ID/时间，而不仅是 main OID。

~~~bash
git -C migration-stage.git remote update --prune
git -C migration-stage.git for-each-ref \
  --format='%(refname)%00%(objectname)%00%(*objectname)%00' \
  > cutover-source-refs.nul
~~~

第二次 refs 采集应在源端写入围栏生效后进行。若仍有变化，先判断是延迟任务、管理员绕过还是未冻结 namespace；不要边同步边宣布完成。

### 4. 只向确认为空的目标写入

~~~bash
git -C migration-stage.git push --mirror "$target_url"
~~~

`--mirror` 会强制更新并删除目标端多出的 refs。执行前必须验证目标仓库身份、为空/可覆盖授权、对象格式和凭据 scope；保存 push porcelain/服务端审计。失败时停止开放写入，从 staging 与目标 refs diff 判断是权限、保护规则、对象限制还是部分写入，不要直接追加 `--force` 猜测。

Push refs 不会替目标平台设置默认分支 symbolic HEAD，也不会迁移保护规则、权限、webhook 或 CI secrets。对本地 bare 验收仓库可以显式执行：

~~~bash
git -C "$target_repo" symbolic-ref HEAD refs/heads/main
~~~

托管平台应使用其受支持的管理员 UI/API 设置默认分支，并按厂商、版本、权限和核对日期保存证据；不要假设本地命令能修改远端服务的 HEAD。

### 5. 验收后才开放新目标写入

至少验证：

1. source/target refs manifest 逐条相同，或每个差异有批准映射；
2. 关键 commit/tree、annotated tag object/peeled target、notes 与签名可读取；
3. LFS payload 从空 cache 可取，submodule 固定 OID 可递归取得；
4. 默认分支、clone/fetch/push、权限、保护规则和必需检查符合目标策略；
5. issue/评审的状态、作者映射、评论、附件和 commit 链接抽样/全量指标通过；
6. CI 从目标平台检出精确候选，生成制品并绑定正确 digest；
7. 新 webhook、机器人和部署身份使用目标 scope，旧凭据准备撤销。

Acceptance clone 必须使用普通开发者/CI 身份和空本地缓存，不能只由迁移管理员在 staging mirror 上执行。

### 6. 旧入口保持拒写并清理客户端

旧服务应进入明确的只读/归档状态，remote URL、网页 banner、机器人和 webhook 都指向新端。客户端更新 URL 后先 fetch 和比较 refs，再 push；不要让旧 clone 用含旧 ancestry 或迁移前远程跟踪状态的 `--mirror` 覆盖新端。

旧服务保留多久由回退、合规和数据删除政策决定。保留不等于继续接受写入；到期删除前再次确认平台附件、审计、LFS 和映射清单已有批准副本。

## LFS、submodule 与签名分别迁移

Git mirror 只迁移 LFS pointer。正式切换前应从源端完整 refs 集合取得 payload，按 OID/size 建清单，上传目标 LFS，随后在空 cache 环境验证。`git lfs fetch --all`/`push --all` 的范围、锁和平台保留行为必须按实际 Git LFS/服务版本验证；本地未安装 `git-lfs`，本章不把 pointer 实验冒充服务迁移。

Submodule 应按依赖顺序迁移：先保证每个依赖 repository 和 gitlink OID 在新端可取，再更新 `.gitmodules` URL；若使用相对 URL，验证新组织/命名空间保持相对拓扑。更新 `.gitmodules` 会生成新 superproject commit，但不应重建依赖 commit 冒充原 OID。

Git 到 Git 原样迁移可以保留 commit/tag 签名字节，但目标验证器还需要原信任根、allowed signers、证书链和撤销状态。改作者、message、tree 或 parent 会生成新对象，旧签名不能验证新对象；平台绿色徽章也不能替代迁移后的组织授权复核。

## 平台元数据需要可追踪的 ID 映射

平台对象通常使用数据库 ID、编号或 URL，不使用 Git OID。迁移表应至少包含：

| 源对象 | 目标对象/归档位置 | 关系与验收 |
| --- | --- | --- |
| Repository/namespace | 新 repository ID/URL | 可见性、owner、默认分支 |
| User/team | 目标 principal/team | 冲突、禁用账号、外部协作者 |
| Issue/MR | 新 ID 或只读归档 URL | 状态、作者、时间、标签、交叉链接 |
| Review/comment | 新 ID 或归档记录 | Thread、resolution、commit/path/line 上下文 |
| Attachment/wiki | 对象摘要与目标 URL | 字节、MIME、访问控制、引用重写 |
| Release/package | 新 ID、digest | Tag/OID、制品摘要、签名和保留 |
| Pipeline/deployment | 证据归档 ID | 候选、workflow、artifact、环境与结果 |
| Policy/audit | 目标规则 ID/导出 ID | 权限、例外、事件连续性 |

某些平台不允许重建原作者、原时间或审批语义。此时必须区分“在目标系统可继续操作”和“只读归档可审计”，不能用迁移机器人作者冒充历史参与者。原 URL 重定向、数字编号冲突和 commit review anchor 丢失也要进入验收报告。

平台事实容易变化。每次迁移都应为 API schema、导出能力、附件范围、速率限制、权限、套餐、保留期和核对日期建立 fact register；核心方案使用厂商无关对象分类，不把某一平台当前界面当永久模型。

## 切换后的回退不是简单把 DNS 改回去

### 新目标尚未开放写入

可以保持旧源冻结，修复目标并重跑；或在确认目标没有独有事件后撤销切换、恢复旧源写入。仍需核对迁移期间触发的 webhook、CI、邮件和审计副作用。

### 新目标已经产生提交或平台事件

此时不能让两端同时恢复写入。先冻结两端，盘点新目标独有 refs、LFS、issue/评审、制品和部署事件，再选择：

- 继续向前修复目标；
- 把目标独有数据受控迁回旧端后回退；
- 保留双端只读证据，建立新的权威端并重新切换。

Git commit 可通过 ref/object 迁移，平台审批、数字 ID、CI run 和部署副作用不一定可逆。回退 runbook 必须在迁移前定义“开放新端写入”这一不可轻易回头的门槛。

## 迁移验收清单

| 层级 | 通过条件 |
| --- | --- |
| 范围 | 源系统、namespace、时间窗口、排除项和负责人已批准 |
| Git refs | 全 refs 清单相同或存在逐条 old/new 映射 |
| Git 对象 | 目标 `fsck` 通过；关键 commit/tree/tag/notes 和对象格式符合策略 |
| 身份 | 原始 author/committer 可追溯，显示映射与平台 principal 不混淆 |
| 外部对象 | LFS payload、submodule OID、附件、package 和 artifact 可从空缓存取得 |
| 平台关系 | Issue/MR/review/comment/label/milestone 的 ID 与交叉链接可追踪 |
| 策略与安全 | 默认分支、权限、保护、CI、webhook、密钥轮换和审计通过 |
| 切换 | 源端拒写、目标端验收后开放、客户端与机器人指向唯一权威端 |
| 回退 | 新写入前后两种回退路径、决策人和停止条件均已演练 |

## 常见失败与恢复

| 症状 | 原因 | 安全动作 |
| --- | --- | --- |
| 目标缺 branch/tag/notes | 源身份不可见、refspec 不完整或平台隐藏 refs 未导出 | 停止切换，对照源端/平台 refs manifest 补采集 |
| OID 意外变化 | 导入器改身份/时间/message/tree，或发生 LFS/清理重写 | 保留两端，生成 old/new map，判断是否符合批准策略 |
| 默认分支不存在或 clone 指错 | Push refs 不设置目标服务默认 HEAD | 在目标控制面显式设置并用普通 clone 验证 |
| `.mailmap` 后日志“身份正确”但平台仍未关联 | Mailmap 只影响显示，不创建账号或审批映射 | 分别维护 commit identity 与平台 principal 映射 |
| SVN tag 数量对不上 | 非标准布局、tag 后续修改、copy/delete 历史被简化 | 回到 revision/path/copy map，不按目录名机械转 tag |
| 代码可 clone，LFS/submodule 失败 | 只迁移了 Git refs/objects | 冻结开放写入，恢复外部 payload/仓库并从空 cache 验证 |
| 两端都出现新提交或评审 | 写入围栏不完整、机器人仍指向旧端 | 立即冻结两端，盘点独有事件，选择单一权威方向合并 |
| 目标 CI 绿但部署关联错误 | Workflow、凭据、候选或 artifact 映射漂移 | 固定候选与制品 digest，重建完整 CI/CD 证据链 |
| 回退后旧 token 仍能写新端 | 凭据未轮换/撤销，权限复制过宽 | 撤销旧会话与 token，按主体和资源重新授权 |

## 合成实验：全 refs 迁移与切换围栏

本书提供 `scripts/verify-repository-migration-cutover.sh`。实验只使用本地 Git 仓库和虚构身份，不安装/模拟 SVN，不连接托管平台、LFS 或 CI。

在仓库根目录执行：

~~~bash
bash scripts/verify-repository-migration-cutover.sh
~~~

脚本验证：

1. staging mirror 初始同步后，源端晚到提交不会自动出现，最终同步才固定 cutover refs；
2. `push --mirror` 到空目标保持 commit/tree、annotated tag、notes、自定义 refs 和 OID；
3. Push 完 refs 后目标 symbolic HEAD 仍需单独设置；
4. `.mailmap` 改变规范显示，但原 commit bytes 与 OID 在源/目标保持一致；
5. 源端安装明确拒写围栏后，旧客户端 push 失败且 source main 不移动；
6. 客户端把 remote 切到目标后才能继续 push，acceptance clone 取得新提交。

脚本不验证 SVN revision/copy/property、平台隐藏 refs、issue/MR/权限、LFS、签名信任、CI、制品或平台只读模式。真实迁移必须用相应工具和管理员权限在专用环境补齐这些验收项。

## 小结

迁移是一次数据、身份、策略和写入权威的转换。Git 到 Git 原样传输可以保持对象 ID，但默认分支、LFS、平台协作数据、权限和 CI 不会因为 refs 到达而自动成立；SVN 等源系统还需要先定义历史模型、布局、属性和身份映射，生成全新的 Git 对象。

完成标准不是目标页面能打开，而是源端已冻结、目标端从普通身份通过验收、所有差异有映射、外部对象和平台关系可恢复，并且新写入只发生在一个权威端。下一章将把迁移和备份放进仓库损坏、远端丢失与区域级故障预案，讨论服务连续性和恢复切换。

## 资料

- [git-clone](https://git-scm.com/docs/git-clone)
- [git-push](https://git-scm.com/docs/git-push)
- [git-ls-remote](https://git-scm.com/docs/git-ls-remote)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [gitmailmap](https://git-scm.com/docs/gitmailmap)
- [git-svn](https://git-scm.com/docs/git-svn)
- [git-fast-export](https://git-scm.com/docs/git-fast-export)
- [git-fast-import](https://git-scm.com/docs/git-fast-import)
