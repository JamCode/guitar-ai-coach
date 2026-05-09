# Strumming Tab Staff (A Style) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current 8-chip strumming grid in `RhythmStrummingView` with an A-style six-line tab-staff visual (time markers + arrows/dot), with fixed string order `① top -> ⑥ bottom`, and mapping `down -> ↑`, `up -> ↓`, `rest -> ·`.

**Architecture:** Keep all practice data and generation logic unchanged (`StrummingPattern.cells` remains 8 slots). Only refactor the view layer in `RhythmStrummingView` by introducing a dedicated tab-staff renderer and a small glyph-mapping helper that can be tested from existing unit tests.

**Tech Stack:** SwiftUI, Swift/XCTest, existing `swift_ios_host` target and `SwiftEarHostTests`.

---

## File map

- Modify: `swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift`
- Modify: `swift_ios_host/Tests/StrummingPatternGeneratorTests.swift`
- Modify: `swift_ios_host/Tests/PracticeAcceptanceChecklist.md`

No new model fields, no migration, no storage changes.

---

### Task 1: Add and verify glyph mapping rules

**Files:**
- Modify: `swift_ios_host/Tests/StrummingPatternGeneratorTests.swift`
- Modify: `swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift`

- [ ] **Step 1: Write failing tests for mapping**

Append tests in `StrummingPatternGeneratorTests.swift`:

```swift
func testTabStaffGlyphMapping_matchesAStyleSpec() {
    XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .down), .downStroke)
    XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .up), .upStroke)
    XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .rest), .rest)

    XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .down).symbol, "↑") // 下扫
    XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .up).symbol, "↓")   // 上扫
    XCTAssertEqual(StrummingTabStaffGlyph.from(kind: .rest).symbol, "·") // 空拍
}
```

- [ ] **Step 2: Run targeted tests (expect fail first)**

Run:

```bash
cd swift_ios_host && xcodebuild test -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,id=16601DEE-6179-4349-B580-C2FECC9339A1' -only-testing:SwiftEarHostTests/StrummingPatternGeneratorTests
```

Expected before implementation: compile failure (`StrummingTabStaffGlyph` not found).

- [ ] **Step 3: Implement mapping helper in view file**

Add internal helper in `RhythmStrummingView.swift`:

```swift
enum StrummingTabStaffGlyph: Equatable {
    case downStroke
    case upStroke
    case rest

    static func from(kind: StrumCellKind) -> Self {
        switch kind {
        case .down: return .downStroke   // 下扫
        case .up: return .upStroke       // 上扫
        case .rest: return .rest
        }
    }

    var symbol: String {
        switch self {
        case .downStroke: return "↑"
        case .upStroke: return "↓"
        case .rest: return "·"
        }
    }
}
```

- [ ] **Step 4: Re-run targeted tests (expect pass)**

Run same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift swift_ios_host/Tests/StrummingPatternGeneratorTests.swift
git commit -m "test(practice): lock strumming tab staff glyph mapping"
```

---

### Task 2: Replace chip grid with A-style six-line tab staff

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift`

- [ ] **Step 1: Replace `StrummingGrid` usage**

In card section, replace:

```swift
StrummingGrid(cells: pattern.cells, beatLabels: beatLabels)
```

with:

```swift
StrummingTabStaffView(cells: pattern.cells, beatLabels: beatLabels)
```

- [ ] **Step 2: Implement `StrummingTabStaffView` (A style)**

Implement a dedicated renderer:

```swift
private struct StrummingTabStaffView: View {
    let cells: [StrumCellKind]
    let beatLabels: [String]

    private let stringLabels = ["①", "②", "③", "④", "⑤", "⑥"] // ①上、⑥下（最粗）

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(0..<8, id: \.self) { i in
                    Spacer(minLength: 0)
                    Text(beatLabels[i]).font(.caption).foregroundStyle(SwiftAppTheme.muted)
                    Spacer(minLength: 0)
                }
            }

            ZStack {
                VStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { _ in
                        Rectangle().fill(SwiftAppTheme.line).frame(height: 1)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        Text(StrummingTabStaffGlyph.from(kind: cells[safe: i] ?? .rest).symbol)
                            .font(.system(size: 24, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(height: 92)
            .padding(10)
            .background(SwiftAppTheme.surfaceSoft.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(SwiftAppTheme.line, lineWidth: 1)
            )

            Text("图例：↑ 下扫，↓ 上扫，· 空拍；弦序为 ① 在上、⑥ 在下（最粗弦）。")
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
        }
    }
}
```

- [ ] **Step 3: Remove obsolete chip-only views**

Delete/replace `StrumCellChip` and old `StrummingGrid` implementation blocks if no longer used, ensuring the file remains focused and warning-free.

- [ ] **Step 4: Run full host tests**

```bash
cd swift_ios_host && xcodebuild test -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,id=16601DEE-6179-4349-B580-C2FECC9339A1' -only-testing:SwiftEarHostTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add swift_ios_host/Sources/Practice/Views/RhythmStrummingView.swift
git commit -m "feat(practice): replace strumming chips with A-style tab staff"
```

---

### Task 3: Update acceptance checklist for new UI contract

**Files:**
- Modify: `swift_ios_host/Tests/PracticeAcceptanceChecklist.md`

- [ ] **Step 1: Update strumming section bullets**

Replace chip-centric wording with staff-centric wording, including:
- six lines visible
- string order `① top / ⑥ bottom`
- symbol legend and direction mapping (`↑=下扫`, `↓=上扫`, `·=空拍`)

- [ ] **Step 2: Commit Task 3**

```bash
git add swift_ios_host/Tests/PracticeAcceptanceChecklist.md
git commit -m "docs(practice): update strumming acceptance for tab staff"
```

---

## Verification checklist before handoff

- [ ] `StrummingPatternGeneratorTests` includes mapping assertions and passes.
- [ ] `RhythmStrummingView` shows A-style six-line staff in place of chips.
- [ ] Full `SwiftEarHostTests` pass.
- [ ] Acceptance checklist reflects new visual contract.

---

## Plan self-review

### 1) Spec coverage
- Replace red-box UI: covered by Task 2.
- Keep existing data model: enforced by file map and no model changes.
- String order and arrow semantics: covered by Task 1 + Task 2.
- A-style simplified scope only: no rhythm beam/complex notation steps included.

### 2) Placeholder scan
- No `TODO/TBD/later` placeholders remain.
- Each task has explicit files and commands.

### 3) Type consistency
- `StrummingTabStaffGlyph` naming is consistent across tests and implementation.
- Mapping symbols are fixed in one helper to prevent divergence.

---

## Execution handoff

Plan complete and saved to `docs/cursor/48e3c1e5/plans/2026-04-21-strumming-tab-staff-a-implementation.md`.

Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration  
2. **Inline Execution** - Execute tasks in this session using `executing-plans`, batch execution with checkpoints

Which approach?

