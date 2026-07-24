# 同时维护多个工作目录：git worktree

## 场景：不想反复收起和切换

你正在功能分支运行本地服务，同时需要在主线修复线上问题。反复 stash、切分支会打断环境。Git 可以让一个仓库拥有多个工作区目录。

查看当前工作树：

```bash
git worktree list
```

主项目目录就是第一个工作树。

## 创建热修复工作树

在项目根目录执行：

```bash
git worktree add ../project-hotfix -b hotfix/payment origin/main
```

这条命令：

- 在相邻路径创建 `project-hotfix` 工作目录；
- 从 `origin/main` 创建本地分支 `hotfix/payment`；
- 在新目录检出该分支。

执行前确认目标路径不存在或为空，并把示例目录、分支改为真实值。

## 共享什么，隔离什么

多个工作树共享同一仓库的对象和大部分引用，因此新提交和分支彼此可见。每个工作树拥有自己的工作区、暂存状态和当前 `HEAD`。

Git 通常不允许同一个本地分支同时在两个工作树中检出，防止两个目录竞争移动同一分支。

## 在新目录工作

```bash
cd ../project-hotfix
git status
git branch --show-current
```

完成热修复、测试和提交。原功能目录保持原分支和未提交状态，不需要收纳。

## 安全移除

确认新工作树状态干净、重要提交已保留后，回到主目录：

```bash
git worktree remove ../project-hotfix
```

它移除工作目录和管理记录，不自动删除 `hotfix/payment` 分支。含未提交修改时通常会拒绝；不要为清理路径轻易使用强制选项。

如果目录被外部工具手工删除，可清理失效管理记录：

```bash
git worktree prune
```

先用 `git worktree list` 核对，不要把 prune 当作日常必跑命令。

## stash 还是 worktree

- 短暂切换、修改很少：stash 可以快速收纳；
- 两项工作都要持续运行、构建或比较：worktree 更清晰；
- 需要协作和长期保留：无论使用哪个目录，都应形成分支与提交。
