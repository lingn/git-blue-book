# Submodule 与 subtree：固定外部提交，还是复制一棵树

把一个依赖目录放进仓库，不只是目录组织问题。团队是在决定：依赖是否拥有独立历史和权限，主项目能否原子地修改它，clone 是否必须再访问其他服务，以及某个版本在几年后还能否完整构建。

Submodule 与 subtree 都能让一个项目包含另一个项目，但对象模型完全不同。Submodule 在超级项目的 tree 中保存 mode `160000` 的 gitlink，值是另一个仓库的 commit OID；subtree 把依赖文件和可选历史作为普通 tree、blob 与 commit 导入当前仓库。前者固定“外部仓库的哪个提交”，后者复制“这棵树及其历史怎样进入本仓库”。

进入本章前，读者应理解 tree、commit、引用、clone/fetch、分离 `HEAD`、refspec、远程认证和递归协议的安全边界。读完后，应能在 monorepo、多仓库包、submodule 与 subtree 之间做工程选择；安全初始化和更新 submodule；解释跨仓库 push 为什么不是原子事务；评审 subtree 的导入、同步与 split 历史；并为 CI、迁移和灾难恢复保存足够证据。

本章命令和隔离实验在 Git 2.49.0 与 macOS 上验证。本机提供 `git subtree`；该命令位于 Git 源码的 `contrib/subtree`，不同发行包不保证安装，执行前应先运行 `git subtree -h`。实验只使用临时 local/bare 仓库，不证明公网服务器、托管平台权限、凭据代理或供应链内容可信。

## 先从变更边界选择拓扑

不要从“团队以前用过什么”或“仓库太大”直接选择。先回答以下问题：

1. 主项目与依赖是否经常需要一次原子提交同时修改？
2. 依赖是否有独立发布版本、所有者、访问控制或保留策略？
3. 消费者需要依赖源码，还是只需要已发布包或接口契约？
4. 构建是否允许访问第二个服务；离线和灾备时怎样取得依赖？
5. 依赖历史要在主仓库完整可查，还是只需固定一个已批准版本？
6. 谁负责上游同步、冲突解决、许可证与漏洞响应？
7. 历史和工作区规模是实际测量出的瓶颈，还是未经验证的印象？

| 方案 | 当前 checkout 是否自包含 | 原子跨目录变更 | 独立历史/权限 | 主要运维成本 |
| --- | --- | --- | --- | --- |
| 单一仓库/monorepo | 是 | 是 | 通常共享仓库边界 | 仓库规模、构建图、所有权和策略扩展 |
| 多仓库 + 包/制品注册表 | 否，需要解析已发布版本 | 否，以版本契约协调 | 强 | 发布、兼容、注册表可用性和来源证明 |
| Submodule | 否，需要取得固定外部 commit | 否，至少两个引用更新 | 强 | 递归 clone、凭据、发布顺序、commit 保留 |
| Subtree | 当前文件是 | 主仓库内部是 | 上游仍可独立，导入副本属于主仓库 | 历史复制、同步冲突、split/push 约定 |

如果两个目录几乎每次功能变更都一起修改，拆成 submodule 会把一个提交变成跨仓库协调；如果依赖必须由另一权限域独立发布，强行合进 monorepo 又可能破坏治理边界。Subtree 更适合“消费者希望普通 clone 即可工作，并愿意在主仓库承担一份源码副本”；包管理器更适合“消费者依赖稳定接口和发布版本，而不是直接编辑依赖源码”。

性能也不是单向答案。Submodule 可以只初始化需要的仓库，却增加连接、refs、认证和嵌套维护；subtree 减少运行时依赖，却把导入 tree 和历史加入主仓库。任何“拆仓会更快”或“合仓会更简单”的结论都应回到[性能测量基线](01-measure-before-optimizing.md)验证。

## Gitlink 只保存外部 commit OID

假设超级项目在 `modules/engine` 固定一个依赖。查看候选提交：

```bash
git ls-tree HEAD -- modules/engine
git show HEAD:.gitmodules
git rev-parse 'HEAD:modules/engine'
```

