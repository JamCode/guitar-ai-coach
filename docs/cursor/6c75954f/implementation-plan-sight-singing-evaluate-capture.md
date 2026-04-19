# 视唱判定拾音可靠性 + 示范直通 — Implementation Plan

> **For agentic workers:** 可按任务顺序执行；每任务内步骤使用 `- [ ]` 勾选跟踪。  
> **关联设计：** `docs/cursor/6c75954f/sight-singing-evaluate-capture-design.md`

**Goal:** 在真机视唱训练中，提升判定窗口内有效拾音样本率与分数稳定性；示范音频播完后自动进入与 `evaluate()` 等价的判定流程，并保留「跳过示范直接判定」；样本不足时不给出误导性低分。

**Architecture:** 在 `SightSingingSessionViewModel` 内集中扩展——结构化判定日志（P0）、示范结束衔接与触发源枚举（P-UX）、判定循环内短窗聚合与样本下限分支（P1）、可选暂停曲线监控任务（P2）、视日志微调 `PitchDetectorConfig.sightSinging` 与窗口常量（P3）。UI 仅在 `SightSingingViews` 底栏做文案/按钮与调用入口调整。

**Tech Stack:** Swift 5、SwiftUI、Swift Package（`swift_app`）、现有 `TunerPitchDetector` / `IntervalTonePlayer`、XCTest（`swift test`）。

---

## 文件与职责一览

| 路径 | 职责 |
|------|------|
| `swift_app/Sources/Features/Ear/SightSingingSessionViewModel.swift` | `evaluate()` 改造、日志、聚合采样、暂停监控开关、`playPreview` 后自动 `evaluate`、防串音延迟、互斥状态 |
| `swift_app/Sources/Features/Ear/SightSingingViews.swift` | 底栏：主路径「示范并判定」、跳过示范、`previewing`/`evaluating` 禁用态与文案 |
| `swift_app/Sources/Features/Ear/SightSingingModels.swift` | 可选：`computeSightSingingScore` 或新增类型仅当 P1 需对外暴露「无效判定」语义时（默认先只在 ViewModel 层短路 `submitAnswer`） |
| `swift_app/Sources/Core/TunerPitchDetector.swift` | P3：`PitchDetectorConfig.sightSinging` 参数微调 |
| `swift_app/Sources/Features/Ear/IntervalTonePlayer.swift` | 只读确认：`playSinglePreview` / `playAscendingPair` 返回即表示播放结束（P-UX 衔接点） |
| `swift_app/Tests/Unit/EarCoreTests.swift` | 扩展：`computeSightSingingScore` 或新纯函数单测（若抽取聚合） |
| `swift_app/Tests/Integration/EarIntegrationTests.swift` | 可选：带 fake `SightSingingPitchTracking` 的集成测试（若投入产出比合适） |

---

### Task 0：基线与分支

**Files:** 无代码，仅流程。

- [ ] **Step 1:** 确认当前分支为 `cursor/6c75954f`，设计文档与计划均在 `docs/cursor/6c75954f/`。
- [ ] **Step 2:** 在真机当前版本记录 3 次「仅判定」与 3 次「示范后手动判定」的主观结果（可为笔记），便于 P0 后对比。

---

### Task 1（P0）：判定结构化日志

**Files:**
- Modify: `swift_app/Sources/Features/Ear/SightSingingSessionViewModel.swift`（`evaluate()` 及调用链）
- Optional create: `swift_app/Sources/Features/Ear/SightSingingEvaluateDebugLog.swift`（若希望减少 ViewModel 体积；否则用 `private struct` 内嵌在同一文件）

**定义（建议字段，一次打印一行 JSON 或 `Logger` 子系统 `ear.sightSinging.evaluate`）：**

- `questionId`, `targetIndex`（音程多段时）
- `evaluateTrigger`: `manual` | `postPreview`
- `windowMs` = `warmupMs + evalMs`（每段）
- `sampleStepMs`
- `ticksTotal`, `ticksAfterWarmup`, `ticksWithHz`（`currentHz != nil`）
- `firstValidSampleOffsetMs`（从该段起点到首个有效样本的时间，无则 `null`）
- `absCentsCount`（进入打分前的样本数）

