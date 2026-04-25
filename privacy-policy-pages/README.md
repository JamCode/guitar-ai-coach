# 玩乐吉他隐私政策页面（GitHub Pages）

最小文件结构：

- `index.html`（隐私政策网页，**同页英中两节**：`#doc-en` / `#doc-zh`）
- `support.html`（技术支持页，**同页英中两节**：`#doc-en` / `#doc-zh`；可填 App Store「技术支持网址」）
- `README.md`（本说明）

每页顶部有 **Jump / 跳转** 与到另一页对应语言锚的链接。App Store 仍可使用**无锚点**根 URL；若需直达某语言，可在路径后加 `#doc-en` 或 `#doc-zh`。

## 线上地址（与 App 内一致）

公开站点使用**独立仓库** `JamCode/wanle-guitar-privacy` 的 GitHub Pages，例如：

- `https://jamcode.github.io/wanle-guitar-privacy/`

（与 `swift_ios_host` 里 `kPrivacyPolicyURLString` 一致。）

## 从本 monorepo 自动同步（推荐）

本仓库工作流 **`.github/workflows/privacy-github-pages.yml`** 在变更 `privacy-policy-pages/**` 并推送到 `main` / `master` / `cursor/swift-tools-tab-migration` 时，会把 `index.html`、`support.html`（及 `README.md`）**推送进** `JamCode/wanle-guitar-privacy` 的默认分支，从而更新上列 Pages。

1. 在 **GitHub → `JamCode/guitar-ai-coach` → Settings → Secrets and variables → Actions** 中新建 **Repository secret**：
   - 名称：`WANLE_GUITAR_PRIVACY_DEPLOY_TOKEN`
   - 值：对 **`JamCode/wanle-guitar-privacy`** 拥有 **Contents: Read and write** 的 [Personal access token (classic)](https://github.com/settings/tokens) 或 *fine-grained* PAT（仅授权该仓即可）。
2. 在 **目标仓 `JamCode/wanle-guitar-privacy` → Settings → Pages**：
   - **Source**：**Deploy from a branch**
   - **Branch**：`main`，目录 **`/(root)`**（若你默认分支是 `master`，请把该仓默认分支切到 `main` 或改工作流里的 `HEAD:main` 为目标分支名）。
3. 推送本仓库含 `privacy-policy-pages` 的提交，或在本仓库 **Actions** 里手动运行 **Sync privacy pages to wanle-guitar-privacy**。

若工作流在 `actions/checkout` 时提示 404/权限错误，请检查 PAT 是否包含目标仓、或目标仓名/组织名是否与工作流中 `repository: JamCode/wanle-guitar-privacy` 一致。

## 仅手动发布（不跑 CI）

在 GitHub 新建公开仓库 `wanle-guitar-privacy`，将 `index.html`、`support.html` 放在**仓库根目录**，Pages 用 **main + /(root)** 即可。与 App 填写的 URL 同结构。

## App Store Connect 填写建议

- 隐私政策 URL：`https://jamcode.github.io/wanle-guitar-privacy/`（可选 `...#doc-zh` 等）
- 技术支持 URL：`https://jamcode.github.io/wanle-guitar-privacy/support.html`（可选 `...#doc-en` / `#doc-zh`）
- 用户隐私选择 URL：如暂无独立页面可留空（按你当前策略）