前置条件是在超级项目根目录，候选提交确实包含该路径。第一条输出形如：

```text
160000 commit 8f7...    modules/engine
```

`160000` 表示 gitlink，OID 是依赖仓库的 commit。第三条只解析 tree entry；这个 commit object 通常不在超级项目对象库里。`.gitmodules` 是提交中的文本配置，至少把 submodule 名称映射到 path 和建议 URL：

```ini
[submodule "modules/engine"]
    path = modules/engine
    url = https://code.example.invalid/team/engine.git
```

Gitlink 不记录 URL、分支名、凭据、服务端身份或“这个 commit 已批准发布”。`.gitmodules` 提供 clone 提示，而初始化后的实际 URL 位于超级项目本地 `.git/config`；本地设置可覆盖 tracked 建议。相对 URL 按超级项目默认远端位置解析，适合成组迁移的仓库，但只有新服务保持相对拓扑时才成立。

这条边界带来三个直接结论：

- 依赖主分支向前移动，不会自动改变超级项目 gitlink；可重复构建依赖固定 OID，而不是 branch 名。
- 普通 `git push` 只更新超级项目远端，不知道外部 commit 是否已发布。
- 超级项目 `git fsck --full` 可以通过，即使 gitlink 指向的 commit 在依赖远端已经不存在。

因此，一个版本清单至少记录超级项目 commit、每个 submodule path、gitlink OID、批准的仓库身份和取得结果。只保存 `.gitmodules` URL 或 branch 名不能重建历史版本。

## Clone 默认不等于完整工作区

普通 clone 会取得超级项目的 Git 对象和 gitlink，但默认不初始化 submodule。一个空的 `modules/engine` 目录不是“依赖没有文件”，而是外部仓库尚未取得。

在已知可信的测试项目中：

```bash
git clone --no-recurse-submodules <superproject-url> application
cd application
git submodule status --cached --recursive
git submodule status --recursive
```

第一条显式不递归，便于先审查 `.gitmodules`、gitlink 和目标服务。`status --cached` 显示 index 记录的 OID；普通 status 显示工作区实际 checkout。输出前缀含义是：

| 前缀 | 状态 |
| --- | --- |
| `-` | 尚未初始化 |
| 空格 | 实际 checkout 与记录 OID 一致 |
| `+` | submodule `HEAD` 与超级项目记录不一致 |
| `U` | gitlink 存在合并冲突 |

对完全不受信任的仓库，还应按[不受信任仓库](../part-10/05-untrusted-repositories.md)章节先执行无 checkout、空模板和协议/凭据隔离；这里的普通 clone 不是安全沙箱。

审查通过后，再初始化固定提交：

```bash
git submodule update --init --recursive --checkout
git submodule status --recursive
git status --short --ignore-submodules=none
```

命令会解析 URL、连接一个或多个仓库、创建本地 submodule Git 目录、取得缺失对象，并把每个工作区检出到 gitlink OID。默认 checkout 过程把 submodule `HEAD` 置于 detached 状态，这是固定依赖而非开发分支。第二条每行应以空格开头；第三条无输出才表示超级项目、gitlink 与 submodule 工作区都没有可见偏离。

`--recursive` 会继续处理嵌套 submodule，也会扩大网络、凭据和供应链范围。不要为了修复一次缺失依赖把 `protocol.file.allow=always`、未知协议或通用写凭据设为全局配置。本书实验只因目标是自己创建的本地 bare 仓库，才在单条命令用 `-c protocol.file.allow=always` 显式放行。

### URL 变更必须先审查，再同步本地配置

上游提交修改 `.gitmodules` 后，已经初始化的 clone 仍可能使用 `.git/config` 中的旧 URL。确认新地址、服务器身份、权限和仓库内容映射后运行：

```bash
git diff -- .gitmodules
git submodule sync --recursive
git submodule update --init --recursive --checkout
```

`sync` 把 tracked URL 同步到已初始化 submodule 的本地配置；它不是信任验证。若 diff 出现新主机、非预期协议、路径重用或所有权变化，停止递归并让仓库所有者/安全负责人批准。凭据不要写进 `.gitmodules` URL。

