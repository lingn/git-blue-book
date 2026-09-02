# Git 技术蓝皮书

一本从心智模型进入工程协作、故障恢复与组织治理的 Git 中文公开读物。

这本书不追求罗列全部 Git 命令，而是先解释 Git 为什么出现、它如何看待文件与历史，再逐步进入提交、分支、远程协作、回滚、历史修改和故障恢复。目标是让读者能够判断当前处境，选择合适的命令，并知道误操作后如何恢复。

## 当前状态

六篇基础教程和已开放的 v2 CI/CD、规模、安全、取证、治理与故障排查专题共 129 个公开页面，52 组隔离 Git 实验已经形成可运行基线。仓库正在按 v2 总纲重构，现有内容不代表出版完成；旧目录迁移、平台专项验证、跨章去重和真实区域级演练仍在补写。

- GitBook 阅读内容位于 [`book/`](book/)
- v2 权威总纲位于 [`docs/MASTER-OUTLINE.md`](docs/MASTER-OUTLINE.md)
- 现状审计位于 [`docs/AUDIT-2026-08-20.md`](docs/AUDIT-2026-08-20.md)
- 改写路线位于 [`docs/REWRITE-ROADMAP.md`](docs/REWRITE-ROADMAP.md)
- 十三篇迁移映射位于 [`docs/CHAPTER-MIGRATION-MAP.md`](docs/CHAPTER-MIGRATION-MAP.md)
- 当前进度位于 [`docs/PROGRESS.md`](docs/PROGRESS.md)
- 写作规范位于 [`docs/WRITING-GUIDE.md`](docs/WRITING-GUIDE.md)
- 知识依赖位于 [`docs/CONCEPT-MAP.md`](docs/CONCEPT-MAP.md)
- 验收标准位于 [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md)
- 可重复实验位于 [`scripts/`](scripts/)

运行全部本地验证：

```bash
./scripts/verify-all.sh
```

## GitBook 同步

仓库根目录的 [`.gitbook.yaml`](.gitbook.yaml) 已将 GitBook 根目录设置为 `book/`。在 GitBook 中连接本仓库后，选择默认分支 `main` 即可同步。

## 内容原则

- 新概念先用普通语言建立直觉，再给出术语和工作定义。
- 命令只在它依赖的概念已经解释后出现。
- 示例必须能运行，并明确执行前提、预期输出和恢复方式。
- 已经公开的历史与仅存在本地的历史分开讲解。
- 真实工作案例会匿名化，不包含公司、项目、同事或内部地址信息。
