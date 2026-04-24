# 玩乐吉他隐私政策页面（GitHub Pages）

最小文件结构：

- `index.html`（隐私政策网页，**同页英中两节**：`#doc-en` / `#doc-zh`）
- `support.html`（技术支持页，**同页英中两节**：`#doc-en` / `#doc-zh`；可填 App Store「技术支持网址」）
- `README.md`（本说明）

每页顶部有 **Jump / 跳转** 与到另一页对应语言锚的链接。App Store 仍可使用**无锚点**根 URL；若需直达某语言，可在路径后加 `#doc-en` 或 `#doc-zh`。

## 最省事发布方案

推荐新建一个公开仓库，例如：

- `wanle-guitar-privacy`

然后把这两个文件放到仓库根目录，直接用：

- **Branch**: `main`
- **Folder**: `/ (root)`

启用 GitHub Pages。

发布后 URL 通常为：

- `https://<你的GitHub用户名>.github.io/wanle-guitar-privacy/`

## App Store Connect 填写建议

- 隐私政策 URL：根目录，例如 `https://<用户>.github.io/wanle-guitar-privacy/`（可选 `.../index.html#doc-en` 或 `#doc-zh`）
- 技术支持 URL：`https://<用户>.github.io/wanle-guitar-privacy/support.html`（可选 `...#doc-en` / `#doc-zh`）
- 用户隐私选择 URL：如果暂时没有独立页面，可留空（按你当前策略）
