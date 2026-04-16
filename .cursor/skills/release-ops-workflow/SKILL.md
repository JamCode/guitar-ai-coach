---
name: release-ops-workflow
description: 统一处理发布运维任务：Swift iOS（`swift_ios_host`）本机 Xcode 归档与 TestFlight 上传、阿里云 ECS SSH 运维登录约定、Python 后端与 Flyway 部署、环境变量与密钥配置管理、发布前后检查与回滚建议。用户提到“打包”“TestFlight”“GitHub Actions”“CI”“上线”“部署”“ECS”“阿里云”“SSH”“登录服务器”“运维”“配置管理”“环境变量”“发布流程”时启用。
---

# 发布与运维工作流（iOS + ECS + 配置管理）

## 适用范围

- iOS：`swift_ios_host/` 的本机 Xcode 归档、IPA 产出、上传 TestFlight（本机为主；仓库内原 Flutter CI 已移除）。
- 后端/前端：ECS 上的 Python 后端 + Nginx 静态站点发布。
- 配置管理：Team/Bundle ID、App Store Connect API Key、后端 `backend.env`、ECS SSH 参数与发布检查项。

## 关键原则

1. **先确认目标环境**：本机测试、TestFlight、还是 ECS 线上。
2. **密钥不入库**：`.p8`、`.pem`、`backend.env` 实值、token 只放本机安全路径或 CI Secret。
3. **发布有检查点**：发布前检查 + 发布后冒烟 + 可回滚路径。
4. **命令优先可复现**：优先执行仓库已有文档中的标准命令，不临时发明流程。

## 运维连接约定：阿里云 ECS（本仓库固定信息）

**对 Agent 的强制口径**：用户要求「登录云服务器 / ECS / 查线上库配置」时，**默认已知**下列约定；应直接在本机用 SSH 执行或给出命令，**不要**回答「不知道服务器地址或路径」。密码、DashScope Key 等敏感值**从不写进本 skill**，须从服务器或本机 `deploy/ecs/backend.env` **现读**（该文件已被 `.gitignore`，勿提交）。

### SSH 与私钥路径

| 项 | 约定值 |
| --- | --- |
| **ECS 公网 IP** | `47.110.78.65`（与 `deploy/ecs/README.md` 一致；若变更以用户或 Variables 为准） |
| **SSH 用户** | `wanghan` |
| **本机私钥（常用）** | 仓库根目录 `my-ecs-key2.pem`（与 `*.pem` 在 `.gitignore` 中；**勿提交 Git**） |
| **SSH 命令模板** | `ssh -i /path/to/guitar-ai-coach/my-ecs-key2.pem -o StrictHostKeyChecking=accept-new wanghan@47.110.78.65 "<远程命令>"` |

本机执行前建议：`chmod 600 my-ecs-key2.pem`。

### 服务器上项目路径与进程

| 项 | 路径或名称 |
| --- | --- |
| **项目根** | `/home/wanghan/guitar-ai-coach`（即下文 `ECS_PATH`） |
| **Python 后端代码** | `/home/wanghan/guitar-ai-coach/backend/code` |
| **后端环境变量文件** | `/home/wanghan/guitar-ai-coach/deploy/ecs/backend.env` |
| **Nginx 静态站点根** | `/home/wanghan/guitar-ai-coach/site`（`ECS_SITE`） |
| **systemd 服务名** | `guitar-ai-coach-backend` |
| **后端本机监听** | `127.0.0.1:18080` |

### MySQL（线上配置从哪读）

- 连接参数在 **ECS** 的 `deploy/ecs/backend.env` 中，变量名为：`MYSQL_HOST`、`MYSQL_PORT`、`MYSQL_USER`、`MYSQL_PASSWORD`、`MYSQL_DATABASE`。
- **当前环境典型约定**（非密钥、便于对齐 GitHub Actions；若与线上文件不一致以线上为准）：
  - `MYSQL_HOST`：`localhost`
  - `MYSQL_PORT`：`3306`
  - `MYSQL_USER`：`guitar_app`
  - `MYSQL_DATABASE`：`guitar_ai_coach`
  - `MYSQL_PASSWORD`：**仅**在 `backend.env` 或用户提供的 Secret 中，**禁止**写入 skill、禁止贴到聊天日志。