## 更新依赖要先发布外部 commit

默认 `git submodule update` 恢复超级项目记录的固定 OID。`git submodule update --remote` 则先 fetch，再按 `submodule.<name>.branch` 或远端 `HEAD` 选择新提交；它适合显式的依赖升级动作，不适合让 CI 静默追随“最新”。Branch 配置只影响怎样选择候选，最终可复现状态仍由新 gitlink commit 固定。

一次受审查的升级可分为两层：

```bash
git -C modules/engine fetch origin
git -C modules/engine switch --detach <approved-engine-oid>
git add modules/engine
git diff --cached --submodule=log -- modules/engine
git commit -m 'build: advance engine dependency'
```

前置条件是超级项目和 submodule 工作区都已记录或保存本地修改，目标 OID 来自已验证的依赖仓库/发布证据。前两条只改变 submodule 对象库与 checkout；`git add modules/engine` 才把新 gitlink 写入超级项目 index。`--submodule=log` 应展示旧、新 OID 之间的依赖提交，评审者仍须进入依赖仓库检查完整 diff、测试、签名和许可证。

如果新 commit 是在 submodule 工作区本地产生的，先把它发布到批准的依赖远端，再发布引用它的超级项目 commit。可在超级项目根目录设置额外门禁：

```bash
git push --recurse-submodules=check origin main
```

`check` 会在超级项目 push 前拒绝未出现在任何已配置 submodule 远端的相关 commit；它不上传对象，也不证明 commit 位于受保护分支、通过评审或来自正确发布者。`--recurse-submodules=on-demand` 可以尝试先 push 所需 submodule，再 push 超级项目，但多个远端之间仍没有一个原子事务：前一个成功、后一个失败时仍需对账和恢复。

普通 `git push origin main` 没有这个前置检查，完全可能成功发布一个别人取不到的 gitlink。服务端若要阻止，还需具备跨仓库可见性和明确策略；不能把客户端选项当成组织级强制。

## CI 要验证“记录 OID”和“实际 checkout”

CI 不应只检查超级项目 `HEAD`。候选证据应包含所有递归 gitlink，且每个依赖以最小只读凭据从允许的仓库取得。

一个厂商无关的初始化顺序是：

1. 固定超级项目候选 commit，不以浮动 branch 代替；
2. 不递归 clone，先解析 `.gitmodules` 和候选 tree 的 gitlink；
3. 将 path/URL/协议与组织 allowlist 比较，为不同仓库分配独立读取权限；
4. 审查通过后执行 `git submodule update --init --recursive --checkout`；
5. 拒绝 `-`、`+`、`U` 状态和任一脏工作区；
6. 保存超级项目 commit、所有 path/OID/仓库身份、Git 版本和取得时间；
7. 在依赖内部单独处理 LFS、签名、生成器和构建依赖，不能假设超级项目配置自动覆盖。

初始化后可以运行：

```bash
git submodule status --cached --recursive
git submodule status --recursive
git submodule foreach --recursive 'test "$(git rev-parse HEAD)" = "$sha1"'
git status --porcelain=v1 --ignore-submodules=none
```

在超级项目根目录执行。`foreach` 中的 `$sha1` 由 Git 传入，表示直接父项目记录的 commit；单引号必须保留到子 shell，不能在外层提前展开。全部成功且最后一条无输出，证明当前 checkout 与记录 OID 对齐；仍不证明远端长期保留、代码可信或构建可重复。

浅克隆、部分克隆和并发 `--jobs` 可以减少特定负载，却会扩大兼容矩阵。若固定 gitlink OID 不在 shallow 边界、服务端不允许按 OID 获取、嵌套仓库不支持 filter，初始化可能失败。先在完整 clone 建正确性基线，再逐层引入限制，并为每个依赖记录回退到完整 fetch 的路径。

超级项目的普通 `git archive` 也不会替你把外部 submodule tree 递归封装成完整源码包。发布归档应显式组装每个固定 checkout，记录清单和摘要，再按[CI/CD 证据链](../part-6/11-ci-evidence-chain.md)验证制品。

