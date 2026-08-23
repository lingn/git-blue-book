# 第十三篇：故障排查手册

“Git 坏了”不是一个可诊断的问题。文件不见、分支不见、push 被拒、认证失败、LFS payload 缺失和对象损坏可能显示相似表象，却发生在工作区、index、引用、对象库、传输、平台控制面或外部存储等完全不同的边界。连续试命令会改写这些边界，让最初故障和后来制造的故障混在一起。

本篇按症状与证据组织。每条路径先固定目标、仓库拓扑、共享范围和原始错误，再找出第一处不满足的不变量；修复动作必须说明会改变什么、怎样验证、失败后如何停止或恢复。命令名只作为定位工具，不作为目录结构。

进入本篇前，读者应理解工作区、index、对象、引用、提交图、远程跟踪引用和共享历史边界。若怀疑恶意仓库、凭据泄漏、对象损坏扩散或组织级服务事故，应先进入第十至十二篇的安全、取证与事件响应流程，不把普通排障命令当作现场保护。

## 当前已开放章节

1. [先别急着修：从症状到最小证据集](01-evidence-first.md)
2. [“不见了”发生在哪一层：文件、路径、提交与恢复边界](02-missing-files-and-commits.md)
3. [push 被拒绝并不都是权限：传输、认证、授权与引用策略](03-push-auth-and-permission-failures.md)
4. [仓库变慢、对象膨胀与磁盘告急：性能和容量故障](04-performance-and-capacity-failures.md)
5. [LFS、子模块与 CI clone 异常：外部对象和固定依赖](05-lfs-submodule-ci-failures.md)
6. [签名无法验证与密钥状态异常：从对象到信任根](06-signature-verification-failures.md)
7. [远程引用过期、默认分支变化与删除残留](07-remote-ref-drift-failures.md)
8. [仓库损坏、锁文件残留与并发操作](08-repository-corruption-locks-concurrency.md)

读完当前章节后，你应能把模糊报障转成可证伪的问题，判断命令是观察还是改变，采集不连接远端的最小本地证据集，区分 `pass`、`fail` 与 `inconclusive`；还能把“文件不见”和“提交不见”分别定位到工作区/index/tree/blob/外部 payload 或 ref/reflog/日志范围/对象来源，并把 push 失败分流到传输、服务器身份、客户端认证、仓库授权、Git 引用规则和平台控制面。

性能与容量章节进一步把 `status`、`log`、switch/checkout、clone/fetch 的慢映射到工作区、历史、对象、传输和外部数据面，定义可比较的 workload 与 p95 口径，分层盘点 Git/LFS/制品/备份/scratch 容量，并在辅助索引和维护前后核对 refs、HEAD、tree、可达对象与工作区不变量。

LFS、子模块与 CI clone 章节则把“主仓库正常但构建不可用”拆成 pointer/payload、gitlink/嵌套仓库和 candidate/checkout/构建输入三条路径，说明外部对象缺失、依赖 commit 未发布、浅/部分克隆和缓存不可信时的证据、恢复顺序与停止条件。

签名故障章节把无签名、密码学失败、未知或未授权 key、撤销/过期、历史改写和错误 tag 目标分开，要求信任根来自候选之外，并把签名验证与 candidate、制品和部署证据分离。

远程引用章节把远端当前事实、本地远程跟踪缓存、上游配置和平台控制面分开，覆盖分支重命名、prune、默认分支 symbolic ref、标签改指向、隐藏/权限边界和多次查询竞态。

仓库损坏章节把锁与写入者、引用条件更新、对象/pack 完整性、linked worktree 和组织级维护互斥分开，说明为什么不能盲删 `.lock`、无条件覆盖 ref 或在原现场运行 GC/repack。
