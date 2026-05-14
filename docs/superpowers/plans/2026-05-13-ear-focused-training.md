# 练耳专项训练功能 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在练耳 Tab 导航栏添加 Menu 按钮（合并原有日历+统计两个按钮），菜单包含「专项训练」「训练统计」「练习日历」，专项训练页展示4个题型入口，点击后进入单题型训练页，答题结果计入听力值系统。

**架构:** 新增3个 View/VM 文件（FocusedEarHubView、FocusedEarTrainingSessionView、FocusedEarTrainingViewModel），共享 AdaptiveEarTrainingEngine 评分引擎和 UserDefaultsAdaptiveEarTrainingStore，将 AdaptiveEarTrainingView 的 toolbar chart 按钮替换为 Menu，移除 PracticeLandingView 的 toolbar calendar 按钮。

**Tech Stack:** SwiftUI, iOS 17+, UserDefaults (local store), Ear library (swift_app)

---

### 文件结构

**新建（3个文件）：**
- `swift_ios_host/Sources/Practice/Views/FocusedEarHubView.swift` — 专项训练首页
- `swift_ios_host/Sources/Practice/Views/FocusedEarTrainingSessionView.swift` — 单题型训练页 UI
- `swift_ios_host/Sources/Practice/Views/FocusedEarTrainingViewModel.swift` — 单题型训练 ViewModel

**修改（2个文件）：**
- `swift_ios_host/Sources/Practice/Views/AdaptiveEarTrainingView.swift` — toolbar chart 改为 Menu
- `swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift` — 移除 toolbar calendar 按钮

---

### Task 1: 创建 FocusedEarTrainingViewModel

**Files:**
- Create: `swift_ios_host/Sources/Practice/Views/FocusedEarTrainingViewModel.swift`

ViewModel 复用自适应练耳的评分引擎和存储，但固定 question kind。

