# 练耳专项训练功能设计

## 需求概述

练耳 Tab 当前展示「自适应练耳」（4种题型混合自动出题），用户希望能进入针对单一题型（音程/和弦/进行/单音）的专项训练模式，训练结果计入同一个听力值评分系统。

## 当前状态

- **练耳 Tab**：展示 `PracticeHomeView` → `PracticeLandingView` → `AdaptiveEarTrainingView`
- **听力值系统**：`AdaptiveEarAbilityState`（包含 overallRating + 各题型子评分），存储在 `UserDefaultsAdaptiveEarTrainingStore`（本地 UserDefaults）
- **答题记录**：`AdaptiveEarAttemptRecord`，同样存于 UserDefaults
- **评分引擎**：`AdaptiveEarTrainingEngine`，ELO 风格算法，根据答题对错更新各维度的评分
- **问题生**器：`IntervalQuestionGenerator`（音程）、`EarChordMcqGenerator`（和弦）、`EarProgressionProceduralGenerator`（进行）、`makeSingleNoteQuestion`（单音）

## 设计

### 导航栏改造

- **当前**：`PracticeLandingView` 有日历按钮，`AdaptiveEarTrainingView` 有统计按钮
- **改后**：两个独立按钮移除，合并为一个 **Menu** 按钮置于 `AdaptiveEarTrainingView` 的 toolbar

```
导航栏右上角：
  [more ▼]
    ├─ 🎯 专项训练  →  NavigationLink 跳转到 FocusedEarHubView
    ├─ 📊 训练统计  →  Sheet 弹出 CombinedStatsView
    └─ 📅 练习日历  →  NavigationLink 跳转到 PracticeCalendarScreen
```

Menu 的 label 使用 `ellipsis.circle` 图标（或 `list.bullet`），不加文字。

### 专项训练首页（FocusedEarHubView）

展示4个题型卡片，每个卡片显示：
- 题型图标和名称
- 简短说明
- 该题型当前听力值评分
- 点击进入对应专项训练

布局为列表式卡片，从上到下排列。

### 专项训练会话页（FocusedEarTrainingSessionView）

- 与 `AdaptiveEarTrainingView` 的题型卡区域相似，但只出指定题型
- 训练过程中同一题型反复出现
- 每答题更新听力值
- 顶部展示当前听力值评分子项
- 无「自动切题型」逻辑，难度按该题型的评分自动调整
- 题型卡片中的「播放」、选项选择、反馈、下一题等交互与自适应页一致

### 数据流

```
FocusedEarTrainingSessionView
  └─ FocusedEarTrainingViewModel (fixedKind: AdaptiveEarQuestionKind)
       └─ AdaptiveEarTrainingEngine.stateAfterAnswer()
            └─ UserDefaultsAdaptiveEarTrainingStore (share with adaptive mode)
                 ├─ saveState()  → AdaptiveEarAbilityState
                 └─ appendAttempt()  → [AdaptiveEarAttemptRecord]
```

### 文件清单

**新建：**

| 文件 | 路径 | 职责 |
|------|------|------|
| `FocusedEarHubView.swift` | `swift_ios_host/Sources/Practice/Views/` | 专项训练首页，4题型入口 |
| `FocusedEarTrainingSessionView.swift` | 同上 | 单题型训练页 UI |
| `FocusedEarTrainingViewModel.swift` | 同上 | 单题型训练 ViewModel |

**修改：**

| 文件 | 改动 |
|------|------|
| `AdaptiveEarTrainingView.swift` | 替换 toolbar chart button → Menu（专项/统计/日历） |
| `PracticeLandingView.swift` | 移除 toolbar 日历 button |

### 核心逻辑细节

1. `FocusedEarTrainingViewModel` 持有 `AdaptiveEarTrainingStore`（与自适应模式同实例）
2. 初始化时传入 `fixedKind: AdaptiveEarQuestionKind`，每次出题强制用该 type，跳过 `selectNextKind()`
3. 难度仍使用 `AdaptiveEarTrainingEngine.difficulty(for:kind:state:)` 基于该题型的评分自动适配
4. `difficultyScore` 仍从 `AdaptiveEarTrainingEngine.difficultyScore(kind:difficulty:)` 获取
5. 答完题调用 `AdaptiveEarTrainingEngine.stateAfterAnswer()`，更新 same `AdaptiveEarAbilityState`
6. UI 复用自适应练耳的播放/选答案/反馈/下一题等组件模式
7. 顶部显示当前题型的评分卡片，显示该子项评分

### 未覆盖范围

- 视唱训练（SightSinging）不在本次范围内
- 不涉及后端 API 修改
- 不涉及数据库 schema 变更
- 不涉及 Swift Package（`swift_app/`）的新增 API
