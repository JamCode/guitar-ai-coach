# Practice Home Flat Entries + Recent Activity Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the practice tab home “快速开始” two-hub layout with a **wireframe-aligned** layout: a **compact recent-activity summary** (rolling 7 calendar days: session count + total duration + last practice time) plus **six direct navigation rows** (视唱练耳 ×3 + 练琴 ×3), reusing existing destinations (`ForegroundPracticeSessionTracker`, `PracticeTaskRouterScreen`, `EarPracticeHubVisibility` for 视唱训练).

**Architecture:** Add **pure functions** on `PracticeSession` arrays in `PracticeModels.swift` for rolling-window stats and “latest completed” timestamp; unit-test them in `PracticeLocalStoreTests.swift`. Refactor `PracticeLandingView.content` to compose a small private summary view + two titled sections that reuse the same `NavigationLink` + `TabBarHiddenContainer` + row styling patterns already used by `PracticeLinkCard` / `EarPracticeHubScreen`. No backend; all data from existing `PracticeLandingViewModel.sessions` after `refresh()`.

**Tech Stack:** SwiftUI, iOS `SwiftEarHost` target, existing `PracticeSession` / `PracticeLocalStore` / `Ear` SPM products.

**UI reference (product):** `docs/practice-home-wireframe.png`

---

## File map (create / modify)

| File | Responsibility |
|------|----------------|
| `swift_ios_host/Sources/Practice/Models/PracticeModels.swift` | Add `computeRollingSevenDayPracticeStats` + `latestCompletedPracticeEndedAt` next to existing `computeTodayMinutes` helpers. |
| `swift_ios_host/Tests/PracticeLocalStoreTests.swift` | New XCTest cases for the two new pure functions (boundary: day -6, exclude day -7; `completed` filter; `latest` max `endedAt`). |
| `swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift` | Replace `content` stack: remove `Text("快速开始")` + `quickStartCard` HStack; add summary card + “视唱练耳” section (3–4 rows) + “练琴” section (3 rows). Keep `PracticeLandingVisibility` gates for legacy blocks unchanged unless product asks to re-enable. |
| `swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift` (`EarPracticeHubScreen`, `PracticeTrainingCatalogView`) | Optionally **delete** duplicated hub-only screens if nothing else references them; safer **first ship**: keep structs but stop linking from home (they remain reachable only from catalog if that flag turns true). |
| `swift_ios_host/docs/PracticeAcceptanceChecklist.md` (if present under `swift_ios_host/`) or repo `docs/` checklist | Add 2–3 manual acceptance bullets for new home layout + empty state. |

---

