# 第四篇：与远程仓库和团队协作

这一篇始终区分“远程服务器上的状态”“本地保存的远程快照”和“当前本地分支”，避免把 `pull` 当作不可解释的同步魔法。

## 本篇内容

1. [远程仓库到底远在哪里](01-remote-model.md)
2. [复制完整仓库：git clone](02-clone.md)
3. [查看和管理远程地址：git remote](03-remote.md)
4. [只获取、不整合：git fetch](04-fetch.md)
5. [远程跟踪分支记录了什么](05-remote-tracking.md)
6. [git pull 实际组合了哪两步](06-pull.md)
7. [发布本地提交：git push 与上游分支](07-push.md)
8. [推送为什么会被拒绝](08-push-rejection.md)
9. [代码评审前整理什么](09-review-ready.md)
10. [变基的本质：重新生成提交](10-rebase-model.md)
11. [安全使用 git rebase](11-rebase-workflow.md)
12. [只迁移需要的提交：git cherry-pick](12-cherry-pick.md)
13. [远程 URL、传输协议与认证边界](13-transport-auth.md)
14. [Refspec、传输协商与受限克隆](14-refspec-partial-clone.md)
15. [综合场景：同步主线并准备代码评审](exercise.md)

本篇完成后，你应能指出每条同步命令改变了哪一层，区分 Git 协议、SSH/HTTPS 保护、客户端认证和仓库授权，并判断一个受限克隆缺的是引用、祖先、对象还是工作区路径。