```swift
import SwiftUI
import Ear
import Foundation

@MainActor
final class FocusedEarTrainingViewModel: ObservableObject {
    @Published private(set) var loading = true
    @Published private(set) var loadError: String?
    @Published private(set) var state: AdaptiveEarAbilityState = .initial
    @Published private(set) var records: [AdaptiveEarAttemptRecord] = []
    @Published private(set) var currentQuestion: AdaptiveEarQuestion?
    @Published private(set) var questionToken = UUID()
    @Published private(set) var isPreparingQuestion = false
    @Published private(set) var selectedChoiceID: String?
    @Published private(set) var hasRevealed = false
    @Published private(set) var feedback: AdaptiveEarFeedback?
    @Published private(set) var isPlaying = false
    @Published private(set) var playError: String?

    let fixedKind: AdaptiveEarQuestionKind

    private let store: AdaptiveEarTrainingStoring
    private let intervalPlayer: IntervalTonePlaying
    private let chordPlayer: EarChordPlaying
    private var rng = SystemRandomNumberGenerator()
    private var questionStartedAt = Date()
    private var previousIntervalLowMidi: Int?
    private var previousSingleNoteMidi: Int?
    private var playTask: Task<Void, Never>?

    init(
        kind: AdaptiveEarQuestionKind,
        store: AdaptiveEarTrainingStoring = UserDefaultsAdaptiveEarTrainingStore(),
        intervalPlayer: IntervalTonePlaying = IntervalTonePlayer(),
        chordPlayer: EarChordPlaying = EarChordPlayer()
    ) {
        self.fixedKind = kind
        self.store = store
        self.intervalPlayer = intervalPlayer
        self.chordPlayer = chordPlayer
    }

    var kindAccuracyText: String {
        guard let accuracy = AdaptiveEarTrainingEngine.recentAccuracy(for: fixedKind, records: records, limit: 12) else {
            return "近12题 --"
        }
        return "近12题 \(Int((accuracy * 100).rounded()))%"
    }

    var ratingDisplay: Int {
        Int(state.rating(for: fixedKind).rounded())
    }

    var kindTitle: String { fixedKind.title }
    var kindShortTitle: String { fixedKind.shortTitle }

    func bootstrap() async {
        loading = true
        loadError = nil
        state = await store.loadState()
        records = await store.loadAttempts()
        loading = false
        if currentQuestion == nil {
            await nextQuestion()
        }
    }

    func playCurrent() async {
        playTask?.cancel()
        playTask = nil
        guard let question = currentQuestion else { return }
        isPlaying = true
        let work = Task { @MainActor in
            do {
                switch question {
                case let .interval(q, _, _):
                    try await intervalPlayer.playAscendingPair(lowMidi: q.lowMidi, highMidi: q.highMidi)
                case let .chord(q, _, _):
                    if let frets = q.playbackFretsSixToOne, frets.count == 6 {
                        try await chordPlayer.playChordFromFretsSixToOne(frets)
                    } else {
                        try await chordPlayer.playChordMidis(EarPlaybackMidi.forSingleChord(q))
                    }
                case let .progression(q, _, _):
                    if let seq = EarProgressionPlayback.playbackFretsSequence(for: q), !seq.isEmpty {
                        try await chordPlayer.playProgressionFromFretsSixToOne(seq)
                    } else {
                        try await chordPlayer.playChordSequence(EarPlaybackMidi.forProgression(q))
                    }
                case let .singleNote(q, _, _):
                    try await intervalPlayer.playAscendingPair(lowMidi: 69, highMidi: q.midi)
                }
                playError = nil
            } catch is CancellationError {
                cancelPlayback()
            } catch {
                playError = "播放失败：\(error.localizedDescription)"
            }
            isPlaying = false
        }
        playTask = work
        await work.value
    }

    func cancelPlayback() {
        playTask?.cancel()
        playTask = nil
        intervalPlayer.cancelIntervalPlayback()
        chordPlayer.cancelChordPlayback()
        isPlaying = false
    }

    func playPreviewNote(midi: Int) async {
        playTask?.cancel()
        playTask = nil
        intervalPlayer.cancelIntervalPlayback()
        let work = Task { @MainActor in
            do {
                try await intervalPlayer.playSinglePreview(midi: midi)
                playError = nil
            } catch is CancellationError {
                cancelPlayback()
            } catch {
                playError = "播放失败：\(error.localizedDescription)"
            }
        }
        playTask = work
        await work.value
    }

    func playReferenceA4() async {
        playTask?.cancel()
        playTask = nil
        intervalPlayer.cancelIntervalPlayback()
        let work = Task { @MainActor in
            do {
                try await intervalPlayer.playSinglePreview(midi: 69)
                playError = nil
            } catch is CancellationError {
                cancelPlayback()
            } catch {
                playError = "播放失败：\(error.localizedDescription)"
            }
        }
        playTask = work
        await work.value
    }

    func playChordForLabel(_ label: String) async {
        playTask?.cancel()
        playTask = nil
        intervalPlayer.cancelIntervalPlayback()
        chordPlayer.cancelChordPlayback()
        let work = Task { @MainActor in
            do {
                if let payload = OfflineChordBuilder.buildPayload(displaySymbol: label),
                   let frets = payload.voicings.first?.explain.frets,
                   frets.count == 6 {
                    try await chordPlayer.playChordFromFretsSixToOne(frets)
                } else {
                    let midis = Self.midiNotesForChordLabel(label)
                    guard !midis.isEmpty else {
                        playError = "无法解析和弦：\(label)"
                        return
                    }
                    try await chordPlayer.playChordMidis(midis)
                }
                playError = nil
            } catch is CancellationError {
                cancelPlayback()
            } catch {
                playError = "播放失败：\(error.localizedDescription)"
            }
        }
        playTask = work
        await work.value
    }

    private static func midiNotesForChordLabel(_ label: String) -> [Int] {
        let raw = label.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return [] }
        let (root, quality) = Self.parseChordLabel(raw)
        let baseMidi = Self.noteNameToMidi(root)
        guard baseMidi >= 0 else { return [] }
        let intervals: [Int]
        switch quality {
        case "m", "min", "minor": intervals = [0, 3, 7]
        case "7", "dom7", "dominant7": intervals = [0, 4, 7, 10]
        case "m7", "min7", "minor7": intervals = [0, 3, 7, 10]
        case "maj7", "Δ": intervals = [0, 4, 7, 11]
        case "dim", "°": intervals = [0, 3, 6]
        case "dim7", "°7": intervals = [0, 3, 6, 9]
        case "sus4": intervals = [0, 5, 7]
        default: intervals = [0, 4, 7]
        }
        return intervals.map { baseMidi + $0 }
    }

    private static func parseChordLabel(_ label: String) -> (root: String, quality: String) {
        let s = label.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return ("C", "") }
        let doubleRoot = String(s.prefix(2))
        let sharpFlatRoots = ["C#", "Db", "D#", "Eb", "F#", "Gb", "G#", "Ab", "A#", "Bb"]
        if sharpFlatRoots.contains(doubleRoot) {
            let rest = String(s.dropFirst(2))
            return (doubleRoot, rest)
        }
        let singleRoot = String(s.prefix(1))
        let roots = ["C", "D", "E", "F", "G", "A", "B"]
        if roots.contains(singleRoot) {
            let rest = String(s.dropFirst())
            return (singleRoot, rest)
        }
        return ("C", "")
    }

    private static func noteNameToMidi(_ name: String) -> Int {
        let normalized = name.uppercased().trimmingCharacters(in: .whitespaces)
        let map: [String: Int] = [
            "C":0,"C#":1,"DB":1,"D":2,"D#":3,"EB":3,"E":4,
            "F":5,"F#":6,"GB":6,"G":7,"G#":8,"AB":8,"A":9,"A#":10,"BB":10,"B":11
        ]
        guard let pc = map[normalized] else { return -1 }
        return 60 + pc
    }

    func submit(_ choice: AdaptiveEarChoice) {
        guard !hasRevealed, let question = currentQuestion else { return }
        selectedChoiceID = choice.id
        let correct = choice.id == question.correctChoiceId
        saveAnswer(question: question, selectedAnswer: choice.label, wasCorrect: correct, skipped: false)
        feedback = AdaptiveEarFeedback(wasCorrect: correct, title: correct ? "答对了" : "再听一遍这个差异")
        hasRevealed = true
    }

    func nextQuestion() async {
        cancelPlayback()
        isPreparingQuestion = true
        let request = makeNextQuestionRequest()
        let question = await Self.makeQuestion(request: request)
        currentQuestion = question
        rememberPreviousMidi(from: question)
        selectedChoiceID = nil
        hasRevealed = false
        feedback = nil
        questionStartedAt = Date()
        questionToken = UUID()
        isPreparingQuestion = false
    }

    private func makeNextQuestionRequest() -> AdaptiveEarQuestionRequest {
        let difficulty = AdaptiveEarTrainingEngine.difficulty(for: fixedKind, state: state)
        let score = AdaptiveEarTrainingEngine.difficultyScore(kind: fixedKind, difficulty: difficulty)
        return AdaptiveEarQuestionRequest(
            kind: fixedKind,
            difficulty: difficulty,
            score: score,
            previousIntervalLowMidi: previousIntervalLowMidi,
            previousSingleNoteMidi: previousSingleNoteMidi
        )
    }

    nonisolated private static func makeQuestion(request: AdaptiveEarQuestionRequest) async -> AdaptiveEarQuestion {
        var rng = SystemRandomNumberGenerator()
        switch request.kind {
        case .interval:
            let q = IntervalQuestionGenerator.next(
                difficulty: request.difficulty.intervalDifficulty,
                antiAbsolutePitch: antiAbsolutePitch(
                    for: request.difficulty.intervalDifficulty,
                    previousIntervalLowMidi: request.previousIntervalLowMidi
                ),
                using: &rng
            )
            return .interval(q, difficulty: request.difficulty, difficultyScore: request.score)
        case .chord:
            let q = EarChordMcqGenerator.makeQuestion(
                difficulty: request.difficulty.chordDifficulty,
                avoid: nil,
                using: &rng
            )
            return .chord(q, difficulty: request.difficulty, difficultyScore: request.score)
        case .progression:
            let q = EarProgressionProceduralGenerator.makeQuestion(
                difficulty: request.difficulty.progressionDifficulty,
                using: &rng
            )
            return .progression(q, difficulty: request.difficulty, difficultyScore: request.score)
        case .singleNote:
            let q = makeSingleNoteQuestion(
                difficulty: request.difficulty,
                avoidMidi: request.previousSingleNoteMidi,
                using: &rng
            )
            return .singleNote(q, difficulty: request.difficulty, difficultyScore: request.score)
        }
    }

    nonisolated private static func antiAbsolutePitch(
        for difficulty: IntervalEarDifficulty,
        previousIntervalLowMidi: Int?
    ) -> IntervalAntiAbsolutePitch? {
        guard let previousIntervalLowMidi else { return nil }
        switch difficulty {
        case .初级: return nil
        case .中级: return IntervalAntiAbsolutePitch(previousLowerMidi: previousIntervalLowMidi, minSemitoneDelta: 3)
        case .高级: return IntervalAntiAbsolutePitch(previousLowerMidi: previousIntervalLowMidi, minSemitoneDelta: 5)
        }
    }

    nonisolated private static func makeSingleNoteQuestion(
        difficulty: AdaptiveEarDifficulty,
        avoidMidi: Int?,
        using rng: inout some RandomNumberGenerator
    ) -> SingleNoteQuestion {
        let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let pool: [(midi: Int, label: String)]
        switch difficulty {
        case .beginner:
            let naturals = [60,62,64,65,67,69,71,72]
            pool = naturals.map { ($0, noteNames[$0 % 12]) }
        case .intermediate:
            pool = (60...71).map { ($0, noteNames[$0 % 12]) }
        case .advanced:
            pool = (52...76).map { ($0, Self.noteLabelWithOctave(midi: $0)) }
        }
        var candidates = pool
        if let avoid = avoidMidi {
            candidates = candidates.filter { $0.midi != avoid }
        }
        if candidates.isEmpty { candidates = pool }
        let target = candidates.randomElement(using: &rng) ?? pool[0]
        var choicePool = pool.filter { $0.midi != target.midi }
        if choicePool.count > 3 { choicePool.shuffle(using: &rng) }
        let wrongs = Array(choicePool.prefix(3))
        var choices = wrongs.map { SingleNoteQuestion.SingleNoteChoice(id: "\($0.midi)", label: $0.label) }
        choices.append(SingleNoteQuestion.SingleNoteChoice(id: "\(target.midi)", label: target.label))
        choices.shuffle(using: &rng)
        return SingleNoteQuestion(midi: target.midi, noteLabel: target.label, choices: choices)
    }

    nonisolated private static func noteLabelWithOctave(midi: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let pc = midi % 12
        let octave = (midi / 12) - 1
        return "\(names[pc])\(octave)"
    }

    private func rememberPreviousMidi(from question: AdaptiveEarQuestion) {
        switch question {
        case let .interval(q, _, _):
            previousIntervalLowMidi = q.lowMidi
            previousSingleNoteMidi = nil
        case let .singleNote(q, _, _):
            previousSingleNoteMidi = q.midi
            previousIntervalLowMidi = nil
        default:
            previousIntervalLowMidi = nil
            previousSingleNoteMidi = nil
        }
    }

    private func saveAnswer(
        question: AdaptiveEarQuestion,
        selectedAnswer: String?,
        wasCorrect: Bool,
        skipped: Bool
    ) {
        let beforeState = state
        let beforeKind = beforeState.rating(for: fixedKind)
        let nextState = AdaptiveEarTrainingEngine.stateAfterAnswer(
            state: beforeState,
            kind: fixedKind,
            difficultyScore: question.difficultyScore,
            wasCorrect: wasCorrect
        )
        state = nextState
        let record = AdaptiveEarAttemptRecord(
            id: UUID().uuidString,
            questionKindRaw: fixedKind.rawValue,
            questionId: question.stableQuestionId,
            difficultyRaw: question.difficulty.rawValue,
            difficultyScore: question.difficultyScore,
            correctAnswer: question.correctAnswerText,
            selectedAnswer: selectedAnswer,
            wasCorrect: wasCorrect,
            responseTimeMs: max(0, Int(Date().timeIntervalSince(questionStartedAt) * 1000)),
            answeredAt: Date(),
            ratingBeforeOverall: beforeState.overallEarRating,
            ratingAfterOverall: nextState.overallEarRating,
            ratingBeforeKind: beforeKind,
            ratingAfterKind: nextState.rating(for: fixedKind),
            skipped: skipped
        )
        records.append(record)
        Task {
            await store.saveState(nextState)
            await store.appendAttempt(record)
        }
    }
}
```

