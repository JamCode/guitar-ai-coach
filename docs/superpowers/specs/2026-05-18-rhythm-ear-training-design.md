# 节奏听写训练设计

## 概述

在练耳模块中新增「节奏听写」题型。用户听到一小段节奏的击打声（唱作），从四个文字标记选项中选择正确的节奏型。同时加入自适应练耳流程（作为第 5 种题型）和专项训练入口。

## 数据模型

### RhythmPattern

核心数据结构：`8` 位 16 分/ 8 分位数组，每位表示该时间点是否有击发声。目前固定 4/4 拍一小节，颗粒度为八分音符（8 个八分位）。

```
[1, 0, 1, 0, 1, 0, 1, 0]  // 四个四分音符
[1, 0, 0, 0, 1, 0, 1, 1]  // 附点二分 + 八分 + 八分
```

**文字展示规则**（用于 UI 选项卡片）：

将 8 个八分位每 2 个一组（共 4 组），每组映射为：

| 八分位组 | 显示文字 | 含义 |
|---|---|---|
| `[1,1]` | `X` | 一个四分 |
| `[1,0]` | `X·` | 附点八分 + 十六分休止（简化显示） |
| `[0,1]` | `·X` | 十六分休止 + 八分 |
| `[0,0]` | `.` | 一个四分休止 |

4 组之间以空格分隔。

示例：
- `[1,0,1,0,1,0,1,0]` → `X X X X`
- `[1,1,1,0,1,0,0,0]` → `XX X· X .` （两个八分 + 附点八分 + X + 休止）

### Swift 表示

```swift
struct RhythmPattern: Equatable, Codable {
    /// 8 个八分位 (0 或 1), 表示一小节
    let grid: [Int]
    
    /// 文字展示（用于选项）
    var displayText: String { ... }
    
    /// 实际用于播放的击打序列
    var hits: [Bool] { grid.map { $0 == 1 } }
}
```

### MCQ 题目模型

直接沿用 `AdaptiveEarQuestion` 枚举，新增一个 case：

```swift
enum AdaptiveEarQuestion: Identifiable {
    case interval(...)
    case chord(...)
    case progression(...)
    case singleNote(...)
    case rhythm(RhythmPattern, choices: [RhythmPattern], difficulty: AdaptiveEarDifficulty, difficultyScore: Int)
}
```

其中 `rhythm` 的 `prompt` 固定为「听节奏，选出正确的节奏型」，选项展示用 `choices.map(\.displayText)`。

## 出题引擎

### RhythmQuestionGenerator

独立的 struct，自适应和专项训练都通过它出题。

```swift
struct RhythmQuestionGenerator {
    /// 生成一道题（正确节奏 + 3 个干扰项 + 4 个选项打乱顺序）
    static func makeQuestion(difficulty: RhythmDifficulty, using rng: inout some RandomNumberGenerator) -> (correct: RhythmPattern, choices: [RhythmPattern])
    
    /// 指定难度下可用的节奏池
    static func pool(for difficulty: RhythmDifficulty) -> [[Int]]
}
```

### 难度分级

| 级别 | 节奏元素 | 初级池举例 |
|---|---|---|
| 初级 (beginner) | 四分 + 八分，无休止 | `X X X X`, `XX XX XX XX`, `X X XX XX`, `XX X X XX` |
| 中级 (intermediate) | 加入休止符 `.` 和附点 `X·` | `X X · X X`, `X· X X X`, `X X X· X`, `X· X· X X` |
| 高级 (advanced) | 加入切分、复杂组合 | `X· XX · X`, `XX ·X X· X`, `·X X· X· X` |

各级至少内置 8~12 个基础节奏型，出题时随机选一个作为正确答案。

### 干扰项生成

对正确节奏型做有限变换生成 3 个干扰项：

1. **单位移位**：随机把一个位置从 `1` 变 `0` 或 `0` 变 `1`
2. **两位置换**：交换两个相邻八分位的值
3. **混合变形**：同时做两种变换

所有干扰项必须与正确答案不同，且彼此不同。最多尝试 20 次。

### 与自适应难度映射

