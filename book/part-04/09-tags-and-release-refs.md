# 标签与发布引用：稳定名字仍需目标、签名和远端证据

标签位于 `refs/tags/`。轻量标签让 ref 直接指向目标对象；附注标签让 ref 指向 tag object，后者再记录目标、目标类型、标签名、tagger、时间、说明和可选签名。两者都只是 Git 名字，不自动创建发布、制品或部署记录。

发布流程优先使用附注标签，因为它能把说明、创建身份和签名容器绑定到固定目标。仍要核对剥离后的 commit、远端实际 ref、制品摘要、审批和运行版本。

## 进入条件与完成标准

创建、移动、删除和推送标签只在临时仓库实验。真实发布前固定：

~~~bash
git status --short --branch
candidate="$(git rev-parse --verify 'HEAD^{commit}')"
git show --no-patch --format='%H%n%P%n%T%n%aI%n%cI%n%s' "$candidate"
git ls-remote --tags origin 'refs/tags/v*'
~~~

`ls-remote` 会访问网络，结果受认证、权限、隐藏 refs 和查询时点影响。先确认 remote URL 和输出保存位置，不能把失败当成远端无标签。

读完本章后，应能区分轻量/附注/签名标签，解析 tag object 与剥离目标，处理短名歧义、显式 push、同名竞态和删除，判断浅克隆/对象缺失，并把 Git 标签与发布证据链分开。

## 轻量标签只有引用

~~~bash
git tag build-20260914 "$candidate"
git show-ref --verify refs/tags/build-20260914
git cat-file -t refs/tags/build-20260914
~~~

若目标是 commit，最后一条输出 `commit`。没有独立 tag object，也没有 tagger、说明或签名容器。轻量标签适合个人临时标记或明确接受这种证据强度的内部流程，不应被名称中的 `release` 自动升级为正式发布。

标签可以指向 blob、tree、tag 或 commit。构建和发布通常要求 commit，因为父历史、根 tree 和签名策略围绕 commit 展开；创建前使用 `^{commit}` 验证，不能只看 `cat-file -t <tag>`。

## 附注标签有两层对象

~~~bash
git tag --annotate v2.4.0 "$candidate" \
  --message 'Release 2.4.0'

tag_object="$(git rev-parse 'refs/tags/v2.4.0^{tag}')"
tag_target="$(git rev-parse 'refs/tags/v2.4.0^{}')"
git cat-file -p "$tag_object"
~~~

`tag_object` 是 tag object OID，`tag_target` 是递归剥离后的目标，正式发布应断言它等于候选 commit。`^{} ` 的概念是 peel；命令中不要在 `^{}` 后加入空格。

Tag object 的 `tag` 字段是对象内容，ref 名在对象外。复制同一个 tag object 到另一个 ref 不会修改对象内部名称，因此工具要同时核对 refname、对象字段和目标。

Tagger 身份和时间由创建环境提供，不等于平台认证主体或可信时间戳。附注说明也不能证明审批完成。

## 签名标签增加密码学证据

~~~bash
git tag -s v2.4.0 "$candidate" -m 'Release 2.4.0'
git verify-tag v2.4.0
git rev-parse 'v2.4.0^{}'
~~~

签名绑定 tag object 内容，不能转移到后来重建的 tag。密码学有效仍不证明 key 对当前仓库和 release 动作有组织授权；信任根不能由待验证候选自行提供。

SSH、OpenPGP/X.509 选择、principal 映射、撤销与候选外授权见[签名与信任策略](../part-10/04-signatures.md)。签名失败时同名 tag ref 不应出现，先核对本地状态和签名程序，不用 `-f` 或无签名标签绕过发布政策。

## Ref 名与对象名都要核对

机器盘点：

~~~bash
git for-each-ref refs/tags/ \
  --format='%(refname) %(objecttype) %(objectname) %(*objecttype) %(*objectname)'
~~~

附注 tag 的 `objecttype/objectname` 是 tag object，带星号字段是剥离一层后的对象；轻量 tag 没有独立剥离字段。对象链可能不止一层，最终发布目标仍用 `^{commit}` 或 `^{}` 约束。

分支和标签可以有相同短名：

~~~text
refs/heads/release
refs/tags/release
~~~

`git show release` 会触发歧义警告或按解析规则选择。脚本和发布清单使用完整 refname，路径参数用 `--` 分隔。不要创建短名冲突后依赖操作者记住优先级。

## Git 不解释版本号语义

`v2.4.0`、`release-20260914` 和 `customer-a` 对 Git 都只是合法 ref 名。Git 不检查 SemVer、发布日期、递增顺序、维护窗口或某标签是否“正式”。

组织另行定义：

- 命名格式和大小写；
- 候选、正式、撤销和补发版本；
- 谁能创建/删除标签；
- 是否要求签名与独立发布身份；
- 标签如何绑定制品、SBOM、provenance 和部署；
- 同名竞态、镜像和缓存怎样处理。

平台 protected tag、ruleset 或权限属于服务端控制面，按产品、版本、权限和套餐登记。

## 标签不会自动推送

显式发布一个标签：

~~~bash
git push origin refs/tags/v2.4.0:refs/tags/v2.4.0
git ls-remote --tags origin \
  refs/tags/v2.4.0 'refs/tags/v2.4.0^{}'
