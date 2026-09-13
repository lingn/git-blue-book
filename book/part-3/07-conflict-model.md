<!-- legacy-redirect -->

# 冲突模型正文已拆入 v2 第三、四篇

本页保留旧 URL。原来的 index stages、三方策略、冲突类型和业务决策内容已于 2026-09-14 拆分，旧页不再维护第二份模型。

权威阅读顺序：

1. [Index 内部结构](../part-03/05-index-internals.md)，解释 stage 0/1/2/3、缺失 stage 与 `write-tree` 边界。
2. [`ort` 三方合并](../part-04/05-three-way-merge-and-ort.md)，解释策略、冲突现场、conflict style 与 `AUTO_MERGE`。
3. [复杂路径冲突](../part-04/06-complex-path-conflicts.md)，处理 add/delete/rename、mode、binary/LFS 和 submodule。
4. [解决、中止与验收](../part-04/07-resolve-abort-and-verify.md)，执行逐路径决策、continue/abort/quit 和最终验证。

本地实验由 `scripts/verify-index-internals.sh`、`scripts/verify-ort-path-conflicts.sh` 和 `scripts/verify-merge-resolution-control.sh` 覆盖。它们不证明真实业务或平台候选正确。