- [ ] **Step 1:** Create `swift_ios_host/Sources/Practice/Views/FocusedEarTrainingViewModel.swift` with the above content

- [ ] **Step 2:** Verify it compiles

Run: `cd /Users/wanghan/Documents/guitar-ai-coach && xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`

- [ ] **Step 3:** Commit

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Practice/Views/FocusedEarTrainingViewModel.swift
git commit -m "feat: add FocusedEarTrainingViewModel for single-type ear training"
```

---

### Task 2: 创建 FocusedEarTrainingSessionView

**Files:**
- Create: `swift_ios_host/Sources/Practice/Views/FocusedEarTrainingSessionView.swift`

单题型训练页 UI。显示该题型听力值评分卡片 + 题目卡片（播放、选项、反馈、下一题）。

```swift
import SwiftUI
import Core
import Ear
import Chords

struct FocusedEarTrainingSessionView: View {
    let kind: AdaptiveEarQuestionKind

    @StateObject private var vm: FocusedEarTrainingViewModel
    @State private var showHintStrip = false

    init(kind: AdaptiveEarQuestionKind) {
        self.kind = kind
        _vm = StateObject(wrappedValue: FocusedEarTrainingViewModel(kind: kind))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ratingCard

                if vm.loading {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity)
                        .appCard()
                } else if let error = vm.loadError {
                    Text(error).foregroundStyle(.red).appCard()
                } else if vm.isPreparingQuestion {
                    ProgressView("正在准备下一题…")
                        .frame(maxWidth: .infinity)
                        .appCard()
                } else if let question = vm.currentQuestion {
                    questionCard(question)
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .appPageBackground()
        .task { await vm.bootstrap() }
        .task(id: vm.questionToken) {
            showHintStrip = false
        }
        .onDisappear { vm.cancelPlayback() }
    }