```swift
extension AdaptiveEarDifficulty {
    var rhythmDifficulty: RhythmDifficulty {
        switch self {
        case .beginner: return .beginner
        case .intermediate: return .intermediate
        case .advanced: return .advanced
        }
    }
}

extension AdaptiveEarTrainingEngine {
    static func difficultyScore(kind: AdaptiveEarQuestionKind, difficulty: AdaptiveEarDifficulty) -> Int {
        switch (kind, difficulty) {
        // ... 现有 cases ...
        case (.rhythm, .beginner): return 320
        case (.rhythm, .intermediate): return 490
        case (.rhythm, .advanced): return 650
        }
    }
}
```

## 音频播放

复用 `MetronomeEngine` 的 click 音合成。但为节奏训练场景，不启动引擎 timer，而是手动调度：

1. 设定 BPM = 90（适中速度，每拍约 0.667s）
2. 预计算每个八分位的时间间隔：`60.0 / 90.0 / 2.0 = 0.333s`
3. 遍历 8 个八分位：
   - 若 `grid[i] == 1`：
     - 第 1 拍起始（i=0）→ 用 accent 音色（1200Hz，略长/强拍）
     - 第 3 拍起始（i=4）→ 也用 accent 音色（4/4 拍的次强拍）
     - 其余 → 用 normal 音色（880Hz，略短）
   - 若 `grid[i] == 0` → 静音等待一个八分位时长
4. 播放完成后回调，标记「已完整试听」

**播放实现**：使用 `AVAudioEngine` + `AVAudioPlayerNode` 直接合成并调度 buffer，不依赖 MetronomeEngine 的 timer 驱动，避免干扰正在运行的节拍器。

关键代码示意：

```swift
/// 为指定节奏生成并调度所有 click buffer
func scheduleRhythm(_ pattern: RhythmPattern, bpm: Int, player: AVAudioPlayerNode, engine: AVAudioEngine) {
    let eighthInterval = 60.0 / Double(bpm) / 2.0  // 八分位间隔（秒）
    let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    
    for (i, hit) in pattern.hits.enumerated() where hit {
        let accent: Bool
        switch i {
        case 0: accent = true       // 强拍
        case 4: accent = true       // 第三拍（次强，也做 accent）
        default: accent = false
        }
        let buffer = makeClickBuffer(format: format, accent: accent)
        let startTime = Double(i) * eighthInterval
        player.scheduleBuffer(buffer, at: ...) // 使用 AVAudioTime
    }
    player.play()
}
```

## UI 设计

### 选项卡片

布局沿袭现有 2×2 网格，每张卡片显示一个 `RhythmPattern.displayText`。

- 字体用等宽字体 `.monospaced()`，字号足够大（headline 或 title3）
- 选项间通过「X」「·」区分明显
- 选中/正确/错误颜色与现有统一

### 提示功能

「逐拍试听」按钮（类似和弦的试听提示），点击后逐个四分位播放 tick：
- 四分位 1 至 4，每播一个停顿一会儿，帮助用户拆解

### 专项训练入口

`FocusedEarHubView` 新增卡片：

```swift
typeCard(
    kind: .rhythm,
    icon: "metronome",
    color: Color(red: 0.85, green: 0.35, blue: 0.75),  // 紫色
    description: "4/4 拍一小节，听节奏选谱例"
)
```

## 自适应集成

### AdaptiveEarQuestionKind 扩展

```swift
enum AdaptiveEarQuestionKind: String, CaseIterable, Codable, Equatable {
    case interval
    case chord
    case progression
    case singleNote
    case rhythm
    
    var title: String {
        switch self {
        case .rhythm: return "节奏听写"
        // ... existing ...
        }
    }
    
    var shortTitle: String {
        case .rhythm: return "节奏"
    }
}
```

### AdaptiveEarAbilityState 扩展

```swift
struct AdaptiveEarAbilityState: Codable, Equatable {
    var overallEarRating: Double
    var intervalRating: Double
    var chordRating: Double
    var progressionRating: Double
    var singleNoteRating: Double
    var rhythmRating: Double    // 新增

    static let initial = AdaptiveEarAbilityState(
        // ...
        rhythmRating: 400       // 初始 400
    )
}
```

