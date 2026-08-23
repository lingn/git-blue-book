# 签名不是绿色徽章：对象、密钥与信任策略

提交中的 `author` 和 `committer` 是对象记录的姓名与邮箱，不是身份认证。任何能创建对象的人都能填写这些字段。commit 或 tag 签名增加了一条更强但范围有限的证据：某个私钥的控制者对一组精确的 Git 对象字节生成了密码学签名。

这仍不是“可信代码”的同义词。签名是否有效，取决于验证器拿到的公钥和算法；密钥属于谁、当时是否获准签这个仓库、评审是否完成、构建是否使用该提交，则分别依赖信任策略、授权系统、评审记录和 CI/CD 证据。

进入本章前，读者应理解 commit、附注 tag、对象 ID、历史改写、远程认证、受保护引用和候选提交。读完后，应能解释签名实际绑定的 payload，独立验证 commit 与 tag，比较 OpenPGP、SSH 和 X.509 路线，设计密钥生命周期，并识别“候选提交修改自己的信任策略”这类自授权缺陷。

本章的命令在 Git 2.49.0 上验证。签名依赖 Git 调用的外部程序、密钥格式和组织信任设施；旧版本或受管环境的配置项可能不同。先运行 `git version` 和相应签名工具的版本命令，不要把本章实验输出冒充生产密钥或托管平台结论。

## 一个“签名通过”至少包含四个判断

把界面上的 `Verified` 或命令的一行 “Good signature” 直接翻译成“可信”会丢失关键前提。完整判断至少分四层：

| 层次 | 要回答的问题 | 主要证据 | 不能推出什么 |
| --- | --- | --- | --- |
| 签名存在 | 对象是否携带某种签名 | commit 的签名 header、tag 对象末尾的签名块 | 签名可验证、密钥属于谁 |
| 密码学有效 | 签名是否匹配对象 payload 和某个公钥 | `verify-commit`、`verify-tag`、算法与指纹 | 密钥持有人获组织授权 |
| 身份映射 | 该公钥在验证策略中映射到哪个 principal | OpenPGP 信任库、SSH allowed signers、X.509 证书链 | 这个身份有权批准当前动作 |
| 组织授权 | 该身份在签名时是否可签此仓库、分支或发布 | 受控策略版本、权限记录、密钥有效期、撤销与离职记录 | 代码正确、评审完成、制品安全 |

后面还要继续问：流水线检出的是否正是该对象，构建输入是否完整，制品摘要是否和部署记录一致。签名是证据链中的一段，不是整条链。

### 历史身份、传输身份和签名身份互不替代

一次推送可能同时出现多种身份：

```text
commit author/committer  对象声称的作者与提交者
transport principal      SSH key、令牌或证书认证出的推送者
signature key/principal  对特定 commit 或 tag payload 签名的密钥与映射身份
review approver          平台记录的批准者
build/deploy identity    构建、制品提升和部署使用的自动化身份
```

它们可以是同一个人，也可以完全不同。开发者创建提交、机器人合并、发布服务签 tag、部署服务提升制品，是合理的职责分离；审计记录必须保留这些关系，不能只看提交页头像。修改 `user.email` 不会修复 SSH 权限，成功推送也不证明 commit 签名有效。

## 签名绑定的是对象 payload

Git 先形成待签名 payload，调用外部签名程序生成 detached signature，再把签名嵌入对象或事务。对象 ID 仍由最终对象的全部字节计算，所以签名内容也是对象身份的一部分。

### Commit 签名

`git commit -S` 对 commit payload 签名。它绑定该提交的 tree、父对象列表、作者、提交者、时间、提交说明和额外 header。签名以多行 header 写入最终 commit 对象。

这带来三个边界：

1. 签名当前 commit 会绑定父提交 ID，但不等于逐个验证所有祖先的签名和授权；
2. 签名 merge commit 会绑定两个或更多父对象以及最终 tree，但不证明冲突解决经过正确测试；
3. amend、rebase、cherry-pick 或 squash 会生成新 commit，对旧对象的有效签名不会自动迁移到新对象。

“签名历史”因此是一条对象级属性，不是一段 diff 可以继承的装饰。历史改写后若策略要求签名，必须由有权主体对新对象重新签名并重新验证。

