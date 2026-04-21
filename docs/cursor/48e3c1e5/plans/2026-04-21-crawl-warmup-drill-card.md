# Crawl warmup drill cards (`scale-walk`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the empty `PracticeTimerSessionView` experience for task `scale-walk` (“爬格子热身”) with a **RhythmStrummingView-style** page: random **drill card** per entry and on “下一组”, **初/中/高** in a gear sheet (persisted), **suggested BPM text only**, **timer + finish/save** matching `PracticeTimerSessionView`, and persist **`scaleWarmupDrillId`** on `PracticeSession` like `rhythmPatternId`.

**Architecture:** Add `ScaleWarmupDrill` + `ScaleWarmupGenerator` (pure Swift, testable). Add `ScaleWarmupSessionView` (SwiftUI) that composes cards + timer + settings sheet + `PracticeFinishDialog`. Extend `PracticeSession` / `PracticeSessionStore` / `PracticeLocalStore` JSON for the new optional id. Route `scale-walk` in `PracticeTaskRouterScreen` to the new view.

**Tech stack:** Swift 5+, SwiftUI, Swift iOS Host target `SwiftEarHost`, XCTest, `UserDefaults` JSON sessions (existing `PracticeLocalStore`).

**Spec:** `docs/cursor/48e3c1e5/specs/2026-04-21-crawl-warmup-drill-card-design.md` (user-approved).

---

## File map (create / modify)

| Path | Role |
|------|------|
| `swift_ios_host/Sources/Practice/Models/ScaleWarmupDrill.swift` | **Create.** `ScaleWarmupDifficulty`, `ScaleWarmupDrill`, `ScaleWarmupGenerator` (+ static pools, `nextDrill`). |
| `swift_ios_host/Sources/Practice/Views/ScaleWarmupSessionView.swift` | **Create.** Main UI: drill card, timer, gear, next drill, finish flow. |
| `swift_ios_host/Tests/ScaleWarmupGeneratorTests.swift` | **Create.** Generator unit tests. |
| `swift_ios_host/Sources/Practice/Models/PracticeModels.swift` | **Modify.** Add `scaleWarmupDrillId: String?` to `PracticeSession`. |
| `swift_ios_host/Sources/Practice/Store/PracticeSessionStore.swift` | **Modify.** Add `scaleWarmupDrillId: String?` parameter to `saveSession`. |
| `swift_ios_host/Sources/Practice/Store/PracticeLocalStore.swift` | **Modify.** Encode/decode key `scaleWarmupDrillId`; pass through in `saveSession` / `decodeSessionDict`. |
| `swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift` | **Modify.** `PracticeTaskRouterScreen`: `case "scale-walk"` → `ScaleWarmupSessionView`. |
| `swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift` | **Modify.** Update `saveSession` call with trailing `scaleWarmupDrillId: nil`. |
| `swift_ios_host/Sources/Practice/Views/PracticeTimerSessionView.swift` | **Modify.** Same. |
| `swift_ios_host/Sources/Sheets/Views/SheetLibraryView.swift` | **Modify.** Same. |
| `swift_ios_host/Tests/PracticeLocalStoreTests.swift` | **Modify.** All `PracticeSession(...)` literals add `scaleWarmupDrillId: nil`; add one decode test with non-nil id. |
| `swift_ios_host/SwiftEarHost.xcodeproj/project.pbxproj` | **Modify.** Register new Swift sources + test file (mirror `StrummingPattern.swift` / `StrummingPatternGeneratorTests.swift` entries: `PBXFileReference`, `PBXBuildFile`, `PBXGroup` “Practice”, both targets’ `PBXSourcesBuildPhase`). |

---

### Task 1: `ScaleWarmupGenerator` + failing tests (TDD)

**Files:**

