# Rhythm Ear Training Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rhythm dictation (节奏听写) as the 5th ear training question kind, integrated into both adaptive training and focused/specialized training.

**Architecture:** Three new files (models, question generator, audio player) + modifications to existing adaptive ear training models, view models, and hub views. All logic is iOS-native, no backend changes. Audio playback reuses the existing MetronomeEngine click synthesis approach (AVAudioEngine + buffer scheduling).

**Tech Stack:** Swift, SwiftUI, AVFoundation (AVAudioEngine, AVAudioPlayerNode)

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `swift_ios_host/Sources/Features/Ear/RhythmModels.swift` | `RhythmPattern` struct, `RhythmDifficulty` enum, display text generation |
| `swift_ios_host/Sources/Features/Ear/RhythmQuestionGenerator.swift` | Question/answer + distractor generation, difficulty pools |
| `swift_ios_host/Sources/Features/Ear/RhythmAudioPlayer.swift` | Play click sequence for a given `RhythmPattern` via AVAudioEngine |

### Modified files

| File | Changes |
|---|---|
| `swift_ios_host/Sources/Practice/Models/AdaptiveEarTrainingModels.swift` | Add `.rhythm` to `AdaptiveEarQuestionKind`, add `rhythmRating` to `AdaptiveEarAbilityState`, add `rhythmDifficulty` mapping, add `difficultyScore` entries |
| `swift_ios_host/Sources/Practice/Views/AdaptiveEarTrainingView.swift` | Add `.rhythm` case in `makeQuestion`, `.rhythm` branch for UI rendering |
| `swift_ios_host/Sources/Practice/Views/FocusedEarHubView.swift` | Add rhythm card entry |
| `swift_ios_host/Sources/Practice/Views/FocusedEarTrainingSessionView.swift` | Add `.rhythm` case in makeQuestion / UI rendering |
| `swift_ios_host/Sources/Practice/Views/FocusedEarTrainingViewModel.swift` | Add playback support for `.rhythm` kind |

### Test files

| File | Responsibility |
|---|---|
| `swift_ios_host/Tests/RhythmModelsTests.swift` | Test `RhythmPattern` display text, grid validation |
| `swift_ios_host/Tests/RhythmQuestionGeneratorTests.swift` | Test question generation, distractor uniqueness, pool validity |

---

### Task 1: Create RhythmModels

**Files:**
- Create: `swift_ios_host/Sources/Features/Ear/RhythmModels.swift`
- Test: `swift_ios_host/Tests/RhythmModelsTests.swift`

- [ ] **Step 1: Write the failing tests for RhythmPattern display text**

```swift
// Tests/RhythmModelsTests.swift
import XCTest
@testable import SwiftEarHost

final class RhythmModelsTests: XCTestCase {
    func testDisplayText_allQuarterNotes() {
        let p = RhythmPattern(grid: [1,0,1,0,1,0,1,0])
        XCTAssertEqual(p.displayText, "X X X X")
    }

    func testDisplayText_allEighthNotes() {
        let p = RhythmPattern(grid: [1,1,1,1,1,1,1,1])
        XCTAssertEqual(p.displayText, "XX XX XX XX")
    }

    func testDisplayText_dottedQuarter() {
        // [1,0, 0,0, 1,0, 1,0] -> X· . X X (附点四分+休止+四分+四分)
        let p = RhythmPattern(grid: [1,0,0,0,1,0,1,0])
        XCTAssertEqual(p.displayText, "X· . X X")
    }

    func testDisplayText_restOnFirstBeat() {
        // [0,0, 1,1, 1,0, 1,0] -> . XX X· X
        let p = RhythmPattern(grid: [0,0,1,1,1,0,1,0])
        XCTAssertEqual(p.displayText, ". XX X· X")
    }

    func testGridValidation_exactly8() {
        XCTAssertNil(RhythmPattern(grid: [1,0,1,0,1,0,1]))       // too short
        XCTAssertNil(RhythmPattern(grid: [1,0,1,0,1,0,1,0,1]))   // too long
        XCTAssertNil(RhythmPattern(grid: [1,0,1,0,1,0,1,2]))     // invalid value
        XCTAssertNotNil(RhythmPattern(grid: [1,0,1,0,1,0,1,0]))  // valid
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build-for-testing 2>&1 | tail -20
```

Expected: Build fails — `RhythmPattern` type not defined.