~~~

普通 `git push` 不保证发送所有本地标签。`--tags` 会发送全部缺失标签，可能扩大范围；`--follow-tags` 只跟随满足条件的附注标签，也不能替代显式发布清单。正式流程逐个列出 ref 和预期 tag object/target。

Push 成功后立即查询远端，只证明该时点服务器对当前身份返回相应 refs。镜像、CDN、制品库和客户端缓存仍可能滞后。

## 同名竞态必须拒绝覆盖

两个发布者都创建 `v2.4.0`，先到达远端者成功，后者普通 push 应被拒绝。失败后保存：

~~~bash
local_tag="$(git rev-parse refs/tags/v2.4.0)"
remote_line="$(git ls-remote --tags origin refs/tags/v2.4.0)"
printf 'local=%s\nremote=%s\n' "$local_tag" "$remote_line"
~~~

不要直接 `git push --force`。先确认远端 tag object、剥离目标、创建事件、制品和消费者。通常创建新版本；若必须撤销错误标签，走审批、公告、缓存/镜像处置和审计流程。

本地误建且未共享时，可保存错误 OID 后删除并重建；同名 `git tag` 默认拒绝覆盖，`-f` 会移动 ref，不能作为常规修正。

## 删除标签只删除某个仓库的 ref

~~~bash
git tag --delete temporary-checkpoint
git push origin :refs/tags/temporary-checkpoint
~~~

第一条只删本地 ref，第二条请求删除远端 ref。其他 clone、镜像、reflog、对象、平台 release、制品和部署不会自动删除。远端可能因保护策略拒绝。

标签 reflog 默认行为与分支不同，不能依赖它恢复强制移动。重要发布在外部登记 tag object、target、签名、远端事件和制品摘要；发现误删时从可信记录或其他 clone 恢复精确 OID。

## Shallow、partial 和按需对象边界

浅 clone 可能只有标签目标却缺少更早父历史，也可能因 refspec/tag 选项没有取得标签。Partial clone 读取 tag 指向的 tree/blob 时可能触发 promisor 网络请求。

~~~bash
git rev-parse --is-shallow-repository
git cat-file -e 'refs/tags/v2.4.0^{tag}'
git cat-file -e 'refs/tags/v2.4.0^{commit}'
git fsck --connectivity-only
~~~

这些本地检查不能证明远端、LFS payload、submodule commit 或制品存在。发布和灾备使用完整证据副本，或明确记录受限边界与对象来源。

## 标签只是发布证据链的一环

正式记录至少包括：

~~~text
tag_ref / tag_object / peeled_commit / source_tree
signature_and_external_authorization
remote_observed_oid / observation_time
artifact_digest / SBOM / provenance
approval / rollout / runtime_digest
revocation_or_supersession_state
~~~

完整制品提升和同名竞态见[发布引用与制品提升](../part-08/05-release-refs-and-artifact-promotion.md)。本章只保证 Git 标签语义没有与外部发布状态混写。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全动作 |
| --- | --- | --- |
| `^{tag}` 失败 | 轻量标签、对象类型和 ref | 识别真实类型，不伪造附注对象 |
| `^{commit}` 失败 | tag 链、目标类型、missing/promisor | 取得可信对象或拒绝作为发布候选 |
| Push 报 tag already exists | 本地/远端 object 与 target、创建事件 | 新版本或审批撤销，不强制覆盖 |
| 网页有标签、本地没有 | fetch 选项/refspec、权限和查询时点 | `ls-remote`/显式 fetch，分开平台 release |
| 标签签名有效但身份未知 | fingerprint、principal、外部策略 | 标记未授权或证据不足，不发布 |
| 删除后消费者仍看到 | 其他 clone、镜像、缓存、release/制品 | 公告并逐层处置，不重复删本地 |
| 标签目标正确但制品不匹配 | manifest、artifact digest、构建候选 | 阻止提升，从同一候选重新构建/核验 |

任何变更前保存完整 tag ref/object/target。发布标签已经共享时，不用历史改写制造“从未发生”。

## 隔离实验

运行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-tags-release-refs.sh
~~~

实验验证轻量/附注标签对象类型、剥离目标、分支/标签短名碰撞、显式 refspec push、远端 peeled ref、同名普通 push 拒绝、条件恢复本地 tag，以及显式远端删除不影响分支。

签名和制品实验由 `verify-signatures-trust.sh` 与 `verify-release-promotion.sh` 负责。本实验不连接托管平台，不验证保护规则、真实 key、制品库或缓存。

## 小结

轻量标签只有 ref，附注/签名标签还有 tag object。发布时同时固定完整 ref、tag object、剥离 commit、签名授权和远端观察；普通 push 不自动发布全部标签，同名竞态也不应强制覆盖。Git 标签给版本命名，制品与运行状态由外部证据链证明。

## 资料

- [git-tag](https://git-scm.com/docs/git-tag)
- [git-check-ref-format](https://git-scm.com/docs/git-check-ref-format)
- [gitrevisions](https://git-scm.com/docs/gitrevisions)
- [git-for-each-ref](https://git-scm.com/docs/git-for-each-ref)
- [git-push](https://git-scm.com/docs/git-push)
- [git-ls-remote](https://git-scm.com/docs/git-ls-remote)
