# 快进与合并提交

上一章的 `main` 没有独立前进，所以合并只需移动分支。真实协作中，两条工作线往往都会产生提交。

## 制造一段分叉历史

确认当前位于 `main` 且状态干净，然后创建功能分支：

```bash
git switch -c feature/navigation
```

创建 `NAVIGATION.md`，写入一段导航说明，随后提交：

```bash
git add NAVIGATION.md
git commit -m "docs: add navigation guide"
```

切回 `main`，在 `README.md` 末尾增加一行版本说明并提交：

```bash
git switch main
git add README.md
git commit -m "docs: add version note"
```

现在两条分支从同一个提交分开：

```text
             N  feature/navigation
            /
... <- B <- C
            \
             V  main
```

C 是两条历史最近的共同祖先。N 和 V 都不是对方的祖先，因此 `main` 无法直接快进到功能分支。

## 创建合并提交

当前位于接收变化的 `main`：

```bash
git merge feature/navigation
```

两个分支修改不同文件，Git 通常可以自动整合，并创建一条有两个父提交的新提交 M：

```text
             N  feature/navigation
            / \
... <- B <- C   M  main
            \ /
             V
```

M 的第一父提交是合并前的 `main`，第二父提交是 `feature/navigation`。M 的快照同时包含双方变化。

查看真实图形：

```bash
git log --oneline --graph --decorate --all
```

## 三种常见策略

### 默认合并

```bash
git merge feature/navigation
```

能快进时直接移动分支；已经分叉时创建合并提交。这是前面实验使用的行为。

### 只允许快进

```bash
git merge --ff-only feature/navigation
```

`--ff-only` 要求当前分支必须能够直接向前移动，否则拒绝并保持历史不变。适合不希望无意产生合并提交的流程。

### 即使能快进也创建合并提交

```bash
git merge --no-ff feature/navigation
```

`--no-ff` 会保留一次明确的分支合并节点。它能突出功能边界，也会增加历史节点。团队应根据评审和发布方式统一，而不是争论哪种图形永远最好。

上面后两条用于解释策略，不要在已经合并的练习分支上重复执行。

## 合并提交与文件内容

合并提交并不是把两个目录简单叠加。Git 从共同祖先出发，分别计算两侧怎样变化，再尝试组合。不同文件或不重叠位置的修改通常能够自动合并；同一语义是否冲突，Git 不一定知道。

因此“没有文本冲突”只能证明 Git 找到了机械合并结果，不能证明业务正确。仍需测试最终快照。

## 清理实验分支

确认图形和内容正确后：

```bash
git branch -d feature/navigation
```

删除的是名字，N 和 M 仍属于 `main` 历史。

## 小结

快进只移动引用；分叉历史需要合并提交把两个父节点汇合。下一章深入合并算法的核心：为什么某些地方必须交给人决定。
