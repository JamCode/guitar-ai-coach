# Swift i18n (en + zh-Hans) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship full-app UI localization for **English** and **Simplified Chinese** by centralizing copy in a **String Catalog in the SwiftEarHost app bundle**, and loading strings from **`Bundle.main`** in `swift_ios_host` + `swift_app` at runtime, plus **`InfoPlist.strings`** for permission/display strings—per [2026-04-24-swift-i18n-design.md](../specs/2026-04-24-swift-i18n-design.md).

**Architecture:** One or more `*.xcstrings` files (same logical table `Localizable`) under **`swift_ios_host/Resources/Localization`**, **target membership = SwiftEarHost**; all user-facing `Text` / `Button` / `Label` / `String` / `alert` / navigation titles use keys whose **English translation** is the primary development string in the catalog, with **`zh-Hans`** providing Simplified Chinese. `INFOPLIST_KEY_*` 用户可见说明改为**英文为默认**或保留键名、由 `InfoPlist.strings` 在 **en** 与 **zh-Hans** 覆盖。`Package.swift` 已设 `defaultLocalization: "en"`，保持不动。

**Tech Stack:** Swift 5.10, String Catalog (`.xcstrings`), `String(localized:…)` / `LocalizedStringResource` / `Text(LocalizedStringResource(…))`, `Bundle.main`, `project.yml` + `xcodegen`, XCTest（现有用例不强制为每条 UI 加测）。

**Related spec:** [2026-04-24-swift-i18n-design.md](../specs/2026-04-24-swift-i18n-design.md)

---

## File structure (create or touch)

| Path | Action |
|------|--------|
| `swift_ios_host/Resources/Localization/Localizable.xcstrings` | Create (primary catalog; 可按域拆多文件，表名仍为 `Localizable`) |
| `swift_ios_host/Resources/Localization/en.lproj/InfoPlist.strings` | Create |
| `swift_ios_host/Resources/Localization/zh-Hans.lproj/InfoPlist.strings` | Create |
| `swift_ios_host/project.yml` | Modify：`developmentLanguage: en`（若未设）、`resources` 增加 Localization 目录 |
| `swift_ios_host/SwiftEarHost.xcodeproj/project.pbxproj` | 由 `xcodegen generate` 再生，或手工加资源引用后勿忘同步 yml |
| 全部含 UI 的 `swift_ios_host/Sources/**/*.swift` | 逐文件 key 化（见下表按任务分批） |
| `swift_app/Sources/**/*.swift`（各 Feature） | 同左 |
| `swift_app/Package.swift` | 仅当需改 `defaultLocalization` 或资源；当前 **`defaultLocalization: "en"` 已存在则不改** |

---

## Key naming 约定（全局执行）

- 使用 **小写 + 下划线** 或 **dot 分隔**，全局唯一，例如 `tab_practice`, `tuner_subtitle`, `transcription_import_from_photos`.
- **Catalog 中 `en` 行**：填自然英文；**`zh-Hans` 行**：填当前产品中文；勿把中文留在 Swift 源码里作唯一源。
- SwiftUI 推荐写法之一（等价即可，全仓统一）：

```swift
Text(LocalizedStringResource("tab_practice", bundle: .main))
// 或
String(localized: String.LocalizationValue("tab_practice"), bundle: .main, locale: nil)
```

- **禁止**在框架内对宿主文案用 `Bundle.module` 查找 `Localizable`；若 `grep` 发现 `String(localized:.*bundle: \\.module` 与主包文案混用，必须改为 `.main` 或移除。

---

## InfoPlist 策略（与 Task 1 同轮完成）

- 在 `project.yml` 的 `INFOPLIST_KEY_NSMicrophoneUsageDescription` / `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` / `INFOPLIST_KEY_CFBundleDisplayName` / `INFOPLIST_KEY_CFBundleName` 使用 **英语默认句**（与 en 用户看到的一致），与 design 不冲突。
- 在 **`en.lproj/InfoPlist.strings`** 中写出相同 key 的英文明示（与 plist 值一致或覆盖）。
- 在 **`zh-Hans.lproj/InfoPlist.strings`** 中写 **同键** 的中文（与当前产品中文说明一致，与 App 内反馈文案、spec 中诚实描述 align）。