### Tag 签名

`git tag -s` 创建附注 tag 对象并对其 payload 签名。payload 包含目标对象 ID 与类型、tag 内部名称、tagger、时间和说明；签名块追加在 tag 对象中。轻量 tag 只有 `refs/tags/...` 引用，没有可承载 tag 签名的对象。

签名 tag 可以表达“发布身份认可这个精确目标和这段发布说明”。它不等于目标 commit 自己有签名，也不保护远端 `refs/tags/...` 的引用更新事件。验证发布时要同时固定：

```text
远端标签引用的对象 ID
tag 对象的签名验证结果
tag 剥离后的目标对象 ID
与该目标关联的制品摘要和发布记录
```

若服务器允许强制移动或删除标签，同名标签稍后可能解析到另一个对象。只保存 `v1.4.0` 这个字符串不足以审计。

## 三类格式解决的是兼容与运维选择

Git 2.49 的 `gpg.format` 支持 `openpgp`、`ssh` 和 `x509`。配置名沿用历史上的 `gpg`，不表示三种格式都使用 OpenPGP。

| 路线 | 常见签名工具与信任根 | 适合的组织条件 | 主要运维问题 |
| --- | --- | --- | --- |
| OpenPGP | GnuPG、组织维护的公钥与信任策略 | 已有 PGP 密钥生命周期或开源发布生态 | key certification、子密钥、过期和撤销分发 |
| SSH | `ssh-keygen`、allowed signers、SSH CA 或受控目录 | 已有成熟 SSH 密钥/证书管理，希望复用工具链 | 签名 key 与登录 key 是否分离、principal 映射、有效期和 KRL |
| X.509 | `gpgsm` 等 CMS/S/MIME 工具、证书链与企业 PKI | 已有企业 CA、证书签发与吊销基础设施 | EKU/策略、证书链、OCSP/CRL 和离线验证 |

选择不应从“哪个命令最短”开始，而应从密钥登记、硬件保护、轮换、撤销、离职回收、离线验证、机器人身份和审计留存开始。SSH 登录认证和 SSH 对象签名可以使用同类密钥格式，但仍应按用途、权限和暴露面决定是否分离密钥。

托管平台怎样把某种 key 映射成绿色徽章属于平台事实。若正文或组织规范依赖该表现，应记录产品、权限、版本和核对日期；本章只使用 Git 本身的验证语义。

## 先观察当前仓库的签名环境

在目标仓库根目录执行以下只读检查：

```bash
git version
git config --show-origin --get gpg.format
git config --show-origin --get user.signingKey
git config --show-origin --get gpg.ssh.allowedSignersFile
git config --show-origin --get gpg.ssh.revocationFile
```

命令读取最终生效值及其来源，不修改仓库。没有输出且退出码为 1 通常表示未配置该项；不要把它当作签名无效，也不要立即覆盖全局或系统策略。`user.signingKey`、agent、外部程序和信任库可能来自不同作用域，排障时要分别记录。

读取某个候选 commit 的签名摘要：

```bash
candidate_commit="$(git rev-parse --verify 'HEAD^{commit}')"
git show --no-patch \
  --format='%H%nstatus=%G?%nsigner=%GS%nkey=%GK%nfingerprint=%GF%nsubject=%s' \
  "$candidate_commit"
```

前提是当前 `HEAD` 就是待判断候选，而不是稍后移动的分支名。命令只读取对象和当前信任配置。`%G?` 为 `G` 表示在当前验证环境中得到 good signature，`N` 表示没有签名；其他状态和 signer 字段必须结合当前 Git/签名后端诊断，不能把任意非空输出视为通过。哈希、指纹和 signer 会随对象与策略变化。

要把验证失败作为程序门禁，应依赖命令退出状态，而不是解析本地化人类文案：

```bash
git verify-commit "$candidate_commit"
```

成功时命令退出 0，并把签名后端的说明写到输出；无签名、密钥未知、策略不信任、签名损坏或外部程序失败时返回非零。它不修改对象、index 或引用。保存门禁证据时记录 Git 版本、对象 ID、策略版本、签名格式、key fingerprint、principal、结果和验证时间。

### 验证 tag 时不要只交给一个可变名字

在已经 fetch 到目标 tag 对象的仓库中：