- Create: `swift_ios_host/Sources/Practice/Models/ScaleWarmupDrill.swift`
- Create: `swift_ios_host/Tests/ScaleWarmupGeneratorTests.swift`
- Modify: `swift_ios_host/SwiftEarHost.xcodeproj/project.pbxproj` (minimum: add test file to **SwiftEarHostTests** so `xcodebuild test` compiles tests; you may defer app target entries until Task 3 if you prefer two-step compile—prefer **one pbxproj edit** after Task 1 that adds **both** new source files to `SwiftEarHost` and test file to `SwiftEarHostTests`.)

- [ ] **Step 1: Write the failing test file**

Create `swift_ios_host/Tests/ScaleWarmupGeneratorTests.swift`:

```swift
import XCTest
@testable import SwiftEarHost

final class ScaleWarmupGeneratorTests: XCTestCase {
    func testPools_nonEmptyPerDifficulty() {
        for d in ScaleWarmupDifficulty.allCases {
            XCTAssertFalse(ScaleWarmupGenerator.drills(for: d).isEmpty, "\(d)")
        }
    }

    func testNext_avoidsImmediateRepeatWhenPoolHasMultiple() {
        var rng = SystemRandomNumberGenerator()
        let difficulty = ScaleWarmupDifficulty.初级
        let first = ScaleWarmupGenerator.nextDrill(difficulty: difficulty, excluding: nil, using: &rng)
        let second = ScaleWarmupGenerator.nextDrill(difficulty: difficulty, excluding: first.id, using: &rng)
        let pool = ScaleWarmupGenerator.drills(for: difficulty)
        if pool.count > 1 {
            XCTAssertNotEqual(first.id, second.id)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd swift_ios_host && xcodebuild test -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SwiftEarHostTests/ScaleWarmupGeneratorTests 2>&1
```

**Expected:** compile error (`ScaleWarmupDifficulty` / `ScaleWarmupGenerator` not found), or linker error if types missing. Fix destination name if needed (`xcodebuild -showdestinations`).

- [ ] **Step 3: Add model + generator implementation**

Create `swift_ios_host/Sources/Practice/Models/ScaleWarmupDrill.swift`:

