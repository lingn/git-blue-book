# 签名无法验证与密钥状态异常：从对象到信任根

“签名失败”不是一个足够精确的故障描述。候选 commit 可能根本没有签名，签名可能与对象字节不匹配，公钥可能未知，principal 可能没有被当前信任策略允许，密钥可能已撤销或超出有效时间；tag 还可能签名有效但指向了错误的 commit。把这些状态都归结为“换一把 key”会破坏审计边界，甚至让候选提交自己修改信任策略后通过验证。

第十篇已经说明签名绑定的对象 payload、签名格式和密钥生命周期。本章只处理故障现场：如何冻结候选 OID，按存在性、密码学、身份映射和组织授权分层采证，怎样在 CI 和发布流程中使用候选之外的信任根，以及签名失败后什么可以修、什么必须停止。

本章以 Git 2.49.0、SSH 对象签名和隔离的 allowed signers 文件为基线，核对日期为 2026-08-22。OpenPGP、X.509、硬件密钥、托管平台徽章、时间戳服务和企业撤销系统必须在目标环境按产品版本、权限和组织策略核对；本地实验不冒充这些服务。

## 先区分六类失败

在签名验证现场，先固定候选 commit 或 tag 的完整 OID、Git 版本、签名格式、验证策略来源和原始 stderr。不要先改全局配置、删除 tag、重写历史或把仓库里的策略文件复制进验证环境。

| 状态 | 首要证据 | 可以得出的结论 | 不能得出的结论 |
| --- | --- | --- | --- |
| 无签名 | commit 原始 header、format %G?、verify-commit 退出码 | 对象没有当前格式的签名 | 作者字段可信、提交一定恶意 |
| 签名不匹配/损坏 | verify-commit 输出、候选完整 OID、对象原始字节 | 当前签名不能证明这个对象 | 私钥一定泄漏，可能是对象被改写或工具故障 |
| key 未知 | fingerprint、验证器 keyring/allowed signers、工具版本 | 当前环境没有该公钥或信任记录 | key 一定不属于该主体 |
| principal/key 未授权 | 策略版本、fingerprint 到主体的登记、仓库/动作范围 | 密码学成立但当前策略不允许 | 代码内容一定错误 |
| 已撤销/过期 | revocation 文件、有效时间窗口、撤销事件和验证时间 | 该 key 当前不能用于这项信任决策 | 历史上所有签名都无效，需按时间策略判断 |
| tag 目标错误 | tag object OID、剥离目标 OID、远端 ref 快照 | tag 自身可验证但发布目标不对 | 签名工具或密钥故障 |

结论要写成带范围的事实，例如“在指定时间、Git 版本、策略摘要和 fingerprint 下，commit OID Z 的密码学验证通过，但 principal 不在发布规则中”，不要只写“签名不可信”。

## 第一轮只读采证

在报障发生的同一个仓库中执行，先把输出写入受限证据目录：

~~~bash
git version
candidate="$(git rev-parse --verify 'HEAD^{commit}')"
git rev-parse --show-object-format
git cat-file -t "$candidate"
git show --no-patch \
  --format='%H%n%G?%n%GS%n%GK%n%GF%n%aI%n%cI%n%s' \
  "$candidate"
git config --show-origin --show-scope \
  --get-regexp '^(gpg\.|user\.signingKey$|commit\.gpgSign$)' || true
~~~

前置条件是仓库已确认可信，HEAD 是待验证候选而不是会继续移动的分支名。命令读取对象和配置，不修改 refs、index 或工作区；配置输出可能暴露私钥路径、内部策略位置和条件 include，原件不能直接公开。

严格门禁依赖退出状态：

~~~bash
set +e
git verify-commit "$candidate" >verify.stdout 2>verify.stderr
verify_status="$?"
set -e
printf 'candidate=%s\nexit=%s\n' "$candidate" "$verify_status"
~~~

退出 0 只表示当前验证器接受该 commit 的签名判断。非零要结合 stdout/stderr 和格式状态分流，不能把任意非零都当作“没有签名”。保存 Git 版本、外部签名工具版本、fingerprint、principal、信任策略摘要、撤销文件摘要和验证时间。

若验证的是发布 tag，先固定 tag object 和剥离目标：

~~~bash
tag_ref='refs/tags/v1.4.0'
tag_object="$(git rev-parse --verify "$tag_ref^{tag}")"
tag_target="$(git rev-parse --verify "$tag_ref^{}")"
git cat-file -t "$tag_object"
git verify-tag "$tag_object"
printf 'tag=%s\ntarget=%s\n' "$tag_object" "$tag_target"
~~~