`rating(for:)` 和 `setRating(_:for:)` 增加 `.rhythm` 分支。

### makeQuestion 扩展

在 `AdaptiveEarTrainingViewModel.makeQuestion` 中新增：

```swift
case .rhythm:
    let q = RhythmQuestionGenerator.makeQuestion(
        difficulty: request.difficulty.rhythmDifficulty,
        using: &rng
    )
    return .rhythm(q.correct, choices: q.choices, difficulty: request.difficulty, difficultyScore: request.score)
```

### UI 渲染

在 `AdaptiveEarTrainingView` 和 `FocusedEarTrainingSessionView` 中新增：

```swift
if case .rhythm = question {
    // 显示节奏提示（如果需要）
}
```

基本不需要特殊 UI 分支——现有的通用卡片布局（播放按钮、2×2 选项、反馈）已经可以覆盖。

### 历史记录

现有 `AdaptiveEarAttemptRecord` 依赖 `questionKindRaw` 和 `questionId`，`rhythm` 的 `questionId` 用 `"rhythm-\(pattern.grid.map(String.init).joined())"` 表示唯一性。

## 音频实现细节

### ClickBuffer 合成

复用 `MetronomeClickBuffers.makeBuffer` 的逻辑，仅注意节奏题的 buffer 参数：

| 参数 | 强拍 (accent) | 普通拍 (normal) |
|---|---|---|
| 频率 | 1200 Hz | 880 Hz |
| 时长 | 0.05s | 0.035s |
| 振幅 | 0.40 | 0.22 |

### 播放时序

使用 `AVAudioPlayerNode.scheduleBuffer(_:at:options:completionCallbackType:)` 的 `at` 参数指定绝对时间点，确保精确对齐。

## 实现文件清单

以下为新文件或需要修改的文件：

### 新增文件

| 文件 | 内容 |
|---|---|
| `Sources/Features/Ear/RhythmModels.swift` | `RhythmPattern` 结构体、`RhythmDifficulty` 枚举 |
| `Sources/Features/Ear/RhythmQuestionGenerator.swift` | 出题引擎、干扰项生成 |
| `Sources/Features/Ear/RhythmAudioPlayer.swift` | play click 序列的音频逻辑 |

### 修改文件

| 文件 | 改动 |
|---|---|
| `Sources/Practice/Models/AdaptiveEarTrainingModels.swift` | 新增 `.rhythm` case、`rhythmRating`、`rhythmDifficulty` 映射、`difficultyScore` |
| `Sources/Practice/Views/AdaptiveEarTrainingView.swift` | `makeQuestion` 新增 `.rhythm` 分支 |
| `Sources/Practice/Views/FocusedEarHubView.swift` | 新增 rhythm 卡片入口 |
| `Sources/Practice/Views/FocusedEarTrainingSessionView.swift` | `makeQuestion` 新增 `.rhythm` 分支（如果复用的是同一个 viewModel）或加 case 处理 |
| `Sources/Practice/Views/FocusedEarTrainingViewModel.swift` | 支持 `.rhythm` 的播放逻辑 |

### 可选修改

| 文件 | 改动 |
|---|---|
| `Sources/Features/Ear/EarMcqSessionViewModel.swift` | 如果不复用现有播放路径，则不改；如果复用则增加节奏试听 |

## 测试

| 测试 | 内容 |
|---|---|
| 单元测试 - RhythmPattern | displayText 正确性、长度有效性 |
| 单元测试 - RhythmQuestionGenerator | 正确产生 4 个不同选项、正确唯一、干扰项有效性 |
| 单元测试 - AdaptiveEarTrainingEngine | scores、rating 计算 |
| UI 测试 | 专项训练入口存在、节奏题显示正常 |

## 非目标（明确不做）

- 暂不支持 2/4、3/4、6/8 等其他拍号
- 暂不支持 16 分音符颗粒度
- 暂不加入 iOS 系统节拍器同步
- 不修改后端；所有逻辑在 iOS 本地完成