Key 名与 `INFOPLIST_KEY_*` 在 plist 中生成的 key 一致，例如 `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`, `CFBundleDisplayName`, `CFBundleName`.

---

## inventory：宿主侧 Swift 文件（按目录分批，便于子任务）

`swift_ios_host/Sources/`

- `SwiftEarHostApp.swift`
- `Practice/Views/`：`PracticeLandingView.swift`, `PracticeTimerSessionView.swift`, `ScaleWarmupSessionView.swift`, `ChordQuickReferenceSheet.swift`, `TodayRecommendationListView.swift`, `ForegroundPracticeSessionTracker.swift`, `ChordPracticeSessionView.swift`, `ChordPracticeDiagramStrip.swift`, `PracticeFinishDialog.swift`, `RhythmStrummingView.swift`, `FlowLayout.swift`（仅处理用户可见字符串）
- `Transcription/Views/`：`TranscriptionHomeView.swift`, `TranscriptionProcessingView.swift`, `TranscriptionResultView.swift`, `TranscriptionHistoryView.swift`, `TranscriptionPlayerComponents.swift`
- `Sheets/Views/`：`SheetLibraryView.swift` 及同目录其它 Swift（若有）
- `Practice/Models/PracticeModels.swift` 等：仅当 `name`/`description` 对用户可见时 key 化（`kDefaultPracticeTasks` 等需进 Catalog 或 `String(localized:)`）

---

## inventory：`swift_app` 按 product（与 Package 对齐）

- `Sources/Core`：面向用户的错误/空状态若有则处理。
- `Sources/Features/Tuner`, `Fretboard`, `Chords`, `ChordChart`, `Profile`, `Ear`, `Practice` 下全部含 UI 的 Swift 文件；`Sources/App/ToolsHomeView.swift`（若未在 host 复用，mac 可执行体仍可能用到—仍应本地化以保包一致）。

---

### Task 1: 工程骨架 — Localization 目录、String Catalog、InfoPlist.strings、project.yml、xcodegen

**Files:**

- Create: `swift_ios_host/Resources/Localization/Localizable.xcstrings`（可先用空表或 1 条探针 key）
- Create: `swift_ios_host/Resources/Localization/en.lproj/InfoPlist.strings`
- Create: `swift_ios_host/Resources/Localization/zh-Hans.lproj/InfoPlist.strings`
- Modify: `swift_ios_host/project.yml`（`options.developmentLanguage: en`；`SwiftEarHost.resources` 增加 `Resources/Localization`；`INFOPLIST_KEY_*` 用户可见项改为英语默认）
- Regenerate: `swift_ios_host/SwiftEarHost.xcodeproj/project.pbxproj`（`xcodegen generate`）

- [ ] **Step 1: 在仓库中创建资源目录**（在 `swift_ios_host` 下）

```bash
mkdir -p swift_ios_host/Resources/Localization/en.lproj
mkdir -p swift_ios_host/Resources/Localization/zh-Hans.lproj
```

- [ ] **Step 2: 在 Xcode 中新建 String Catalog**（或复制最小有效 `Localizable.xcstrings` 模板后提交）

路径保存为：  
`swift_ios_host/Resources/Localization/Localizable.xcstrings`  
打开后在 Catalog 中新增 **探针** key（示例）：

| Key (source) | en | zh-Hans |
|--------------|----|---------|
| `build_probe` | Build probe | 构建探针 |

- [ ] **Step 3: 编写 `InfoPlist.strings`（en + zh-Hans）**  
  `en.lproj/InfoPlist.strings` 示例（键名以工程实际 `GENERATE_INFOPLIST_FILE` 产出为准，可用一次 Archive 后从 built Info 核对）：

```text
"CFBundleDisplayName" = "Wanle Guitar";
"CFBundleName" = "Wanle Guitar";
"NSMicrophoneUsageDescription" = "Wanle Guitar needs the microphone for tuning and some sound input exercises.";
"NSPhotoLibraryUsageDescription" = "Allow photo library access to import sheet music images or videos.";
```

`zh-Hans.lproj/InfoPlist.strings` 用当前中文产品名与权限句（与现有一致，例如 玩乐吉他 与 麦克风/相册说明）。