^{tag} 会拒绝轻量 tag，避免把“没有 tag 对象”误当作签名失败。verify-tag 只验证 tag payload，不验证 tag ref 没有被强制移动，也不验证制品和部署。远端 ref 必须另用受控只读查询和审计记录核对。

## 按四层证据处理失败

### 1. 对象是否带签名

Commit 原始内容可以直接观察是否有 gpgsig header：

~~~bash
git cat-file commit "$candidate" | sed -n '1,24p'
git show --no-patch --format='%G?' "$candidate"
~~~

空的 %G? 或状态 N 只说明当前对象没有被验证为带签名。不要修改 author/committer、重新设置 user.email 或复制一个签名到对象中；commit payload 改变就会产生新 OID。若团队只要求发布 tag 签名，无签名开发 commit 可能是允许状态；若主线门禁要求签名，应进入受控补救，而不是静默绕过。

### 2. 密码学是否匹配

密码学失败可能由截断/损坏对象、错误签名程序、算法不兼容、错误 key 或对象被重写造成。保存完整 OID、原始对象和验证器输出，在隔离副本重复一次：

~~~bash
git fsck --full --no-progress
git cat-file -p "$candidate" >candidate.object
git verify-commit "$candidate"
~~~

fsck 通过只说明 Git 对象图可读，不说明签名 key 属于正确主体。不要为了让 verify-commit 通过而替换对象、使用 replace ref 或直接重建同名分支；这些都会改变证据范围。

### 3. key 和 principal 是否映射

SSH 签名验证使用 allowed signers 文件把 principal 映射到公钥；OpenPGP 和 X.509 有各自的 keyring、证书链和信任规则。验证现场至少记录 fingerprint，而不是只记录显示姓名：

~~~bash
git config --show-origin --get gpg.ssh.allowedSignersFile
git config --show-origin --get gpg.ssh.revocationFile
git show --no-patch --format='%GF%n%GS' "$candidate"
~~~

如果 key 未知，先让密钥 owner 或安全团队核对登记、用途和来源。不要把候选提交中的 ci/allowed_signers、仓库 local config 或评审附件自动当作权威信任根。

### 4. 当前动作是否被授权

密码学有效的签名只证明某个 key 对某个对象签过名。发布、合并和主线更新还要查 principal 是否属于允许角色，key 是否在签名时有效，仓库/分支/动作是否在范围内，审批和必需检查是否绑定同一 candidate，策略版本是否已部署。这个结论来自组织控制面、审计日志和发布记录，不是 Git 客户端能独立证明的。

## 密钥过期、撤销和时间边界

记录至少四个时间：对象中的 author/committer/tagger 时间，签名服务或平台的事件时间，key 或证书的有效起止时间，以及验证器读取策略和撤销信息的时间。

对象时间由创建者填写，不能单独证明签名发生在撤销之前。某些验证后端允许按签名时间判断，另一些策略以当前撤销状态为准；组织必须明确语义并用真实工具版本验证。删除旧公钥可能让历史合法签名无法再验证，永远保留旧 key 又可能允许新对象继续使用。轮换要区分停止新签名和保留历史验证。

若怀疑私钥泄漏：

1. 先阻止该 key 继续签新对象或更新高价值 refs；
2. 固定 fingerprint、受影响 refs、签名对象和时间窗口；
3. 从可信审计或签名服务取得撤销/禁用事件；
4. 盘点该 key 签过的 commit、tag、制品和部署；
5. 用新信任根重建必要对象或发布，不静默移动旧 tag；
6. 保留旧策略和验证结果，说明历史签名按哪个时间规则解释。

修改 allowed signers 文件改变未来验证判断，不等于清理 Git 历史；远端 refs、镜像和下游 clone 仍需独立处置。

## 历史改写后签名为什么消失

amend、rebase、cherry-pick、squash 和冲突重解都会产生新 commit。旧 commit 的 gpgsig header 不会自动迁移：

~~~bash
old_commit='OLD-FULL-OID'
new_commit='NEW-FULL-OID'
git show --no-patch --format='%H %G? %GF %s' "$old_commit" "$new_commit"
git range-diff "$old_commit^..$old_commit" "$new_commit^..$new_commit"
git verify-commit "$new_commit"
~~~

前置条件是两个对象都仍可读，且比较范围已由评审固定。range-diff 只能帮助比较补丁序列，不把旧签名转移到新对象。若新对象必须被签名，重新由有权主体签名并重新走评审/CI；若历史已共享，不要用无条件 force push 覆盖别人依赖的对象。