## Submodule 失败时先判断是哪一个仓库

| 症状 | 首要证据 | 安全恢复 |
| --- | --- | --- |
| 路径为空、status 为 `-` | `.gitmodules`、gitlink、active/config 状态 | 审查 URL 后 `update --init`，不要创建同名普通文件 |
| `not our ref`/无法取得固定 OID | gitlink OID、实际 URL、远端 refs、对象保留、权限 | 从批准镜像或其他 clone 恢复同一 commit，再重试；或经评审更新 gitlink |
| status 为 `+` | recorded OID、submodule `HEAD`、本地分支与修改 | 先在 submodule 保存工作，决定升级 gitlink还是恢复固定 OID |
| Submodule 工作区脏 | 子仓库 `status/diff`，超级项目 ignore 配置 | 在子仓库提交、stash 或恢复；不要只设置 `ignore=all` 隐藏 |
| Gitlink merge 冲突为 `U` | 双方 OID、依赖提交图、兼容测试 | 在依赖仓库产生/选择包含所需变化的 commit，取得后 `git add <path>` |
| URL 仍指向旧服务 | `.gitmodules` 与 `.git/config` 来源 | 审批新地址后 `submodule sync`；验证仓库身份再 update |
| Reset/switch 后子模块仍旧 | 超级项目 gitlink与子模块实际 HEAD | 保存子仓库工作后显式递归 update；谨慎使用 `--force` |

`git submodule deinit <path>` 只注销本地配置并移除该 submodule 工作区，gitlink 与 `.gitmodules` 仍在超级项目历史中，`update --init` 可以恢复。`deinit --force` 会丢弃 submodule 工作区修改，只应在已验证的可销毁 checkout 使用。

真正从项目移除 submodule 通常使用 `git rm <path>` 并提交 `.gitmodules` 变化；历史提交仍引用旧 gitlink，本地 `$GIT_DIR/modules/<name>` 也可能为历史 checkout 保留对象。不要把手工删除该目录当成普通清理动作，尤其在事故恢复和离线环境中。

## Subtree 是普通目录和本仓库历史

Subtree 导入后，`vendor/engine` 在当前 tree 中是 mode `040000` 的普通目录，内部文件是本仓库 blobs；没有 gitlink，也不要求消费者理解 `.gitmodules`。普通 clone 可以得到当前候选的完整目录。

先确认工具和工作区：

```bash
git subtree -h
git status --short --branch
git remote -v
```

安装了该命令时，`git subtree -h` 会打印以 `usage: git subtree` 开头的用法；像许多 Git help 路径一样，它仍可能返回非零状态，不能只凭退出码判定缺失。若输出是 `git: 'subtree' is not a git command`，说明当前发行包没有该 contrib 命令或安装不完整；不要改用一组未经验证的 merge/read-tree 命令假装等价。其余输出用于固定当前 branch、修改和上游身份，可能包含内部 URL，应脱敏。

在干净的专用分支导入一个已批准 ref：

```bash
git subtree add \
  --prefix=vendor/engine \
  <dependency-url> <approved-ref> \
  --squash
```

前置条件是 prefix 尚不存在、目标 ref 和仓库身份已经固定，当前用户允许 fetch 并创建提交。命令会取得依赖，创建包含导入 tree 的 commit，并自动提交；它不是仅修改工作区的预览。`--squash` 只把本次选定范围作为一个合并提交导入，避免把所有上游 commit 展开进主线；不加该选项则保留可连接的上游历史。

选择 squash 还是完整历史要保持一致并记录：

| 策略 | 收益 | 代价 |
| --- | --- | --- |
| 完整历史 | 可在主仓库直接追踪上游提交和 ancestry | 对象/refs 视图更大，多个副本或重加时历史更复杂 |
| `--squash` | 主线只看到每次引入范围的摘要，允许切回旧版本 | 主仓库不保留逐提交上游 ancestry，审计需回到来源仓库 |

导入后至少检查普通 tree、来源 ref、许可证、构建和仓库增长；“clone 自包含”不表示来源可信。