```swift
import Foundation

/// 与节奏扫弦一致的三档中文难度（rawValue 用于 Picker 展示）。
enum ScaleWarmupDifficulty: String, CaseIterable, Identifiable {
    case 初级, 中级, 高级
    var id: String { rawValue }
}

/// 单次随机题卡（可持久化 `id` 到练习记录）。
struct ScaleWarmupDrill: Equatable, Sendable {
    let id: String
    let stringsLabel: String
    let fretLabel: String
    let patternLabel: String
    let suggestedBpm: Int
    let roundsHint: String
    let tip: String

    var titleLine: String { "\(stringsLabel) · \(fretLabel)" }
    var detailLine: String { "\(patternLabel) · 建议 \(suggestedBpm) BPM · \(roundsHint)" }
}

enum ScaleWarmupGenerator {
    /// 暴露给测试：各难度静态池（至少 2 条/档，便于去重测试）。
    static func drills(for difficulty: ScaleWarmupDifficulty) -> [ScaleWarmupDrill] {
        switch difficulty {
        case .初级:
            return [
                ScaleWarmupDrill(
                    id: "crawl_b_6_4_68",
                    stringsLabel: "⑥–④弦",
                    fretLabel: "1–4 品",
                    patternLabel: "半音四品型（上行）",
                    suggestedBpm: 68,
                    roundsHint: "建议 4 轮",
                    tip: "力度均匀，换品时贴弦减少杂音。"
                ),
                ScaleWarmupDrill(
                    id: "crawl_b_5_4_64",
                    stringsLabel: "⑤–③弦",
                    fretLabel: "1–3 品",
                    patternLabel: "半音三品型（上行）",
                    suggestedBpm: 64,
                    roundsHint: "建议 3 轮",
                    tip: "左手保留指能留则留，减少跳指。"
                ),
            ]
        case .中级:
            return [
                ScaleWarmupDrill(
                    id: "crawl_m_6_6_80",
                    stringsLabel: "⑥–③弦",
                    fretLabel: "1–6 品",
                    patternLabel: "半音四品型（跨弦）",
                    suggestedBpm: 80,
                    roundsHint: "建议 5 轮",
                    tip: "换弦时拇指在琴颈后方稳定支撑。"
                ),
                ScaleWarmupDrill(
                    id: "crawl_m_6_8_84",
                    stringsLabel: "⑥–③弦",
                    fretLabel: "3–8 品",
                    patternLabel: "半音四品型（往返）",
                    suggestedBpm: 84,
                    roundsHint: "建议 4 轮",
                    tip: "下行同样控制音量，避免「砸」弦。"
                ),
            ]
        case .高级:
            return [
                ScaleWarmupDrill(
                    id: "crawl_a_6_12_96",
                    stringsLabel: "⑥–②弦",
                    fretLabel: "1–12 品",
                    patternLabel: "半音四品型（全弦跨度）",
                    suggestedBpm: 96,
                    roundsHint: "建议 6 轮",
                    tip: "高把位注意指尖立起，避免蹭相邻弦。"
                ),
                ScaleWarmupDrill(
                    id: "crawl_a_6_12_100",
                    stringsLabel: "⑥–②弦",
                    fretLabel: "5–12 品",
                    patternLabel: "半音四品型（把位平移）",
                    suggestedBpm: 100,
                    roundsHint: "建议 5 轮",
                    tip: "换把时先慢后快，优先干净再提速。"
                ),
            ]
        }
    }

    static func nextDrill(
        difficulty: ScaleWarmupDifficulty,
        excluding: String?,
        using rng: inout some RandomNumberGenerator
    ) -> ScaleWarmupDrill {
        let pool = drills(for: difficulty)
        let candidates = pool.filter { $0.id != excluding }
        let pickFrom = candidates.isEmpty ? pool : candidates
        let idx = pickFrom.indices.randomElement(using: &rng)!
        return pickFrom[idx]
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Same `xcodebuild` command as Step 2.

**Expected:** `ScaleWarmupGeneratorTests` passes.

- [ ] **Step 5: Commit**

```bash
git add swift_ios_host/Sources/Practice/Models/ScaleWarmupDrill.swift \
        swift_ios_host/Tests/ScaleWarmupGeneratorTests.swift \
        swift_ios_host/SwiftEarHost.xcodeproj/project.pbxproj
git commit -m "feat(practice): add scale crawl warmup drill generator"
```

---

### Task 2: Persist `scaleWarmupDrillId` on `PracticeSession`

**Files:**

- Modify: `swift_ios_host/Sources/Practice/Models/PracticeModels.swift`
- Modify: `swift_ios_host/Sources/Practice/Store/PracticeSessionStore.swift`
- Modify: `swift_ios_host/Sources/Practice/Store/PracticeLocalStore.swift`
- Modify: `swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift`
- Modify: `swift_ios_host/Sources/Practice/Views/PracticeTimerSessionView.swift`
- Modify: `swift_ios_host/Sources/Sheets/Views/SheetLibraryView.swift`
- Modify: `swift_ios_host/Tests/PracticeLocalStoreTests.swift`

- [ ] **Step 1: Extend `PracticeSession`**

In `PracticeModels.swift`, add after `rhythmPatternId`:

```swift
    /// 爬格子热身题卡 id（可空，兼容旧数据）。
    let scaleWarmupDrillId: String?