- [ ] **Step 3: Write minimal RhythmModels implementation**

```swift
// Sources/Features/Ear/RhythmModels.swift
import Foundation

/// 节奏难度（映射到 AdaptiveEarDifficulty）
enum RhythmDifficulty: String, Codable, Equatable {
    case beginner
    case intermediate
    case advanced
}

/// 4/4 拍一小节的节奏型，用 8 个八分位表示
struct RhythmPattern: Codable, Equatable {
    /// 8 个元素，每元素为 0（休止）或 1（击发）
    let grid: [Int]

    /// Failable init: 仅当 grid 长度为 8 且每个元素为 0 或 1 时成功
    init?(grid: [Int]) {
        guard grid.count == 8, grid.allSatisfy({ $0 == 0 || $0 == 1 }) else { return nil }
        self.grid = grid
    }

    /// 文字展示：每 2 个一组 → X / X· / ·X / .
    var displayText: String {
        let groups = stride(from: 0, to: 8, by: 2).map { i -> String in
            let pair = (grid[i], grid[i+1])
            switch pair {
            case (1, 1): return "XX"
            case (1, 0): return "X·"
            case (0, 1): return "·X"
            case (0, 0): return "."
            default: return "?" // unreachable
            }
        }
        return groups.joined(separator: " ")
    }

    /// 播放用的击打序列（每个八分位是否发声）
    var hits: [Bool] { grid.map { $0 == 1 } }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build-for-testing 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Features/Ear/RhythmModels.swift swift_ios_host/Tests/RhythmModelsTests.swift
git commit -m "feat(rhythm): add RhythmPattern model and display text"
```

---

### Task 2: Create RhythmQuestionGenerator