- [ ] **Step 1:** 在 `SightSingingSessionViewModel` 增加 `private enum EvaluateTrigger { case manual, postPreview }`，为 `evaluate(trigger: EvaluateTrigger = .manual) async` 或内部参数，**不改变** `submitAnswer` 对外字段（先只打日志）。
- [ ] **Step 2:** 在 `evaluate()` 的 `for (idx, target)` 循环内，每 `sampleStepMs` 迭代末尾累计上述计数；循环结束后 `print`/统一日志封装输出一行。
- [ ] **Step 3:** 真机跑一单音、一单音程，确认控制台/Xcode 可见完整字段。

```bash
cd swift_app && swift test
```

预期：全绿（未改行为）。

- [ ] **Step 4:** Commit 示例：`git commit -m "chore(ear): 视唱 evaluate 增加结构化调试日志（P0）"`

---

### Task 2（P-UX）：示范结束自动 `evaluate()`

**Files:**
- Modify: `swift_app/Sources/Features/Ear/SightSingingSessionViewModel.swift`
- Modify: `swift_app/Sources/Features/Ear/SightSingingViews.swift`

**常量（首版可写死，文档注明真机可调）：**

- `postPreviewEvaluateDelayMs = 300`（防串音；spec 建议 200～400ms）
- 在 `playPreview()` **正常返回**后 `try? await Task.sleep(nanoseconds: 300_000_000)`，再 `await evaluate(trigger: .postPreview)`。

**互斥：**

- `playPreview` 开头：`guard !previewing, !evaluating`（已有类似则对齐）；`evaluate` 开头保持 `guard !evaluating`。
- 若用户在示范中又点示范：`playPreview` 应 `previewGraphTask?.cancel()` 等已有逻辑基础上，**不**在取消路径自动触发 `evaluate`（仅「正常播完返回」触发）。

- [ ] **Step 1:** 在 `SightSingingSessionViewModel` 新增 `public func playPreviewAndEvaluate() async`：直接 `await playPreview()`（内部已维护 `previewing` 与 `defer`）；仅在 `playPreview` **正常返回且无提前 `return`** 后执行 `try? await Task.sleep(nanoseconds: 300_000_000)`，再 `await evaluate(trigger: .postPreview)`。若 `playPreview` 因 `guard` 早退（无题目等），**不得**调用 `evaluate`。当前 `playPreview` 在 `catch` 里写 `errorText` 仍会继续执行尾部清理；**实现时**须二选一：`playPreview` 改为返回 `Bool` / `throws`，或在 `catch` 内 `return`，以便试听失败时**不**自动 `evaluate`。将 `evaluateTrigger` 传入 P0 日志路径。
- [ ] **Step 2:** 保留原 `public func playPreview()` 不动，供将来「仅试听」或测试复用；UI 首版用 `playPreviewAndEvaluate` + 跳过按钮调 `evaluate(trigger: .manual)`。
- [ ] **Step 3:** `SightSingingViews.swift` 底栏主按钮改为调用 `Task { await viewModel.playPreviewAndEvaluate() }`（文案如「示范并判定」）；次要按钮「跳过示范，直接判定」→ `Task { await viewModel.evaluate(trigger: .manual) }`（或仅 `evaluate()` 默认 manual）。
- [ ] **Step 4:** `previewing || evaluating` 时禁用另一按钮与「下一题」，与现逻辑对齐。
- [ ] **Step 5:** 真机手测：播完不点第二按钮即进入判定；跳过示范路径仍一键判定。

```bash
cd swift_app && swift test
```

- [ ] **Step 6:** Commit：`feat(ear): 示范结束后自动判定（P-UX）`

---

### Task 3（P1）：短窗聚合 + 有效样本下限

**Files:**
- Modify: `swift_app/Sources/Features/Ear/SightSingingSessionViewModel.swift`
- Modify: `swift_app/Sources/Features/Ear/SightSingingModels.swift`（仅当需在 UI 外复用「无效」结果类型时）
- Modify: `swift_app/Sources/Features/Ear/SightSingingViews.swift`（展示 `errorText` 或专用 `@Published evaluateQualityMessage`）

**算法（首版建议，可测后改）：**