### Pull 会 fetch 并 merge，不是锁文件更新

后续同步仍需显式给出来源和 ref：

```bash
git subtree pull \
  --prefix=vendor/engine \
  <dependency-url> <approved-ref> \
  --squash
```

命令先 fetch 再把新版本 merge 到 prefix，自动创建提交；本地对 subtree 的修改会参与合并，可能冲突。执行前要求工作区干净、备份/分支可恢复，并使用与初次导入一致的 squash 策略。若冲突，`git status` 和 `git diff --cc` 读取普通 merge 现场；决定中止时使用 `git merge --abort`，再从原分支 OID 验证工作区。不要删除整个 prefix 后重拷贝，否则会丢掉可审查的合并关系与本地补丁。

上游同步评审应保存旧导入点、新上游 commit、prefix diff、许可证/漏洞扫描和业务测试。Subtree 没有 `.gitmodules` 保存来源 URL 或默认 branch；团队要在仓库文档、脚本或受审策略中记录，不能依赖某位维护者的 shell history。

### Split 生成一条以 prefix 为根的合成历史

若主项目在 subtree 内修复了问题，可抽取历史供上游评审：

```bash
git subtree split \
  --prefix=vendor/engine \
  --annotate='(engine split) ' \
  --branch=engine-export
```

命令遍历主项目历史，保留影响 prefix 的变化，把 prefix 移到新历史根并创建本地 branch；不会自动发布。只要输入历史和 `--annotate` 等选项相同，重复 split 会生成相同 commit OID。大型历史可能耗时，混合修改主项目与 subtree 的 commit 会产生上下文贫乏的抽取说明，所以最好把两类变化拆成提交。

`--rejoin` 把合成历史合回主项目，使后续 split 可以从上次连接继续，却会让 log 出现原提交与合成提交两份视角。决定使用后要统一 annotate、squash/rejoin 策略。`git subtree push` 只是 split 后再 push；上游和主项目引用仍是两个非原子更新，必须像 submodule 一样处理权限、拒绝和中途成功。

## 供应链风险不因固定 OID 消失

Gitlink OID 和 subtree commit 都能固定字节，却不回答这些字节是否应被信任。引入外部源码至少验证：

- URL 最终连接的服务器和仓库身份，而不只是显示名称；
- commit/tag 签名、发布审批和维护者授权；
- 许可证、来源声明、漏洞与恶意代码扫描；
- 生成文件是否可由受信工具重建；
- 依赖仓库中的 hooks、filters、LFS、CI 配置和嵌套 submodule；
- 仓库转移、删除、历史清理与密钥泄漏时的通知/冻结流程。

对 `.gitmodules`、依赖升级脚本、subtree 来源规则和 gitlink 变化设置明确 CODEOWNERS/审批策略。平台是否能对特定路径、跨仓库提交存在性或签名实施强制，属于易变能力，应按产品和核对日期登记，不能从本地实验推断。

## 备份必须覆盖拓扑，而不只是超级项目

Submodule 灾备至少包含超级项目所有承诺 refs、每个历史 gitlink 可达的依赖 commit、依赖仓库对象/refs、URL 映射、访问策略和递归层级。只 mirror 超级项目会完整保存 gitlink，却不保存它指向的对象。恢复演练要在空 cache、主依赖服务不可用的环境中改用批准镜像并成功 checkout 所有固定 OID。

若依赖服务已丢失，但某个开发 clone 仍持有 commit，先把 clone 隔离为证据，验证对象与来源，再将同一 OID 推送到受控恢复仓库；随后审查 `.gitmodules`/本地 URL 迁移。不要重新创建“内容看起来一样”的 commit 冒充原 OID。

Subtree 的当前文件随主仓库备份，构建当前候选不依赖原服务；但若采用 squash，主仓库可能没有完整上游历史，未来同步、许可证取证或向上游回推仍需来源仓库和导入记录。备份范围取决于恢复目标，不能把“当前 tree 可读”误写成“上游关系已恢复”。

## 两种模型之间迁移