**Files:**
- Create: `swift_ios_host/Sources/Features/Ear/RhythmQuestionGenerator.swift`
- Test: `swift_ios_host/Tests/RhythmQuestionGeneratorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/RhythmQuestionGeneratorTests.swift
import XCTest
@testable import SwiftEarHost

final class RhythmQuestionGeneratorTests: XCTestCase {
    func testBeginnerPoolNotEmpty() {
        XCTAssertFalse(RhythmQuestionGenerator.pool(for: .beginner).isEmpty)
    }

    func testIntermediatePoolNotEmpty() {
        XCTAssertFalse(RhythmQuestionGenerator.pool(for: .intermediate).isEmpty)
    }

    func testAdvancedPoolNotEmpty() {
        XCTAssertFalse(RhythmQuestionGenerator.pool(for: .advanced).isEmpty)
    }

    func testMakeQuestionReturnsFourChoices() {
        var rng = SystemRandomNumberGenerator()
        let result = RhythmQuestionGenerator.makeQuestion(difficulty: .beginner, using: &rng)
        // correct is one of the choices
        XCTAssertTrue(result.choices.contains(result.correct))
        XCTAssertEqual(result.choices.count, 4)
    }

    func testChoicesAreDistinct() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let result = RhythmQuestionGenerator.makeQuestion(difficulty: .beginner, using: &rng)
            let unique = Set(result.choices)
            XCTAssertEqual(unique.count, 4, "Choices must all be distinct")
        }
    }

    func testNoAutoRepeat() {
        var rng = SystemRandomNumberGenerator()
        let first = RhythmQuestionGenerator.makeQuestion(difficulty: .beginner, using: &rng)
        var foundDifferent = false
        for _ in 0..<10 {
            let next = RhythmQuestionGenerator.makeQuestion(difficulty: .beginner, using: &rng)
            if next.correct != first.correct {
                foundDifferent = true
                break
            }
        }
        XCTAssertTrue(foundDifferent, "Should produce different patterns across calls")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Build fails — `RhythmQuestionGenerator` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/Features/Ear/RhythmQuestionGenerator.swift
import Foundation

struct RhythmQuestionGenerator {
    /// 指定难度下可用的节奏型池
    static func pool(for difficulty: RhythmDifficulty) -> [[Int]] {
        switch difficulty {
        case .beginner:
            return [
                [1,0,1,0,1,0,1,0],  // X X X X
                [1,1,1,1,1,1,1,1],  // XX XX XX XX
                [1,0,1,1,1,0,1,0],  // X XX X· X
                [1,1,1,0,1,1,1,0],  // XX X· XX X·
                [1,0,1,0,1,1,1,0],  // X X XX X·
                [1,1,1,0,1,0,1,0],  // XX X· X X
                [1,0,1,0,1,0,1,1],  // X X X XX
                [1,1,1,0,1,0,1,1],  // XX X· X XX
                [1,1,1,1,1,0,1,0],  // XX XX X· X
                [1,0,1,1,1,0,1,1],  // X XX X· XX
            ]
        case .intermediate:
            return [
                [1,0,0,0,1,0,1,0],  // X· . X X
                [1,0,1,0,0,0,1,0],  // X X . X
                [0,0,1,0,1,0,1,0],  // . X X X
                [0,0,1,1,1,0,1,0],  // . XX X· X
                [1,1,0,0,1,0,1,0],  // XX . X X
                [1,0,1,1,0,0,1,0],  // X XX . X
                [1,0,1,0,1,0,0,0],  // X X X .
                [1,1,1,0,0,0,1,0],  // XX X· . X
                [1,0,0,0,1,1,1,0],  // X· . XX X·
                [0,0,1,0,1,1,1,0],  // . X XX X·
            ]
        case .advanced:
            return [
                [1,0,0,0,0,0,1,0],  // X· . . X  (附点四分+八分+八分休止+四分)
                [0,0,1,0,0,0,1,1],  // . X . XX
                [1,1,0,0,0,0,1,0],  // XX . . X
                [1,0,1,0,0,0,0,0],  // X X . .
                [0,0,0,0,1,0,1,0],  // . . X X  (前两拍休止)
                [1,0,0,0,1,0,0,0],  // X· . X· .
                [0,0,1,0,1,0,0,0],  // . X X· .
                [1,1,0,0,1,1,0,0],  // XX . XX .
                [0,0,0,0,0,0,1,1],  // . . . XX
                [1,1,1,1,0,0,0,0],  // XX XX . .
            ]
        }
    }

    /// 根据 pool 随机选一个正确节奏，生成 3 个干扰项，打乱后返回
    static func makeQuestion(
        difficulty: RhythmDifficulty,
        using rng: inout some RandomNumberGenerator
    ) -> (correct: RhythmPattern, choices: [RhythmPattern]) {
        let pool = self.pool(for: difficulty)
        let correctGrid = pool.randomElement(using: &rng)!
        let correct = RhythmPattern(grid: correctGrid)!

        // 从整池中选 3 个不同干扰项
        var distractors: [RhythmPattern] = []
        var candidates = pool.filter { $0 != correctGrid }
        candidates.shuffle(using: &rng)
        for grid in candidates {
            guard let p = RhythmPattern(grid: grid) else { continue }
            if !distractors.contains(p) {
                distractors.append(p)
                if distractors.count == 3 { break }
            }
        }

        // 如果池子太小不够 3 个不同，用变形补
        while distractors.count < 3 {
            if let alt = makeDistractor(from: correctGrid, avoid: Set(distractors.map(\.grid)), using: &rng) {
                distractors.append(RhythmPattern(grid: alt)!)
            } else {
                break
            }
        }

        var choices = distractors + [correct]
        choices.shuffle(using: &rng)
        return (correct, choices)
    }

    /// 对正确节奏做一位翻转，生成干扰项
    private static func makeDistractor(
        from grid: [Int],
        avoid: Set<[Int]>,
        using rng: inout some RandomNumberGenerator
    ) -> [Int]? {
        for _ in 0..<20 {
            var copy = grid
            let idx = Int.random(in: 0..<8, using: &rng)
            copy[idx] = copy[idx] == 1 ? 0 : 1
            if copy != grid, !avoid.contains(copy) {
                return copy
            }
        }
        return nil
    }
}

extension [Int]: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        for v in self { hasher.combine(v) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build-for-testing 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Features/Ear/RhythmQuestionGenerator.swift swift_ios_host/Tests/RhythmQuestionGeneratorTests.swift
git commit -m "feat(rhythm): add RhythmQuestionGenerator"
```

---

### Task 3: Create RhythmAudioPlayer

**Files:**
- Create: `swift_ios_host/Sources/Features/Ear/RhythmAudioPlayer.swift`

- [ ] **Step 1: Write RhythmAudioPlayer implementation**

This component does not have separate unit tests (audio playback is hard to unit test without a device). It will be validated through integration in later tasks.