```

Update **every** `PracticeSession(` initializer in the repo (grep) to pass `scaleWarmupDrillId: nil` except new tests you add.

- [ ] **Step 2: Extend store protocol + local store JSON**

`PracticeSessionStore.saveSession` signature: add final parameter:

```swift
        scaleWarmupDrillId: String?
```

Implement in `PracticeLocalStore.saveSession`:

- Thread into `PracticeSession(..., scaleWarmupDrillId: scaleWarmupDrillId)`.

In `encodeSessions`:

```swift
        if let scaleWarmupDrillId = s.scaleWarmupDrillId { m["scaleWarmupDrillId"] = scaleWarmupDrillId }
```

In `decodeSessionDict`:

```swift
    let scaleWarmupDrillId = dict["scaleWarmupDrillId"] as? String
```

and pass into `PracticeSession(...)`.

- [ ] **Step 3: Update all `saveSession` call sites**

Append `scaleWarmupDrillId: nil` to:

- `RhythmStrummingView.save`
- `PracticeTimerSessionView.save`
- `SheetLibraryView` auto-save block

(Until Task 3, all remain `nil`.)

- [ ] **Step 4: Add decode test for new key**

In `PracticeLocalStoreTests.swift`, add:

```swift
    func testDecodeSessions_acceptsScaleWarmupDrillId() {
        let raw: [String: Any] = [
            "id": "1",
            "taskId": "scale-walk",
            "taskName": "爬格子热身",
            "startedAt": "2026-01-01T00:00:00Z",
            "endedAt": "2026-01-01T00:01:00Z",
            "durationSeconds": 60,
            "completed": true,
            "difficulty": 3,
            "scaleWarmupDrillId": "crawl_b_6_4_68",
        ]
        let data = try! JSONSerialization.data(withJSONObject: [raw], options: [])
        let sessions = decodeSessions(String(data: data, encoding: .utf8)!)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.scaleWarmupDrillId, "crawl_b_6_4_68")
    }
```

Update existing `PracticeSession(...)` fixtures in the same file: add `scaleWarmupDrillId: nil`.

- [ ] **Step 5: Run tests**

```bash
cd swift_ios_host && xcodebuild test -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SwiftEarHostTests/PracticeLocalStoreTests 2>&1
```

**Expected:** PASS.

- [ ] **Step 6: Commit**

```bash
git add swift_ios_host/Sources/Practice/Models/PracticeModels.swift \
        swift_ios_host/Sources/Practice/Store/PracticeSessionStore.swift \
        swift_ios_host/Sources/Practice/Store/PracticeLocalStore.swift \
        swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift \
        swift_ios_host/Sources/Practice/Views/PracticeTimerSessionView.swift \
        swift_ios_host/Sources/Sheets/Views/SheetLibraryView.swift \
        swift_ios_host/Tests/PracticeLocalStoreTests.swift
git commit -m "feat(practice): persist scaleWarmupDrillId on practice sessions"
```

---

### Task 3: `ScaleWarmupSessionView` + routing + pbxproj sources

**Files:**

- Create: `swift_ios_host/Sources/Practice/Views/ScaleWarmupSessionView.swift`
- Modify: `swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift`
- Modify: `swift_ios_host/SwiftEarHost.xcodeproj/project.pbxproj` (if not already added in Task 1)

- [ ] **Step 1: Implement the SwiftUI view**

Create `ScaleWarmupSessionView.swift` modeled on `RhythmStrummingView.swift` + timer from `PracticeTimerSessionView.swift`:

**State:**

- `@AppStorage("practice.scaleWarmup.difficultyRaw") private var difficultyRaw: String = ScaleWarmupDifficulty.初级.rawValue`
- Computed `selectedDifficulty: ScaleWarmupDifficulty` get/set via `rawValue`.
- `@State private var drill: ScaleWarmupDrill`
- `@State private var openedAt: Date = Date()`
- `@State` mirror timer: `startedAt`, `elapsedSeconds`, `running`, `ticker` (`Timer.publish(every: 1, on: .main, in: .common).autoconnect()`)
- Sheets/alerts: `showSettings`, `showFinishSheet`, `noteText`, `showNeedStartHint`, `savingError`, `savedToast` — same patterns as the two reference views.

**Layout (inside `ScrollView`):**

1. `Text(task.description)` (muted/leading).
2. Card “本组练习”: section title + capsule shows `selectedDifficulty.rawValue`; `Text(drill.titleLine)` semibold; `Text(drill.detailLine)` subheadline; `Text(drill.tip)` footnote muted.
3. Card “计时”: large `mm:ss` (`formatDuration` — copy private helper from `PracticeTimerSessionView` or share `PracticeLandingView` static if already public; duplicating 6 lines is OK).
4. HStack buttons: 开始 / 暂停 / 结束 — same enable rules as timer view.
5. `Button("下一组")` → `nextDrill()` using `SystemRandomNumberGenerator()`.

**Lifecycle:**

- `.onAppear`: `nextDrill(excluding: nil)` **or** set initial drill in `init` — ensure first paint has a drill.
- `.onChange(of: selectedDifficulty)`: `nextDrill(excluding: nil)` to force new pool.

**Toolbar:**

- Leading back `dismiss()` (same as `RhythmStrummingView`).
- Trailing gear opens `Form` with `Picker` for `ScaleWarmupDifficulty` + footnote “变更后立即按该难度抽新题卡。” + short “图示说明” section stating **no built-in metronome audio** (same product line as strumming).

**Finish:**

- `finishTapped`: require `elapsedSeconds > 0` else alert “先开始练习再结束哦”.
- `PracticeFinishDialog`: use title `"本次练习"` and `showCompletedGoal: false` to match `RhythmStrummingView` (timer-based completion is ambiguous).
- `save`: `durationSeconds: elapsedSeconds`, `rhythmPatternId: nil`, **`scaleWarmupDrillId: drill.id`**.

**Imports:** `SwiftUI`, `Core`.

- [ ] **Step 2: Wire router**

In `PracticeLandingView.swift` `PracticeTaskRouterScreen.body`:

```swift
        case "scale-walk":
            ScaleWarmupSessionView(task: task, store: store)
