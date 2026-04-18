# Ear Bank B procedural progression generator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace JSON `ear_seed_v1.json` Bank B pool with a rule-based `EarProgressionProceduralGenerator` that emits `EarBankItem` values matching `docs/superpowers/specs/2026-04-18-ear-progression-procedural-design.md` (conservative Roman numerals, N∈{3,4,5} by tier, four options same N, playable via existing `EarPlaybackMidi` / `EarProgressionPlayback`).

**Architecture:** Add `EarProgressionMcqDifficulty` and a pure generator module under `Sources/Features/Ear/`. `EarMcqSessionViewModel` stops calling `EarSeedLoader` when `bank == "B"`; it draws questions with an inout `RandomNumberGenerator` (reuse existing `chordRng` field since a VM instance is either bank A or B). Capped sessions pre-fill `session`; unlimited calls `makeQuestion` on each `nextOrFinish`. UI gains an optional `progressionDifficulty` parameter defaulting to `.初级`.

**Tech stack:** Swift 5.10, SwiftPM target `Ear` (`swift_app/Package.swift`), existing types `EarBankItem`, `EarMcqOption`, `EarPlaybackMidi`, `EarProgressionPlayback`, `OfflineChordBuilder` (via `EarProgressionPlayback`).

---

## File map (create / modify)

| File | Responsibility |
|------|----------------|
| `swift_app/Sources/Features/Ear/EarPlaybackMidi.swift` | Add `romanNumeralSegmentCount(_:)` for validation and tests (single source of truth for `-` split rules). |
| `swift_app/Sources/Features/Ear/EarProgressionProceduralGenerator.swift` | **Create:** `EarProgressionMcqDifficulty` enum + static generator + template/key tables + distractor + shuffle. |
| `swift_app/Sources/Features/Ear/EarMcqSessionViewModel.swift` | Bank B bootstrap / `nextOrFinish` / capped `session` use generator; new `progressionDifficulty` property; no `EarSeedLoader` on B. |
| `swift_app/Sources/Features/Ear/EarMcqSessionView.swift` | Thread `progressionDifficulty` into `EarMcqSessionViewModel` init. |
| `swift_app/Sources/Features/Ear/EarHomeView.swift` | Optionally pass `.初级` explicitly (default already covers). |
| `swift_app/Tests/Unit/EarCoreTests.swift` | Add progression procedural tests + deterministic RNG struct. |

No `Package.swift` change (Ear target is directory-based).

---

### Task 1: Segment count helper on `EarPlaybackMidi`

**Files:**
- Modify: `swift_app/Sources/Features/Ear/EarPlaybackMidi.swift`
- Test: covered in Task 5 (generator tests call this)

- [ ] **Step 1: Add public static method**

Insert after `forProgression` (or before `private static func progressionRoot`), keeping `public` visibility consistent with the enum:

```swift
    /// `progression_roman` 按 `-` 分割后的功能标记段数（与 `letterChordSymbols` 分割规则一致）。
    public static func romanNumeralSegmentCount(_ progressionRoman: String) -> Int {
        progressionRoman
            .split(separator: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }
```

- [ ] **Step 2: Run existing tests**

Run:

```bash
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/ospc/swift_app && swift test
```

Expected: all tests pass (no behavior change yet).

- [ ] **Step 3: Commit**

```bash
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/ospc
git add swift_app/Sources/Features/Ear/EarPlaybackMidi.swift
git commit -m "feat(ear): add romanNumeralSegmentCount for progression strings"
git push origin HEAD
```

---

### Task 2: Create `EarProgressionProceduralGenerator.swift`

**Files:**
- Create: `swift_app/Sources/Features/Ear/EarProgressionProceduralGenerator.swift`

- [ ] **Step 1: Add new file with full contents**

Use this implementation (adjust hints/strings if product copy changes later):