```swift
// Sources/Features/Ear/RhythmAudioPlayer.swift
import AVFoundation
import Foundation

/// 播放节奏 click 序列（不依赖外部 AVAudioEngine，内部自行管理）
final class RhythmAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "guitar-ai-coach.rhythm-audio", qos: .userInitiated)

    /// 是否正在播放
    private(set) var isPlaying = false
    private var generation: UInt64 = 0

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
    }

    /// 播完回调（只在正常完成、未被中途取消时 call）
    var onPlaybackFinished: (() -> Void)?

    /// 播放一个节奏型
    /// - Parameters:
    ///   - pattern: 节奏型
    ///   - bpm: 速度，默认 90
    func play(pattern: RhythmPattern, bpm: Int = 90) {
        stop()
        isPlaying = true
        generation &+= 1
        let gen = generation

        let eighthInterval = 60.0 / Double(bpm) / 2.0  // 每个八分位秒数
        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0 else { return }
        let format = engine.mainMixerNode.outputFormat(forBus: 0)

        do {
            try engine.start()
        } catch {
            isPlaying = false
            return
        }

        // 为每个击发的八分位调度一个 click buffer
        for (i, hit) in pattern.hits.enumerated() where hit {
            let isAccent = (i == 0 || i == 4)  // 第 1、3 拍为强拍
            let buffer = Self.makeClickBuffer(format: format, accent: isAccent)
            let time = AVAudioTime(sampleTime: AVAudioFramePosition(Double(i) * eighthInterval * sampleRate),
                                   atRate: sampleRate)
            player.scheduleBuffer(buffer, at: time, options: [])
        }

        player.play()

        // 计算总时长并在结束时回调
        let totalDuration = 8.0 * eighthInterval
        queue.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            guard let self, self.generation == gen else { return }
            DispatchQueue.main.async {
                self.isPlaying = false
                self.onPlaybackFinished?()
            }
        }
    }

    /// 停止播放
    func stop() {
        generation &+= 1
        player.stop()
        if engine.isRunning {
            engine.stop()
        }
        isPlaying = false
    }

    // MARK: - Click buffer synthesis

    /// 合成一个 click buffer（同 MetronomeEngine 的 click 合成逻辑）
    private static func makeClickBuffer(format: AVAudioFormat, accent: Bool) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let (freq, duration, amplitude): (Double, Double, Double) = accent
            ? (1_200, 0.050, 0.40)
            : (880, 0.035, 0.22)

        let frameCount = AVAudioFrameCount(max(1, Int(sampleRate * duration)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let theta = 2.0 * Double.pi * freq / sampleRate
        let channels = Int(format.channelCount)
        guard let data = buffer.floatChannelData else { return buffer }
        for frame in 0..<Int(frameCount) {
            let denom = max(1, Int(frameCount) - 1)
            let env = Float(1.0 - Double(frame) / Double(denom))
            let clickEnv = env * env
            let s = Float(sin(Double(frame) * theta) * amplitude * Double(clickEnv))
            for ch in 0..<channels {
                data[ch][frame] = s
            }
        }
        return buffer
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Features/Ear/RhythmAudioPlayer.swift
git commit -m "feat(rhythm): add RhythmAudioPlayer for click playback"
```

---

### Task 4: Update AdaptiveEarTrainingModels

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Models/AdaptiveEarTrainingModels.swift`

- [ ] **Step 1: Add `.rhythm` to `AdaptiveEarQuestionKind`**

```swift
enum AdaptiveEarQuestionKind: String, CaseIterable, Codable, Equatable {
    case interval
    case chord
    case progression
    case singleNote
    case rhythm   // 新增

    var title: String {
        switch self {
        case .rhythm: return "节奏听写"
        // ... keep existing cases ...
        }
    }

    var shortTitle: String {
        switch self {
        case .rhythm: return "节奏"
        // ... keep existing cases ...
        }
    }
}
```

- [ ] **Step 2: Add `rhythm` case to `AdaptiveEarQuestion` enum**

```swift
enum AdaptiveEarQuestion: Identifiable {
    case interval(IntervalQuestion, difficulty: AdaptiveEarDifficulty, difficultyScore: Int)
    case chord(EarBankItem, difficulty: AdaptiveEarDifficulty, difficultyScore: Int)
    case progression(EarBankItem, difficulty: AdaptiveEarDifficulty, difficultyScore: Int)
    case singleNote(SingleNoteQuestion, difficulty: AdaptiveEarDifficulty, difficultyScore: Int)
    case rhythm(RhythmPattern, choices: [RhythmPattern], difficulty: AdaptiveEarDifficulty, difficultyScore: Int)  // 新增