- 在 ECS 上查看（不含解密需求时只看键名）：  
  `grep '^MYSQL_' /home/wanghan/guitar-ai-coach/deploy/ecs/backend.env`

### Flyway（与线上库一致）

- 迁移脚本目录（仓库内）：`backend/database/flyway/sql/`
- 在服务器上同步后常见路径：`/home/wanghan/guitar-ai-coach/backend/database/flyway/`
- 详见：`backend/database/flyway/README.md`

### GitHub Actions 与数据库相关的 Secret 名称（交叉引用）

- 工作流：`.github/workflows/ecs-backend-deploy.yml`
- `FLYWAY_USER` / `FLYWAY_PASSWORD`：与 ECS `backend.env` 中 `MYSQL_USER` / `MYSQL_PASSWORD` 一致；在 GitHub **Settings → Secrets and variables → Actions** 配置。
- `ECS_SSH_PRIVATE_KEY`：`my-ecs-key2.pem` 的**全文**（多行粘贴）。

### 本机开发副本（与 ECS 对照）

- 本机示例/编辑路径：`deploy/ecs/backend.env`（与 ECS 同步用 `rsync`，见 `deploy/ecs/README.md`）。

## 单次任务执行顺序

1. 明确本次目标（仅打包 / 打包+上传 / 前后端部署 / 全链路发布）。
2. 检查版本与配置（iOS build 号、Bundle ID、Team ID、ECS 环境变量）。
3. 执行发布动作（按下方子流程）。
4. 采集结果（关键输出、Delivery UUID、服务状态、HTTP 冒烟码）。
5. 形成交付记录（做了什么、结果、下一步）。

## A. iOS 本机打包与 TestFlight 上传

### A1. 打包前检查

- Bundle ID 与 App Store Connect 一致（当前 Xcode 目标默认：`com.jamcode.swift-ear-host`；若与 App Store Connect 不一致以线上为准）。
- Xcode `Signing & Capabilities` 使用正确 Team，自动签名无红字。
- **Build**（构建号）每次上传前必须大于 App Store Connect 上已有构建；在 Xcode 目标的 **General → Identity → Build**（或等价 `CURRENT_PROJECT_VERSION`）递增。

### A1.1 build 号递增规则（强制）

每次准备上传 TestFlight 前，必须先执行以下动作：

1. 打开 `swift_ios_host/SwiftEarHost.xcodeproj`
2. 选中宿主 App 目标，将 **Build** 至少加 1（或与团队约定的版本字段一致）
3. 再执行 **Product → Archive** 并导出 App Store 类型 IPA

若忘记递增，上传阶段会被 App Store Connect 拒绝（构建号重复）。

### A2. 构建 IPA（本机）

在 Xcode 中打开工程后：

1. `cd swift_ios_host && open SwiftEarHost.xcodeproj`
2. 选择真机或 `Any iOS Device (arm64)`，**Product → Archive**
3. Organizer 中选择归档 → **Distribute App** → App Store Connect → 按向导导出或上传

若需命令行归档，请按团队已验证的 `xcodebuild -scheme … -archivePath …` 脚本执行（以本机 Xcode 与 scheme 名为准）。

### A3. 命令行上传 TestFlight（altool）

前置：

- 本机有 `AuthKey_<KEY_ID>.p8`（当前约定放在 `~/Documents/certs/`）
- `KEY_ID`、`ISSUER_ID` 已确认
- IPA 文件已由 Xcode Organizer 导出到本机路径（例如 `~/Desktop/…ipa` 或自定义导出目录）

路径约定：

- API key 默认源文件：`~/Documents/certs/AuthKey_<KEY_ID>.p8`
- altool 读取目录：`~/.private_keys/AuthKey_<KEY_ID>.p8`
- 禁止将 `.p8` 放在仓库目录或提交 Git

