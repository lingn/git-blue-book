# 第十一篇：取证、迁移与灾难恢复

恢复不是“想办法让命令重新成功”，而是先判断哪一类状态丢失、哪些证据仍可信、恢复目标是什么。逻辑误操作、对象损坏、服务不可用、凭据事故和合规调查需要不同的现场保护与授权；错误的第一步可能覆盖 reflog、清理不可达对象、改写 index 或让远端继续变化。

进入本篇前，读者应理解对象、refs、reflog、pack、远程传输、LFS、submodule、制品证据链和安全事故的副本边界。本篇从现场保护开始，再逐步进入对象取证、历史归因、备份恢复、迁移和区域故障演练。尚未完成的主题不以占位页进入导航。

## 当前已开放章节

1. [先冻结，再恢复：Git 事故现场保护与证据采集](01-preserve-and-acquire.md)
2. [对象还在不等于历史能回来：fsck、lost-found、pack 与替代对象库](02-object-forensics-and-recovery.md)
3. [谁改了这一行：历史归因、搜索与证据边界](03-history-attribution.md)
4. [备份不是 mirror：bundle、恢复点与恢复演练](04-bundle-mirror-backup.md)
5. [迁移不是换一个 remote：代码、身份、平台数据与切换](05-repository-platform-migration.md)
6. [故障转移不是改 DNS：远端丢失、区域故障与安全回切](06-disaster-failover-and-failback.md)

读完当前章节后，你应能区分文件系统现场、Git 逻辑快照、平台控制面和运行环境证据；在不继续修改事故仓库的前提下保存 refs、index、工作区差异、reflog、进行中操作、对象库布局和配置来源；也能解释为什么 clone、mirror 或 bundle 不能单独承担完整取证副本。继续阅读第二章后，还能从可达、不可达、缺失和损坏状态中选择候选对象，识别 alternates 与 replace refs 的解释偏差，并在恢复副本中验证 pack、tree 和 refs。第三章进一步把 blame、pickaxe、rename、merge 和外部评审/部署记录串成可复核的历史归因链。第四章则用 RPO/RTO、完整与增量 bundle、镜像删除传播和空环境恢复演练建立备份验收模型。第五章把 Git/SVN 历史、身份、LFS、平台元数据、权限和 CI 放入同一迁移切换清单，并以单一写入权威约束 cutover。第六章把副本滞后、donor 补齐、条件提升、旧主围栏和安全回切组织成故障状态机。
