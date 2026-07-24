# 看清改了什么：git diff

`git status` 告诉你哪些文件发生变化，`git diff` 则显示具体内容差异。

## 先制造一处工作区修改

在 `README.md` 末尾增加：

```markdown

这个仓库用于练习 Git 的基本工作流。
```

保存后执行：

```bash
git diff
```

不带额外参数的 `git diff` 比较工作区与暂存区。你会看到以 `-` 开头的删除行、以 `+` 开头的新增行，以及帮助定位的上下文。

当前暂存区与最近提交一致，所以输出正好是提交后新增的文字。

## 怎样读差异头部

典型输出包含：

```diff
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ ... @@
 这是上下文
+这是新增内容
```

`a/` 和 `b/` 是比较两侧的标签，不是项目中真的多了两个目录。`@@` 行标识差异所在范围。颜色只是显示辅助，真正语义仍由前缀表示。

## 查看暂存区准备提交的差异

先暂存当前修改：

```bash
git add README.md
```

再次执行 `git diff`，输出为空，因为工作区和暂存区现在一致。这不表示变化消失了。

查看暂存区与最近提交的差异：

```bash
git diff --staged
```

`--staged` 指定比较已经为下次提交准备的内容。也可以看到写法 `--cached`，在这个场景中效果相同；本书主线使用语义更直观的 `--staged`。

## 同一文件两种差异

在已经暂存后，再给 `README.md` 增加一行但不要执行 `git add`。此时：

- `git diff` 显示暂存之后的新修改；
- `git diff --staged` 显示已经准备提交的修改；
- `git status` 会把同一文件列入两组状态。

两条差异加在一起，才是工作区相对最近提交的全部变化。

## 差异输出太长

Git 可能使用分页器展示长输出。按空格向下翻页，按 `q` 退出。退出分页器不会撤销或改变任何内容。

只看某个文件：

```bash
git diff -- README.md
git diff --staged -- README.md
```

单独的 `--` 表示后面按路径解释，避免文件名与其他参数产生歧义。

## 提交前检查顺序

形成习惯：

```bash
git status
git diff
git diff --staged
```

先看文件范围，再看未暂存内容，最后审查真正会进入提交的内容。只有 `git diff --staged` 的结果符合本次意图，才进入提交。

## 完成本章实验

把希望纳入文档说明的最终内容重新暂存，然后创建第二条提交：

```bash
git add README.md
git diff --staged
git commit -m "docs: explain repository purpose"
```

提交后运行 `git status`，确认工作区干净。
