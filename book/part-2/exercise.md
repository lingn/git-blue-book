# 综合场景：把混合改动拆成可靠提交

现在用一次完整练习把本篇命令连起来。目标不是“把状态清空”，而是把不同意图记录成不同提交。

## 准备场景

在 `git-first-lab` 中创建两个文件：

`CONTRIBUTING.md`：

```markdown
# Contributing

提交前请检查差异并运行项目测试。
```

`notes.txt`：

```text
个人草稿：后续考虑增加分支练习。
```

同时修改 `README.md`，补充一句：

```markdown
贡献说明请查看 CONTRIBUTING.md。
```

现在有三项变化，但它们不属于同一意图：`README.md` 和 `CONTRIBUTING.md` 是团队文档，`notes.txt` 是个人草稿。

## 第一步：观察，不要全量暂存

```bash
git status
git diff
```

你应看到一个已修改文件和两个未跟踪文件。此时执行 `git add .` 会把个人草稿也选入暂存区，因此应明确选择路径。

## 第二步：准备团队文档提交

```bash
git add README.md CONTRIBUTING.md
git status
git diff --staged
```

检查点：

- `README.md` 和 `CONTRIBUTING.md` 位于暂存区；
- `notes.txt` 仍是未跟踪文件；
- 暂存差异只包含贡献说明。

确认后提交：

```bash
git commit -m "docs: add contribution guide"
```

## 第三步：处理个人草稿

个人草稿是否提交取决于团队规则。这个场景决定不提交它，把规则加入 `.gitignore`：

```gitignore
notes.txt
```

检查规则：

```bash
git check-ignore -v notes.txt
git status
```

然后只提交忽略规则：

```bash
git add .gitignore
git diff --staged
git commit -m "chore: ignore personal notes"
```

## 第四步：检查结果

```bash
git status
git log --oneline
git show --stat
```

你应该能够证明：

1. 工作区状态干净，`notes.txt` 仍保留在磁盘上但被忽略；
2. 团队文档和忽略规则属于两个不同提交；
3. 每条提交说明都能解释一个单独意图；
4. 没有任何命令连接或上传远程仓库。

如果结果不同，不要删除仓库重新开始。先用 `git status`、`git diff`、`git diff --staged` 和 `git log --oneline` 判断差异位于哪个区域，再回到对应章节处理。
