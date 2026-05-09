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
    /// 当前题是否已至少成功完整播放一次两音；未满足前不可选答案。
    @Published public private(set) var hasCompletedInitialAudition = false

    /// `nil` 表示不限题量，可一直「下一题」由算法续出题；非 `nil` 时答满后结束并弹出小结。
    public let maxQuestions: Int?
    /// 当前难度；可在未揭示本题答案前通过 `setDifficultyIfChanged` 调整（会重出一题并需重新试听）。
    @Published public private(set) var difficulty: IntervalEarDifficulty
    private let player: IntervalTonePlaying
    private let historyStore: any IntervalEarHistoryStoring
    private var rng: SystemRandomNumberGenerator
    private var pairPlaybackTask: Task<Void, Never>?

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

    /// 切换难度：仅在本题尚未判分揭示时允许；会取消播放、重随机本题，并清空「已完整试听」状态。
    public func setDifficultyIfChanged(_ newValue: IntervalEarDifficulty) {
        guard newValue != difficulty else { return }
        guard !revealed else { return }
        let anchorLow = pageIndex > 0 ? question?.lowMidi : nil
        cancelPlayback()
        difficulty = newValue
        selectedChoiceIndex = nil
        question = IntervalQuestionGenerator.next(
            difficulty: difficulty,
            antiAbsolutePitch: Self.antiAbsolutePitch(for: difficulty, previousLowerMidi: anchorLow),
            using: &rng
        )
        hasCompletedInitialAudition = false
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

    /// 播放当前题上行两音；若已在播放会先取消上一轮。`async` 以便单测与 UI 在「整段播完」后再判题。
    public func playPair() async {
        pairPlaybackTask?.cancel()
        pairPlaybackTask = nil
        guard let q = question else { return }
        isPlaybackInProgress = true
        defer {
            isPlaybackInProgress = false
            pairPlaybackTask = nil
        }
        let work = Task { @MainActor in
            do {
                try await self.player.playAscendingPair(lowMidi: q.lowMidi, highMidi: q.highMidi)
                self.playError = nil
                self.hasCompletedInitialAudition = true
            } catch is CancellationError {
                self.player.cancelIntervalPlayback()
            } catch {
                self.playError = "播放失败：\(error.localizedDescription)"
            }
        }
        pairPlaybackTask = work
        await work.value
    }

    /// 离开音程页或需要立刻静音时调用：取消尚未完成的 `Task.sleep` 间隔，并截断采样器上本题两音。
    public func cancelPlayback() {
        player.cancelIntervalPlayback()
        pairPlaybackTask?.cancel()
        pairPlaybackTask = nil
        isPlaybackInProgress = false
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
        guard hasCompletedInitialAudition else { return }
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
        hasCompletedInitialAudition = false
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