```swift
import Foundation
import Chords

/// 和弦进行（Bank B）程序化难度：与和弦听辨 `EarChordMcqDifficulty` 分离，避免语义混淆。
public enum EarProgressionMcqDifficulty: String, Sendable, CaseIterable, Codable {
    case 初级
    case 中级
    case 高级
}

/// 规则生成和弦进行四选一题（不读 `ear_seed` Bank B）。
public enum EarProgressionProceduralGenerator {
    private static let romanTokens = ["I", "ii", "iii", "IV", "V", "vi"]

    private static let templatesByN: [Int: [String]] = [
        3: ["ii-V-I", "I-IV-V", "vi-IV-I", "I-V-vi", "IV-V-I"],
        4: ["I-V-vi-IV", "vi-IV-I-V", "I-vi-IV-V", "I-IV-V-I", "ii-V-I-IV"],
        5: ["I-vi-IV-V-I", "ii-V-I-vi-IV", "I-IV-vi-V-I", "vi-IV-I-V-vi", "I-V-vi-IV-I"],
    ]

    public static func keys(for difficulty: EarProgressionMcqDifficulty) -> [String] {
        switch difficulty {
        case .初级:
            return ["C", "G", "D", "F"]
        case .中级:
            return ["C", "G", "D", "F", "A", "E", "Bb"]
        case .高级:
            return ["C", "G", "D", "F", "A", "E", "Bb", "B", "Db", "Eb", "Ab"]
        }
    }

    public static func makeQuestion(
        difficulty: EarProgressionMcqDifficulty,
        using rng: inout some RandomNumberGenerator
    ) -> EarBankItem {
        let n: Int
        switch difficulty {
        case .初级: n = 3
        case .中级: n = 4
        case .高级: n = 5
        }
        let keys = Self.keys(for: difficulty)
        let templates = Self.templatesByN[n] ?? ["I-IV-V"]
        var musicKey = keys.randomElement(using: &rng)!
        var progressionRoman = templates[0]
        for _ in 0 ..< 64 {
            musicKey = keys.randomElement(using: &rng)!
            progressionRoman = templates.randomElement(using: &rng)!
            let probe = stubItem(musicKey: musicKey, progressionRoman: progressionRoman)
            if EarProgressionPlayback.playbackFretsSequence(for: probe) != nil {
                break
            }
        }
        let wrong = makeWrongLabels(correct: progressionRoman, n: n, using: &rng)
        let (options, correctKey) = shuffleOptions(correctLabel: progressionRoman, wrong: wrong, using: &rng)
        return EarBankItem(
            id: UUID().uuidString,
            mode: "B",
            questionType: "progression_recognition",
            promptZh: "听和弦进行，选择最符合的一项",
            options: options,
            correctOptionKey: correctKey,
            root: nil,
            targetQuality: nil,
            musicKey: musicKey,
            progressionRoman: progressionRoman,
            hintZh: hintZh(for: difficulty),
            playbackFretsSixToOne: nil
        )
    }

    private static func stubItem(musicKey: String, progressionRoman: String) -> EarBankItem {
        EarBankItem(
            id: "stub",
            mode: "B",
            questionType: "progression_recognition",
            promptZh: "",
            options: [EarMcqOption(key: "A", label: progressionRoman)],
            correctOptionKey: "A",
            root: nil,
            targetQuality: nil,
            musicKey: musicKey,
            progressionRoman: progressionRoman,
            hintZh: nil,
            playbackFretsSixToOne: nil
        )
    }

    private static func hintZh(for difficulty: EarProgressionMcqDifficulty) -> String {
        switch difficulty {
        case .初级:
            return "常见终止与正格进行"
        case .中级:
            return "流行主副歌常见进行"
        case .高级:
            return "较长进行，注意听低音与功能"
        }
    }

    private static func shuffleOptions(
        correctLabel: String,
        wrong: [String],
        using rng: inout some RandomNumberGenerator
    ) -> (options: [EarMcqOption], correctKey: String) {
        precondition(wrong.count == 3)
        var labels = wrong + [correctLabel]
        labels.shuffle(using: &rng)
        let keys = ["A", "B", "C", "D"]
        let options = zip(keys, labels).map { EarMcqOption(key: $0.0, label: $0.1) }
        let correctKey = options.first { $0.label == correctLabel }!.key
        return (options, correctKey)
    }

    private static func makeWrongLabels(
        correct: String,
        n: Int,
        using rng: inout some RandomNumberGenerator
    ) -> [String] {
        var pool = (templatesByN[n] ?? []).filter { $0 != correct }
        pool.shuffle(using: &rng)
        var out: [String] = []
        for p in pool where out.count < 3 {
            if !out.contains(p) { out.append(p) }
        }
        var attempts = 0
        while out.count < 3 && attempts < 300 {
            attempts += 1
            if let m = randomMutant(from: correct, using: &rng),
               m != correct,
               !out.contains(m),
               EarPlaybackMidi.romanNumeralSegmentCount(m) == n
            {
                out.append(m)
            }
        }
        precondition(
            out.count == 3,
            "could not build 3 distractors for correct=\(correct) n=\(n); extend templates or mutator"
        )
        return out
    }

    private static func randomMutant(from correct: String, using rng: inout some RandomNumberGenerator) -> String? {
        var parts = correct.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        let idx = Int.random(in: 0 ..< parts.count, using: &rng)
        let old = parts[idx]
        guard let replacement = romanTokens.filter({ $0 != old }).randomElement(using: &rng) else { return nil }
        parts[idx] = replacement
        return parts.joined(separator: "-")
    }
}
```

