# 完整处理一次冲突

本章继续使用练习仓库，先确认位于 `main` 且状态干净。实验会两次触发同一冲突：第一次中止，第二次完成。

## 准备两个不同标题

创建功能分支：

```bash
git switch -c feature/title
```

把 `README.md` 第一行改为：

```markdown
# Git Quick Start Lab
```

提交：

```bash
git add README.md
git commit -m "docs: rename guide for quick start"
```

切回 `main`，把同一行改成另一种标题：

```markdown
# Git Practice Handbook
```

```bash
git switch main
git add README.md
git commit -m "docs: rename guide as handbook"
```

## 第一次合并：观察并中止

```bash
git merge feature/title
```

命令会报告 `CONFLICT` 并停止。先观察：

```bash
git status
git diff
```

`git status` 会说明正在合并，并把 `README.md` 列为双方都修改。`git diff` 会显示冲突区域。

如果此时发现合并目标错误，或需要先与同事确认意图，可以回到合并前：

```bash
git merge --abort
```

再运行：

```bash
git status
git log --oneline --graph --decorate --all
```

应回到干净的 `main`，两条分支提交都仍存在。`--abort` 不是“选择 main 内容”，而是取消整次合并尝试。

合并前若已有未提交修改，恢复可能更复杂，因此开始前保持工作区干净。

## 第二次合并：形成业务最终结果

重新触发：

```bash
git merge feature/title
```

打开 `README.md`，先读双方标题和周围内容。假设团队决定最终标题既强调练习，也保留快速开始含义，编辑为：

```markdown
# Git Quick Start Practice
```

删除所有 `<<<<<<<`、`=======`、`>>>>>>>` 标记，保存文件。

## 标记已解决并完成合并

```bash
git add README.md
git status
git diff --staged
```

这里 `git add` 的含义仍是把最终文件放入暂存区。对冲突路径而言，这同时告诉 Git：你已经给出该路径的解决结果。

确认暂存内容正确后：

```bash
git commit -m "merge: reconcile guide title"
```

也可以运行 `git merge --continue`，让 Git 使用准备好的合并说明；它可能打开编辑器。无论哪种方式，都先确认没有未解决路径。

## 验证不是可选步骤

```bash
git status
git log --oneline --graph --decorate --all
```

还应运行项目测试，并搜索是否残留冲突标记。当前文档仓库可以执行：

```bash
git grep -n -e '<<<<<<<' -e '=======' -e '>>>>>>>'
```

没有输出表示被跟踪文件中没有这些文本。真实项目可能合法包含教学示例或分隔线，需要人工判断命中结果。

## 怎样向同事说明冲突

不要只说“有冲突，我解决了”。使用下面四项：

```text
冲突文件：README.md 第一行
当前分支意图：把文档定位为完整练习手册
功能分支意图：突出快速开始入口
最终处理：改为 Git Quick Start Practice，同时保留两侧定位；已检查提交图并完成文档校验
```

这份说明让原作者能够检查你是否理解双方意图。对于代码冲突，最后一项应写具体测试、请求样例或运行结果。

确认无误后可删除功能分支：

```bash
git branch -d feature/title
```
