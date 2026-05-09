# Strumming Timing Model (Eighth Unit) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade strumming patterns from plain `cells[8]` to an event-based timing model (`action + eighth-note units`) so patterns can express "下 = 一拍" and "下上 = 一拍", while keeping the current 4/4 UI and compatibility.

**Architecture:** Keep `cells` as compatibility/display output, add `events` as canonical timing source, and derive `cells` from `events` through a single expansion function. Update pattern definitions to use events-first construction. Update six-line staff rendering to show sustain/hold slots for multi-unit events.

**Tech Stack:** Swift, SwiftUI, XCTest, existing `swift_ios_host` target (`SwiftEarHost`).

**Spec Inputs:**
- `docs/cursor/48e3c1e5/specs/2026-04-21-strumming-tab-staff-a-design.md`
- `docs/cursor/48e3c1e5/specs/2026-04-21-strumming-timing-unit-eighth-design.md`

---

## File structure and responsibility

- Modify: `swift_ios_host/Sources/Practice/Models/StrummingPattern.swift`
  - Add timing event types.
  - Add event validation and `events -> cells` expansion.
  - Convert built-in patterns to events-first declarations.

- Modify: `swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift`
  - Update tab-staff renderer to use event timing for sustain slot rendering.
  - Keep glyph mapping and six-line orientation unchanged (① top, ⑥ bottom).

- Modify: `swift_ios_host/Tests/StrummingPatternGeneratorTests.swift`
  - Add timing integrity tests (unit sum = 8 in 4/4).
  - Add expansion tests for one-beat down vs one-beat down-up behavior.

- Modify: `swift_ios_host/Tests/PracticeAcceptanceChecklist.md`
  - Add acceptance bullets for timing semantics ("下=一拍", "下上=一拍").

---

### Task 1: Introduce timing event model in `StrummingPattern`

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Models/StrummingPattern.swift`
- Test: `swift_ios_host/Tests/StrummingPatternGeneratorTests.swift`

- [ ] **Step 1: Write failing tests for timing model**

Add test skeletons in `StrummingPatternGeneratorTests.swift`:

```swift
func testAllBuiltInPatterns_totalUnitsEqualsEightIn44() {
    for p in kStrummingPatterns {
        XCTAssertEqual(p.events.reduce(0) { $0 + $1.units }, 8, "pattern=\(p.id)")
    }
}

func testExpandEvents_downOneBeat_thenDownUpOneBeat() {
    let events: [StrumActionEvent] = [
        .init(kind: .down, units: 2), // 1 beat
        .init(kind: .down, units: 1), // half beat
        .init(kind: .up, units: 1),   // half beat
        .init(kind: .rest, units: 4), // remaining 2 beats
    ]
    let cells = expandStrumEventsToCells(events, totalUnits: 8)
    XCTAssertEqual(cells.count, 8)
    XCTAssertEqual(cells, [.down, .down, .up, .rest, .rest, .rest, .rest, .rest])
}
```

- [ ] **Step 2: Run target tests to observe failure**

```bash
cd swift_ios_host && xcodebuild test -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,id=16601DEE-6179-4349-B580-C2FECC9339A1' -only-testing:SwiftEarHostTests/StrummingPatternGeneratorTests
```

Expected pre-implementation failure: missing `events`, `StrumActionEvent`, `expandStrumEventsToCells`.

- [ ] **Step 3: Add event types and expansion helpers**

In `StrummingPattern.swift`, add:

```swift
enum StrumActionKind: String, Codable, Hashable {
    case down
    case up
    case rest
    case mute
}

struct StrumActionEvent: Codable, Equatable, Hashable {
    let kind: StrumActionKind
    let units: Int // smallest unit: eighth note
}

func expandStrumEventsToCells(_ events: [StrumActionEvent], totalUnits: Int = 8) -> [StrumCellKind] {
    var cells: [StrumCellKind] = []
    for e in events {
        guard e.units > 0 else { continue }
        let cellKind: StrumCellKind = switch e.kind {
        case .down: .down
        case .up: .up
        case .rest, .mute: .rest
        }
        // First slot uses action, remaining slots are sustain placeholders.
        cells.append(cellKind)
        if e.units > 1 {
            cells.append(contentsOf: Array(repeating: .rest, count: e.units - 1))
        }
    }
    if cells.count < totalUnits {
        cells.append(contentsOf: Array(repeating: .rest, count: totalUnits - cells.count))
    }
    return Array(cells.prefix(totalUnits))
}
```

- [ ] **Step 4: Extend `StrummingPattern` to include `events`**

Add field:

```swift
let events: [StrumActionEvent]
```

Introduce helper constructor to avoid repetitive manual `cells`:

```swift
private func makePattern(
    id: String,
    name: String,
    subtitle: String,
    tip: String,
    difficulty: StrummingDifficulty,
    events: [StrumActionEvent]
) -> StrummingPattern {
    let total = events.reduce(0) { $0 + $1.units }
    precondition(total == 8, "4/4 + eighth unit requires exactly 8 units: \(id)")
    return StrummingPattern(
        id: id,
        name: name,
        subtitle: subtitle,
        tip: tip,
        difficulty: difficulty,
        cells: expandStrumEventsToCells(events, totalUnits: 8),
        events: events
    )
}
```

- [ ] **Step 5: Convert built-in pattern declarations to events-first**

For each pattern, replace direct `cells:` with `events:` via `makePattern(...)`.

Examples:

```swift
// every-beat down (4 beats)
events: [.init(kind: .down, units: 2), .init(kind: .down, units: 2), .init(kind: .down, units: 2), .init(kind: .down, units: 2)]

