import Foundation

@MainActor
public final class IntervalEarSessionViewModel: ObservableObject {
    @Published public private(set) var pageIndex = 0
    @Published public private(set) var correctCount = 0
    /// 已判分题目数（每题提交一次后 +1），用于正确率。
    @Published public private(set) var answeredCount = 0
    @Published public private(set) var question: IntervalQuestion?
    @Published public var selectedChoiceIndex: Int?
    @Published public private(set) var revealed = false
    @Published public private(set) var finished = false
    @Published public private(set) var playError: String?
    /// 整段两音（含间隔与第二音释音）播放结束前为 `true`，用于禁用「播放」。
    @Published public private(set) var isPlaybackInProgress = false

    /// `nil` 表示不限题量，可一直「下一题」由算法续出题；非 `nil` 时答满后结束并弹出小结。
    public let maxQuestions: Int?
    public let difficulty: IntervalEarDifficulty
    private let player: IntervalTonePlaying
    private let historyStore: any IntervalEarHistoryStoring
    private var rng: SystemRandomNumberGenerator

    public init(
        maxQuestions: Int? = nil,
        difficulty: IntervalEarDifficulty = .初级,
        player: IntervalTonePlaying = IntervalTonePlayer(),
        historyStore: any IntervalEarHistoryStoring = IntervalEarFileHistoryStore.shared
    ) {
        self.maxQuestions = maxQuestions.map { max(1, $0) }
        self.difficulty = difficulty
        self.player = player
        self.historyStore = historyStore
        self.rng = SystemRandomNumberGenerator()
        self.question = IntervalQuestionGenerator.next(difficulty: difficulty, antiAbsolutePitch: nil, using: &rng)
    }

    /// 是否有题量上限（有则最后一题后进入「查看结果」流程）。
    public var hasSessionCap: Bool { maxQuestions != nil }

    /// 在「有上限」模式下是否已处于最后一题（已揭示后点按钮将结束）。
    public var isOnLastCappedQuestion: Bool {
        guard let cap = maxQuestions else { return false }
        return pageIndex >= cap - 1
    }

    /// 当前会话正确率说明（不限题量时持续更新）。
    public var sessionStatsLine: String {
        if answeredCount == 0 {
            return "作答后在此累计正确率"
        }
        let pct = (Double(correctCount) / Double(answeredCount) * 100).rounded()
        return "已答 \(answeredCount) 题 · 答对 \(correctCount) · 正确率 \(Int(pct))%"
    }

    public func playPair() async {
        guard let q = question else { return }
        guard !isPlaybackInProgress else { return }
        isPlaybackInProgress = true
        defer { isPlaybackInProgress = false }
        do {
            try await player.playAscendingPair(lowMidi: q.lowMidi, highMidi: q.highMidi)
            playError = nil
        } catch {
            playError = "播放失败：\(error.localizedDescription)"
        }
    }

    /// 音区条单音试听（与指板同源采样，略短音长）。
    public func playPreviewNote(midi: Int) async {
        do {
            try await player.playSinglePreview(midi: midi)
        } catch {
            // 试听失败不阻断答题流；如需可后续接轻提示
        }
    }

    /// 点选某一格后立即判分并揭示（不再单独点「提交答案」）。
    public func selectChoice(_ index: Int) {
        guard !revealed, let q = question, q.choices.indices.contains(index) else { return }
        selectedChoiceIndex = index
        submit()
    }

    public func submit() {
        guard let q = question, let idx = selectedChoiceIndex, !revealed else { return }
        let picked = q.choices[idx]
        let ok = picked.semitones == q.answer.semitones
        if ok {
            correctCount += 1
        }
        answeredCount += 1
        let record = IntervalEarAttemptRecord(
            difficultyRaw: difficulty.rawValue,
            lowMidi: q.lowMidi,
            highMidi: q.highMidi,
            answerSemitones: q.answer.semitones,
            answerNameZh: q.answer.nameZh,
            selectedIndex: idx,
            selectedSemitones: picked.semitones,
            selectedNameZh: picked.nameZh,
            wasCorrect: ok,
            choiceSemitones: q.choices.map(\.semitones),
            choiceLabelsZh: q.choices.map(\.nameZh),
            pageIndex: pageIndex
        )
        revealed = true
        let store = historyStore
        Task { await store.appendAttempt(record) }
    }

    public func nextOrFinish() {
        if let cap = maxQuestions, pageIndex >= cap - 1 {
            finished = true
            return
        }
        let previousLow = question?.lowMidi
        pageIndex += 1
        selectedChoiceIndex = nil
        revealed = false
        question = IntervalQuestionGenerator.next(
            difficulty: difficulty,
            antiAbsolutePitch: Self.antiAbsolutePitch(for: difficulty, previousLowerMidi: previousLow),
            using: &rng
        )
    }

    /// 中/高档默认拉开相邻题低音 MIDI，减轻「记绝对音高」猜题。
    private static func antiAbsolutePitch(
        for difficulty: IntervalEarDifficulty,
        previousLowerMidi: Int?
    ) -> IntervalAntiAbsolutePitch? {
        guard let p = previousLowerMidi else { return nil }
        switch difficulty {
        case .初级:
            return nil
        case .中级:
            return IntervalAntiAbsolutePitch(previousLowerMidi: p, minSemitoneDelta: 3)
        case .高级:
            return IntervalAntiAbsolutePitch(previousLowerMidi: p, minSemitoneDelta: 5)
        }
    }

    public var summaryText: String {
        if let cap = maxQuestions {
            let pct = answeredCount == 0 ? 0 : Int((Double(correctCount) / Double(answeredCount) * 100).rounded())
            return "本轮 \(cap) 题 · 答对 \(correctCount) / \(answeredCount) · 正确率 \(pct)%"
        }
        let pct = answeredCount == 0 ? 0 : Int((Double(correctCount) / Double(answeredCount) * 100).rounded())
        return "累计 \(answeredCount) 题 · 答对 \(correctCount) · 正确率 \(pct)%"
    }
}