- [ ] **Step 2: Build**

Run:

```bash
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/ospc/swift_app && swift build --target Ear
```

Expected: success.

- [ ] **Step 3: Commit**

```bash
git add swift_app/Sources/Features/Ear/EarProgressionProceduralGenerator.swift
git commit -m "feat(ear): add procedural progression MCQ generator"
git push origin HEAD
```

---

### Task 3: Wire `EarMcqSessionViewModel` for Bank B

**Files:**
- Modify: `swift_app/Sources/Features/Ear/EarMcqSessionViewModel.swift`

- [ ] **Step 1: Add stored property**

Add after `chordDifficulty`:

```swift
    /// 仅 `bank == "B"`（和弦进行）时使用：程序化出题难度。
    public let progressionDifficulty: EarProgressionMcqDifficulty
```

- [ ] **Step 2: Extend initializer**

Add parameter with default (preserves call sites):

```swift
        progressionDifficulty: EarProgressionMcqDifficulty = .初级,
```

Assign `self.progressionDifficulty = progressionDifficulty` in the initializer body.

- [ ] **Step 3: Replace Bank B branch in `bootstrap()`**

Replace the entire `do { let doc = try await loader.load() ... }` block for bank B with logic that **does not** call `loader.load()` when `bank == "B"`.

Concrete behavior:

1. If `bank != "B"`, keep existing behavior (today only `"A"` returns earlier; if future banks exist, preserve loader path only for non-B).
2. When `bank == "B"`:
   - `loadError = nil`
   - `bankBSourcePool = []` and `bankBDealingQueue = []` (no pool)
   - If `maxQuestions == nil`:
     - `session = []`
     - `question = EarProgressionProceduralGenerator.makeQuestion(difficulty: progressionDifficulty, using: &chordRng)`
   - Else let `cap = max(1, maxQuestions!)`:
     - `session = (0 ..< cap).map { _ in EarProgressionProceduralGenerator.makeQuestion(difficulty: progressionDifficulty, using: &chordRng) }`
     - `question = session.first`
   - Set counters and flags same as today; `loading = false`

3. Remove dependence on `doc.bankB.isEmpty` for B (no empty pool error).

- [ ] **Step 4: Update `nextOrFinish()` for Bank B unlimited**

Replace the body that refills `bankBDealingQueue` from `bankBSourcePool` with:

```swift
            question = EarProgressionProceduralGenerator.makeQuestion(
                difficulty: progressionDifficulty,
                using: &chordRng
            )
```

- [ ] **Step 5: Run tests**

```bash
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/ospc/swift_app && swift test
```

Expected: pass (Task 5 tests not present yet is OK).

- [ ] **Step 6: Commit**

```bash
git add swift_app/Sources/Features/Ear/EarMcqSessionViewModel.swift
git commit -m "feat(ear): use procedural generator for bank B sessions"
git push origin HEAD
```

---

### Task 4: Thread difficulty through `EarMcqSessionView`

**Files:**
- Modify: `swift_app/Sources/Features/Ear/EarMcqSessionView.swift`

- [ ] **Step 1: Add init parameter**

```swift
        progressionDifficulty: EarProgressionMcqDifficulty = .初级,
```

Pass through to `EarMcqSessionViewModel(..., progressionDifficulty: progressionDifficulty)`.

- [ ] **Step 2: Optional UI badge (YAGNI default)**

Spec不要求 UI 改版：首版可不展示进行中难度。若需与 Bank A 一致，可在 `q.promptZh` 同行对 `bank == "B"` 显示 `Text(progressionDifficulty.rawValue)`；本计划**默认不做**，避免 scope 膨胀。

- [ ] **Step 3: Commit**

```bash
git add swift_app/Sources/Features/Ear/EarMcqSessionView.swift
git commit -m "feat(ear): pass progressionDifficulty into ear MCQ session"
git push origin HEAD
```

---

### Task 5: Unit tests (property-style + deterministic RNG)

**Files:**
- Modify: `swift_app/Tests/Unit/EarCoreTests.swift`

