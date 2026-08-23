# 第九篇：大仓库、二进制与仓库组合

仓库变慢不是一个单一故障。提交图很深、refs 很多、packfile 零散、tracked paths 数量巨大、工作区位于高延迟文件系统，都会让不同命令出现完全不同的瓶颈。直接套用“开启某配置”或“运行一次 gc”既可能无效，也可能在事故窗口缩短恢复机会。

进入本篇前，读者应理解对象与 packfile、commit graph、refs、index、工作区、远程协商、部分克隆和稀疏检出。本篇先建立可比较的测量与维护证据，再讨论二进制、LFS、submodule、subtree 和仓库拓扑。

## 当前已开放章节

1. [先测量，再优化：大仓库性能与维护基线](01-measure-before-optimizing.md)
2. [二进制与 Git LFS：pointer 不是文件本体](02-binary-and-lfs.md)
3. [Submodule 与 subtree：固定外部提交，还是复制一棵树](03-submodule-and-subtree.md)
4. [稀疏与部分工作流：减少本地负担，不削弱候选证据](04-sparse-partial-workflows.md)
5. [Monorepo 拓扑治理：用构建图和所有权决定边界](05-monorepo-topology-and-ownership.md)

第九篇已覆盖测量、受限工作流、二进制、LFS、submodule、subtree 和 monorepo 拓扑治理。跨仓迁移和组织级治理仍按总纲继续校验。尚未完成的主题不以占位页面进入导航。

读完当前章节后，你应能把慢命令定位到历史、对象、refs、index、工作区或网络层，建立包含冷热缓存与环境变量的基线，并验证辅助索引或维护任务没有改变逻辑历史；还能区分 Git pointer blob、LFS payload 和工作区水合状态，设计二进制选型、CI 完整性门禁、迁移与灾难恢复边界，并在 monorepo、多仓库包、submodule 与 subtree 之间按变更原子性、权限、构建和运维成本作出选择。
