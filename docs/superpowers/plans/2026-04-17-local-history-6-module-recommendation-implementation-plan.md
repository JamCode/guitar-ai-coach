# Local History 6-Module Recommendation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-history-driven daily recommendation planner that outputs one generated item for each of six procedural modules and assigns per-module difficulty (初级/中级/高级).

**Architecture:** Add a Core recommendation pipeline with three layers: history ingestion (`RecommendationHistoryStore`), scoring (`RecommendationDifficultyAdvisor`), and orchestration (`TodayRecommendationPlanner`). Keep generation adapters thin and reuse existing generators in `Ear` and `Practice` domains. Persist module outcomes locally so next-day recommendations can be computed without backend data.

**Tech Stack:** Swift 5.10, Swift Package targets (`Core`, `Ear`, new `Practice`), XCTest unit + integration tests, UserDefaults local persistence.

---

## File Structure

- Create: `swift_app/Sources/Core/RecommendationModels.swift`
- Create: `swift_app/Sources/Core/RecommendationHistoryStore.swift`
- Create: `swift_app/Sources/Core/RecommendationDifficultyAdvisor.swift`
- Create: `swift_app/Sources/Core/TodayRecommendationPlanner.swift`
- Create: `swift_app/Sources/Features/Practice/PracticeModels.swift`
- Create: `swift_app/Sources/Features/Practice/ChordSwitchGenerator.swift`
- Create: `swift_app/Sources/Features/Practice/ScaleTrainingGenerator.swift`
- Create: `swift_app/Sources/Features/Practice/TraditionalCrawlGenerator.swift`
- Modify: `swift_app/Package.swift` (add `Practice` library target + dependencies)
- Modify: `swift_app/Sources/Features/Ear/IntervalEarSessionViewModel.swift` (emit completion records)
- Modify: `swift_app/Sources/Features/Ear/EarMcqSessionViewModel.swift` (emit completion records)
- Modify: `swift_app/Sources/Features/Ear/SightSingingSessionViewModel.swift` (emit completion records)
- Modify: `swift_app/Sources/App/ToolsHomeView.swift` (wire planner entry point only, no UI redesign)
- Test: `swift_app/Tests/Unit/RecommendationDifficultyAdvisorTests.swift`
- Test: `swift_app/Tests/Unit/TodayRecommendationPlannerTests.swift`
- Test: `swift_app/Tests/Integration/RecommendationPipelineIntegrationTests.swift`

### Task 1: Add Recommendation Domain Models

**Files:**
- Create: `swift_app/Sources/Core/RecommendationModels.swift`
- Test: `swift_app/Tests/Unit/TodayRecommendationPlannerTests.swift`

- [ ] **Step 1: Write the failing test for data shape**

```swift
func testPlanContainsSixModuleSlots() {
    let plan = TodayRecommendationPlan(
        generatedAt: Date(timeIntervalSince1970: 0),
        items: RecommendationModule.allCases.map {
            RecommendationItem(module: $0, difficulty: .初级, reason: "cold start", payload: .placeholder)
        }
    )
    XCTAssertEqual(plan.items.count, 6)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift_app && swift test --filter TodayRecommendationPlannerTests/testPlanContainsSixModuleSlots`  
Expected: FAIL with "cannot find type 'TodayRecommendationPlan' in scope"

- [ ] **Step 3: Add minimal model implementation**

```swift
public enum RecommendationModule: String, CaseIterable, Codable, Sendable {
    case intervalEar, earChord, sightSinging, chordSwitch, scaleTraining, traditionalCrawl
}

public enum RecommendationDifficulty: String, Codable, Sendable { case 初级, 中级, 高级 }

public struct TodayRecommendationPlan: Sendable {
    public let generatedAt: Date
    public let items: [RecommendationItem]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift_app && swift test --filter TodayRecommendationPlannerTests/testPlanContainsSixModuleSlots`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add swift_app/Sources/Core/RecommendationModels.swift swift_app/Tests/Unit/TodayRecommendationPlannerTests.swift