- [ ] **Step 4: 修改 `project.yml`**

  - 在 `options:` 下增加：`developmentLanguage: en`（与 XcodeGen 文档一致时生效）。
  - 在 `SwiftEarHost` → `resources:` 中增加对 `Resources/Localization` 的包含（`folder` 或明确列出 `Localizable.xcstrings` 与 `en.lproj`、`zh-Hans.lproj`）。
  - 将 `INFOPLIST_KEY_CFBundleDisplayName` / `CFBundleName` / `NSMicrophoneUsageDescription` / `NSPhotoLibraryUsageDescription` 改为 **与 `en` 展示一致** 的英语字符串（避免 en 与 plist 默认双源长期分叉）。

- [ ] **Step 5: 重新生成工程并编译**

```bash
cd swift_ios_host
xcodegen generate
xcodebuild -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build
```

**期望：** `BUILD SUCCEEDED`；无 missing resource。

- [ ] **Step 6: 在 `SwiftEarHostApp.swift` 中临时用探针**（可选，验证后删或改正式 key）

在 `body` 内某处加仅 Debug 的 `Text` 使用 `build_probe`（**勿提交长期 Debug UI 到发版**；若用探针，任务结束前移除）。

- [ ] **Step 7: Commit**

```bash
git add swift_ios_host/Resources/Localization swift_ios_host/project.yml swift_ios_host/SwiftEarHost.xcodeproj/project.pbxproj
# 若改动了 SwiftEarHostApp.swift 的探针，一并 add；探针已删则只交资源与 yml
git commit -m "feat(ios): add String Catalog, InfoPlist lproj, and en dev language wiring"
```

---

### Task 2: 宿主 `SwiftEarHostApp` — Tab、工具、关于、反馈、邮件主题

**Files:**

- Modify: `swift_ios_host/Sources/SwiftEarHostApp.swift`（`Label`/`Text`/`NavigationStack`/`alert`/`kPrivacy` 相关展示句；`makeFeedbackMailURL` 的 subject/body 模板）

- [ ] **Step 1:** 列出文件内所有用户可见 `String`（含 `subject` / `body` 模板、tab 标题、工具区 section 标题、`alert` 文案）。  
- [ ] **Step 2:** 为每条分配 **唯一 key**，写入 `Localizable.xcstrings` 的 en + zh-Hans。  
- [ ] **Step 3:** 用 `LocalizedStringResource` 或 `String(localized:…, bundle: .main)` 替换字面量。  
- [ ] **Step 4:** 构建

```bash
cd swift_ios_host && xcodebuild -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build
```

