# 对象身份与格式：同一内容在不同仓库格式中怎样命名

对象 ID（OID）不是文件内容单独做一次哈希得到的名称。Git 先把对象类型、内容长度和原始字节组成规范输入，再使用仓库的对象格式计算 OID。同一段字节作为 blob 和 tree 会得到不同身份；同一个文件内容放进 SHA-1 与 SHA-256 仓库，也会得到不同长度、不同算法的名称。

## 进入条件与完成标准

命令在一次性临时仓库中执行。开始前确认 Git 版本和仓库格式：

~~~bash
git version
git rev-parse --show-object-format
git rev-parse --show-ref-format
~~~

后两条必须在仓库中执行。输出由当前仓库决定，例如 `sha1` 或 `sha256`，引用格式常见为 `files`，也可能是当前 Git 支持的其他格式。对象格式与引用存储格式是两件事，不能因为 refs 使用 files backend 就推断对象使用 SHA-1。

读完本章后，应能解释对象规范输入、完整与缩写 OID、仓库对象格式、跨格式边界和签名重建影响，并能用 `hash-object`、`cat-file` 和 `rev-parse` 验证实际仓库。

## 对象的规范输入包含类型和长度

设文件内容为 `hello\n`。blob 的哈希输入可以表示为：

~~~text
blob 6\0hello\n
~~~

`\0` 是 NUL 字节，不是两个可见字符。`6` 是 payload 的字节长度，不是字符数。tree、commit 和 tag 使用相同的“类型 + 空格 + 长度 + NUL + payload”框架，payload 结构各不相同。

在仓库根目录观察一个文件：

~~~bash
printf 'hello\n' > sample.txt
oid="$(git hash-object sample.txt)"
printf 'oid=%s\n' "$oid"
git cat-file -t "$oid"
git cat-file -s "$oid"
git cat-file blob "$oid"
~~~

不带 `-w` 的 `hash-object` 计算 OID，但不要求把对象写入当前对象数据库。`cat-file` 只有在对象已经由 `add`、`hash-object -w`、fetch 或其他操作写入后才能读取它。要让上面三条读取命令成功，先执行：

~~~bash
git hash-object -w sample.txt
~~~

成功输出完整 OID。它会写对象数据库，不更新 index、`HEAD` 或任何分支，因此 `status` 仍把 `sample.txt` 视为未跟踪路径。

## 四类对象的身份来自完整 payload

blob 保存字节，不保存文件名。tree 保存路径名、模式和子对象 OID。commit 保存根 tree、父提交、author、committer、时间、时区和说明。附注 tag 对象保存目标、目标类型、tagger 和说明。

由此可以推导：

- 两个路径内容逐字节相同，可指向同一个 blob；
- 文件改名通常改变 tree，即使 blob 不变；
- 只改提交说明、父提交或 committer 时间，也会生成新 commit OID；
- 附注标签的 tag object 与它指向的 commit 是两个对象；
- repack、传输和压缩方式变化不改变对象规范输入，因此不改变 OID。

`git cat-file -p` 适合人工阅读对象，输出是解释视图。需要保留原始 payload 时按已验证类型使用 `git cat-file blob`，或使用批处理接口并记录 Git 版本，不能把格式化展示当成对象文件原始字节。

## 仓库创建时选择对象格式

Git 2.49.0 的 `git init` 支持：

~~~bash
git init --object-format=sha1 sha1-repo
git init --object-format=sha256 sha256-repo
~~~

当前实现中 SHA-1 仍是新仓库的常见默认值，SHA-256 是否可用取决于安装版本和构建能力。脚本先运行 `git init --object-format=sha256` 探测，不应手工编辑 `.git/config` 把现有仓库改成另一算法。对象目录、refs、索引、提交内容、签名和协议协商都与格式有关，修改一个配置字段不能完成迁移。

在两个仓库写入相同字节：

~~~bash
printf 'same bytes\n' > sha1-repo/payload.bin
cp sha1-repo/payload.bin sha256-repo/payload.bin

sha1_oid="$(git -C sha1-repo hash-object -w payload.bin)"
sha256_oid="$(git -C sha256-repo hash-object -w payload.bin)"
printf 'sha1=%s\nsha256=%s\n' "$sha1_oid" "$sha256_oid"
~~~

SHA-1 OID 通常是 40 个十六进制字符，SHA-256 OID 通常是 64 个。长度是当前算法的结果，不是所有 Git 仓库永远不变的协议常量。自动化应从仓库和协议取得对象格式，保存完整 OID，不用固定长度正则替代解析。

