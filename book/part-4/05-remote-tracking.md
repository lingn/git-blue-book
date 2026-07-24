# 远程跟踪分支记录了什么

## origin/main 不是远程服务器本身

`origin/main` 的准确工作定义是：本地保存的引用，记录最近一次成功获取或推送后，远程 `origin` 的 `main` 分支位置。

它通常不能像本地分支那样直接提交。切换或提交日常工作应使用本地 `main`、功能分支等。

## 三种常见关系

### 两边一致

```text
A <- B
     ^
main, origin/main
```

本地没有未发布提交，也没有已获取但未整合的远程提交。

### 本地领先

```text
A <- B <- C  main
     ^
origin/main
```

C 只在本地历史中，尚未推送。

### 本地落后

```text
A <- B <- C  origin/main
     ^
    main
```

获取到了远程 C，但本地 `main` 还未整合。

还可能双方都独立前进，形成分叉。那时不能靠移动一个名字同时保留双方，需要合并或变基。

## 查看双方各自拥有的提交

先更新远程记录：

```bash
git fetch origin
```

只在远程跟踪分支、尚不在本地 `main` 的提交：

```bash
git log --oneline main..origin/main
```

`A..B` 表示从 B 可达、但从 A 不可达的提交。因此这里回答“远程有哪些是本地 main 没有的”。

反过来查看只在本地的提交：

```bash
git log --oneline origin/main..main
```

同时查看分叉图：

```bash
git log --oneline --graph --decorate --all
```

## ahead 与 behind

`git status` 在本地分支配置了上游关系时，可能报告 `ahead` 或 `behind`：

- ahead：本地有上游没有的提交；
- behind：上游有本地没有的提交；
- diverged：双方各有独立提交。

这里的比较对象是本地保存的远程跟踪引用。长时间没有 `fetch` 时，结果可能过时。

## 小结

远程跟踪分支是上次通信后的本地证据。先 `fetch`，再比较提交范围，才能基于较新的证据决定拉取、合并、变基或推送。
