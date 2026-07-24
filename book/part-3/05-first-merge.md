# 把两条历史合到一起：git merge

练习仓库当前状态应类似：

```text
main ---------------- C
                       \
feature/quick-start ---- D
```

D 是功能分支的新提交。现在希望让 `main` 也包含它。

## 合并的动作方向

`git merge <另一个分支>` 的含义是：把指定分支可达、而当前分支尚未包含的历史整合进当前分支。

因此必须先切换到接收变化的分支：

```bash
git switch main
git status
```

确认当前是 `main` 且工作区干净，再执行：

```bash
git merge feature/quick-start
```

不要只记“main merge feature”这句话，要记住动作对象：当前分支会变化，命令参数所指分支不会因为这次合并而移动。

## 这次为什么只是向前移动

`main` 停在 C，而功能分支 D 的历史中包含 C。Git 不需要组合两套不同修改，只要让 `main` 从 C 向前移动到 D：

```text
                    main
                      v
C <- D
     ^
feature/quick-start
```

输出会包含 `Fast-forward`。本书把**快进合并**定义为：当前分支是目标提交的祖先，因此只需把当前分支引用向前移动，不创建新的合并提交。

验证：

```bash
git log --oneline --graph --decorate --all
git status
```

`main` 和 `feature/quick-start` 现在指向同一提交，`QUICKSTART.md` 出现在当前工作区。

## 合并成功不等于功能正确

Git 能判断历史和文本是否可以整合，不能判断业务行为是否正确。真实项目合并后还需要运行测试、构建或人工检查。版本控制验证和产品验证是两层证据。

## 分支合并后是否必须删除

功能分支名字已经完成使命时可以删除，但不是合并动作的必要部分。先确认：

```bash
git branch --merged
```

它列出已经合入当前历史的本地分支。删除已合并功能分支：

```bash
git branch -d feature/quick-start
```

`-d` 会在 Git 认为分支尚未合并时拒绝，提供一层保护。大写 `-D` 会强制删除，本实验不需要，也不应把它当作清理快捷方式。

删除后提交 D 仍由 `main` 到达，因此历史没有消失。

## 下一章

这次合并很简单，因为 `main` 没有独立前进。下一章会让两条工作线各自产生提交，比较快进与合并提交，并解释 Git 怎样寻找共同祖先。