// D U D U ... (all eighth)
events: Array(repeating: [.init(kind: .down, units: 1), .init(kind: .up, units: 1)], count: 4).flatMap { $0 }
```

Keep existing IDs unless explicitly renamed.

- [ ] **Step 6: Run target tests; ensure pass**

Run same command as Step 2.

- [ ] **Step 7: Commit Task 1**

```bash
git add swift_ios_host/Sources/Practice/Models/StrummingPattern.swift swift_ios_host/Tests/StrummingPatternGeneratorTests.swift
git commit -m "feat(practice): add event-based strumming timing model (eighth units)"
```

---

### Task 2: Update six-line staff rendering for timing semantics

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift`

- [ ] **Step 1: Add expansion for UI slots from `pattern.events`**

Create local display slot model:

```swift
private struct StrumDisplaySlot {
    let glyph: StrummingTabStaffGlyph
    let isPrimary: Bool
}
```

And converter:

```swift
private func makeDisplaySlots(from events: [StrumActionEvent], totalUnits: Int = 8) -> [StrumDisplaySlot]
```

Rules:
- first unit in event: `isPrimary = true`, show glyph.
- remaining units in same event: `isPrimary = false`, show hold marker (e.g., "—" or faint "·").

- [ ] **Step 2: Render tab staff from display slots (not raw `cells`)**

`StrummingTabStaffView` should accept `events`:

```swift
StrummingTabStaffView(events: pattern.events, beatLabels: beatLabels)
```

Preserve:
- string order text (`①..⑥`)
- legend (`↑ 下扫, ↓ 上扫, · 空拍`)
- six-line background and spacing.

- [ ] **Step 3: Add legend note for timing**

Add concise hint:

```swift
Text("同一动作跨一拍时，首格显示箭头，后续格显示延续占位。")
```

- [ ] **Step 4: Run full test suite**

```bash
cd swift_ios_host && xcodebuild test -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,id=16601DEE-6179-4349-B580-C2FECC9339A1' -only-testing:SwiftEarHostTests
```

- [ ] **Step 5: Commit Task 2**

```bash
git add swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift
git commit -m "feat(practice): render strumming tab staff from timing events"
```

---

### Task 3: Acceptance checklist alignment

**Files:**
- Modify: `swift_ios_host/Tests/PracticeAcceptanceChecklist.md`

- [ ] **Step 1: Add timing-specific acceptance bullets**

Under "节奏扫弦", add:
- "下=一拍" case displays one primary glyph + one sustain slot.
- "下上=一拍" case displays two primary glyphs within that beat.
- mapping remains `↑/↓/·`.

- [ ] **Step 2: Commit Task 3**

```bash
git add swift_ios_host/Tests/PracticeAcceptanceChecklist.md
git commit -m "docs(practice): add strumming timing semantics acceptance items"
```

---

## Final verification

- [ ] `StrummingPatternGeneratorTests` pass with new timing tests.
- [ ] `SwiftEarHostTests` pass.
- [ ] Existing IDs remain resolvable for saved history (`strummingPatternNameForId` unchanged behavior).
- [ ] UI in simulator confirms:
  - ① top / ⑥ bottom,
  - ↓↑ mapping unchanged per existing spec,
  - visible difference between one-beat action and two half-beat actions.

---

## Plan self-review

**Spec coverage:** Includes eighth-unit modeling, validation to 8 units, and UI differentiation for duration semantics.  
**Placeholders:** None; all steps contain concrete files/commands.  
**Consistency:** Single source (`events`) with derived `cells`; avoids dual-authoring drift.

---

## Execution handoff

Plan complete and saved to `docs/cursor/48e3c1e5/plans/2026-04-21-strumming-timing-unit-eighth-implementation.md`.

Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration  
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

