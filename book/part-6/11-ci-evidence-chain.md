<!-- legacy-redirect -->

# CI/CD 证据链正文已迁入第八篇

本页保留旧 URL。原来的 CI/CD 证据链正文已于 2026-08-30 收束到第八篇，旧页不再复制候选、构建、制品和部署定义。

权威阅读顺序：

1. [触发与 checkout：CI 首先要证明自己检出了什么](../part-08/01-triggers-and-checkout.md)，固定事件、实际 HEAD、浅/部分克隆和路径输入。
2. [候选提交：把一次检查绑定到精确对象](../part-08/02-candidate-commits.md)，区分功能头、临时合并、squash、rebase 和队列候选。
3. [从源码到运行版本：制品与部署证据链](../part-08/03-source-artifact-deployment-evidence.md)，连接流水线、runner、依赖、制品摘要、部署请求和实例观测。
4. [可重复构建：把同一输入变成可比较的输出](../part-08/04-reproducible-builds.md)，处理输入闭包、非确定性和构建缓存。
5. [发布引用与制品提升](../part-08/05-release-refs-and-artifact-promotion.md)，把候选、标签、审批和制品摘要连起来。

本地实验继续由 scripts/verify-ci-evidence-chain.sh 验证分离 HEAD、候选源码归档、摘要清单和部署副本关系。它只证明合成 Git 与文件摘要行为，不证明真实 CI 平台、身份令牌、制品权限或生产实例状态。