```bash
tag_name=v1.4.0
tag_object="$(git rev-parse --verify "$tag_name^{tag}")"
release_commit="$(git rev-parse --verify "$tag_name^{commit}")"
git verify-tag "$tag_object"
printf 'tag=%s\ncommit=%s\n' "$tag_object" "$release_commit"
```

`^{tag}` 要求名字最终是 tag 对象；轻量标签会在这里失败，防止把“没有附注 tag 对象”误当作“签名标签”。`verify-tag` 只读对象并按当前信任策略返回成功或失败。它验证 tag payload，不验证制品仓库、部署环境或远端引用保护。

## 配置 SSH 签名时，签名 key 与信任策略是两件事

下面的配置片段用于说明状态变化，不应直接把示例路径复制到个人机器。前提是安全团队已经给出签名私钥/agent 用法和受控 allowed signers 文件，并确认 Git 与 OpenSSH 版本兼容：

```bash
git config --local gpg.format ssh
git config --local user.signingKey /secure/path/release_signing_key
git config --local gpg.ssh.allowedSignersFile /etc/company/git-allowed-signers
git config --show-origin --get-regexp '^gpg\.|^user\.signingKey$'
```

前三条修改当前仓库的 `.git/config`，不创建签名、不改变历史，也不把密钥内容写入 Git 对象。私钥路径仍可能泄漏本机布局；使用 agent 时，`user.signingKey` 可按当前 Git 文档配置为公钥路径或 `key::...` 形式，私钥必须只在受控 agent、硬件设备或秘密存储中可用。

`gpg.ssh.allowedSignersFile` 每行把 principal 映射到允许的 SSH 公钥。公钥存在于文件中时，Git 的 SSH 验证才会把它视为受信任；`gpg.ssh.revocationFile` 可指向 SSH KRL 或撤销公钥清单。allowed signers 的有效期和撤销策略必须由组织生命周期系统维护，不能依赖每位开发者手工同步。

回退自己刚添加的本地配置前，先用 `--show-origin` 确认值确实来自当前仓库：

```bash
git config --local --unset gpg.ssh.allowedSignersFile
git config --local --unset user.signingKey
git config --local --unset gpg.format
```

这些命令只删除当前仓库配置，不删除密钥、不撤销公钥，也不会移除已有对象里的签名。若组织配置来自系统文件、条件 include 或设备管理，应由相应管理面修改，不能用本地 unset 假装完成撤销。

## 创建签名对象的失败边界

### 签名 commit

假设 index 已经只包含本次原子变化，工作区测试通过，当前分支允许直接提交：

```bash
git diff --staged --check
git diff --staged
git commit -S -m 'fix: preserve retry idempotency'
git verify-commit HEAD
```

`commit -S` 先形成 payload，再调用配置的签名程序。成功后创建带签名的新 commit，并移动当前分支；工作区和 index 的普通提交变化与未签名 commit 相同。签名程序找不到、agent 没有 key、硬件设备未解锁或算法被拒绝时，commit 不应创建，已暂存内容仍留在 index。先用 `git status` 和 `git rev-parse HEAD` 确认状态，再修复签名环境重试。

不要把 `--no-gpg-sign` 当作默认恢复命令。它会明确绕过 `commit.gpgSign=true`，可能制造平台随后拒绝的提交。只有事故流程允许无签名对象并记录例外时才能使用。

全局启用 `commit.gpgSign` 会影响 rebase 等批量生成 commit 的操作，也可能频繁调用 agent 或硬件 key。团队应先验证开发工具、机器人、离线工作和历史改写流程，再决定是每个 commit 必签，还是只在合并、发布等信任边界签名。

### 签名发布 tag

先固定已经通过评审和构建的候选 commit：

```bash
release_commit="$(git rev-parse --verify 'refs/remotes/origin/main^{commit}')"
git tag -s -m 'Release 1.4.0' v1.4.0 "$release_commit"
git verify-tag v1.4.0
git rev-parse 'v1.4.0^{}'
```

`tag -s` 成功后创建 tag 对象和本地 `refs/tags/v1.4.0`；若签名失败，标签引用不应出现。命令没有 `-f`，同名标签已存在时会拒绝而不是覆盖。验证通过后仍要比较剥离目标是否等于 `release_commit`，再按发布流程推送和关联制品。

