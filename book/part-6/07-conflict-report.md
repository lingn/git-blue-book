<!-- legacy-redirect -->

# 冲突解决报告正文已迁入 v2 第六篇

本页保留旧 URL。原来的冲突报告正文已于 2026-09-02 收束到 v2 第六篇的[可审查变更：范围、提交序列与堆叠评审](../part-06/04-reviewable-changes-and-stacks.md)，旧页不再复制 merge-base、冲突现场、父提交、路径决策和恢复边界。

权威章节新增了冲突结果报告模板，要求记录操作类型、base/source、目标前后 OID、完整 parent 列表、冲突路径、按路径写出的最终语义、验证命令、审批影响和回滚或向前修复边界。复杂冲突的数据和操作机制分别见[Index 内部结构](../part-03/05-index-internals.md)、[`ort` 三方合并](../part-04/05-three-way-merge-and-ort.md)与[Rerere](../part-04/08-rerere.md)。

本地实验由 scripts/verify-complex-conflicts-rerere.sh 和 scripts/verify-troubleshooting-snapshot.sh 验证；实验不模拟平台评审、业务正确性或真实部署。