```bash
mkdir -p "$HOME/.private_keys"
cp "$HOME/Documents/certs/AuthKey_<KEY_ID>.p8" "$HOME/.private_keys/AuthKey_<KEY_ID>.p8"
chmod 600 "$HOME/.private_keys/AuthKey_<KEY_ID>.p8"

xcrun altool --upload-app --type ios \
  -f "/abs/path/to/<your>.ipa" \
  --apiKey "<KEY_ID>" \
  --apiIssuer "<ISSUER_ID>"
```

### A4. 上传后检查

- 记录 `UPLOAD SUCCEEDED` 与 `Delivery UUID`。
- 到 App Store Connect -> TestFlight 等待构建处理完成。

## B. iOS CI 上传 TestFlight（GitHub Actions）

- **现状**：随 `flutter_app/` 移除，仓库内原 **Flutter** TestFlight / 集成测试相关 workflow 已删除；当前 **无** 预置的 Swift iOS GitHub Actions 上传流水线。
- **需要 CI 时**：新建基于 macOS Runner 的 workflow（证书、`xcodebuild archive/export`、`xcrun altool` 或 `notarytool`），并与本仓库 `swift_ios_host` 的 scheme、签名方式对齐。

### B0. 什么时候会跑（重要）

- 在未新增 Swift iOS workflow 前，**不会**由 GitHub Actions 自动产出 IPA。
- 若日后新增 `workflow_dispatch` 或 `push` 触发的 iOS 工作流，必须配套 **build 号自动递增** 或发布分支纪律，否则易因「构建号重复」失败。

### B1. 如何触发（本机 CLI）

若仓库重新加入 iOS 工作流后，再使用 `gh workflow run "<工作流显示名>" --ref <分支名>`；当前以 **A 节本机 Xcode** 为准。

### B2. CI 内大致步骤（便于排错，供将来恢复/新建 workflow 时参考）

1. 从 Secrets 还原 `.p12` 与 `.mobileprovision` 到临时钥匙串与 `~/Library/MobileDevice/Provisioning Profiles`。
2. 生成或检出 `ExportOptions` plist（`method=app-store`、`signingStyle=manual` 等，与目标一致）。
3. `xcodebuild archive` + `xcodebuild -exportArchive`（scheme 指向 `swift_ios_host` 宿主 App）。
4. `xcrun altool --upload-app`（依赖 `APP_STORE_CONNECT_*` 与 `~/.private_keys/AuthKey_*.p8`）。

### B3. 必备 Secrets（仓库 Settings → Secrets and variables → Actions）

- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`：Apple Distribution 的 `.p12` 整文件 **base64 单行**（无换行）。
- `IOS_DISTRIBUTION_P12_PASSWORD`：导出 `.p12` 时的密码。
- `IOS_APPSTORE_PROVISION_PROFILE_BASE64`：**App Store** 类型 `.mobileprovision` 的 base64 单行。
- `IOS_APPSTORE_PROVISIONING_PROFILE_NAME`：开发者网站里该 Profile 的 **名称**（Name），不是 UUID。
- `IOS_KEYCHAIN_PASSWORD`：CI 临时钥匙串密码（任意强随机字符串）。
- `APP_STORE_CONNECT_ISSUER_ID`、`APP_STORE_CONNECT_KEY_ID`、`APP_STORE_CONNECT_PRIVATE_KEY`：App Store Connect API（`.p8` 全文含 BEGIN/END）。

**`.p12` 兼容性**：若 CI 报 `PKCS12 import wrong password` 而本机密码无误，常见是 OpenSSL 3 默认加密与 `security import` 不兼容；在本机用 `openssl pkcs12 -export -provider default -provider legacy -legacy ...` 再生成一份 `.p12` 后重新 base64 写入 Secret。

### B4. Profile 与能力（本仓库易踩坑）

- App 使用 **Sign in with Apple** 时，**App Store** 分发用的 Provisioning Profile 必须基于已勾选 **Sign in with Apple** 的 App ID 生成；否则归档阶段会报类似：`requires a provisioning profile with the Sign in with Apple feature`。
- 在开发者网站改完 App ID 能力后，应 **重新生成并下载** App Store Profile，更新 Secret `IOS_APPSTORE_PROVISION_PROFILE_BASE64`（必要时核对 `IOS_APPSTORE_PROVISIONING_PROFILE_NAME` 与新 Profile 一致）。

### B5. 跑 CI 前检查（与 A1.1 相同）

- 先递增 Xcode 目标的 **Build**，**commit 并 push** 到将要触发的分支，再 Run workflow；否则上传易被拒。

### B6. 可选：改为 push 自动上 TestFlight

仅在用户明确要求且接受 Runner 分钟数与失败噪声时新增 YAML，并对 `swift_ios_host/**`（及 workflow 文件本身）配置 `paths` 过滤；同时需约定：**每次可上传的提交都必须唯一 build 号**（脚本 bump 或发布分支只合并可发布 commit）。

## C. ECS 后端与前端部署

主文档：`deploy/ecs/README.md`（以该文档为准，不重复发明新命令）。

### C1. 后端部署最小闭环

1. `rsync backend/code/` 到服务器 `${ECS_PATH}/backend/code/`
2. 如有数据库/迁移变更，同步 `backend/database/`，并按 Flyway 规则执行迁移
3. 需要时同步 `deploy/ecs/backend.env`（注意敏感信息）
4. `sudo systemctl restart guitar-ai-coach-backend`
5. `sudo systemctl is-active guitar-ai-coach-backend`
6. `curl http://127.0.0.1:18080/styles`（服务器本机）或公网 `/api/styles` 验证

### C2. 前端部署最小闭环

1. 本地 `cd frontend && npm ci && npm run build`
2. `rsync --delete frontend/dist/` 到 `${ECS_SITE}`
3. 若改了 Nginx 站点配置，`rsync deploy/ecs/nginx/guitar-server.conf` 后执行 `sudo nginx -t && sudo systemctl reload nginx`
4. 公网冒烟：`/`、`/dictionary`、`/api/styles`

## D. 配置管理清单（每次发布必查）

### D1. iOS 配置

- Bundle ID 是否与 App Store Connect 一致
- Team ID、证书、Profile 是否匹配
- build 号是否递增（检查 Xcode 目标 **Build**；上传前强制 +1）
- `ExportOptions.plist`（若使用命令行导出）的 `method/teamID/signingStyle` 是否符合目标

### D2. 密钥与凭据

- `.p8`、`.pem`、`backend.env` 不提交 Git
- GitHub Actions Secrets 是否齐全
- 本机私钥权限 `chmod 600`

### D3. 服务器配置

- `ECS_HOST/ECS_USER/ECS_KEY/ECS_PATH/ECS_SITE` 是否正确
- `backend.env` 中 `DASHSCOPE_API_KEY`、`MYSQL_*` 是否就绪
- Nginx `/api/` 反代与 SPA `try_files` 是否仍正确

## E. 失败时的优先排查

- iOS 上传失败：
  - 检查 build 号重复、Bundle ID 不一致、证书/Profile 不匹配、API Key 无权限
- GitHub Actions 归档失败（含 Sign in with Apple）：
  - 若日志提示 Runner 需要带 **Sign in with Apple** 的 profile：在 Apple Developer 为 App ID 开启能力并 **重新生成 App Store Profile**，更新 `IOS_APPSTORE_PROVISION_PROFILE_BASE64` / `IOS_APPSTORE_PROVISIONING_PROFILE_NAME` 后重跑
- GitHub Actions `PKCS12 import wrong password`：
  - 见 **B3** 的 legacy `.p12` 说明
- TestFlight 无构建：
  - 看 altool 输出、App Store Connect 处理状态、出口合规项
- ECS 发布后 5xx：
  - 先查 `systemctl status` 与服务日志，再查 `backend.env` 和数据库连通性
- 前端路由 404：
  - 检查 `guitar-server.conf` 的 `try_files $uri $uri/ /index.html;`

## F. 交付输出模板（执行后）

- 发布目标：
- 执行动作：
- 关键产物（IPA 路径 / Delivery UUID / commit / workflow run）：
- 验证结果（状态码、服务状态）：
- 风险与下一步：

## 参考文件

- iOS 上传记录（历史路径可能仍写 Flutter，需按 `swift_ios_host` 对照）：`docs/tiaoyinqi/testflight-upload.md`
- ECS 部署总文档：`deploy/ecs/README.md`