迁移会改变 tree entry 类型、构建输入、历史查询和责任归属，应在专用 clone 演练并保存路径级映射。

### Submodule 转 subtree

1. 固定并备份当前 gitlink OID 与依赖仓库；
2. 确保该 commit 已从批准远端取得，验证许可证、LFS 和嵌套依赖；
3. 在迁移分支移除 gitlink/对应 `.gitmodules` 条目并提交；
4. 以同一 OID 作为 ref，用 `git subtree add` 导入空出的 prefix；
5. 验证迁移前 submodule tree 与迁移后普通 tree 字节相同；
6. 更新 CI、CODEOWNERS、漏洞扫描、发布与备份流程。

若需要保留完整上游 ancestry，不要在演练中无记录地加 `--squash`。旧提交仍使用 gitlink，历史构建仍需依赖仓库。

### Subtree 转 submodule

1. 用一致选项 `git subtree split` 生成独立历史并保存 OID map；
2. 先把 split 历史发布到受控依赖仓库，验证从空 clone 可取得；
3. 在超级项目移除普通目录并提交；
4. 用已发布 commit 添加 submodule，审查 `.gitmodules` 并提交 gitlink；
5. 验证主项目构建、递归 checkout、权限和灾备；
6. 明确旧 subtree 历史仍留在超级项目，不因迁移自动缩小。

两个方向都可能打断 path history、bisect、签名和外部链接。迁移完成的证据是候选 tree 等价、来源可恢复、CI/发布使用精确 OID，以及团队明确接受新的跨仓库事务边界，而不是“目录看起来一样”。

## 隔离实验验证了什么

在本书仓库根目录运行：

```bash
./scripts/verify-submodule-subtree.sh
```

前置条件是 Bash、Git 2.49 或兼容实现、已安装 `git subtree`、`cmp`、`grep`、`mktemp` 和可写临时目录。脚本隔离 system/global 配置，只创建自己的临时仓库，退出时删除，不连接网络。

实验先建立依赖与超级项目 bare 远端，断言超级项目保存 mode `160000` 和精确依赖 OID。无递归 clone 的 submodule 未初始化；默认递归 file transport 失败，命令级显式放行后才 checkout 固定 commit，并处于 detached `HEAD`。

随后脚本在 submodule 产生尚未发布的 commit：`push --recurse-submodules=check` 拒绝，而普通 push 可以把相同超级项目 commit 发布到 `unsafe` 分支；fresh clone 能取得超级项目，却无法取得 gitlink。发布缺失依赖 commit 后，递归 update 恢复，主分支的检查式 push 和递归 clone 通过。实验还验证 deinit 不改变历史 gitlink，重新 init 可恢复工作区。

第二部分用 `git subtree add --squash` 导入同一依赖，断言 prefix 是普通 mode `040000` tree、没有 `.gitmodules`，普通 clone 已含文件。上游前进后，`subtree pull` 合并新 tree；本地 prefix 修改经两次相同参数 split 得到同一个合成 OID，并在新历史根出现。成功时只输出：

```text
Submodule gitlink, recursive checkout, publication ordering, and subtree copy/split passed.
```

实验没有验证公网传输、平台跨仓策略、签名、包注册表、LFS、嵌套恶意仓库、访问撤销、并发 push 或大历史性能。Local `file` URL 和一次性身份不能冒充真实服务。

## 小结

Submodule 固定另一个仓库的 commit：历史与权限独立，但 clone、认证、发布、备份和恢复都必须递归。Subtree 把依赖复制为当前仓库的普通 tree：消费者简单、自包含，却由主仓库承担对象增长、同步冲突和合成历史约定。

选择的核心不是哪条命令更短，而是哪一种失败边界符合团队现实。若变更需要原子完成，优先评估单仓库；若依赖以版本契约消费，优先评估包/制品发布；若必须固定独立源码历史，submodule 才有清晰价值；若必须让普通 clone 持有当前源码副本并接受手工同步，subtree 更合适。无论哪种模型，精确 OID 只是可重复性的起点，来源信任、跨仓事务和灾难恢复仍要单独设计。