- [ ] **Step 1: Append deterministic RNG + tests at end of `EarCoreTests`**

Add before the final closing brace of the class (or as a new `final class EarProgressionProceduralTests` in same file — prefer **same file** to avoid new test target wiring issues):

```swift
/// 可复现的 64-bit LCG，仅单测使用。
private struct TestLCG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

extension EarCoreTests {
    func testProgressionProceduralOptionsSameSegmentCountAsAnswer() {
        for difficulty in EarProgressionMcqDifficulty.allCases {
            var rng = SystemRandomNumberGenerator()
            for _ in 0 ..< 80 {
                let q = EarProgressionProceduralGenerator.makeQuestion(difficulty: difficulty, using: &rng)
                guard let roman = q.progressionRoman else {
                    XCTFail("missing progression_roman")
                    continue
                }
                let n = EarPlaybackMidi.romanNumeralSegmentCount(roman)
                XCTAssertEqual(q.options.count, 4)
                let keys = Set(q.options.map(\.key))
                XCTAssertEqual(keys.count, 4)
                let labels = Set(q.options.map(\.label))
                XCTAssertEqual(labels.count, 4, "duplicate option label")
                for opt in q.options {
                    XCTAssertEqual(EarPlaybackMidi.romanNumeralSegmentCount(opt.label), n, opt.label)
                }
                let correctLabel = q.options.first { $0.key == q.correctOptionKey }?.label
                XCTAssertEqual(correctLabel, roman)
                XCTAssertNotNil(EarProgressionPlayback.playbackFretsSequence(for: q))
            }
        }
    }

    func testProgressionProceduralGoldenSeed() {
        var rng = TestLCG(seed: 42)
        let q = EarProgressionProceduralGenerator.makeQuestion(difficulty: .中级, using: &rng)
        XCTAssertEqual(q.questionType, "progression_recognition")
        XCTAssertEqual(q.mode, "B")
        XCTAssertNotNil(q.musicKey)
        XCTAssertNotNil(q.progressionRoman)
        XCTAssertEqual(EarPlaybackMidi.romanNumeralSegmentCount(q.progressionRoman!), 4)
    }
}
```

- [ ] **Step 2: Run targeted test then full suite**

```bash
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/ospc/swift_app && swift test --filter EarCoreTests.testProgressionProceduralOptionsSameSegmentCountAsAnswer
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/ospc/swift_app && swift test
```

Expected: all pass. If `playbackFretsSequence` returns nil for any generated question, **fix templates or key retry loop** before merging (tests will catch).

- [ ] **Step 3: Commit**

```bash
git add swift_app/Tests/Unit/EarCoreTests.swift
git commit -m "test(ear): cover procedural progression generator invariants"
git push origin HEAD
```

---

### Task 6: Cleanup and docs cross-reference (optional but quick)

**Files:**
- Modify: `docs/superpowers/specs/2026-04-18-ear-progression-procedural-design.md` (one line under §5.3: “实现见 plans/2026-04-18-ear-progression-procedural-generator.md”)

- [ ] **Step 1: Add single cross-link line** (if product accepts doc churn)

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-04-18-ear-progression-procedural-design.md
git commit -m "docs: link progression procedural spec to implementation plan"
git push origin HEAD
```

If you prefer zero spec churn, skip Task 6.

---

## Plan self-review (vs spec)

| Spec section | Covered by |
|--------------|------------|
| §2 保守罗马 | `romanTokens` + 模板只用 I–vi |
| §3.1 同 N 四选项 | `shuffleOptions` + tests |
| §3.2 播放/揭示 | `playbackFretsSequence` probe loop |
| §3.3 四选项互异 | `Set(labels).count == 4` test + pool/mutator |
| §3.4 可复现 RNG | `using: &rng` + `TestLCG` golden test |
| §4 难度 N=3/4/5 | `makeQuestion` switch + `templatesByN` |
| §5.1 模块 | 新文件 + ViewModel |
| §5.2 干扰项 | 池 + `randomMutant` |
| §5.3 集成 Bank B | Task 3 |
| §7 N 最大 5 | 无 N=6 模板 |
| §6 测试 | Task 5 |

**Known gap (acceptable YAGNI):** History `EarMcqAttemptRecord.chordDifficultyRaw` still only populated for bank A; bank B progression tier is not persisted. Add a follow-up task if analytics need it (new optional field + decode compatibility).

**Placeholder scan:** None intentional; `precondition` in generator documents failure mode if template set too small.

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-18-ear-progression-procedural-generator.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — Dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
