# Flutter 吉他助手 · 一期骨架需求

> 对照个人思考稿 `requirements/我的几个需求的思考.m'd` 与实施计划，锁定**一期可验收范围**与**明确不做项**。  
> 实现代码位于 `flutter_app/lib/`。

## 1. 一期骨架（In Scope）

| 方向 | 交付内容 |
|------|----------|
| 小工具 | 底部 Tab「工具」：调音器、和弦查询、初级乐理、和弦表（静态页）。和弦查询为分步下拉 + 变调预览 + `POST /chords/explain-multi`，按法以文本/品格行展示。 |
| 练耳 | Tab「练耳」：已实现「音程识别」入口；A/B/C（单和弦、进行、错题与每日复习）为占位说明，指向 `练耳训练一期-ABC-需求.md` 与 `练耳题库-一期种子.json`。 |
| 练习 | Tab「练习」：单一占位页，说明后续和弦切换/单音跟弹等。 |
| 我的谱 | Tab「我的谱」：`file_picker` 选文件 → 复制到应用文档目录 → 列表展示；左滑或按钮删除；点开为「预览开发中」对话框。 |
| 配置 | AppBar「API 设置」：持久化 API 基址（与 Web `VITE_API_BASE_URL` 同语义）。支持编译期 `--dart-define=GUITAR_API_BASE_URL=...` 作为未保存时的默认值。 |

## 2. 明确不做（Out of Scope · 本期）

- 和弦按法试听、Canvas 指板图与 Web 完全一致的视觉还原。  
- 练耳一期 ABC 题库接入、错题本、变速播放。  
- 练习模块的交互引擎、节拍器、跟弹判分。  
- 谱子 PDF/图片内嵌预览、云同步、标注。  
- 尤克里里 / 非标准调弦（与 Web 和弦字典 backlog 一致）。

## 3. 配置说明

1. **应用内**：任意 Tab → 右上角设置 → 填写基址，例如 `https://你的域名/api`（无末尾 `/`）。  
2. **编译期**：`flutter run --dart-define=GUITAR_API_BASE_URL=https://你的域名/api`  
3. **接口**：和弦查询使用 `POST {基址}/chords/transpose`（变调预览）与 `POST {基址}/chords/explain-multi`（多套按法）。服务端需可用（如配置 `DASHSCOPE_API_KEY` 等），否则界面展示可读错误信息。

## 4. 验收清单

- [ ] 底部四个 Tab 可切换，标题与内容一致。  
- [ ] 工具 → 调音器、和弦查询、乐理、和弦表均可进入并返回。  
- [ ] 配置有效基址后，和弦查询能拉取并展示至少一条按法（依赖后端）。  
- [ ] 练耳 → 音程识别流程可完成答题。  
- [ ] 我的谱 → 导入至少一个文件后列表可见，可删除。  

## 5. 测试命令

```bash
cd flutter_app
flutter pub get
dart analyze
flutter test
flutter test integration_test/app_test.dart
```

## 6. 平台说明

- Android 已声明 `INTERNET` 权限。  
- iOS 麦克风说明沿用现有 `Info.plist`；谱子选择依赖系统文档选择器。