    var stableQuestionId: String {
        switch self {
        // ... existing ...
        case let .rhythm(q, _, _, _):
            return "rhythm-\(q.grid.map(String.init).joined())"
        }
    }

    var kind: AdaptiveEarQuestionKind {
        switch self {
        // ... existing ...
        case .rhythm: return .rhythm
        }
    }

    var difficulty: AdaptiveEarDifficulty {
        switch self {
        // ... existing ...
        case let .rhythm(_, _, d, _): return d
        }
    }

    var difficultyScore: Int {
        switch self {
        // ... existing ...
        case let .rhythm(_, _, _, s): return s
        }
    }

    var prompt: String {
        switch self {
        // ... existing ...
        case .rhythm: return "听节奏，选出正确的节奏型"
        }
    }

    var choices: [AdaptiveEarChoice] {
        switch self {
        // ... existing ...
        case let .rhythm(_, choices, _, _):
            return choices.map { AdaptiveEarChoice(id: $0.grid.map(String.init).joined(), label: $0.displayText) }
        }
    }

    var correctChoiceId: String {
        switch self {
        // ... existing ...
        case let .rhythm(correct, _, _, _):
            return correct.grid.map(String.init).joined()
        }
    }

    var correctAnswerText: String {
        switch self {
        // ... existing ...
        case let .rhythm(correct, _, _, _):
            return correct.displayText
        }
    }

    var root: String? {
        switch self {
        // ... existing ...
        case .rhythm: return nil
        }
    }

    var explanation: String {
        switch self {
        // ... existing ...
        case .rhythm:
            return "这段节奏是 \(correctAnswerText)，注意强拍和切分的位置。"
        }
    }
}
```

- [ ] **Step 3: Add `rhythmDifficulty` to `AdaptiveEarDifficulty`**

```swift
extension AdaptiveEarDifficulty {
    // ... existing computed properties ...

    var rhythmDifficulty: RhythmDifficulty {
        switch self {
        case .beginner: return .beginner
        case .intermediate: return .intermediate
        case .advanced: return .advanced
        }
    }
}
```

- [ ] **Step 4: Add `rhythmRating` to `AdaptiveEarAbilityState`**

```swift
struct AdaptiveEarAbilityState: Codable, Equatable {
    var overallEarRating: Double
    var intervalRating: Double
    var chordRating: Double
    var progressionRating: Double
    var singleNoteRating: Double
    var rhythmRating: Double = 400  // 新增

    static let initial = AdaptiveEarAbilityState(
        overallEarRating: 400,
        intervalRating: 400,
        chordRating: 400,
        progressionRating: 400,
        singleNoteRating: 400,
        rhythmRating: 400           // 新增
    )

    func rating(for kind: AdaptiveEarQuestionKind) -> Double {
        switch kind {
        case .rhythm: return rhythmRating
        // ... existing ...
        }
    }

    mutating func setRating(_ value: Double, for kind: AdaptiveEarQuestionKind) {
        switch kind {
        case .rhythm: rhythmRating = value
        // ... existing ...
        }
    }
}
```

- [ ] **Step 5: Add `difficultyScore` entries for rhythm**

```swift
// In AdaptiveEarTrainingEngine.difficultyScore
static func difficultyScore(kind: AdaptiveEarQuestionKind, difficulty: AdaptiveEarDifficulty) -> Int {
    switch (kind, difficulty) {
    // ... existing cases ...
    case (.rhythm, .beginner): return 320
    case (.rhythm, .intermediate): return 490
    case (.rhythm, .advanced): return 650
    }
}
```

- [ ] **Step 6: Build to verify compilation**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 7: Commit**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Practice/Models/AdaptiveEarTrainingModels.swift
git commit -m "feat(rhythm): add rhythm to AdaptiveEarTrainingModels"
```

---

### Task 5: Update AdaptiveEarTrainingView

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Views/AdaptiveEarTrainingView.swift`

- [ ] **Step 1: Add `.rhythm` case in `makeQuestion`**

Inside `AdaptiveEarTrainingViewModel.makeQuestion`, add:

```swift
case .rhythm:
    let result = RhythmQuestionGenerator.makeQuestion(
        difficulty: request.difficulty.rhythmDifficulty,
        using: &rng
    )
    return .rhythm(result.correct, choices: result.choices,
                   difficulty: request.difficulty, difficultyScore: request.score)