若本地 tag 错指但尚未共享，先保存错误对象 ID 与原因，再删除本地引用并用正确目标重建。已经共享的发布标签不应静默强制移动；创建新版本或走带审计的撤销流程，并评估缓存、镜像、消费者和制品记录。

## 信任策略不能由待验证对象自行决定

SSH 验证最常见的设计缺陷不是算法问题，而是信任根来源错误。假设 CI 检出候选提交后执行：

```bash
git config gpg.ssh.allowedSignersFile "$PWD/ci/allowed_signers"
git verify-commit HEAD
```

如果候选可以同时修改 `ci/allowed_signers`，攻击者就能提交自己的公钥、用对应私钥签 candidate，然后让 candidate 自己宣布该 key 受信任。密码学验证会真实成功，但组织授权问题被循环定义了。

更可靠的验证流程是：

1. 从候选事件固定不可变 commit ID，不用可移动分支名；
2. 从候选之外取得信任策略，例如受保护控制面、runner 镜像、密钥目录服务，或已经验证的目标分支基线；
3. 记录策略自身的版本、摘要和授权来源；
4. 用该策略验证候选对象和预期 principal/key；
5. 检查签名者在签名时是否有权执行当前动作；
6. 把结果绑定到候选 ID，候选改变后重新验证；
7. 引用更新、制品构建与部署继续使用同一候选证据链。

把 allowed signers 放在仓库中并非一律错误，但更新顺序必须避免自授权。例如只从受保护目标分支读取策略，要求旧策略中的已授权 key 批准新增 key，并通过平台权限限制策略路径。单独的 `CODEOWNERS` 文本也不能证明服务端真的强制了审批。

## Principal 名称来自策略，不是 SSH 签名内置身份

SSH 签名把 key 与 payload 关联；`allowedSignersFile` 中的 principal 用来标识该 key。相同公钥若在另一份策略中写成另一个 principal，验证输出的 signer 名称也可能改变。因此：

- 不根据 `%GS` 的字符串外观自动授予权限；
- key fingerprint 才是稳定的密码学标识，principal 是策略映射；
- principal 到员工、机器人、仓库角色的关系必须有可审计来源；
- 同一 key 不应无记录地同时代表个人、发布机器人和部署服务。

OpenPGP user ID 或 X.509 subject 也不能只凭可读名称判断归属。身份绑定强度取决于 key enrollment、证书签发和组织目录，而不是姓名看起来像公司邮箱。

## 把组织授权落成候选之外的策略记录

Git 可以告诉验证器“哪个 key 签了这个对象”，却不会替组织回答“这个 key 当时是否有权执行 release”。如果把签名者、动作和候选 OID 的授权判断留在一个模糊的绿色状态里，审计无法区分密码学通过与业务允许。

一种可审计的做法是维护候选之外的授权投影。它可以来自受保护的策略仓库、签名服务或平台控制面；无论来源是什么，都至少固定以下字段：

| 字段 | 作用 | 缺失时的边界 |
| --- | --- | --- |
| candidate OID | 把授权绑定到精确 commit 或 tag target | 只写分支名会随引用移动 |
| key fingerprint | 绑定密码学 key，而不是可变显示名 | 只写邮箱可能把两个 key 混为一谈 |
| principal | 记录组织目录中的主体映射 | 不能由 commit 自己提供 |
| action | 说明是 release、merge 还是 deploy | “已签名”不自动授权所有动作 |
| policy version/expiry | 说明使用哪份规则及其有效窗口 | 无版本无法复现历史决定 |
| decision | `allow` 或 `deny` 及原因 | 失败与未评估不能都写成拒绝 |

门禁应先对 candidate 做密码学验证，再用候选之外的策略按 OID、fingerprint、principal 和 action 精确匹配。任何一项不匹配都进入 `deny` 或 `inconclusive`，不能仅因为签名有效就降级为允许。策略文件本身也要有独立的版本摘要、审批记录和访问控制；把它复制进待验证提交后再读取，会重新引入候选自授权问题。

下面的命令只演示如何在一次性实验目录中读取策略投影。`release-authorization.tsv` 是本地合成文件，不是 GitHub、GitLab 或任何制品平台的权限 API：

