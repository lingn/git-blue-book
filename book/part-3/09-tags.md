# 给重要提交命名：标签引用、附注对象与发布边界

分支表示一条会继续前进的工作线，标签表示一个需要稳定识别的对象。标签常被用作版本名，但 Git 本身只保存引用和对象，不知道某个版本是否已经发布、是否通过审批或是否正在生产运行。

## 进入条件与完成标准

准备一个有明确候选提交的练习仓库，工作区干净。创建标签前先保存：

~~~bash
git status --short --branch
candidate="$(git rev-parse HEAD)"
git show --no-patch --format='%H%n%T%n%s' "$candidate"
~~~

读完本章后，你应能：

- 区分轻量标签、附注标签和签名标签；
- 证明标签引用最终指向哪个对象和提交；
- 解释标签创建、移动、删除与远端发布是不同动作；
- 在同名标签竞态或候选不明确时停止操作；
- 把 tag OID、target OID、制品摘要和审批证据分开记录；
- 识别 Git 标签不能替代平台发布控制面和运行状态。

## 标签引用指向对象

标签名字通常位于 refs/tags/ 下。轻量标签直接把引用值写成目标对象的 OID：

~~~bash
git tag experiment-1 HEAD~1
git cat-file -t experiment-1
git rev-parse experiment-1^{commit}
git show-ref --tags
~~~

如果目标是 commit，cat-file 类型为 commit。轻量标签没有自己的说明、创建者或签名对象，适合临时标记，不宜单独作为正式发布证据。

附注标签会创建一个 tag 对象，再让标签引用指向该对象：

~~~bash
git tag -a v0.1.0 -m "First Git workflow lab release" "$candidate"
git cat-file -t v0.1.0
git rev-parse v0.1.0^{tag}
git rev-parse v0.1.0^{commit}
git show --format=fuller --no-patch v0.1.0
~~~

tag 对象记录目标对象、目标类型、标签名、创建者、时间、说明，并可包含签名。^{commit} 会沿 tag 对象解析到最终提交，便于核对“标签对象”和“被标记提交”是两个 OID。

标签不一定指向 commit，也可以指向 tree、blob 或另一个 tag。发布流程应明确要求目标类型为 commit，不要看到标签名字就默认它是可检出的版本。

## 创建发布标签前的检查

正式版本标签至少核对：

~~~bash
git status --short --branch
git rev-parse --verify "$candidate^{commit}"
git diff "$candidate" --exit-code -- .
git show --stat --format=fuller "$candidate"
git log --first-parent --oneline "$candidate"
~~~

最后三条分别用于查看工作区相对候选是否变化、候选文件统计和主线位置。若工作区有未提交修改，不能把“当前文件看起来正确”当作候选提交正确。

在团队流程中，还应把以下信息写进发布清单：

- 完整 candidate commit OID；
- tag object OID（附注标签）和 target commit OID；
- 构建制品摘要；
- 评审与必需检查结果；
- 目标环境、审批人和核对时间。

标签只覆盖 Git 对象的一部分。构建、制品、配置、数据库和运行实例必须有各自证据。

## 轻量、附注和签名标签的选择

| 形式 | 引用直接指向 | 自带说明/创建者 | 可签名 | 典型用途 |
| --- | --- | --- | --- | --- |
| 轻量标签 | 任意对象 | 没有 | 没有 | 临时本地标记 |
| 附注标签 | tag 对象 | 有 | 可使用签名形式 | 发布候选与版本记录 |
| 签名附注标签 | tag 对象 | 有 | 有 | 需要验证签名的发布流程 |

签名只证明某个密钥对精确 tag 对象签名，并不能自动证明该密钥有权发布、制品来自该 commit 或部署已成功。验证规则、密钥到主体映射和组织授权在安全篇处理。

如果本地没有配置签名工具，不要把普通附注标签写成“已签名发布”。可以保存未签名 tag，再由受控发布环境生成和验证签名标签。

## 标签不是不可移动的封条

Git 允许删除或移动本地标签：