**期望：** `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit** `git commit -m "feat(ios): localize SwiftEarHostApp shell (tabs, tools, support)"`

---

### Task 3: 宿主 `Practice/Views` 全量

**Files（逐一处理，可并行多人但合并注意冲突）：**

- `swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift`
- 同目录：`PracticeTimerSessionView.swift`, `ScaleWarmupSessionView.swift`, `ChordQuickReferenceSheet.swift`, `TodayRecommendationListView.swift`, `ForegroundPracticeSessionTracker.swift`, `ChordPracticeSessionView.swift`, `ChordPracticeDiagramStrip.swift`, `PracticeFinishDialog.swift`, `RhythmStrummingView.swift`, `FlowLayout.swift`（仅 UI 文案部分）

- [ ] **Step 1:** 对每文件 `grep` 中文或用户可见英语  
  `rg '[\u4e00-\u9fff]' swift_ios_host/Sources/Practice/Views`  
- [ ] **Step 2–3:** 同 Task 2：key → catalog → 替换。  
- [ ] **Step 4:** 处理 `PracticeModels` / 任务常量在 **同一 PR 内** 一并 key 化（`kDefaultPracticeTasks` 等显示给用户的 `name`/`description` 来自 localization，避免运行时语言切换仍显示中文常量）。**实现方式：** 保持 `id` 为稳定 id；展示名用 `String(localized: "task_\(id)_name", bundle: .main)` 或在 `PracticeTask` 中改为**仅 id**，展示层查表。在计划中统一一种，避免二义。  
- [ ] **Step 5: Build**（同上 `xcodebuild`）。  
- [ ] **Step 6: Commit** `feat(ios): localize host Practice module UI`

---

### Task 4: 宿主 `Transcription` 与 `Sheets`

**Files:**

- `swift_ios_host/Sources/Transcription/Views/*.swift`
- `swift_ios_host/Sources/Sheets/Views/SheetLibraryView.swift` 等

- [ ] 同 Task 2 流程；注意 **文件格式/时长说明** 等长句用 **单 key + format 参数**（如 `transcription_file_limit_format %lld` 英/中语序在 Catalog 中调）。  
- [ ] **Commit** `feat(ios): localize Transcription and Sheets`

---

### Task 5: `swift_app` — `Tuner` + `Fretboard` + `Chords` + `ChordChart` + `Profile`

**Files:** `swift_app/Sources/Features/Tuner/**/*.swift`（及 Fretboard, Chords, ChordChart, Profile 下全部 UI）

- [ ] 每子目录一轮：`swift build` 或经 host `xcodebuild`（**推荐**仍用 `xcodebuild` 编宿主以验证主包内字符串解析）：

```bash
cd /path/to/guitar-ai-coach/swift_ios_host
xcodebuild -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build
```

- [ ] **Commit** 可按 target 分两次避免单次过大：  
  `feat(ios): localize Tuner, Fretboard` / `feat(ios): localize Chords, ChordChart, Profile`

---

### Task 6: `swift_app` — `Ear`

**Files:** `swift_app/Sources/Features/Ear/**/*.swift`（含 `Resources` 中 JSON 内若有面向用户且从 bundle 读出的默认文案；若仅为数据种子且非展示可跳过）

- [ ] 大模块单独 branch 或单 PR 内多 commit；**构建验证** 同上。  
- [ ] **Commit** `feat(ios): localize Ear module`

---

### Task 7: `swift_app` — `Practice` + `App/ToolsHomeView`

**Files:**

- `swift_app/Sources/Features/Practice/**/*.swift`
- `swift_app/Sources/App/ToolsHomeView.swift`

- [ ] 与 host 已存在的「练习」文案 **key 命名对齐**或共享 key（**同一 `tab_practice` 只定义一次**）。  
- [ ] **Commit** `feat(ios): localize Practice package and App tools list`

---

### Task 8: 仓库级扫尾与门禁

- [ ] **Step 1: 全仓扫描** 用户可见中文字面量（允许注释、文档、spec 中的中文）

```bash
cd /path/to/guitar-ai-coach
rg '[\u4e00-\u9fff]' --glob '*.swift' swift_ios_host/Sources swift_app/Sources
```

**期望：** 无命中于 **会编译进产物的** UI 路径；**允许** 注释 `//` 中文、**测试里** 若需保留中文，应用 `#if DEBUG` 或测 mock，避免 App Store 产物含硬编码中字串。  
若仍有命中：回到对应任务补 key。

- [ ] **Step 2: 单元测试**（不强制全量，但**不得**因改文案大面积碎测）

```bash
cd swift_ios_host && xcodebuild test -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

**期望：** 与改前一致或仅有已知的、与 `Bundle.main` 无关的用例可修。

- [ ] **Step 3: 手动双语言**（见 spec §7）  
  模拟器 **Settings → General → Language** 切 **English** 与 **简体中文** 各走练习/我的谱/扒歌/工具、打开关于/隐私/反馈。

- [ ] **Step 4: 文档**  
  在 `README` 或 `swift_ios_host/README` 增加 **一段**：新增文案须更新 `Localizable.xcstrings` 与 en/zh-Hans、勿在 Swift 中写死面向用户的中文字面量。  
- [ ] **Step 5: Commit** `chore(ios): i18n sweep, tests, and contributor note`

---

## 回归命令速查

```bash
cd swift_ios_host
xcodegen generate   # 若 yml 有变
xcodebuild -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' test
```

（Simulator 名称随本机安装替换。）

---

## 注意事项（执行时必读）

- **Xcode 版本**：String Catalog 需与团队 Xcode 版本一致；**勿手改** `project.pbxproj` 中 UUID 段若不理解，优先 **yml + xcodegen**。  
- **发版前** 删除任何 **探针** `Text` 或 **Debug 仅中文** 的临时 UI。  
- **不** 在本计划中修改 Flutter 或后端；与 spec 一致。

---

**计划自检：** 无 `TBD` 占位；任务与 spec 范围 **A 全量 + B 双语** 对齐；`Bundle.main` 与 `InfoPlist.strings` 已覆盖；测试策略与 spec 第 7 节一致。