### Task 1: Rolling seven-day stats + latest session time (pure functions)

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Models/PracticeModels.swift` (append after `computeStreakDays`, before `private func isSameDay`)

- [ ] **Step 1: Write the failing tests**

**File:** `swift_ios_host/Tests/PracticeLocalStoreTests.swift` — append inside `final class PracticeLocalStoreTests`:

```swift
    func testRollingSevenDayStats_includesSixCalendarDaysBackFromStartOfToday() {
        let cal = Calendar(identifier: .gregorian)
        // Anchor: 2026-01-08 12:00 UTC — window is startOfDay(2026-01-02) ... now
        let now = ISO8601DateFormatter().date(from: "2026-01-08T12:00:00Z")!
        let inside = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!.addingTimeInterval(3600)
        let outside = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!.addingTimeInterval(3600)

        let sessions: [PracticeSession] = [
            PracticeSession(
                id: "in", taskId: "x", taskName: "x",
                startedAt: inside.addingTimeInterval(-10), endedAt: inside,
                durationSeconds: 120, completed: true, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
            PracticeSession(
                id: "out", taskId: "x", taskName: "x",
                startedAt: outside.addingTimeInterval(-10), endedAt: outside,
                durationSeconds: 999, completed: true, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
            PracticeSession(
                id: "incomplete", taskId: "x", taskName: "x",
                startedAt: now.addingTimeInterval(-20), endedAt: now,
                durationSeconds: 60, completed: false, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
        ]

        let stats = computeRollingSevenDayPracticeStats(sessions, now: now)
        XCTAssertEqual(stats.sessionCount, 1)
        XCTAssertEqual(stats.totalDurationSeconds, 120)
    }

    func testLatestCompletedPracticeEndedAt_picksMaxEndedAtAmongCompleted() {
        let t1 = ISO8601DateFormatter().date(from: "2026-01-01T10:00:00Z")!
        let t2 = ISO8601DateFormatter().date(from: "2026-01-02T10:00:00Z")!
        let sessions: [PracticeSession] = [
            PracticeSession(
                id: "a", taskId: "x", taskName: "x",
                startedAt: t1.addingTimeInterval(-1), endedAt: t1,
                durationSeconds: 1, completed: true, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
            PracticeSession(
                id: "b", taskId: "x", taskName: "x",
                startedAt: t2.addingTimeInterval(-1), endedAt: t2,
                durationSeconds: 1, completed: false, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
            PracticeSession(
                id: "c", taskId: "x", taskName: "x",
                startedAt: t2.addingTimeInterval(-1), endedAt: t2,
                durationSeconds: 1, completed: true, difficulty: 3,
                note: nil, progressionId: nil, musicKey: nil, complexity: nil,
                rhythmPatternId: nil, scaleWarmupDrillId: nil
            ),
        ]
        XCTAssertEqual(latestCompletedPracticeEndedAt(sessions), t2)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/o5l8/swift_ios_host && xcodebuild -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SwiftEarHostTests/PracticeLocalStoreTests/testRollingSevenDayStats_includesSixCalendarDaysBackFromStartOfToday test 2>&1 | tail -n 30
```

Expected: **build or link failure**, or **undefined symbol** / test not found until symbols exist. After symbols missing, Xcode reports errors on `computeRollingSevenDayPracticeStats` / `latestCompletedPracticeEndedAt`.

- [ ] **Step 3: Implement minimal functions in `PracticeModels.swift`**

Append before `private func isSameDay`:

```swift
/// 从 `now` 所在自然日往前共 7 天（含当天）：`endedAt` ∈ [startOfDay(now − 6d), `now`]，且仅 `completed == true`。
func computeRollingSevenDayPracticeStats(_ sessions: [PracticeSession], now: Date) -> (sessionCount: Int, totalDurationSeconds: Int) {
    let calendar = Calendar(identifier: .gregorian)
    let startOfToday = calendar.startOfDay(for: now)
    guard let windowStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) else {
        return (0, 0)
    }
    var sessionCount = 0
    var totalDurationSeconds = 0
    for session in sessions where session.completed {
        let ended = session.endedAt
        guard ended >= windowStart, ended <= now else { continue }
        sessionCount += 1
        totalDurationSeconds += max(0, session.durationSeconds)
    }
    return (sessionCount, totalDurationSeconds)
}

func latestCompletedPracticeEndedAt(_ sessions: [PracticeSession]) -> Date? {
    sessions.filter(\.completed).map(\.endedAt).max()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/o5l8/swift_ios_host && xcodebuild -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SwiftEarHostTests/PracticeLocalStoreTests test 2>&1 | tail -n 25
```

Expected: **Test Suite `PracticeLocalStoreTests` passed**.

- [ ] **Step 5: Commit**

```bash
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/o5l8
git add swift_ios_host/Sources/Practice/Models/PracticeModels.swift swift_ios_host/Tests/PracticeLocalStoreTests.swift
git commit -m "feat(practice): add rolling 7-day stats and latest session helpers"
```

---

### Task 2: Summary card UI + string formatting

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift` (`private var content` and new `private struct PracticeRecentSummaryCard`)

- [ ] **Step 1: Add formatter helpers (file-private)**

At bottom of `PracticeLandingView.swift` (or next to `PracticeSessionDisplay`), add:

```swift
private enum PracticeHomeCopy {
    static func rollingSummaryLine(sessionCount: Int, totalSeconds: Int) -> String {
        let minutes = max(0, totalSeconds) / 60
        let hours = minutes / 60
        let rem = minutes % 60
        let durationZh: String
        if hours > 0 {
            durationZh = rem > 0 ? "\(hours)小时\(rem)分钟" : "\(hours)小时"
        } else {
            durationZh = "\(minutes)分钟"
        }
        return "近7天 · \(sessionCount)次 · 共\(durationZh)"
    }

    static func lastPracticeLine(endedAt: Date?, now: Date = Date()) -> String {
        guard let endedAt else { return "还没有练习记录" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        if Calendar(identifier: .gregorian).isDate(endedAt, inSameDayAs: now) {
            let time = DateFormatter()
            time.locale = f.locale
            time.dateFormat = "HH:mm"
            return "上次练习：今天 \(time.string(from: endedAt))"
        }
        return "上次练习：\(f.string(from: endedAt))"
    }
}
```

- [ ] **Step 2: Add `PracticeRecentSummaryCard` view**

Still in `PracticeLandingView.swift`, above `PracticeHomeView`:

```swift
private struct PracticeRecentSummaryCard: View {
    let sessions: [PracticeSession]

    var body: some View {
        let now = Date()
        let stats = computeRollingSevenDayPracticeStats(sessions, now: now)
        let last = latestCompletedPracticeEndedAt(sessions)
        VStack(alignment: .leading, spacing: 6) {
            Text(PracticeHomeCopy.rollingSummaryLine(sessionCount: stats.sessionCount, totalSeconds: stats.totalDurationSeconds))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.text)
            Text(PracticeHomeCopy.lastPracticeLine(endedAt: last, now: now))
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SwiftAppTheme.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SwiftAppTheme.line, lineWidth: 1)
        )
    }
}
```

- [ ] **Step 3: Build only (no new tests required for pure SwiftUI layout)**

Run:

```bash
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/o5l8/swift_ios_host && xcodebuild -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build 2>&1 | tail -n 20
```

Expected: **BUILD SUCCEEDED**.

- [ ] **Step 4: Commit**

```bash
git add swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift
git commit -m "feat(practice): add practice home recent summary card copy"
```

---

### Task 3: Flatten home — six entries + wire `content`

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift` (`private var content`, approx. lines 52–100)

- [ ] **Step 1: Replace `content` body**

Use this structure (preserve existing gated blocks for `todayTrainingCard` and `全部训练项目` unchanged):

```swift
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if PracticeLandingVisibility.showTodayRecommendedTraining {
                    todayTrainingCard
                }

                PracticeRecentSummaryCard(sessions: vm.sessions)

                Text("视唱练耳")
                    .appSectionTitle()

                PracticeLinkCard(title: "音程识别", subtitle: "两音上行、四选一", icon: "play.circle") {
                    ForegroundPracticeSessionTracker(task: kIntervalEarPracticeTask, note: nil) {
                        IntervalEarView()
                    }
                }
                PracticeLinkCard(
                    title: "和弦听辨",
                    subtitle: "大三 / 小三 / 属七 · 题库离线 · 吉他采样合成",
                    icon: "pianokeys"
                ) {
                    ForegroundPracticeSessionTracker(task: kEarChordMcqPracticeTask, note: nil) {
                        EarMcqSessionView(title: "和弦听辨", bank: "A")
                    }
                }
                PracticeLinkCard(title: "和弦进行", subtitle: "常见流行进行 · 不限题量 · 指法揭示", icon: "music.note.list") {
                    ForegroundPracticeSessionTracker(task: kEarProgressionMcqPracticeTask, note: nil) {
                        EarMcqSessionView(title: "和弦进行", bank: "B")
                    }
                }
                if EarPracticeHubVisibility.showSightSingingTraining {
                    PracticeLinkCard(
                        title: "视唱训练",
                        subtitle: "立刻出题 · 齿轮内调音域与模式 · 设置自动保存",
                        icon: "mic"
                    ) {
                        ForegroundPracticeSessionTracker(task: kSightSingingPracticeTask, note: nil) {
                            SightSingingSessionView()
                        }
                    }
                }

                Text("练琴")
                    .appSectionTitle()

                ForEach(kDefaultPracticeTasks) { task in
                    PracticeLinkCard(
                        title: task.name,
                        subtitle: task.description,
                        icon: practiceHomeIcon(for: task.id)
                    ) {
                        PracticeTaskRouterScreen(task: task)
                    }
                }

                if PracticeLandingVisibility.showAllTrainingItemsLink {
                    NavigationLink {
                        TabBarHiddenContainer {
                            PracticeTrainingCatalogView()
                        }
                    } label: {
                        HStack {
                            Text("全部训练项目")
                                .font(.subheadline)
                                .foregroundStyle(SwiftAppTheme.muted)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SwiftAppTheme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .practiceScrollPageBackground()
        .refreshable { await vm.refresh(blockingUI: false) }
    }

    private func practiceHomeIcon(for taskId: String) -> String {
        switch taskId {
        case "chord-switch": return "guitars"
        case "rhythm-strum": return "waveform"
        case "scale-walk": return "hand.raised.fingers.spread"
        default: return "music.note.list"
        }
    }
```

- [ ] **Step 2: Remove dead helpers only if unused**

Delete `quickStartCard` **only after** `content` no longer references it. Grep:

```bash
grep -n "quickStartCard" /Users/wanghan/.cursor/worktrees/guitar-ai-coach/o5l8/swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift
```

If no matches, remove the entire `private func quickStartCard` method (formerly ~lines 187–212).

- [ ] **Step 3: Full test run**

```bash
cd /Users/wanghan/.cursor/worktrees/guitar-ai-coach/o5l8/swift_ios_host && xcodebuild -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -n 30
```

Expected: **All tests passed**.

- [ ] **Step 4: Commit**

```bash
git add swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift
git commit -m "feat(practice): flatten home with six entries and recent summary"
```

---

### Task 4: Docs + manual QA checklist

**Files:**
- Modify: `swift_ios_host/PracticeAcceptanceChecklist.md` **or** create `docs/practice-home-layout-acceptance.md` if the checklist path does not exist (search first).

- [ ] **Step 1: Locate checklist**

```bash
find /Users/wanghan/.cursor/worktrees/guitar-ai-coach/o5l8 -name "PracticeAcceptanceChecklist.md" 2>/dev/null
```

- [ ] **Step 2: Append bullets**

Add:

```markdown
- [ ] 练习首页首屏可见「近7天 · 次数 · 共时长」与「上次练习」行；无记录时副文案为「还没有练习记录」且不隐藏六个入口。
- [ ] 「视唱练耳」下三项可进入且返回后下拉刷新摘要变化（与本地会话写入一致）。
- [ ] 「练琴」下三项与原先 `PracticeTaskRouterScreen` 行为一致（和弦切换 / 节奏扫弦 / 爬格子）。
- [ ] `EarPracticeHubVisibility.showSightSingingTraining == false` 时首页不出现「视唱训练」行。
```

- [ ] **Step 3: Commit**

```bash
git add <path-from-step-1>
git commit -m "docs(practice): acceptance bullets for flat practice home"
```

---

## Self-review

1. **Spec coverage:** Rolling summary (7-day, count, duration, last time) → Task 1–2. Six flat entries (3 ear + 3 guitar, sight-singing gated) → Task 3. QA → Task 4. **Gap (explicit):** `EarPracticeHubScreen` / `GuitarPracticeHubScreen` become **unlinked** from home; they remain valid compile targets for catalog / deep links — if product requires deleting them, add a follow-up Task 5 “remove dead structs + fix references”.
2. **Placeholder scan:** None intentional; stats definition is fixed to **近7天** per wireframe caption.
3. **Type consistency:** Uses existing `PracticeLinkCard`, `ForegroundPracticeSessionTracker`, `PracticeTaskRouterScreen`, `kIntervalEarPracticeTask`, etc., already in repo.

---

**Plan complete and saved to** `docs/superpowers/plans/2026-04-22-practice-home-flat-six-entries-summary.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. **REQUIRED SUB-SKILL:** `superpowers:subagent-driven-development`.

2. **Inline Execution** — run tasks in this session with checkpoints. **REQUIRED SUB-SKILL:** `superpowers:executing-plans`.

**Which approach?**
