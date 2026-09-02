# 易变事实登记表

本表记录正文中依赖版本、权限、套餐、计费或厂商实现的事实。Git 的稳定核心语义仍在各章来源中记录；平台界面文案和操作路径不得只靠截图长期保存。

## 登记字段

| 字段 | 要求 |
| --- | --- |
| 事实 ID | 稳定短名，供正文和审校记录引用 |
| 主题 | 认证、评审、CI、审计、LFS、计费等 |
| 厂商与产品 | 写明云服务、自托管版和产品层级 |
| 事实陈述 | 可核对的单一断言，不混合多个条件 |
| 版本或套餐 | 最低版本、许可层级或“不适用” |
| 权限 | 执行或查看该能力所需角色 |
| 计费影响 | 无、包含、按量或需要另行核对 |
| 核对日期 | `YYYY-MM-DD` |
| 官方来源 | 官方文档或发布说明链接 |
| 正文位置 | 使用该事实的章节 |
| 状态 | 待核对、有效、已变化、已移除 |

## 当前记录

| 事实 ID | 主题 | 厂商与产品 | 事实陈述 | 版本或套餐 | 权限 | 计费影响 | 核对日期 | 官方来源 | 正文位置 | 状态 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PF-GENERIC-001 | 分支保护 | 厂商无关抽象 | 分支保护由托管平台或服务端控制面实施，不属于本地 Git 客户端语义 | 不适用 | 平台配置者 | 不适用 | 2026-08-20 | 待各厂商实例补充 | `book/part-06/08-protected-refs-and-exceptions.md`、`book/part-12/03-policy-rules-and-exceptions.md` | 有效 |
| LFS-UPSTREAM-001 | LFS 客户端 | Git LFS 官方项目 | 核对时官方 latest release 为 Git LFS 3.7.1，发布于 2025-10-17 | 3.7.1 | 不适用 | 无 | 2026-08-20 | [官方 release](https://github.com/git-lfs/git-lfs/releases/tag/v3.7.1) | `book/part-09/02-binary-and-lfs.md` | 有效 |
| LFS-LOCK-001 | LFS 锁 | Git LFS File Locking API | 官方 API 定义创建、列出、验证和删除路径锁；实际可用性与强制入口仍取决于服务端和客户端配置 | API v2.0 起；本章按 3.7.1 文档 | 创建/验证通常需要 push 权限，列出至少需要 pull 权限 | 服务端成本另行核对 | 2026-08-20 | [官方锁 API](https://github.com/git-lfs/git-lfs/blob/v3.7.1/docs/api/locking.md) | `book/part-09/02-binary-and-lfs.md` | 有效 |
| FILTER-REPO-UPSTREAM-001 | 历史清理工具 | git-filter-repo 官方项目 | 核对时官方 latest release 为 2.47.0，发布于 2024-12-04 | 2.47.0 | 本机执行者需有 cleanup clone 权限；远端更新权限另行核对 | 工具免费；平台清理成本另行核对 | 2026-08-20 | [官方 release](https://github.com/newren/git-filter-repo/releases/tag/v2.47.0) | `book/part-10/01-credential-leak-history-cleanup.md` | 有效 |
| GH-DEPLOY-KEY-001 | 机器身份 | GitHub.com | Deploy key 关联单个仓库，默认只读，可显式开启写入且没有到期日；官方在需要更细权限时推荐 GitHub App | 云服务当前文档；GitHub Enterprise Server 需按版本复核 | 仓库管理员创建/移除；运行端持有私钥 | 无单独 token 费用；账户/服务成本另行核对 | 2026-08-20 | [官方文档](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys) | `book/part-10/02-machine-identities.md` | 有效 |
| GH-APP-TOKEN-001 | 机器身份 | GitHub.com GitHub Apps | Installation token 不能超出 app/installation 已授予的仓库与权限，请求时可进一步缩小，并在一小时后到期 | 云服务当前文档；GitHub Enterprise Server 需按版本复核 | App 私钥持有者可签发；安装与权限由相应管理员批准 | 无单独 token 费用；App 与账户成本另行核对 | 2026-08-20 | [官方文档](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app) | `book/part-10/02-machine-identities.md` | 有效 |
| GH-ACTIONS-OIDC-001 | 工作负载身份 | GitHub.com Actions | 每个 job 可请求唯一 OIDC JWT，目标云服务依据 subject 等 claims 决定是否签发短期访问 token | 云服务当前文档；自托管 runner 和 GitHub Enterprise Server 支持边界需另行核对 | Workflow 需获准请求 ID token；目标身份管理员配置 trust policy | Actions 与目标服务计费另行核对 | 2026-08-20 | [概念](https://docs.github.com/en/actions/concepts/security/openid-connect)、[参考](https://docs.github.com/en/actions/reference/security/oidc) | `book/part-10/02-machine-identities.md` | 有效 |
| GL-CI-IDTOKEN-001 | 工作负载身份 | GitLab CI/CD | Job 可用 `id_tokens` 生成用于第三方 OIDC 认证的 JWT，并可为不同 token 配置不同 `aud` | 官方页标注 Free/Premium/Ultimate；GitLab.com、Self-Managed、Dedicated，具体 claims 按版本复核 | CI 配置作者声明 token；第三方服务管理员配置验证策略 | GitLab 与第三方服务成本另行核对 | 2026-08-20 | [官方文档](https://docs.gitlab.com/ci/secrets/id_token_authentication/) | `book/part-10/02-machine-identities.md` | 有效 |
| GH-ACTIONS-PIN-001 | CI 供应链 | GitHub.com Actions | 官方 secure-use 文档把完整 commit SHA 描述为当前唯一可把 Action 当作不可变 release 使用的引用，并提供仓库/组织级强制完整 SHA 策略 | 云服务当前文档；GitHub Enterprise Server 与策略可用性按版本复核 | Workflow 作者选择依赖；仓库/组织管理员配置策略 | Actions 用量与套餐另行核对 | 2026-08-20 | [官方文档](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions) | `book/part-10/03-ci-dependency-supply-chain.md` | 有效 |
| GL-INCLUDE-INTEGRITY-001 | CI 供应链 | GitLab CI/CD | `include:integrity` 可为 `include:remote` 指定 Base64 编码 SHA-256，内容不匹配时不处理文件并让 pipeline 失败 | 当前主线文档；Self-Managed/Dedicated 最低版本需按部署复核 | Pipeline 配置作者声明；项目维护者控制变更 | GitLab 套餐与外部托管成本另行核对 | 2026-08-20 | [YAML 官方文档](https://docs.gitlab.com/ci/yaml/#includeintegrity) | `book/part-10/03-ci-dependency-supply-chain.md` | 有效 |
| GH-SECRET-PUSH-001 | 秘密扫描 | GitHub.com secret scanning/push protection | Push protection 旨在秘密进入仓库前阻止或告警；支持模式、组织/企业设置、绕过和超大/超时边界不能替代完整历史或副本扫描 | 云服务当前文档；Enterprise Server 按版本复核 | 仓库、组织或企业安全配置者；结果访问权限另行核对 | 套餐与用量另行核对 | 2026-08-20 | [Push protection](https://docs.github.com/en/code-security/concepts/secret-security/push-protection)、[patterns](https://docs.github.com/en/code-security/reference/secret-security/supported-secret-scanning-patterns) | `book/part-10/06-secret-scanning-and-exports.md` | 有效 |
| GL-SECRET-SCAN-001 | 秘密扫描 | GitLab CI/CD secret detection/push protection | Pipeline 检测与 pre-receive push protection 的覆盖范围不同；historic scan 需单独执行，浅克隆、二进制、超大 diff、超时和未变化旧秘密是边界 | GitLab.com、Self-Managed、Dedicated 的具体能力按版本复核 | Pipeline 配置者、项目维护者和报告查看者按部署授权 | 套餐、runner 和 artifact 保留成本另行核对 | 2026-08-20 | [Pipeline secret detection](https://docs.gitlab.com/user/application_security/secret_detection/pipeline/)、[push protection](https://docs.gitlab.com/user/application_security/secret_detection/secret_push_protection/) | `book/part-10/06-secret-scanning-and-exports.md` | 有效 |

新增厂商实例前，先核对官方文档并补齐表格。GitHub、GitLab 或其他服务的 LFS 单文件限制、存储/带宽配额、锁支持、保留和计费尚未登记，正文不写具体数字。无法确认套餐或权限时，正文保持抽象描述，不猜测。
