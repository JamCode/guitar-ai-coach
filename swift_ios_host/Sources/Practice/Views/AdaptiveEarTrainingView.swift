import SwiftUI
import Core
import Ear

struct AdaptiveEarTrainingView: View {
    let sessions: [PracticeSession]

    @StateObject private var vm = AdaptiveEarTrainingViewModel()
    @AppStorage("adaptive_ear_auto_play_next") private var autoPlayNext = false
    @AppStorage("adaptive_ear_show_explanation") private var showExplanation = true
    @State private var showingCombinedStats = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                abilityCard

                if vm.loading {
                    ProgressView("生成练耳题中…")
                        .frame(maxWidth: .infinity)
                        .appCard()
                } else if let error = vm.loadError {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error)
                            .foregroundStyle(SwiftAppTheme.text)
                        Button("重试") {
                            Task { await vm.bootstrap() }
                        }
                        .appPrimaryButton()
                    }
                    .appCard()
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
        .practiceAdaptiveScrollBackground()
        .refreshable { await vm.bootstrap() }
        .task { await vm.bootstrap() }
        .task(id: vm.questionToken) {
            guard autoPlayNext else { return }
            await vm.playCurrent()
        }
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
        .sheet(isPresented: $showingCombinedStats) {
            NavigationStack {
                CombinedStatsView(
                    state: vm.state,
                    records: vm.records,
                    sessions: sessions
                )
            }
        }
        .onDisappear {
            vm.cancelPlayback()
        }
    }

    private var abilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("听力值 \(vm.state.roundedOverallRating)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(SwiftAppTheme.text)
                        .monospacedDigit()
                    Text(vm.recommendationLine)
                        .font(.footnote)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(vm.state.levelTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(SwiftAppTheme.brandSoft)
                        .clipShape(Capsule())
                    Text(vm.recentAccuracyText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SwiftAppTheme.text)
                    Text(vm.todayCountText)
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                }
            }

            HStack(spacing: 8) {
                ratingChip(title: "音程", value: vm.state.intervalRating)
                ratingChip(title: "和弦", value: vm.state.chordRating)
                ratingChip(title: "进行", value: vm.state.progressionRating)
            }
        }
        .appCard()
        .accessibilityIdentifier("adaptiveEar.abilityCard")
    }

    private func ratingChip(title: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(SwiftAppTheme.muted)
            Text("\(Int(value.rounded()))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SwiftAppTheme.text)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(SwiftAppTheme.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                Text("第 \(vm.state.totalAnswered + 1) 题")
                    .font(.caption)
                    .foregroundStyle(SwiftAppTheme.muted)
            }

            Text(question.prompt)
                .font(.title3.weight(.bold))
                .foregroundStyle(SwiftAppTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            playButton

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(question.choices) { choice in
                    answerButton(choice: choice, question: question)
                }
            }

            if let feedback = vm.feedback {
                feedbackCard(feedback, question: question)
            }

            HStack(spacing: 10) {
                Button("下一题") {
                    Task { await vm.nextQuestion() }
                }
                .appPrimaryButton()
                .frame(maxWidth: .infinity)
                .disabled(!vm.hasRevealed)
            }
        }
        .appCard()
        .accessibilityIdentifier("adaptiveEar.questionCard")
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

    private func answerButton(choice: AdaptiveEarChoice, question: AdaptiveEarQuestion) -> some View {
        let state = vm.answerVisualState(choice: choice, question: question)
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
            if showExplanation {
                Text(question.explanation)
                    .font(.footnote)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            intervalChromaticStrip(for: question)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((feedback.wasCorrect ? Color.green : Color.red).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func intervalChromaticStrip(for question: AdaptiveEarQuestion) -> some View {
        if case let .interval(interval, _, _) = question {
            let strip = IntervalChromaticStrip.midisCoveringOctaveIncluding(
                lowMidi: interval.lowMidi,
                highMidi: interval.highMidi
            )
            let firstRowCount = (strip.count + 1) / 2
            let row1 = Array(strip.prefix(firstRowCount))
            let row2 = Array(strip.suffix(strip.count - firstRowCount))

            VStack(alignment: .leading, spacing: 8) {
                Text("本题音区（可点试听，至少一个八度）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.muted)
                VStack(alignment: .leading, spacing: 6) {
                    intervalChromaticPillRow(midis: row1, question: interval)
                    intervalChromaticPillRow(midis: row2, question: interval)
                }
            }
            .padding(.top, 4)
        }
    }

    private func intervalChromaticPillRow(midis: [Int], question: IntervalQuestion) -> some View {
        HStack(spacing: 6) {
            ForEach(midis, id: \.self) { midi in
                let isQuestionNote = midi == question.lowMidi || midi == question.highMidi
                Button {
                    Task { await vm.playPreviewNote(midi: midi) }
                } label: {
                    Text(Self.scientificPitchLabel(midi: midi))
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
                        .stroke(
                            isQuestionNote ? SwiftAppTheme.brand : SwiftAppTheme.line,
                            lineWidth: isQuestionNote ? 2 : 1
                        )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func scientificPitchLabel(midi: Int) -> String {
        "\(PitchMath.midiToNoteName(midi))\(midi / 12 - 1)"
    }

    }

private struct AdaptiveAnswerVisualState {
    let background: Color
    let border: Color
    let textColor: Color
}

private extension AdaptiveEarTrainingViewModel {
    func answerVisualState(choice: AdaptiveEarChoice, question: AdaptiveEarQuestion) -> AdaptiveAnswerVisualState {
        guard hasRevealed else {
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
        if choice.id == selectedChoiceID {
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
}

struct AdaptiveEarFeedback: Equatable {
    let wasCorrect: Bool
    let title: String
}

@MainActor
final class AdaptiveEarTrainingViewModel: ObservableObject {
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

    private let store: AdaptiveEarTrainingStoring
    private let intervalPlayer: IntervalTonePlaying
    private let chordPlayer: EarChordPlaying
    private var rng = SystemRandomNumberGenerator()
    private var questionStartedAt = Date()
    private var previousIntervalLowMidi: Int?
    private var playTask: Task<Void, Never>?
    private var prefetchTask: Task<AdaptiveEarQuestion, Never>?

    init(
        store: AdaptiveEarTrainingStoring = UserDefaultsAdaptiveEarTrainingStore(),
        intervalPlayer: IntervalTonePlaying = IntervalTonePlayer(),
        chordPlayer: EarChordPlaying = EarChordPlayer()
    ) {
        self.store = store
        self.intervalPlayer = intervalPlayer
        self.chordPlayer = chordPlayer
    }

    var recentAccuracyText: String {
        guard let accuracy = AdaptiveEarTrainingEngine.recentAccuracy(records: records) else {
            return "近20题 --"
        }
        return "近20题 \(Int((accuracy * 100).rounded()))%"
    }

    var todayCountText: String {
        let calendar = Calendar(identifier: .gregorian)
        let count = records.filter { calendar.isDateInToday($0.answeredAt) }.count
        return "今日 \(count) 题"
    }

    var recommendationLine: String {
        AdaptiveEarTrainingEngine.recommendationLine(state: state, records: records)
    }

    var mistakeCountText: String {
        let count = records.filter { !$0.wasCorrect }.count
        return count == 0 ? "暂无错题" : "\(count) 道错题"
    }

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
        isPlaying = true
        let work = Task { @MainActor in
            do {
                try await intervalPlayer.playSinglePreview(midi: midi)
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

    func submit(_ choice: AdaptiveEarChoice) {
        guard !hasRevealed, let question = currentQuestion else { return }
        selectedChoiceID = choice.id
        let correct = choice.id == question.correctChoiceId
        saveAnswer(question: question, selectedAnswer: choice.label, wasCorrect: correct, skipped: false)
        feedback = AdaptiveEarFeedback(wasCorrect: correct, title: correct ? "答对了" : "再听一遍这个差异")
        hasRevealed = true
        startPrefetchingNextQuestion()
    }

    func markTooHard() {
        guard !hasRevealed, let question = currentQuestion else { return }
        saveAnswer(question: question, selectedAnswer: nil, wasCorrect: false, skipped: true)
        feedback = AdaptiveEarFeedback(wasCorrect: false, title: "已标记太难")
        hasRevealed = true
        startPrefetchingNextQuestion()
    }

    func skipQuestion() {
        guard !hasRevealed else { return }
        Task { await nextQuestion() }
    }

    func nextQuestion() async {
        cancelPlayback()
        isPreparingQuestion = true
        let question: AdaptiveEarQuestion
        if let prefetchTask {
            question = await prefetchTask.value
            self.prefetchTask = nil
        } else {
            question = await Self.makeQuestion(request: makeNextQuestionRequest())
        }
        currentQuestion = question
        rememberIntervalLowMidi(from: question)
        selectedChoiceID = nil
        hasRevealed = false
        feedback = nil
        questionStartedAt = Date()
        questionToken = UUID()
        isPreparingQuestion = false
    }

    private func startPrefetchingNextQuestion() {
        prefetchTask?.cancel()
        let request = makeNextQuestionRequest()
        prefetchTask = Task.detached(priority: .utility) {
            await Self.makeQuestion(request: request)
        }
    }

    private func makeNextQuestionRequest() -> AdaptiveEarQuestionRequest {
        let kind = AdaptiveEarTrainingEngine.selectNextKind(
            state: state,
            records: records,
            roll: Double.random(in: 0 ..< 1, using: &rng)
        )
        let difficulty = AdaptiveEarTrainingEngine.difficulty(for: kind, state: state)
        let score = AdaptiveEarTrainingEngine.difficultyScore(kind: kind, difficulty: difficulty)
        return AdaptiveEarQuestionRequest(
            kind: kind,
            difficulty: difficulty,
            score: score,
            previousIntervalLowMidi: previousIntervalLowMidi
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
        }
    }

    private func rememberIntervalLowMidi(from question: AdaptiveEarQuestion) {
        if case let .interval(q, _, _) = question {
            previousIntervalLowMidi = q.lowMidi
        }
    }

    private func saveAnswer(
        question: AdaptiveEarQuestion,
        selectedAnswer: String?,
        wasCorrect: Bool,
        skipped: Bool
    ) {
        let beforeState = state
        let beforeKind = beforeState.rating(for: question.kind)
        let nextState = AdaptiveEarTrainingEngine.stateAfterAnswer(
            state: beforeState,
            kind: question.kind,
            difficultyScore: question.difficultyScore,
            wasCorrect: wasCorrect
        )
        state = nextState
        let record = AdaptiveEarAttemptRecord(
            id: UUID().uuidString,
            questionKindRaw: question.kind.rawValue,
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
            ratingAfterKind: nextState.rating(for: question.kind),
            skipped: skipped
        )
        records.append(record)
        Task {
            await store.saveState(nextState)
            await store.appendAttempt(record)
        }
    }

    nonisolated private static func antiAbsolutePitch(
        for difficulty: IntervalEarDifficulty,
        previousIntervalLowMidi: Int?
    ) -> IntervalAntiAbsolutePitch? {
        guard let previousIntervalLowMidi else { return nil }
        switch difficulty {
        case .初级:
            return nil
        case .中级:
            return IntervalAntiAbsolutePitch(previousLowerMidi: previousIntervalLowMidi, minSemitoneDelta: 3)
        case .高级:
            return IntervalAntiAbsolutePitch(previousLowerMidi: previousIntervalLowMidi, minSemitoneDelta: 5)
        }
    }
}

private struct AdaptiveEarQuestionRequest: Sendable {
    let kind: AdaptiveEarQuestionKind
    let difficulty: AdaptiveEarDifficulty
    let score: Int
    let previousIntervalLowMidi: Int?
}

private struct CombinedStatsView: View {
    let state: AdaptiveEarAbilityState
    let records: [AdaptiveEarAttemptRecord]
    let sessions: [PracticeSession]

    var body: some View {
        List {
            Section("听力能力") {
                statsRow("总听力值", "\(state.roundedOverallRating) · \(state.levelTitle)")
                statsRow("音程", "\(Int(state.intervalRating.rounded()))")
                statsRow("和弦", "\(Int(state.chordRating.rounded()))")
                statsRow("和弦进行", "\(Int(state.progressionRating.rounded()))")
            }
            Section("近期表现") {
                statsRow("总题数", "\(records.count)")
                statsRow("近 20 题正确率", recentAccuracyText)
                statsRow("连续答对", "\(state.consecutiveCorrect)")
                statsRow("连续答错", "\(state.consecutiveWrong)")
                statsRow("今日题数", "\(todayCount)")
            }
            Section("最近 7 天练习") {
                let s = computeRollingSevenDayPracticeStats(sessions, now: Date())
                statsRow("练习次数", "\(s.sessionCount) 次")
                statsRow("总时长", "\(s.totalDurationSeconds / 60) 分钟")
            }
        }
        .navigationTitle("训练统计")
    }

    private var recentAccuracyText: String {
        guard let accuracy = AdaptiveEarTrainingEngine.recentAccuracy(records: records) else { return "--" }
        return "\(Int((accuracy * 100).rounded()))%"
    }

    private var todayCount: Int {
        let calendar = Calendar(identifier: .gregorian)
        return records.filter { calendar.isDateInToday($0.answeredAt) }.count
    }

    private func statsRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func practiceAdaptiveScrollBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(SwiftAppTheme.bg.ignoresSafeArea())
            .tint(SwiftAppTheme.brand)
    }
}
