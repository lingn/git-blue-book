# 查看和管理远程地址：git remote

继续位于刚克隆的 `git-book-reading`。

## 查看远程名称

```bash
git remote
```

通常输出：

```text
origin
```

`origin` 是 `clone` 默认给来源仓库使用的本地简称。它只是约定名称，不是 Git 中“中央仓库”的保留字。

查看名称对应的获取和推送地址：

```bash
git remote -v
```

`-v` 表示显示更详细信息。通常同一远程会有 fetch 与 push 两行，地址可以相同，也可以按需要分别配置。

## 查看一个远程的详细关系

```bash
git remote show origin
```

这条命令可能访问网络，显示默认分支、跟踪关系和推送状态。网络不可用时不要把连接失败误解为本地历史损坏。

## 添加第二个远程

在开源协作中，个人派生仓库可能叫 `origin`，原项目常被命名为 `upstream`：

```bash
git remote add upstream <原项目仓库URL>
```

`add` 创建本地远程配置，`upstream` 是你选择的名称。请替换占位符，不要连尖括号一起执行。

同一个本地仓库可以配置多个远程。远程名称帮助区分交换目标，不会复制工作区文件。

## 修改错误地址

先查看当前值，再修改：

```bash
git remote get-url origin
git remote set-url origin <正确仓库URL>
```

修改地址不会搬运服务器仓库，也不会重写提交，只改变后续连接目标。执行前要确认新地址对应正确仓库，避免把代码推向错误位置。

## 删除远程配置

```bash
git remote remove upstream
```

它删除本地对该远程的配置和相应远程跟踪引用，不会删除服务器仓库。本书练习仓库没有实际添加 `upstream` 时不要执行。

## 小结

远程名称是本地别名，URL 才是连接目标。下一章使用 `origin` 获取变化，但暂不改动本地工作分支。
