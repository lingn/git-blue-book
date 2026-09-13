# 第五篇：远程仓库、协议与认证

Git 的“远程”是另一个仓库，不是当前分支自动同步的云端副本。远程协作至少涉及服务器 refs、本地 remote-tracking refs、本地分支、upstream、对象传输、连接身份、仓库授权和平台控制面。把这些状态压成一个 `origin/main`，会让 fetch、pull、push 和权限错误无法诊断。

本篇先建立厂商无关的数据面模型，再进入 clone、remote/refspec、fetch、pull、push、传输协议与认证、协商和受限克隆。GitHub、GitLab、Bitbucket 或公司平台的易变功能只作为带版本、权限、套餐和核对日期的实例，不把界面按钮当作 Git 语义。

## 进入条件

开始前应理解对象、引用、提交图、本地分支和合并，并能用完整 OID 判断祖先关系。所有远程数据面实验使用 `mktemp` 下的本地 bare 仓库或 `file://` URL，不读取真实凭据，不连接互联网。

## 已落地内容

1. [远程状态模型：服务器事实、本地缓存和工作分支不能混写](01-remote-state-model.md)

后续章节按迁移表继续落地 clone、remote/refspec、fetch/`FETCH_HEAD`、pull、push、拒绝/原子推送、传输认证、协商/受限克隆和综合练习。旧第四篇在目标章节完成前继续承担未迁移正文。

## 实验边界

当前实验验证本地 bare 服务器、`ls-remote`、remote-tracking ref、upstream、`FETCH_HEAD` 和本地分支的独立变化。它不验证 DNS、SSH/TLS、真实令牌、SSO、平台权限、隐藏 refs、分支保护、审计、复制延迟、LFS 或 CI。
