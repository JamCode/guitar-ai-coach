# Swift 工程国际化（i18n）设计说明

- **状态**：已评审（自洽检查通过）
- **目标发行**：第一期全量简中 + 英语；与 brainstorming 中选定方案 **①**（主 App 集中 String Catalog + `Bundle.main`）一致
- **范围**：`swift_ios_host` 与 `swift_app` 内全部**用户可见**界面文案、系统向用户展示的 **Info 字段**、（可选）**本地化应用显示名**

---

## 1. 目标与成功标准

- 用户在 iOS 系统语言为 **English** 或 **中文（简体）** 时，应用界面与系统权限等说明与所选语言一致；其他系统语言时按 Apple 标准在**已提供语言**间回退，不出现空白或错误 key 裸露。
- **第一期（本 spec）** 不新增第三种语言；后续若扩展，应沿用同一 key 与目录结构。
- 上架与审核角度：商店元数据、App 内功能描述一致；`Info` 中权限用途与各语言下展示文案含义一致（不要求逐字直译，但须诚实、不缩小范围）。

---

## 2. 范围

### 2.1 必做

- 所有在运行时展示给**终端用户**的字符串：SwiftUI / UIKit 界面、`Alert`、`confirmationDialog`、`TextField` 的 placeholder、导航标题、空状态、错误提示、**工具类里拼出的用户可见句子**等。
- **Info 用户可见项**：`NSMicrophoneUsageDescription`、`NSPhotoLibraryUsageDescription` 等当前及未来在 plist 中向用户说明用途的键；随工程增减同步维护多语言 `InfoPlist.strings`。
- **开发工程配置**：Xcode 工程与（若使用）`project.yml` 中 `knownRegions` / 本地化能力与本 spec 一致，避免 `xcodegen` 或脚本覆盖后丢引用（需在实现阶段显式记录「须保留项」）。

### 2.2 不纳入本 spec

- **Flutter** 子工程、非本 Swift 产物的文案。
- **服务器/远程配置** 返回的富文本（当前若不存在则略）。
- 用户内容本身：如用户命名的谱册名、从文件系统来的文件名，**默认不随界面语言机翻**；仅包装句本地化（如「已保存：%@」中「已保存」本地化，`%@` 为原样文件名）。

---

## 3. 非功能需求

- **可维护性**：同一条文案在一个逻辑位置定义翻译，避免在多个 `.strings` 中重复同义变体（允许按模块拆多份 String Catalog 文件，但 key 命名全局唯一、有前缀或命名空间）。
- **可测试性**：主路径在 **真机或模拟器** 上切换系统语言**抽样**通过；对依赖 `Bundle.main` 的模块单元测试，在 spec 中明确「脱离宿主时的策略」（见第 7 节）。
- **与现有发版流兼容**：不改变现有 Bundle ID、签名与上架流程；ONNX/资源体积不因本地化显著膨胀。

---

## 4. 架构决策

### 4.1 单宿主 String Catalog + `Bundle.main`

- 在 **SwiftEarHost** 目标下维护 **String Catalog**（`*.xcstrings`）。可按业务域拆成多文件（如 `Localizable+Practice.xcstrings`），**均加入同一 App target**，编译后处于**应用主包**中。
- `swift_app` 各包内 UI 代码使用 **`String(localized: "key", table: "Localizable", bundle: .main, …)`** 或等价 API，保证运行时从**宿主 App 包**取翻译。同一进程内动态框架中 **`Bundle.main` 为应用程序主包**，与框架资源分离时的常见模式一致；若某处误用 `Bundle.module` 会读不到主包翻译，**实现阶段用 grep 与审查约束**。

### 4.2 Key 与源语言

- 代码中 **使用英文为 key 语义**（`snake_case` 或 `dot.notation` 风格统一即可），`xcstrings` 中 **en** 与 **zh-Hans** 各填一条翻译；**禁止**在 Swift 源码中长期保留大段中文字面量作为唯一来源。
- **开发区域（development region）** 在 Xcode 中设为 **English (`en`)**，这样缺失某语言时回退到英文，符合国际常见习惯，且与 key 为英文一致。

### 4.3 可选：类型安全封装

- 在 `Core` 或 `swift_ios_host` 中增加 **薄层** `enum` / `struct`（如 `L10n`）集中持 `String.LocalizationValue` 或静态方法，**减少字符串散落**；**非强制**，若工期紧可先 `String(localized:)` 直接调用，再迭代封装。

### 4.4 Info 与显示名

- 权限说明、**若需要多语言应用图标下名称**的 `CFBundleDisplayName`：在 **`en.lproj/InfoPlist.strings`** 与 **`zh-Hans.lproj/InfoPlist.strings`** 中写与 Info 中键名一致的项；值随语言变化。
- 主 Info 仍可通过 **生成 Info**（`INFOPLIST_KEY_*`）维护非本地化键；**用户可见的说明句以 `InfoPlist.strings` 覆盖语言为准**（与苹果文档一致）。

---

## 5. 文件与工程布局（建议）

- `swift_ios_host/Resources/Localization/`（或同等级目录）：
  - `Localizable.xcstrings` 或分片 `*.xcstrings`（**Target Membership**：SwiftEarHost）
  - `en.lproj/InfoPlist.strings`
  - `zh-Hans.lproj/InfoPlist.strings`
- 不在每个 SwiftPM 包中复制整套翻译文件（**除非**后续为可独立发布的包单独发版，再评估拆分）。

---

## 6. 实现约定

- **复数、变体**：需复数时优先使用 **String Catalog 的复数/变体** 能力，避免手工拼复数词尾。
- **插值**：`String(localized: "key \(value)")` 在 Swift 5+ 与 Catalog 配合时注意 **可本地化插槽** 规范；长句拆 key，避免多段无序号拼接（利于翻译语序调整）。
- **一致性**：同义词（如「练习」「练耳」在导航与正文）使用同一 key 或同一条翻译策略，在评审清单中可抽查。

---

## 7. 测试与验收

- **手动**：系统语言 **English** 与 **简体中文** 下各走通「练习 / 我的谱 / 扒歌 / 工具」主路径、触发一次**权限**相关页面（或设置中查看描述）、**关于/反馈/隐私** 外链入口文案。
- **自动化**：不强制为每条字符串加快照测试；若包内单测因 `Bundle.main` 在测试进程中与真机不一致失败，**允许**对纯逻辑测试剥离文案，或对本地化相关测试放到 **host 的 UITest/手动清单**。

---

## 8. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 漏提字符串 | 分模块 grep 中文/硬编码，提交前 checklist |
| 误用 `Bundle.module` 导致不显示翻译 | 代码规范 + 审查 + 双语言实机看屏 |
| `project.yml` 重生成丢资源 | 在 `project.yml` 或团队文档中登记 localization 块；合并前 diff |
| 动态拼接产生语序问题 | 使用带位置的 format，避免多段无序号拼接 |

---

## 9. 与实现计划的衔接

- 实现阶段应拆为：**工程与目录搭建 → 提取字符串与 key 化 → 填英/简中翻译 → InfoPlist.strings → 全量手测**。
- 下一文档：`writing-plans` 产出的**实现计划**（按文件/模块分任务、估计顺序）。

---

## 10. 自备检查（自洽）

- 无未填占位；范围与用户确认的 **A + B** 一致；架构单一路径，无互相矛盾；未承诺 Flutter 与服务器文案。

---

## 11. 审批

- 产品/作者：**已同意**（用户于对话中确认「同意，出 spec」）
- 实现前须再经 **实现计划** 评审后开工。
