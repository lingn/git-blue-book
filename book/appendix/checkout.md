# 旧教程中的 git checkout

现代 Git 把旧 `checkout` 的主要职责拆成 `switch` 和 `restore`。阅读旧文档时可以按意图转换。

| 旧写法 | 现代主线写法 | 意图 |
| --- | --- | --- |
| `git checkout main` | `git switch main` | 切换分支 |
| `git checkout -b feature/x` | `git switch -c feature/x` | 创建并切换分支 |
| `git checkout -- README.md` | `git restore README.md` | 从暂存区恢复工作区文件 |
| `git checkout <提交> -- README.md` | `git restore --source=<提交> README.md` | 从指定提交恢复文件 |
| `git checkout <提交>` | `git switch --detach <提交>` | 进入 HEAD 分离状态 |

`checkout` 仍然可用，也可能是老版本 Git 的唯一选择。拆分后的命令减少了“本想切分支却覆盖文件”这类意图混淆。

## HEAD 分离状态的安全离开

如果只查看旧提交且没有创建新提交：

```bash
git switch <原分支名>
```

如果已经创建需要保留的新提交，先建立分支：

```bash
git switch -c recovery/detached-work
```

再检查提交图。不要直接离开后依赖自己记住提交 ID。

## 版本边界

`switch` 和 `restore` 从 Git 2.23 起提供；`git init --initial-branch` 从 Git 2.28 起提供。本书命令主线以 Git 2.28 及以上为基线。旧环境可查当前版本对应手册，但升级通常比长期混用旧接口更清晰。