```bash
candidate_oid="$(git rev-parse --verify 'HEAD^{commit}')"
fingerprint="$(git show --no-patch --format='%GF' "$candidate_oid")"
principal="$(git show --no-patch --format='%GS' "$candidate_oid")"
awk -F '\t' \
  -v oid="$candidate_oid" \
  -v fingerprint="$fingerprint" \
  -v principal="$principal" \
  '$1 == oid && $2 == fingerprint && $3 == principal && $4 == "release" && $5 == "allow" { found = 1 } END { exit found ? 0 : 1 }' \
  /path/to/external/release-authorization.tsv
```

命令在验证 clone 中只读取对象和候选之外的策略文件，不改变 refs、index 或工作区。退出码为 0 只表示这五个字段在该策略版本中存在一条允许 release 的记录；退出码为 1 可能是签名者未授权、候选已过期、策略没有该 OID，或文件读取失败，必须结合策略加载日志分流。不要把真实 fingerprint、内部 principal 或 token 写入公开 CI 输出。

## 组织授权实验验证了什么

本章的隔离实验额外在临时目录生成一份只允许 release key 对“第一个已签名 commit”执行 `release` 的 TSV 策略。它先用外部 allowed signers 验证签名，再按 candidate OID、key fingerprint、principal 和 action 匹配 `allow`；候选提交即使通过了自己修改的 allowed signers，也无法在外部授权清单中取得 release 权限。

这个实验把“密码学有效”和“组织允许”拆成两个明确的退出码。它没有模拟平台管理员、分支保护、审批记录、密钥撤销服务或时间戳；生产门禁仍应从受保护控制面取得同等字段，并把策略版本、审批者、评估时间和服务端审计 ID 绑定到发布证据。

## 密钥生命周期决定历史验证能持续多久

签名策略至少覆盖以下状态机：

```text
申请 -> 身份核验 -> 签发/登记 -> 激活 -> 使用与监测
                                -> 轮换 -> 历史验证
                                -> 撤销/离职/泄漏处置
```

### 登记与存储

记录 key fingerprint、主体、用途、允许的仓库或动作、签发与到期时间、登记审批和恢复联系人。私钥不得进入 Git 历史、CI 日志、普通构建缓存或容器层。高价值发布 key 应考虑硬件保护、短期证书、双人审批或隔离签名服务。

### 轮换

新旧 key 可以在有限窗口并存。验证策略要保留历史对象需要的旧公钥和有效期，而签名系统停止用旧私钥生成新签名。直接删掉旧公钥会让过去的合法签名无法按原策略验证；永远保留为“当前可签”又扩大风险窗口。

### 撤销与泄漏

私钥疑似泄漏时，先阻止新签名继续被接受，再调查该 key 在风险窗口内签过哪些对象、更新过哪些引用、触发过哪些构建和发布。密码学上仍能匹配的旧签名，可能因策略撤销而不再获得组织信任。

只用 commit/tag 自带时间判断“泄漏前签名”不够。Git 对象时间由创建者提供，组织还需要服务器引用更新日志、签名服务日志或可信时间戳来界定事件。轮换、到期和 allowed signers 的时间范围是控制措施，不是不可伪造的审计时钟。

### 机器人与 CI

机器人签名证明自动化身份控制的 key 对对象签了名，不证明人类逐行审查。机器人 key 应使用最小仓库/动作权限、短生命周期和可追踪工作负载身份；签名事件要关联流水线版本、输入 candidate、审批和制品摘要。把长期个人私钥复制进 CI 会同时破坏个人归属和秘密管理。

## 按信任边界制定签名政策

不是所有团队都需要每个开发 commit 强制签名。可按风险选择：

| 边界 | 可选政策 | 还需要的控制 |
| --- | --- | --- |
| 个人本地提交 | 可签，用于来源提示 | 本地密钥保护；不把未共享签名当审批 |
| 进入受保护主线 | 要求被允许的开发者或合并机器人签名 | 审批、必需检查、候选过期和条件引用更新 |
| 发布 tag | 由独立发布身份签名并固定 target | tag 保护、制品摘要、发布审批和部署记录 |
| 供应链证明 | 由受控构建身份签署 provenance/制品 | 构建隔离、输入清单、透明日志和验证策略 |

