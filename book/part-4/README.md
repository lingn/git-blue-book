# 旧第四篇：远程仓库迁移目录

本目录保留既有 URL。远程状态、clone 和 remote/refspec 已迁入 v2 第五篇；rebase/cherry-pick 已迁入 v2 第七篇。Fetch、pull、push、认证、受限 clone 与综合练习在目标章节完成前继续保留原正文。

## 已迁移主题

1. [v2 第五篇：远程仓库、协议与认证](../part-05/README.md)
2. [v2 第七篇：改写、撤销与恢复](../part-07/README.md)

旧 URL 兼容入口：

- [远程状态模型](01-remote-model.md)
- [Clone](02-clone.md)
- [Remote 配置](03-remote.md)
- [Rebase 模型](10-rebase-model.md)
- [Rebase 工作流](11-rebase-workflow.md)
- [Cherry-pick](12-cherry-pick.md)

## 尚未迁移的正文

1. [只获取，不整合：fetch 的对象和引用变化](04-fetch.md)
2. [远程跟踪分支：本地保存的远端观察点](05-remote-tracking.md)
3. [pull 实际组合了哪两步：获取与整合必须分开诊断](06-pull.md)
4. [发布本地提交：push、上游与引用更新](07-push.md)
5. [push 为什么会被拒绝：先区分传输、认证和历史保护](08-push-rejection.md)
6. [代码评审前整理什么：把候选、范围和验证绑定起来](09-review-ready.md)
7. [远程 URL、传输协议与认证边界](13-transport-auth.md)
8. [Refspec、传输协商与受限克隆](14-refspec-partial-clone.md)
9. [综合场景：同步主线，再准备一次可追溯评审](exercise.md)

迁移完成以 `docs/CHAPTER-MIGRATION-MAP.md`、隔离实验和整库回归为准。旧路径保留不表示旧正文仍是权威来源。