## 缩写只在当前解析范围内成立

Git 接受足以唯一识别当前对象集合的 OID 前缀：

~~~bash
git rev-parse --short HEAD
git rev-parse --short=12 HEAD
git rev-parse --verify '<prefix>^{commit}'
~~~

缩写长度可能因对象数量和前缀碰撞增长。某个前缀今天唯一，仓库增加对象后可能歧义；另一个 clone 的对象集合也可能不同。人类日志可以显示缩写，CI、审计、制品、迁移映射和跨系统 API 使用完整 OID，并同时记录仓库稳定 ID 与对象格式。

## 跨格式不能直接搬运 OID

SHA-1 仓库中的对象名不能原样当作 SHA-256 仓库的存储 OID。同一逻辑提交在转换格式时，tree 中的子对象名、父提交名和签名输入都会变化，形成一组新对象身份。

迁移前要明确目标：

- **保持对象格式**，复制 refs 与对象，要求目标服务和工具支持原格式；
- **转换对象格式**，保存完整旧新 OID 映射，并重新验证父关系、tree、tag、签名和外部引用；
- **导出文件快照**，只保留某个 tree 的文件，不声称保留 Git 历史身份。

不要在两个格式不同的仓库之间直接复制 `.git/objects`，也不要只更新分支文本。Clone/fetch/push 是否支持目标格式和转换能力由客户端、服务端、协议与具体版本共同决定，迁移要在代表性工具链中实测。

## 内容寻址不等于身份授权

OID 能帮助验证“当前读取的规范对象与名称一致”，不能证明作者是谁、谁有权更新分支、代码是否安全或平台是否批准发布。Commit/tag 签名把签名绑定到特定对象内容；历史重建或对象格式转换后 OID 改变，旧签名不能自动转移到新对象。

安全结论至少区分对象完整性、密钥密码学验证、principal 映射、组织授权和发布候选。完整模型见[签名与信任策略](../part-10/04-signatures.md)。

## 失败方式与恢复边界

| 现象 | 先确认 | 安全处理 |
| --- | --- | --- |
| `cat-file` 报对象不存在 | 仓库路径、对象格式、完整 OID、promisor/alternate | 取得正确对象来源，不用另一格式 OID 猜文件名 |
| 脚本只接受 40 位 OID | 仓库格式、协议字段、第三方库版本 | 改用 Git/结构化 API 解析，增加 SHA-256 测试 |
| 手改 `extensions.objectFormat` 后仓库打不开 | 原配置、对象目录、备份、修改时间 | 停止写入，从原始副本恢复配置；不要继续生成对象 |
| 转换后签名无法验证 | 旧新 OID 映射、签名对象和信任根 | 对新对象按组织策略重新签名/授权，保留旧证据 |
| 两个仓库 tree 相似但 OID 不同 | 对象格式、模式、路径、子对象和属性 | 比较结构与内容，不用 OID 相等作为跨格式前提 |

## 隔离实验

在本书仓库根目录执行：

~~~bash
TMPDIR=/private/tmp ./scripts/verify-object-format-lifecycle.sh
~~~

实验创建 SHA-1 与 SHA-256 仓库，验证相同 blob 在两种格式中得到不同长度的 OID、payload 可还原、完整 OID 与仓库格式匹配。脚本还用系统摘要工具独立计算 `blob <长度>\0<payload>`，与 `git hash-object` 逐字比较。若当前 Git 不支持 SHA-256，脚本明确报错并退出非零，不把未执行写成通过。

实验还验证 pack 与对象清理，由下一章解释。它只操作临时仓库，不迁移真实项目，也不证明远程协议、托管平台和第三方库已经支持 SHA-256。

## 小结

对象身份来自类型、长度和完整 payload，再由仓库对象格式选择哈希算法。完整 OID 必须连同仓库和对象格式解释；缩写只在当前对象集合中成立。跨格式迁移会改变对象身份和签名输入，必须保存映射并重新验证，不能靠复制对象目录或修改配置字段完成。

## 资料

- [git-hash-object](https://git-scm.com/docs/git-hash-object)
- [git-cat-file](https://git-scm.com/docs/git-cat-file)
- [git-init](https://git-scm.com/docs/git-init)
- [git-rev-parse](https://git-scm.com/docs/git-rev-parse)
- [Git repository layout](https://git-scm.com/docs/gitrepository-layout)
- [Hash function transition](https://git-scm.com/docs/hash-function-transition)
