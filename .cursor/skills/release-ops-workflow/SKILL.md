---
name: release-ops-workflow
description: 统一处理发布运维任务：Flutter iOS 本机或 GitHub Actions 打包并上传 TestFlight、ECS 前后端部署、环境变量与密钥配置管理、发布前后检查与回滚建议。用户提到“打包”“TestFlight”“GitHub Actions”“CI”“上线”“部署”“配置管理”“环境变量”“发布流程”时启用。
---

# 发布与运维工作流（iOS + ECS + 配置管理）

## 适用范围

- iOS：`flutter_app` 的本机打包、IPA 产出、上传 TestFlight（本机命令或 CI）。
- 后端/前端：ECS 上的 Python 后端 + Nginx 静态站点发布。
- 配置管理：Team/Bundle ID、App Store Connect API Key、后端 `backend.env`、ECS SSH 参数与发布检查项。

## 关键原则

1. **先确认目标环境**：本机测试、TestFlight、还是 ECS 线上。
2. **密钥不入库**：`.p8`、`.pem`、`backend.env` 实值、token 只放本机安全路径或 CI Secret。
3. **发布有检查点**：发布前检查 + 发布后冒烟 + 可回滚路径。
4. **命令优先可复现**：优先执行仓库已有文档中的标准命令，不临时发明流程。

## 单次任务执行顺序

1. 明确本次目标（仅打包 / 打包+上传 / 前后端部署 / 全链路发布）。
2. 检查版本与配置（iOS build 号、Bundle ID、Team ID、ECS 环境变量）。
3. 执行发布动作（按下方子流程）。
4. 采集结果（关键输出、Delivery UUID、服务状态、HTTP 冒烟码）。
5. 形成交付记录（做了什么、结果、下一步）。

## A. iOS 本机打包与 TestFlight 上传

### A1. 打包前检查

- Bundle ID 与 App Store Connect 一致（当前项目默认：`com.wanghan.guitarhelper`）。
- Xcode `Signing & Capabilities` 使用正确 Team，自动签名无红字。
- `pubspec.yaml` 的 build 号递增（`version: x.y.z+build` 的 `build` 必须大于上一次上传值）。

### A1.1 build 号递增规则（强制）

每次准备上传 TestFlight 前，必须先执行以下动作：

1. 打开 `flutter_app/pubspec.yaml`
2. 将 `version: x.y.z+build` 的 `build` 至少加 1
3. 保存后再执行 `flutter build ipa`

示例：

- 上一次上传是 `1.0.0+1`
- 本次至少改为 `1.0.0+2`

若忘记递增，上传阶段会被 App Store Connect 拒绝（构建号重复）。

### A2. 构建 IPA（本机）

```bash
cd flutter_app
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --export-options-plist=ios/ExportOptions.plist
```

### A3. 命令行上传 TestFlight（altool）

前置：

- 本机有 `AuthKey_<KEY_ID>.p8`（当前约定放在 `~/Documents/certs/`）
- `KEY_ID`、`ISSUER_ID` 已确认
- IPA 文件存在于 `flutter_app/build/ios/ipa/*.ipa`

路径约定：

- API key 默认源文件：`~/Documents/certs/AuthKey_<KEY_ID>.p8`
- altool 读取目录：`~/.private_keys/AuthKey_<KEY_ID>.p8`
- 禁止将 `.p8` 放在仓库目录（如 `flutter_app/ios/`）或提交 Git

```bash
mkdir -p "$HOME/.private_keys"
cp "$HOME/Documents/certs/AuthKey_<KEY_ID>.p8" "$HOME/.private_keys/AuthKey_<KEY_ID>.p8"
chmod 600 "$HOME/.private_keys/AuthKey_<KEY_ID>.p8"

xcrun altool --upload-app --type ios \
  -f "/abs/path/to/flutter_app/build/ios/ipa/<your>.ipa" \
  --apiKey "<KEY_ID>" \
  --apiIssuer "<ISSUER_ID>"
```

### A4. 上传后检查

- 记录 `UPLOAD SUCCEEDED` 与 `Delivery UUID`。
- 到 App Store Connect -> TestFlight 等待构建处理完成。

## B. iOS CI 上传 TestFlight（GitHub Actions）

- 工作流文件：`.github/workflows/flutter-ios-testflight.yml`
- 作用：在 macOS Runner 上导入证书与描述文件 → 生成 App Store 类型 IPA → `xcrun altool` 上传到 App Store Connect（供 TestFlight）。

### B0. 什么时候会跑（重要）

- **默认不会**在每次 `git push` 时自动打包上传。
- 工作流 `on` 以 **`workflow_dispatch`** 为主时：**只有**在 GitHub 网页「Actions」里手动 Run，或用 `gh workflow run` 触发，才会执行。
- 若日后在 YAML 中增加 `push` / `tag` 等触发器，才会在对应事件自动跑；届时必须配套 **build 号自动递增** 或发布分支纪律，否则易因「构建号重复」失败。

### B1. 如何触发（本机 CLI）

```bash
cd /path/to/guitar-ai-coach
gh workflow run "Flutter iOS TestFlight" --ref <分支名>
gh run list --workflow "Flutter iOS TestFlight" --limit 3
```

### B2. CI 内大致步骤（便于排错）

1. 从 Secrets 还原 `.p12` 与 `.mobileprovision` 到临时钥匙串与 `~/Library/MobileDevice/Provisioning Profiles`。
2. 生成 `ios/ExportOptions-ci-appstore.plist`（`method=app-store`、`signingStyle=manual`、Bundle ID → Profile Name）。
3. `flutter build ios --release --no-codesign`
4. `xcodebuild archive` + `xcodebuild -exportArchive`（避免在命令行全局强加 `PROVISIONING_PROFILE_SPECIFIER` 到 Pods 子目标）。
5. `xcrun altool --upload-app`（依赖 `APP_STORE_CONNECT_*` 与 `~/.private_keys/AuthKey_*.p8`）。

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

- 先递增 `flutter_app/pubspec.yaml` 的 `+build`，**commit 并 push** 到将要触发的分支，再 Run workflow；否则上传易被拒。

### B6. 可选：改为 push 自动上 TestFlight

仅在用户明确要求且接受 Runner 分钟数与失败噪声时改 YAML，例如：

```yaml
on:
  workflow_dispatch:
  push:
    branches: [ main ]
    paths:
      - 'flutter_app/**'
      - '.github/workflows/flutter-ios-testflight.yml'
```

同时需约定：**每次可上传的提交都必须唯一 build 号**（脚本 bump 或发布分支只合并可发布 commit）。

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
- build 号是否递增（检查 `flutter_app/pubspec.yaml` 的 `version`；上传前强制 +1）
- `ios/ExportOptions.plist` 的 `method/teamID/signingStyle` 是否符合目标

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

- iOS 上传记录：`docs/tiaoyinqi/testflight-upload.md`
- iOS CI（ad-hoc）：`.github/workflows/flutter-ios-build.yml`
- iOS CI（TestFlight）：`.github/workflows/flutter-ios-testflight.yml`
- ECS 部署总文档：`deploy/ecs/README.md`