## CI 和发布门禁必须使用候选之外的策略

CI 任务应把候选 OID 从可信事件或控制面传入，并从受控镜像、系统策略或独立签名服务取得信任根：

~~~bash
candidate_oid='FULL-OID-FROM-TRUSTED-EVENT'
test "$(git rev-parse HEAD)" = "$candidate_oid"
git config --local gpg.ssh.allowedSignersFile /run/company/git-allowed-signers
git verify-commit "$candidate_oid"
git status --porcelain=v1
~~~

这段示例会写当前 checkout 的 local config，适合一次性 job 目录；不要在长期开发 clone 中照抄路径。策略文件必须在候选代码之外供应，并且其 digest、版本、获取身份和有效时间写入构建证据。若构建 checkout 是 merge queue 生成的临时 commit，验证该 candidate，不要验证触发事件里的原始 branch tip。

失败时：

- candidate 与 HEAD 不一致：停止构建，检查 checkout/队列竞态；
- 签名存在但策略不信任：进入授权审批，不替换成候选自带策略；
- 验证器或 key 工具版本不一致：固定受控 runner 镜像，保存版本矩阵；
- 验证通过但制品/部署 OID 不一致：按第八篇证据链继续排查，不回头改签名；
- 密钥服务不可用：按组织 break-glass 流程停止或转人工，不用长期个人 key 绕过。

## 受控恢复和停止条件

签名故障的动作卡应写明：

~~~text
candidate：完整 commit/tag OID
现象：原始 stdout/stderr、退出码、验证时间
假设：无签名 / key 未知 / 策略不授权 / 对象损坏 / tag 目标错误
前置条件：对象可读、信任根来源固定、共享边界已确认
动作：只读验证，或在隔离 clone 重新签名/重建 tag
应改变：明确的新对象或新的候选 ref
不得改变：原始 refs、远端共享 tag、证据文件、候选外信任根
停止：OID 不符、策略来源不可证明、旧 key 仍可写、审计缺口
验证：对象签名、principal、授权、CI checkout、制品 digest、部署记录
恢复：从原始 refs/备份重建，不连续覆盖现场
~~~

下列情况立即停止并升级：验证策略只能从候选代码取得；fingerprint 无法映射到稳定主体；撤销时间和签名时间无法解释；远端 tag 在验证期间移动；签名通过但 candidate、制品或部署不一致；或需要关闭验证、使用未知 key、修改对象才能继续。

## 隔离实验：验证对象、策略和图不被诊断改变

本书提供 scripts/verify-signature-troubleshooting.sh。在仓库根目录执行：

~~~bash
bash scripts/verify-signature-troubleshooting.sh
~~~

实验在 mktemp 中生成两对一次性 SSH key 和外部 allowed signers 文件，验证：

1. 签名 commit 和附注 tag 在正确策略下通过，tag 对象和剥离目标保持一致；
2. 无签名 commit 的 %G? 与严格 verify-commit 失败，验证前后 HEAD、refs、index 和工作区不变；
3. 候选提交修改仓库内 allowed signers 后，在候选自带策略下看似通过，但切回候选之外的外部策略后被拒绝；
4. 验证策略切换、失败采集和 tag/commit 查询不会移动 refs 或改变工作区，实验保留 fingerprint、OID 和策略摘要；
5. 本地实验只验证 SSH 对象签名和外部信任文件，不模拟 OpenPGP/X.509、硬件密钥、托管平台、撤销服务或组织授权。

实验不把 key 生成、allowed signers 或 verify-commit 输出当作生产身份；真实密钥、撤销、时间戳、平台审批和发布证据必须在专用环境验证。

## 小结

签名排障先分层：对象有没有签名，签名是否匹配，key 映射到谁，当前动作是否授权。密钥过期或撤销还要结合策略的时间语义；历史改写后新 commit 必须重新签名；tag 签名有效也要独立核对 tag ref、目标 OID、制品和部署。

诊断动作应保持只读和可回放，信任根必须来自候选之外。任何需要关闭验证、替换对象、使用候选自带策略或静默移动共享 tag 的“修复”都应停止并升级。

## 资料

- [git-verify-commit](https://git-scm.com/docs/git-verify-commit)
- [git-verify-tag](https://git-scm.com/docs/git-verify-tag)
- [git-show](https://git-scm.com/docs/git-show)
- [git-rev-parse](https://git-scm.com/docs/git-rev-parse)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
- [gpg-interface](https://git-scm.com/docs/gpg-interface)
- [OpenSSH ssh-keygen allowed signers](https://man.openbsd.org/ssh-keygen)