git commit -m "feat(core): add recommendation domain models"
```

### Task 2: Implement Local History Store

**Files:**
- Create: `swift_app/Sources/Core/RecommendationHistoryStore.swift`
- Test: `swift_app/Tests/Unit/RecommendationDifficultyAdvisorTests.swift`

- [ ] **Step 1: Write failing test for persistence and time-window filtering**

```swift
func testLoadRecentRecordsReturnsOnlyLast7Days() async throws {
    let store = InMemoryRecommendationHistoryStore()
    try await store.append(.mock(daysAgo: 1, module: .intervalEar))
    try await store.append(.mock(daysAgo: 10, module: .intervalEar))

    let items = try await store.loadRecent(module: .intervalEar, now: .fixedNow, days: 7)
    XCTAssertEqual(items.count, 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift_app && swift test --filter RecommendationDifficultyAdvisorTests/testLoadRecentRecordsReturnsOnlyLast7Days`  
Expected: FAIL with missing `RecommendationHistoryStore`

- [ ] **Step 3: Implement store protocol and UserDefaults-backed store**

```swift
public protocol RecommendationHistoryStore: Sendable {
    func append(_ record: RecommendationRecord) async throws
    func loadRecent(module: RecommendationModule, now: Date, days: Int) async throws -> [RecommendationRecord]
}

public actor UserDefaultsRecommendationHistoryStore: RecommendationHistoryStore {
    // encode/decode JSON array, filter by module and date window
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift_app && swift test --filter RecommendationDifficultyAdvisorTests/testLoadRecentRecordsReturnsOnlyLast7Days`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add swift_app/Sources/Core/RecommendationHistoryStore.swift swift_app/Tests/Unit/RecommendationDifficultyAdvisorTests.swift
git commit -m "feat(core): add local recommendation history store"
```

### Task 3: Implement Difficulty Advisor (Strategy A)

**Files:**
- Create: `swift_app/Sources/Core/RecommendationDifficultyAdvisor.swift`
- Test: `swift_app/Tests/Unit/RecommendationDifficultyAdvisorTests.swift`

- [ ] **Step 1: Write failing tests for cold-start and thresholds**

```swift
func testColdStartDefaultsToBeginnerWhenSampleLessThan3() {
    let advisor = RecommendationDifficultyAdvisor()
    let decision = advisor.decide(module: .earChord, records: [.mock(), .mock()], now: .fixedNow)
    XCTAssertEqual(decision.difficulty, .初级)
}

func testThresholdMapsToIntermediate() {
    let advisor = RecommendationDifficultyAdvisor()
    let records = RecommendationRecordFixtures.stableMediumPerformance(count: 7)
    let decision = advisor.decide(module: .intervalEar, records: records, now: .fixedNow)
    XCTAssertEqual(decision.difficulty, .中级)
}
```

- [ ] **Step 2: Run test to verify they fail**

Run: `cd swift_app && swift test --filter RecommendationDifficultyAdvisorTests`  
Expected: FAIL with missing `RecommendationDifficultyAdvisor`

- [ ] **Step 3: Implement score composition and guard rails**

```swift
let masteryScore = accuracyScore + completionScore + stabilityScore + streakScore
if sampleCount < 3 { return .beginnerColdStart(...) }
if recentTwoFailed { difficulty = difficulty.demoteOneLevel() }
if inactiveFor3Days { difficulty = min(difficulty, .中级) }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd swift_app && swift test --filter RecommendationDifficultyAdvisorTests`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add swift_app/Sources/Core/RecommendationDifficultyAdvisor.swift swift_app/Tests/Unit/RecommendationDifficultyAdvisorTests.swift
git commit -m "feat(core): implement local mastery-based difficulty advisor"
```

### Task 4: Add Practice Procedural Generators Target

**Files:**
- Modify: `swift_app/Package.swift`
- Create: `swift_app/Sources/Features/Practice/PracticeModels.swift`
- Create: `swift_app/Sources/Features/Practice/ChordSwitchGenerator.swift`
- Create: `swift_app/Sources/Features/Practice/ScaleTrainingGenerator.swift`
- Create: `swift_app/Sources/Features/Practice/TraditionalCrawlGenerator.swift`
- Test: `swift_app/Tests/Unit/TodayRecommendationPlannerTests.swift`

- [ ] **Step 1: Write failing compile-level test for practice generators exposure**

```swift
func testPracticeGeneratorsCanBuildOneExerciseEach() {
    var rng = SeededRandomNumberGenerator(seed: 7)
    XCTAssertNotNil(ChordSwitchGenerator.buildExercise(difficulty: .初级, using: &rng))
    XCTAssertNotNil(ScaleTrainingGenerator.buildExercise(difficulty: .初级, using: &rng))
    XCTAssertNotNil(TraditionalCrawlGenerator.buildExercise(difficulty: .初级, using: &rng))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift_app && swift test --filter TodayRecommendationPlannerTests/testPracticeGeneratorsCanBuildOneExerciseEach`  
Expected: FAIL with missing `Practice` symbols

- [ ] **Step 3: Add `Practice` target and minimal generator implementations**

```swift
.library(name: "Practice", targets: ["Practice"])
...
.target(
    name: "Practice",
    dependencies: ["Core", "Fretboard"],
    path: "Sources/Features/Practice"
)
```

- [ ] **Step 4: Run test to verify pass**

Run: `cd swift_app && swift test --filter TodayRecommendationPlannerTests/testPracticeGeneratorsCanBuildOneExerciseEach`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add swift_app/Package.swift swift_app/Sources/Features/Practice swift_app/Tests/Unit/TodayRecommendationPlannerTests.swift
git commit -m "feat(practice): add procedural practice generators target"
```

### Task 5: Build Today Recommendation Planner Orchestration

**Files:**
- Create: `swift_app/Sources/Core/TodayRecommendationPlanner.swift`
- Test: `swift_app/Tests/Unit/TodayRecommendationPlannerTests.swift`

- [ ] **Step 1: Write failing test that planner returns exactly six items**

```swift
func testPlannerBuildsSixItemsWithPerModuleDifficulty() async throws {
    let planner = TodayRecommendationPlanner(
        historyStore: .fixture(records: RecommendationRecordFixtures.mixed),
        advisor: RecommendationDifficultyAdvisor(),
        generators: .testDoubles
    )
    let plan = try await planner.buildPlan(now: .fixedNow)
    XCTAssertEqual(plan.items.map(\.module).count, 6)
    XCTAssertEqual(Set(plan.items.map(\.module)).count, 6)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift_app && swift test --filter TodayRecommendationPlannerTests/testPlannerBuildsSixItemsWithPerModuleDifficulty`  
Expected: FAIL with missing planner type

- [ ] **Step 3: Implement planner and module adapters**

```swift
for module in RecommendationModule.allCases {
    let records = try await historyStore.loadRecent(module: module, now: now, days: 7)
    let decision = advisor.decide(module: module, records: records, now: now)
    let payload = try generators.generate(module: module, difficulty: decision.difficulty)
    items.append(.init(module: module, difficulty: decision.difficulty, reason: decision.reason, payload: payload))
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `cd swift_app && swift test --filter TodayRecommendationPlannerTests`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add swift_app/Sources/Core/TodayRecommendationPlanner.swift swift_app/Tests/Unit/TodayRecommendationPlannerTests.swift
git commit -m "feat(core): add six-module today recommendation planner"
```

### Task 6: Instrument Ear Module Completion Records

**Files:**
- Modify: `swift_app/Sources/Features/Ear/IntervalEarSessionViewModel.swift`
- Modify: `swift_app/Sources/Features/Ear/EarMcqSessionViewModel.swift`
- Modify: `swift_app/Sources/Features/Ear/SightSingingSessionViewModel.swift`
- Test: `swift_app/Tests/Integration/RecommendationPipelineIntegrationTests.swift`

- [ ] **Step 1: Write failing integration test for record emission**

```swift
func testEarSessionCompletionAppendsRecommendationRecord() async throws {
    let history = InMemoryRecommendationHistoryStore()
    let vm = EarMcqSessionViewModel(..., recommendationHistoryStore: history)
    // complete one session in test double mode
    let items = try await history.loadRecent(module: .earChord, now: .fixedNow, days: 7)
    XCTAssertEqual(items.count, 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift_app && swift test --filter RecommendationPipelineIntegrationTests/testEarSessionCompletionAppendsRecommendationRecord`  
Expected: FAIL with no record appended

- [ ] **Step 3: Inject store and append completion events on finish**

```swift
if finished {
    try? await recommendationHistoryStore.append(
        RecommendationRecord(module: .earChord, completed: true, successRate: score, durationSeconds: elapsed, occurredAt: Date())
    )
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `cd swift_app && swift test --filter RecommendationPipelineIntegrationTests/testEarSessionCompletionAppendsRecommendationRecord`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add swift_app/Sources/Features/Ear/IntervalEarSessionViewModel.swift swift_app/Sources/Features/Ear/EarMcqSessionViewModel.swift swift_app/Sources/Features/Ear/SightSingingSessionViewModel.swift swift_app/Tests/Integration/RecommendationPipelineIntegrationTests.swift
git commit -m "feat(ear): persist local records for recommendation"
```

### Task 7: Instrument Practice Module Completion Records

**Files:**
- Modify: `swift_app/Sources/Features/Practice/*PracticeView.swift` (completion callbacks)
- Modify: `swift_app/Sources/Core/TodayRecommendationPlanner.swift` (practice module payload adapters if needed)
- Test: `swift_app/Tests/Integration/RecommendationPipelineIntegrationTests.swift`

- [ ] **Step 1: Write failing integration test for practice record modules**

```swift
func testPracticeCompletionWritesChordSwitchScaleAndCrawlRecords() async throws {
    let history = InMemoryRecommendationHistoryStore()
    // simulate complete callbacks from three practice flows
    let modules = try await history.loadModules(now: .fixedNow, days: 7)
    XCTAssertTrue(modules.contains(.chordSwitch))
    XCTAssertTrue(modules.contains(.scaleTraining))
    XCTAssertTrue(modules.contains(.traditionalCrawl))
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `cd swift_app && swift test --filter RecommendationPipelineIntegrationTests/testPracticeCompletionWritesChordSwitchScaleAndCrawlRecords`  
Expected: FAIL (practice records missing)

- [ ] **Step 3: Wire completion callbacks to `RecommendationHistoryStore.append`**

```swift
onPracticeFinished = { result in
    Task {
        try? await recommendationHistoryStore.append(
            .init(module: .scaleTraining, completed: result.completed, successRate: result.successRate, durationSeconds: result.durationSeconds, occurredAt: Date())
        )
    }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `cd swift_app && swift test --filter RecommendationPipelineIntegrationTests/testPracticeCompletionWritesChordSwitchScaleAndCrawlRecords`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add swift_app/Sources/Features/Practice swift_app/Tests/Integration/RecommendationPipelineIntegrationTests.swift
git commit -m "feat(practice): persist local completion records for recommendations"
```

### Task 8: End-to-End Planner Integration + Logging

**Files:**
- Modify: `swift_app/Sources/App/ToolsHomeView.swift`
- Modify: `swift_app/Sources/Core/TodayRecommendationPlanner.swift` (decision logs)
- Test: `swift_app/Tests/Integration/RecommendationPipelineIntegrationTests.swift`

- [ ] **Step 1: Write failing integration test for full pipeline output**

```swift
func testFullRecommendationPipelineReturnsSixItemsEvenWhenOneGeneratorFails() async throws {
    let planner = TodayRecommendationPlanner(... failingGenerator: .intervalEar)
    let plan = try await planner.buildPlan(now: .fixedNow)
    XCTAssertEqual(plan.items.count, 6)
    XCTAssertEqual(plan.items.first(where: { $0.module == .intervalEar })?.difficulty, .初级)
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `cd swift_app && swift test --filter RecommendationPipelineIntegrationTests/testFullRecommendationPipelineReturnsSixItemsEvenWhenOneGeneratorFails`  
Expected: FAIL (pipeline throws / no fallback)

- [ ] **Step 3: Add fallback item + decision log persistence**

```swift
do {
    payload = try generators.generate(module: module, difficulty: decision.difficulty)
} catch {
    payload = .fallback(message: "generator_failed")
    difficulty = .初级
}
decisionLogger.log(module: module, sampleCount: records.count, masteryScore: decision.masteryScore, difficulty: difficulty)
```

- [ ] **Step 4: Run full test suite**

Run: `cd swift_app && swift test`  
Expected: PASS for Unit + Integration + UI tests

- [ ] **Step 5: Commit**

```bash
git add swift_app/Sources/App/ToolsHomeView.swift swift_app/Sources/Core/TodayRecommendationPlanner.swift swift_app/Tests/Integration/RecommendationPipelineIntegrationTests.swift
git commit -m "feat(app): wire robust local-history recommendation pipeline"
```

## Self-Review

### 1) Spec coverage

- 6 模块各 1 条输出：Task 5 + Task 8
- 本地历史判档与冷启动初级：Task 2 + Task 3
- 保护规则（降档/久未练封顶）：Task 3
- 异常兜底保证输出稳定：Task 8
- 可观测性日志：Task 8
- 不绑定 UI 重构：Task 8 仅接入入口，不改导航结构

### 2) Placeholder scan

- 已检查：无 `TODO/TBD/implement later` 等占位语句。
- 每个任务包含明确文件、测试命令、期望结果。

### 3) Type consistency

- 统一使用：`RecommendationModule`、`RecommendationDifficulty`、`RecommendationRecord`、`TodayRecommendationPlan`。
- 任务间接口名保持一致，避免后续实现重命名漂移。
