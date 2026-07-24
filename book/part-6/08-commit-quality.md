# 提交信息、粒度与可审查历史

## 好提交的目标

一条提交应让未来读者回答：为什么改、改了什么边界、怎样验证、能否独立撤销。它不是保存频率记录，也不是追求漂亮图形的装饰。

## 提交粒度

适合放在同一提交的变化通常共同完成一个意图，例如实现输入校验以及对应测试。下列内容通常应拆开：

- 无关的格式化与业务修复；
- 两个可以独立发布的功能；
- 大规模重命名与行为改变；
- 生成物更新与不相关源码调整。

拆分不是按文件数。一个数据库变更可能合理涉及迁移、实体、服务、测试和文档；它们共同表达一个完整兼容策略。

## 提交说明结构

简短主题应具体、使用主动语义：

```text
fix: prevent duplicate settlement on retry
```

需要正文时说明动机和边界，而不是复述差异：

```text
fix: prevent duplicate settlement on retry

Persist the provider request key before the first external call so a
worker retry reuses the same operation. Database migration is backward
compatible with the previous worker version.
```

团队可使用统一前缀和任务号，但模板不能替代清楚因果。

## 提交前自审

```bash
git status
git diff
git diff --staged
```

提交后再看：

```bash
git show --stat HEAD
git show HEAD
```

运行测试，并确认敏感信息、调试代码和本地产物没有进入历史。

## 历史不必伪装成从未犯错

个人未分享分支可以通过 amend 或交互式变基整理噪音。已经评审或共享的提交应优先保持坐标稳定。可审查性包括真实的修复和回滚记录，不等于删除所有过程。

## 生成提交与人工责任

工具可以生成说明或建议拆分，但提交者仍要核对文件范围、业务意图和测试证据。作者身份是审计记录，不是文字生成来源声明。