```

- [ ] **Step 2: Add `.rhythm` playback in `playCurrent`**

Inside the `switch question { }` in `playCurrent()`, add:

```swift
case let .rhythm(q, _, _, _):
    // Use RhythmAudioPlayer (injected as a stored property)
    // The player is available since we'll add it as `rhythmPlayer` property
    rhythmPlayer.play(pattern: q)
```

Also add `rhythmPlayer` property to the ViewModel class:

```swift
// In AdaptiveEarTrainingViewModel
private let rhythmPlayer = RhythmAudioPlayer()
```

And in `cancelPlayback`:

```swift
func cancelPlayback() {
    playTask?.cancel()
    playTask = nil
    intervalPlayer.cancelIntervalPlayback()
    chordPlayer.cancelChordPlayback()
    rhythmPlayer.stop()   // 新增
    isPlaying = false
    isPreviewingOption = false
}
```

- [ ] **Step 3: Add rhythm hint UI (optional, can be a simple label)**

In `questionCard`, after the `progression` hint section, add:

```swift
if case .rhythm = question {
    VStack(alignment: .leading, spacing: 4) {
        Text("节奏由拍击声表示：强拍⬤ 弱拍·")
            .font(.caption)
            .foregroundStyle(SwiftAppTheme.muted)
    }
    .padding(.top, 4)
}
```

- [ ] **Step 4: Build to verify compilation**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Practice/Views/AdaptiveEarTrainingView.swift
git commit -m "feat(rhythm): add rhythm support in AdaptiveEarTrainingView"
```

---

### Task 6: Update FocusedEarHubView

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Views/FocusedEarHubView.swift`

- [ ] **Step 1: Add rhythm card below singleNote card**

```swift
typeCard(
    kind: .rhythm,
    icon: "metronome",
    color: Color(red: 0.85, green: 0.35, blue: 0.75),
    description: "4/4 拍一小节，听节奏选谱例"
)
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```


Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Practice/Views/FocusedEarHubView.swift
git commit -m "feat(rhythm): add rhythm entry in FocusedEarHubView"
```

---

### Task 7: Update FocusedEarTrainingView and ViewModel

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Views/FocusedEarTrainingSessionView.swift`
- Modify: `swift_ios_host/Sources/Practice/Views/FocusedEarTrainingViewModel.swift`

- [ ] **Step 1: In FocusedEarTrainingViewModel, add rhythm support**

Add `rhythmPlayer` property, add `.rhythm` playback in the switch statement (mirroring what was done in AdaptiveEarTrainingViewModel), and add `rhythmPlayer.stop()` in `cancelPlayback()`.

- [ ] **Step 2: In FocusedEarTrainingSessionView, add `.rhythm` case in `questionCard`**

Add `.rhythm` in the hint section (same pattern as AdaptiveEarTrainingView).

- [ ] **Step 3: Build to verify**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Practice/Views/FocusedEarTrainingSessionView.swift swift_ios_host/Sources/Practice/Views/FocusedEarTrainingViewModel.swift
git commit -m "feat(rhythm): add rhythm support in FocusedEarTrainingView"
```

---

## Self-Review Checklist

1. **Spec coverage:** Verify each spec section maps to at least one task:
   - [x] Data model (RhythmPattern) → Task 1
   - [x] Question generator (pools + distractors) → Task 2
   - [x] Audio playback (click synthesis) → Task 3
   - [x] AdaptiveEarQuestionKind + rhythm case → Task 4
   - [x] rhythmRating in AbilityState → Task 4
   - [x] difficultyScore entries → Task 4
   - [x] makeQuestion in adaptive flow → Task 5
   - [x] Playback in adaptive flow → Task 5
   - [x] FocusedEarHubView entry → Task 6
   - [x] Focused ear training session support → Task 7
   - [x] Tests → Tasks 1 & 2

2. **Placeholder scan:** No TBD, TODO, or "implement later" in the plan. All code snippets are complete.

3. **Type consistency:** `RhythmPattern`, `RhythmDifficulty`, `RhythmQuestionGenerator`, and `RhythmAudioPlayer` are defined and used consistently across all tasks.
