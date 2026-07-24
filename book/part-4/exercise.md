# 综合场景：同步主线并准备代码评审

你在尚未分享的 `feature/search-filter` 上有两条提交。远程 `main` 已被同事更新。目标是取得最新主线、整理本地功能历史、验证后首次推送，全程不覆盖他人提交。

## 一、保护现场并获取证据

```bash
git status
git branch --show-current
git fetch origin
git log --oneline --graph --decorate --all
```

确认当前分支正确、工作区干净，并查看双方独有提交：

```bash
git log --oneline feature/search-filter..origin/main
git log --oneline origin/main..feature/search-filter
```

## 二、选择整合方式

该功能分支从未推送、只有你使用，团队希望评审分支基于最新主线，因此可以变基：

```bash
git rebase origin/main
```

如果分支已经被同事使用，应停止并协调；合并通常能在不改写已有提交的情况下保留双方工作。

发生冲突时逐条处理并 `git rebase --continue`；发现判断错误则 `git rebase --abort`。

## 三、评审前检查

```bash
git status
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
```

运行项目规定测试，确认只有搜索过滤功能变化，没有凭据、调试文件或无关格式化。

## 四、首次发布功能分支

```bash
git push -u origin feature/search-filter
```

平台创建评审后，记录：功能目的、主要决策、验证命令与结果、部署影响和回滚思路。

## 五、结果判断

你应能证明：

1. `origin/main` 已通过 `fetch` 更新；
2. 远程主线提交全部保留；
3. 本地功能提交因变基得到新 ID，这是预期重建；
4. 功能最终差异没有丢失；
5. 使用普通首次推送，没有强制覆盖任何远程引用；
6. 上游关系已经建立，后续 `status` 能显示领先或落后。

这个流程的安全来自先观察共享边界，再选择历史整合方式，而不是来自某一条固定命令。