```

- [ ] **Step 3: Xcode project membership**

Ensure `ScaleWarmupDrill.swift` and `ScaleWarmupSessionView.swift` are in **SwiftEarHost** target `Sources` phase (if not done in Task 1). Use existing `StrummingPattern.swift` / `RhythmStrummingView.swift` entries as templates in `project.pbxproj`.

- [ ] **Step 4: Build + full host tests**

```bash
cd swift_ios_host && xcodebuild test -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SwiftEarHostTests 2>&1
```

**Expected:** all `SwiftEarHostTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add swift_ios_host/Sources/Practice/Views/ScaleWarmupSessionView.swift \
        swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift \
        swift_ios_host/SwiftEarHost.xcodeproj/project.pbxproj
git commit -m "feat(practice): scale crawl warmup session with drill cards"
```

---

### Task 4: Spec / checklist touch-up (optional but recommended)

**Files:**

- Modify: `swift_ios_host/Tests/PracticeAcceptanceChecklist.md` (add 1–3 bullets: drill card visible, next drill, gear difficulty, saved record contains drill id)

- [ ] **Step 1: Edit checklist** to match new UX.

- [ ] **Step 2: Commit**

```bash
git add swift_ios_host/Tests/PracticeAcceptanceChecklist.md
git commit -m "docs(practice): update acceptance checklist for crawl warmup"
```

---

## Plan self-review (spec coverage)

| Spec section | Task |
|--------------|------|
| Random card on entry + “下一组” | Task 1 pools, Task 3 `onAppear` + button |
| Difficulty gear 初/中/高 + remember | Task 3 `@AppStorage` + sheet |
| No built-in metronome audio | Task 3 settings copy |
| Timer + finish parity with timer view | Task 3 copied controls + same guard |
| `scaleWarmupDrillId` persistence | Task 2 + Task 3 save |
| Tests | Tasks 1–2 |

**Placeholder scan:** none intentional; all file paths explicit.

**Type consistency:** `ScaleWarmupDifficulty` used in generator, tests, and SwiftUI binding — same name throughout.

---

## Execution handoff

Plan complete and saved to `docs/cursor/48e3c1e5/plans/2026-04-21-crawl-warmup-drill-card.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration (**skill:** `superpowers:subagent-driven-development`).
2. **Inline Execution** — run tasks in this session with checkpoints (**skill:** `superpowers:executing-plans`).

**Which approach do you want?**