    private var ratingCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.kindTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(SwiftAppTheme.text)
                Text(vm.kindAccuracyText)
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(vm.ratingDisplay)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .monospacedDigit()
                Text("听力值")
                    .font(.caption2)
                    .foregroundStyle(SwiftAppTheme.muted)
            }
        }
        .padding(14)
        .background(SwiftAppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(SwiftAppTheme.line, lineWidth: 1))
    }

    private func questionCard(_ question: AdaptiveEarQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(question.kind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(SwiftAppTheme.brandSoft)
                    .clipShape(Capsule())
                Text(question.difficulty.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                Spacer()
            }

            Text(question.prompt)
                .font(.title3.weight(.bold))
                .foregroundStyle(SwiftAppTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            playButton

            if case .interval = question {
                hintButton("提示", active: $showHintStrip) {
                    hintChromaticStrip(for: question)
                }
            }
            if case .chord = question {
                hintButton("试听各选项", active: $showHintStrip) {
                    chordHintOptionsView(for: question)
                }
            }
            if case .progression = question {
                hintButton("逐和弦试听", active: $showHintStrip) {
                    progressionHintOptionsView(for: question)
                }
            }
            if case .singleNote = question {
                hintButton("逐音试听", active: $showHintStrip) {
                    singleNoteHintView
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(question.choices) { choice in
                    answerButton(choice: choice, question: question)
                }
            }

            if let feedback = vm.feedback {
                feedbackCard(feedback, question: question)
            }

            if vm.hasRevealed {
                Button("下一题") {
                    Task { await vm.nextQuestion() }
                }
                .appPrimaryButton()
                .frame(maxWidth: .infinity)
            }
        }
        .appCard()
    }

    private var playButton: some View {
        Button {
            Task { await vm.playCurrent() }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: vm.isPlaying ? "waveform" : "play.circle.fill")
                    .font(.system(size: 48, weight: .semibold))
                Text(vm.isPlaying ? "播放中…" : "播放题目")
                    .font(.headline)
            }
            .foregroundStyle(SwiftAppTheme.brand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(SwiftAppTheme.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(vm.isPlaying)
    }

    private func hintButton<Content: View>(
        _ title: String,
        active: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    active.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: active.wrappedValue ? "lightbulb.fill" : "lightbulb")
                        .font(.caption)
                    Text(active.wrappedValue ? "收起提示" : title)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(SwiftAppTheme.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(SwiftAppTheme.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if active.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 8)
            }
        }
    }

    private func answerButton(choice: AdaptiveEarChoice, question: AdaptiveEarQuestion) -> some View {
        let state = answerVisualState(choice: choice, question: question)
        return Button {
            vm.submit(choice)
        } label: {
            Text(choice.label)
                .font(.headline.weight(.semibold))
                .foregroundStyle(state.textColor)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 8)
                .background(state.background)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(state.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(vm.hasRevealed)
    }

    private func answerVisualState(choice: AdaptiveEarChoice, question: AdaptiveEarQuestion) -> AdaptiveAnswerVisualState {
        guard vm.hasRevealed else {
            return AdaptiveAnswerVisualState(
                background: SwiftAppTheme.surfaceSoft,
                border: SwiftAppTheme.line,
                textColor: SwiftAppTheme.text
            )
        }
        if choice.id == question.correctChoiceId {
            return AdaptiveAnswerVisualState(
                background: Color.green.opacity(0.14),
                border: Color.green.opacity(0.65),
                textColor: SwiftAppTheme.text
            )
        }
        if choice.id == vm.selectedChoiceID {
            return AdaptiveAnswerVisualState(
                background: Color.red.opacity(0.12),
                border: Color.red.opacity(0.55),
                textColor: SwiftAppTheme.text
            )
        }
        return AdaptiveAnswerVisualState(
            background: SwiftAppTheme.surfaceSoft,
            border: SwiftAppTheme.line,
            textColor: SwiftAppTheme.muted
        )
    }

    private struct AdaptiveAnswerVisualState {
        let background: Color
        let border: Color
        let textColor: Color
    }

    private func feedbackCard(_ feedback: AdaptiveEarFeedback, question: AdaptiveEarQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: feedback.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(feedback.wasCorrect ? Color.green : Color.red)
                Text(feedback.title)
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
            }
            Text("正确答案：\(question.correctAnswerText)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((feedback.wasCorrect ? Color.green : Color.red).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Hint strip helpers (simplified)

    @ViewBuilder
    private func hintChromaticStrip(for question: AdaptiveEarQuestion) -> some View {
        if case let .interval(q, _, _) = question {
            let strip = IntervalChromaticStrip.midisCoveringOctaveIncluding(lowMidi: q.lowMidi, highMidi: q.highMidi)
            chromaticPillGrid(strip: strip, highlightSet: [q.lowMidi, q.highMidi])
        }
    }

    @ViewBuilder
    private func chordHintOptionsView(for question: AdaptiveEarQuestion) -> some View {
        if case .chord = question {
            VStack(alignment: .leading, spacing: 8) {
                Text("点击各选项试听和弦声音")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(question.choices) { choice in
                        Button {
                            Task { await vm.playChordForLabel(choice.label) }
                        } label: {
                            Text(choice.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SwiftAppTheme.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(SwiftAppTheme.surfaceSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(SwiftAppTheme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func progressionHintOptionsView(for question: AdaptiveEarQuestion) -> some View {
        if case let .progression(item, _, _) = question {
            let key = item.musicKey ?? "C"
            let roman = item.progressionRoman ?? ""
            let chords = EarPlaybackMidi.letterChordSymbols(key: key, progressionRoman: roman)
            if !chords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("点击各和弦试听，拆解本题进行")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.brand)
                    HStack(spacing: 8) {
                        ForEach(chords, id: \.self) { chord in
                            Button {
                                Task { await vm.playChordForLabel(chord) }
                            } label: {
                                Text(chord)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SwiftAppTheme.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(SwiftAppTheme.surfaceSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(SwiftAppTheme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var singleNoteHintView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("标准音 A4（可点击重复播放）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.brand)
            Button {
                Task { await vm.playReferenceA4() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2").font(.caption)
                    Text("播放 A4（440Hz）").font(.subheadline.weight(.medium))
                }
                .foregroundStyle(SwiftAppTheme.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(SwiftAppTheme.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            let allNotes = [60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71]
            chromaticPillGrid(strip: allNotes, highlightSet: [])
        }
    }

    private func chromaticPillGrid(strip: [Int], highlightSet: Set<Int>) -> some View {
        let firstRowCount = (strip.count + 1) / 2
        let row1 = Array(strip.prefix(firstRowCount))
        let row2 = Array(strip.suffix(strip.count - firstRowCount))
        VStack(alignment: .leading, spacing: 6) {
            chromaticPillRow(midis: row1, highlights: highlightSet)
            chromaticPillRow(midis: row2, highlights: highlightSet)
        }
    }

    private func chromaticPillRow(midis: [Int], highlights: Set<Int>) -> some View {
        HStack(spacing: 6) {
            ForEach(midis, id: \.self) { midi in
                let isHl = highlights.contains(midi)
                Button {
                    Task { await vm.playPreviewNote(midi: midi) }
                } label: {
                    Text(scientificPitchLabel(midi: midi))
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(SwiftAppTheme.text)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .background(SwiftAppTheme.surfaceSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isHl ? SwiftAppTheme.brand : SwiftAppTheme.line, lineWidth: isHl ? 2 : 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scientificPitchLabel(midi: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let pc = midi % 12
        let octave = (midi / 12) - 1
        return "\(names[pc])\(octave)"
    }
}
```

- [ ] **Step 1:** Create `swift_ios_host/Sources/Practice/Views/FocusedEarTrainingSessionView.swift` with the above content

- [ ] **Step 2:** Verify it compiles

Run: `cd /Users/wanghan/Documents/guitar-ai-coach && xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`

- [ ] **Step 3:** Commit

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Practice/Views/FocusedEarTrainingSessionView.swift
git commit -m "feat: add FocusedEarTrainingSessionView for single-type training UI"
```

---

### Task 3: 创建 FocusedEarHubView（专项训练首页）

**Files:**
- Create: `swift_ios_host/Sources/Practice/Views/FocusedEarHubView.swift`

展示4个题型卡片，显示各题型名称、描述、当前听力值评分，点击跳转到对应专项训练。

```swift
import SwiftUI
import Core
import Ear

struct FocusedEarHubView: View {
    @State private var state: AdaptiveEarAbilityState = .initial
    @State private var loaded = false
    private let store: AdaptiveEarTrainingStoring = UserDefaultsAdaptiveEarTrainingStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("选择要强化的题型")
                    .font(.headline)
                    .foregroundStyle(SwiftAppTheme.text)
                Text("每道题的结果都会计入你的听力值")
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .padding(.bottom, 4)

                typeCard(
                    kind: .interval,
                    icon: "play.circle",
                    color: Color(red: 0.26, green: 0.57, blue: 0.98),
                    description: "听两音选音程"
                )
                typeCard(
                    kind: .chord,
                    icon: "pianokeys",
                    color: Color(red: 0.92, green: 0.27, blue: 0.21),
                    description: "大三 / 小三 / 属七 / 大七 / 小七"
                )
                typeCard(
                    kind: .progression,
                    icon: "music.note.list",
                    color: Color(red: 0.20, green: 0.65, blue: 0.33),
                    description: "常见流行进行，四选一"
                )
                typeCard(
                    kind: .singleNote,
                    icon: "speaker.wave.2",
                    color: Color(red: 0.98, green: 0.74, blue: 0.02),
                    description: "标准音 A4 参考，四选一"
                )
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("专项训练")
        .appPageBackground()
        .task {
            state = await store.loadState()
            loaded = true
        }
    }

    private func typeCard(kind: AdaptiveEarQuestionKind, icon: String, color: Color, description: String) -> some View {
        NavigationLink {
            TabBarHiddenContainer {
                FocusedEarTrainingSessionView(kind: kind)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(state.rating(for: kind).rounded()))")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(SwiftAppTheme.brand)
                        .monospacedDigit()
                    Text("听力值")
                        .font(.caption2)
                        .foregroundStyle(SwiftAppTheme.muted)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
            }
            .appCard()
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 1:** Create `swift_ios_host/Sources/Practice/Views/FocusedEarHubView.swift` with the above content

- [ ] **Step 2:** Verify it compiles

Run: `cd /Users/wanghan/Documents/guitar-ai-coach && xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`

- [ ] **Step 3:** Commit

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Practice/Views/FocusedEarHubView.swift
git commit -m "feat: add FocusedEarHubView as focused training entry page"
```

---

### Task 4: 修改 AdaptiveEarTrainingView — toolbar chart 改为 Menu

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Views/AdaptiveEarTrainingView.swift` (lines 52-61)

将 toolbar 中的 `chart.bar.fill` 按钮替换为 `ellipsis.circle` Menu，包含三个选项：训练统计、专项训练、练习日历。

修改位置（line 52-61）：

**修改前：**
```swift
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCombinedStats = true
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(SwiftAppTheme.text)
                }
                .accessibilityLabel("训练统计")
            }
        }
```

**修改后：**
```swift
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        TabBarHiddenContainer {
                            FocusedEarHubView()
                        }
                    } label: {
                        Label("专项训练", systemImage: "target")
                    }

                    Button {
                        showingCombinedStats = true
                    } label: {
                        Label("训练统计", systemImage: "chart.bar.fill")
                    }

                    NavigationLink {
                        TabBarHiddenContainer {
                            PracticeCalendarScreen(sessions: sessions)
                        }
                    } label: {
                        Label("练习日历", systemImage: "calendar")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(SwiftAppTheme.text)
                }
                .accessibilityLabel("更多")
            }
        }
```

需要把 `PracticeCalendarScreen` 从 `PracticeLandingView` 中改为内部可访问。当前它是 `PracticeLandingView` 的 private struct。需要将其改为 `fileprivate` 或将定义移到文件顶层。最简单的方式是在 `PracticeLandingView.swift` 中将 `PracticeCalendarScreen` 改为 `fileprivate`（当前已经是 private，fileprivate 即可被同文件其他类型访问，但 AdaptiveEarTrainingView 在其他文件）。

因此，需要将 `PracticeCalendarScreen` 的定义复制到 `AdaptiveEarTrainingView.swift` 文件顶部（作为 private struct），或提取到单独文件。

**更简单的方法：** 在 AdaptiveEarTrainingView.swift 顶部添加一个与 `CombinedStatsView` 同级的 `PracticeCalendarScreen` 副本。但为了避免重复，最佳方案是把 `PracticeCalendarScreen` 提取到独立文件。

注意：`CombinedStatsView` 已经是 `AdaptiveEarTrainingView.swift` 内的 `private struct`（line 1144），所以可以直接使用。

Also need to add import for `Practice` module at the top of the file (PracticeCalendarScreen references `PracticeSession` and related types).

```swift
// 在文件顶部 imports 后添加
import Practice
```

- [ ] **Step 1:** Edit `AdaptiveEarTrainingView.swift` replace the toolbar block (lines 52-61) with the Menu version above

- [ ] **Step 2:** Add `import Practice` to the file's imports

- [ ] **Step 3:** Verify it compiles

Run: `cd /Users/wanghan/Documents/guitar-ai-coach && xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30`

- [ ] **Step 4:** Commit

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Practice/Views/AdaptiveEarTrainingView.swift
git commit -m "refactor: replace toolbar chart button with Menu (focused training, stats, calendar)"
```

---

### Task 5: 移除 PracticeLandingView 的日历按钮

**Files:**
- Modify: `swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift` (lines 36-48)

移除 toolbar 中的 calendar NavigationLink。

**修改前（lines 36-48）：**
```swift
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TabBarHiddenContainer {
                        PracticeCalendarScreen(sessions: vm.sessions)
                    }
                } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(SwiftAppTheme.text)
                }
                .accessibilityLabel(AppL10n.t("practice_a11y_training_calendar"))
            }
        }
```

**修改后：** 移除整个 `.toolbar { ... }` 块。

- [ ] **Step 1:** Edit `PracticeLandingView.swift` remove the `.toolbar { ... }` block (lines 36-48)

- [ ] **Step 2:** Verify it compiles

Run: `cd /Users/wanghan/Documents/guitar-ai-coach && xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`

- [ ] **Step 3:** Commit

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add swift_ios_host/Sources/Practice/Views/PracticeLandingView.swift
git commit -m "refactor: remove calendar toolbar button from PracticeLandingView (moved to Menu)"
```

---

### Task 6: 验证整体编译

- [ ] **Step 1:** Full build

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
xcodebuild -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2:** If there are compilation errors, fix them

常见问题排查：
1. `PracticeCalendarScreen` 在 AdaptiveEarTrainingView.swift 中不可见 — 需要将其定义提取或复制到同一文件。如果编译报错，在 AdaptiveEarTrainingView.swift 底部、extension 之前添加一个简单的 PracticeCalendarScreen 副本。
2. `TabBarHiddenContainer` 是否在 scope 中 — 检查 import。
3. `Practice` 模块导入是否正确。

- [ ] **Step 3:** Final commit if any fixes were needed

```bash
cd /Users/wanghan/Documents/guitar-ai-coach
git add -A
git commit -m "fix: resolve compilation issues from toolbar refactor"
```
