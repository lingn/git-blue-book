# 取消暂存，但保留文件修改

## 事故现场

你把 `debug.conf` 或一个尚未完成的文件加入了暂存区，但希望文件继续留在工作区，只是不进入下一次提交。

先确认：

```bash
git status
git diff --staged -- debug.conf
```

取消暂存：

```bash
git restore --staged debug.conf
```

`--staged` 把恢复目标改为暂存区。默认来源是 `HEAD`，因此暂存区回到当前提交中的状态；工作区文件不变。

## 验证两个结果

```bash
git status
git diff -- debug.conf
git diff --staged -- debug.conf
```

预期：

- 文件变化出现在未暂存区域；
- 暂存差异中不再包含它；
- 磁盘文件内容仍是你的修改。

## 新文件的情况

如果新文件是在已有历史的仓库中首次暂存，`git restore --staged new-file.txt` 会把它从暂存区移回未跟踪状态，文件仍在。

仓库尚无第一条提交时没有 `HEAD` 可作为默认来源，命令行为会受到限制。这种特殊情况下可以使用：

```bash
git rm --cached new-file.txt
```

`--cached` 只从暂存区移除路径，不删除工作区文件。执行后用 `git status` 验证。

## 与丢弃修改的区别

```bash
git restore --staged README.md
```

保留工作区修改，只取消暂存。

```bash
git restore README.md
```

覆盖工作区修改，默认取暂存区版本。

两条命令只差一个选项，数据影响完全不同。不要为了“撤销 add”误执行第二条。

## 一次取消多个路径

可以明确列出：

```bash
git restore --staged README.md debug.conf
```

也可以对整个当前目录操作，但在复杂现场中明确路径更容易验证。完成后重新选择真正属于本次提交的内容。