- 在 `warmupMs` 之后的每个 `sampleStepMs` 节拍：将最近最多 `k = 3` 次读到的 `currentHz`（含当前与向前缓存的非 nil 值）取 **MIDI 中位数**，若不足 2 个非 nil 则本节拍**不**写入 `absCents`。
- **段级下限**：该 `target` 段结束后若 `absCents.count < 5`（示例阈值，实现前用 P0 日志填真实数字），则：
  - **不调用** `repository.submitAnswer`；
  - 设置用户可见文案：`未稳定拾音，请重试`（可用 `errorText` 或新 `@Published` 字段避免与网络错误混淆——推荐 `evaluateUserHint: String?`）。

- [ ] **Step 1:** 在 ViewModel 内增加小型 `private struct HzRingBuffer`（容量 3，`append(nil)` 合法），提供 `medianMidiIfReady() -> Double?`。
- [ ] **Step 2:** 替换 `evaluate()` 循环内 `if let hz = currentHz` 为「聚合后 midi → `abs((midi - targetMidi)*100)`」。
- [ ] **Step 3:** 实现段末样本数检查与跳过 `submitAnswer`；`lastScore` 置 `nil` 或保留上次由产品决定——**建议**置 `nil`，并清 hint 在下一题。
- [ ] **Step 4:** `SightSingingViews` 在判定结果卡上方展示 hint（`.foregroundStyle(.orange)` 等）。
- [ ] **Step 5:** 单元测试：对 `computeSightSingingScore` 已有用例保持；若抽取 `medianOf` 到 `Core` 可测，否则以真机清单为主。

```bash
cd swift_app && swift test
```

- [ ] **Step 6:** Commit：`fix(ear): 判定采样聚合与有效样本下限（P1）`

---

### Task 4（P2，可选开关）：判定时暂停曲线监控

**Files:**
- Modify: `swift_app/Sources/Features/Ear/SightSingingSessionViewModel.swift`

**做法：**

- `private let pauseGraphWhileEvaluating = true`（编译期常量即可，便于 A/B）。
- `evaluate()` 进入时 `monitoringTask?.cancel(); monitoringTask = nil`，`defer` 末尾若 session 仍有效则 `startPitchMonitoringIfNeeded()`。

- [ ] **Step 1:** 实现上述开关与恢复。
- [ ] **Step 2:** 对比 P0 日志中 `ticksWithHz` 是否提升；无增益则默认 `false` 并提交说明。

```bash
cd swift_app && swift test
```

- [ ] **Step 3:** Commit：`chore(ear): 可选判定时暂停曲线监控（P2）`

---

### Task 5（P3）：检测器与窗口微调

**Files:**
- Modify: `swift_app/Sources/Core/TunerPitchDetector.swift`（`sightSinging` 静态配置）
- Modify: `swift_app/Sources/Features/Ear/SightSingingSessionViewModel.swift`（`warmupMs` / `evalMs` / `postPreviewEvaluateDelayMs`）

- [ ] **Step 1:** 根据 P0 日志统计拒帧比例，逐项微调 `minRms`、`minPeakCorrelation`、`minPeakToMedianRatio`（每次只改一项并记录）。
- [ ] **Step 2:** 若 `firstValidSampleOffsetMs` 系统性偏大，考虑 `warmupMs` +100～200ms 或略增 `postPreviewEvaluateDelayMs`。
- [ ] **Step 3:** 更新本 plan 或 design 文档中的「已标定数值」表（表格形式即可）。

```bash
cd swift_app && swift test
```

- [ ] **Step 4:** Commit：`chore(ear): 视唱拾音检测器与判定窗口微调（P3）`

---

## 手测清单（合并 spec §7）

1. 单音：仅示范直通；跳过示范直判；播完立即唱；停半拍再唱。  
2. 音程：同上 + 确认两段 `targetIndex` 日志独立。  
3. 示范中途再次点示范：不应触发半截 `evaluate`。  
4. 判定中：示范按钮禁用。  
5. 小声 / 正常音量各一轮，看 P1 hint 是否仅在真不足样本时出现。

---

## 提交与合并建议

- 每个 Task 末尾独立 commit；P2 若默认关闭可单独说明。  
- PR 描述中链接本 plan 与 design spec 路径。

---

## 计划自检

- 无 `TBD`：阈值处已写「先用 5 / 300ms，用 P0 日志回填」。  
- 与 design 非目标一致：未要求重做曲线动画；后端协议默认不变（不提交无效答案时不调 `submitAnswer`）。  
- `evaluateTrigger` 满足 design 对日志的要求。
