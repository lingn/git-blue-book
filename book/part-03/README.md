# 第三篇：对象模型决定命令行为

Git 的多数高风险操作都能还原成三个问题：对象是否已经写入，对象是否仍可达，哪个引用或 index 条目正在指向它。只记命令效果，很难解释为什么 amend 会改变 OID、删除分支后提交还可能找回、repack 不改变历史、冲突时 index 会出现多个阶段。

本篇深入对象数据库、引用、提交图、index 和物理存储。第一篇保留面向初学者的仓库地图，第二篇负责日常操作，第九篇负责性能测量；本篇承担这些操作背后的权威数据模型。

## 进入条件

开始前应理解工作区、index、commit、分支和 `HEAD` 的基本用途，并能在临时仓库运行 `status`、`add`、`commit` 和 `log`。正文会使用 plumbing 命令观察内部状态，但不会要求在日常仓库手工修改 `.git` 文件。

## 已落地内容

1. [对象身份与格式：同一内容在不同仓库格式中怎样命名](01-object-identity-and-formats.md)
2. [Pack、delta 与对象生命周期：物理整理不会改写历史](02-pack-delta-and-lifecycle.md)
3. [引用、HEAD 与 reflog：名字怎样移动，旧位置怎样留下证据](03-refs-head-and-reflog.md)
4. [提交图与可达性：父关系比时间和分支名更可靠](04-commit-graph-and-reachability.md)
5. [Index 内部结构：下一棵 tree、冲突候选与稀疏目录](05-index-internals.md)
6. [Porcelain 与 plumbing：便利工作流和底层原语的责任边界](06-porcelain-and-plumbing.md)

第三篇规划的模型主题已经落盘，接下来按迁移表处理旧第三篇与 v2 第四篇的职责，并进行跨章术语、重复和出版审校。自动检查通过只能证明当前链接与实验不变量，不能替代技术编辑、目标环境验证和全书验收。

## 实验边界

本篇实验在 `mktemp` 目录创建 SHA-1 和 SHA-256 仓库，写入合成对象，并在可销毁仓库中运行 repack 和立即 prune。引用实验另外构造 unborn、附着和分离 `HEAD`、packed refs、linked worktree 与本地 clone；提交图实验构造分叉、合并、时钟偏移、不可达 commit、commit-graph 和浅边界；index 实验覆盖普通/冲突 entries、替代 index 与 sparse-directory；plumbing 实验逐层构造对象并发布条件引用。它不迁移真实仓库，不连接远端，也不验证平台、LFS、签名服务或生产备份。真实事故现场不得照抄立即过期和清理命令。