逐步落地通常比“一次性所有提交必签”更可靠：先观察现有签名格式和失败率；再对发布 tag 建立强制验证；然后把主线或高风险路径纳入；最后处理机器人、离线开发、密钥轮换和紧急例外。门禁要定义 fail closed 的范围，也要有带审批和事后复盘的 break-glass 流程。

## 常见失败与恢复

| 症状 | 首要证据 | 安全处理 |
| --- | --- | --- |
| `commit -S` 找不到 key | `gpg.format`、`user.signingKey`、agent/设备状态、签名程序版本 | 不创建无签名替代；确认 HEAD 未移动、index 仍在后修复 key |
| `verify-commit` 报无签名 | `%G?`、commit 原始 header、候选 ID | 判断策略是否要求签名；不要把作者邮箱当签名 |
| 本机通过、CI 失败 | 两端 Git/签名工具版本、信任库、revocation、策略摘要 | 对齐受控验证环境，不能把 CI 信任库替换成候选自带文件 |
| principal 正确但 key 不符 | fingerprint、allowed signers 来源和登记记录 | 按 fingerprint 调查，不只比较姓名；拒绝未登记 key |
| rebase 后签名消失 | 新旧 commit ID、`range-diff`、新对象 `%G?` | 按共享历史策略重新评审并由有权主体重签新对象 |
| tag 签名有效但部署错误 | tag/commit ID、制品摘要、部署和运行记录 | 保留签名证据，按发布链定位，不把签名当部署证明 |
| key 泄漏或离职 | key 使用范围、引用更新与签名服务日志 | 撤销信任、轮换、枚举受影响对象和发布，记录历史处置策略 |

验证错误时不要反复改全局配置直到出现绿色结果。先复制完整错误、Git/签名工具版本、对象 ID、fingerprint 和配置来源；在隔离环境用明确策略复现。更换信任库会改变“谁被信任”的结论，本身就是受控安全变更。

## 隔离实验验证了什么

在本书仓库根目录运行：

```bash
./scripts/verify-signatures-trust.sh
```

前置条件是 Bash、Git 2.49 或兼容的 SSH 对象签名实现、`ssh-keygen`、`awk` 和可写临时目录。脚本创建临时仓库与两对无口令实验 key，设置隔离的系统/全局 Git 配置，退出时删除整个实验目录。它不读取个人 key、不连接网络、不修改蓝皮书仓库，也不适合生成生产密钥。

实验先用 release key 创建签名 commit 和签名附注 tag，断言 `verify-commit`、`verify-tag`、tag 对象类型和剥离目标；同时在实验目录写入一条只允许该 commit 执行 `release` 的外部授权记录，并按 OID、fingerprint、principal 和 action 验证记录命中。随后创建无签名 commit，确认 `%G?` 为 `N` 且严格验证失败。

最后，另一个 key 创建候选提交，并把工作区中的 `ci/allowed_signers` 改为信任自己。把验证配置指向候选工作区时，该提交通过；切换到候选之外、只允许 release key 的策略时，同一对象被拒绝；即使只看密码学结果，外部授权清单也因 candidate OID、fingerprint 和 principal 不匹配而拒绝 release。原 release commit/tag 仍通过。实验由此验证的是“验证结果依赖 payload、公钥、信任策略和独立授权记录”，不是攻击者签名在任何组织中都可信。

成功时只输出：

```text
SSH commit/tag signing, unsigned rejection, external trust, and release authorization passed.
```

实验没有验证硬件 key、SSH agent、OpenPGP web of trust、企业 CA、托管平台徽章、服务器端强制规则、可信时间戳或真实撤销服务。这些能力必须在专用环境按当前产品和组织策略采集证据。

## 小结

commit 签名绑定 commit payload，tag 签名绑定附注 tag payload；对象 ID 使任何字节变化生成新身份。密码学有效只回答“这个 key 签了这个对象”，principal 映射、组织授权、评审、构建和部署仍需独立证据。

成熟策略从信任根和密钥生命周期出发：固定候选对象，从候选之外取得验证策略，按 fingerprint 与授权范围判断，记录策略版本，并把结果接入引用更新和发布证据链。签名由此成为可审计控制，而不是一个脱离上下文的绿色徽章。