~~~bash
git tag -d experiment-1
git tag -f v0.1.0 "$candidate"
~~~

-f 会覆盖现有本地 tag 引用。它不会修改目标 commit，但会让同一个版本名在不同时间指向不同对象。正式发布后不要把移动同名标签当作修复版本，优先创建新的版本号或修订标签，并记录旧 target OID。

远端服务是否允许删除、移动和强制更新 tag，取决于接收端规则和平台保护策略。Git 本地成功不等于远端接受，也不等于所有 clone 已经刷新。

## 标签发布是一次远程引用更新

创建标签仍然只改本地：

~~~bash
git remote -v
git push origin v0.1.0
~~~

第二条会连接远端并尝试创建远程 tag ref。它需要认证、仓库授权和接收端规则；本章的本地实验不执行。发布前应先用远端查询确认同名 tag 是否存在，并保存 old/new OID。平台的发布页面、制品仓库和部署系统还要单独核对。

删除远端标签通常是显式 refspec：

~~~bash
git push origin :refs/tags/v0.1.0
~~~

这是破坏远程引用的动作，只能在明确授权、记录影响范围并确认没有并发发布时使用。不要把删除本地 tag 当作远端撤销。

## 同名标签竞态

两个发布者可能同时为 v0.1.0 选择不同提交。即使双方本地创建成功，远端接收顺序也可能不同。可靠流程应：

1. 固定 candidate OID、构建摘要和审批；
2. 查询远端现有 tag ref；
3. 使用接收端支持的条件更新或不可变标签策略；
4. 发布后再次读取远端 tag target；
5. 如果发生竞态，停止提升，不用移动同名 tag 掩盖。

Git 的 file 或本地 bare 实验只能模拟 ref 更新和拒绝，不能证明托管平台的发布锁、权限、审核或不可变 tag 功能。

## 读取标签和排查错误

~~~bash
git show-ref --tags
git for-each-ref refs/tags/ --format='%(refname) %(objectname) %(objecttype)'
git cat-file -p v0.1.0
git rev-parse v0.1.0^{commit}
git show --no-patch --format='%H%n%P%n%T%n%s' v0.1.0^{commit}
~~~

附注标签的 ref objecttype 是 tag，^{commit} 解析出的 objecttype 是 commit。比较两者可以发现标签对象被重建、标签说明改变或目标被改指向。

如果标签无法解析，先检查名字、refs/tags、对象库和是否处于浅克隆。不要创建一个同名新标签来覆盖错误。

## 失败路径和恢复

| 现象 | 先收集 | 处理 |
| --- | --- | --- |
| tag already exists | 本地 tag OID、tag 类型、target OID | 停止覆盖，确认候选和责任人 |
| 标签指向错误提交 | tag ref、tag object、target、制品清单 | 未共享时重建；已共享时追加修订版本并记录 |
| push 被拒绝 | 远端 ref、认证、保护规则、old/new OID | 按远程拒绝分流，不强推 |
| 本地有 tag、远端没有 | push 输出、远端 ls-remote | 这只是本地标记，不能写成已发布 |
| tag object 与 target 混淆 | cat-file 类型、^{commit} 结果 | 分开记录两个 OID |
| 签名验证失败 | tag object、密钥、信任规则 | 不把绿色徽章当授权，交给安全流程 |

删除或移动标签前，先把旧 ref、对象和发布清单导出。不要运行无条件的 tag -f、远端删除或历史重写。

## 隔离实验验证了什么

运行：

~~~bash
./scripts/verify-part-3-conflicts.sh
~~~

现有实验在解决冲突后创建附注标签，验证 tag 对象类型和解析到的提交 OID，并额外创建、检查和删除轻量标签。它不验证真实签名、托管平台 tag 保护、发布制品或远端并发。

## 小结

标签是给对象取的名字，轻量标签直接指向目标，附注标签再增加一个 tag 对象。创建标签不会发布，移动标签不会修复已经共享的版本事实。发布流程必须同时保存 tag OID、target commit、制品摘要、审批和部署证据，不能让版本名独自承担整条供应链。
