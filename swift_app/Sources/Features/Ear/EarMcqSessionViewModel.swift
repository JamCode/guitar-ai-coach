import Foundation

@MainActor
public final class EarMcqSessionViewModel: ObservableObject {
    @Published public private(set) var loading = true
    @Published public private(set) var loadError: String?
    @Published public private(set) var session: [EarBankItem] = []
    @Published public private(set) var pageIndex = 0
    @Published public private(set) var correctCount = 0
    @Published public private(set) var answeredCount = 0
    @Published public private(set) var question: EarBankItem?
    @Published public var selectedChoiceIndex: Int?
    @Published public private(set) var revealed = false
    @Published public private(set) var finished = false
    @Published public private(set) var playError: String?
    /// 整段和弦（或进行）播放结束前为 `true`，用于禁用「播放」。
    @Published public private(set) var isPlaybackInProgress = false

    public let title: String
    public let bank: String
    /// `bank == "A"` 时：`nil` 为不限题量（与音程练耳一致，可持续「下一题」）；非 `nil` 为本轮题量上限。
    /// `bank == "B"` 时：从题库抽取至多 `maxQuestions ?? 10` 题。
    public let maxQuestions: Int?

    /// 仅 `bank == "A"`（和弦听辨）时使用：程序化出题难度。
    public let chordDifficulty: EarChordMcqDifficulty

    private let loader: EarSeedLoader
    private let player: EarChordPlaying
    private let historyStore: any EarMcqHistoryStoring
    private var chordRng = SystemRandomNumberGenerator()

    public init(
        title: String,
        bank: String,
        maxQuestions: Int? = nil,
        chordDifficulty: EarChordMcqDifficulty = .初级,
        loader: EarSeedLoader = .shared,
        player: EarChordPlaying = EarChordPlayer(),
        historyStore: any EarMcqHistoryStoring = EarMcqFileHistoryStore.shared
    ) {
        self.title = title
        self.bank = bank
        self.maxQuestions = maxQuestions.map { max(1, $0) }
        self.chordDifficulty = chordDifficulty
        self.loader = loader
        self.player = player
        self.historyStore = historyStore
    }

    /// `bank == "A"` 且 `maxQuestions == nil` 时可一直「下一题」；和弦进行等题库模式始终有上限。
    public var hasSessionCap: Bool {
        if bank == "A" { return maxQuestions != nil }
        return true
    }

    /// 有上限时，当前题是否为最后一题（揭示后按钮文案为「查看结果」）。
    public var isOnLastCappedQuestion: Bool {
        guard hasSessionCap else { return false }
        guard !session.isEmpty else { return false }
        return pageIndex >= session.count - 1
    }

    /// 与音程练耳一致：不限题量会话内持续累计正确率（本题判分前 `answeredCount` 不含当前题）。
    public var sessionStatsLine: String {
        if answeredCount == 0 {
            return "作答后在此累计正确率"
        }
        let pct = (Double(correctCount) / Double(answeredCount) * 100).rounded()
        return "已答 \(answeredCount) 题 · 答对 \(correctCount) · 正确率 \(Int(pct))%"
    }

    public func bootstrap() async {
        loading = true
        loadError = nil
        if bank == "A" {
            if let cap = maxQuestions {
                session = EarChordMcqGenerator.buildSession(
                    count: cap,
                    difficulty: chordDifficulty,
                    using: &chordRng
                )
                question = session.first
            } else {
                session = []
                question = EarChordMcqGenerator.makeQuestion(
                    difficulty: chordDifficulty,
                    avoid: nil,
                    using: &chordRng
                )
            }
            pageIndex = 0
            correctCount = 0
            answeredCount = 0
            selectedChoiceIndex = nil
            revealed = false
            finished = false
            loading = false
            return
        }
        do {
            let doc = try await loader.load()
            let pool = bank == "B" ? doc.bankB : doc.bankA
            if pool.isEmpty {
                loadError = "题库为空（bank \(bank)）"
                loading = false
                return
            }
            let cap = max(1, maxQuestions ?? 10)
            session = Array(pool.shuffled().prefix(min(cap, pool.count)))
            question = session.first
            pageIndex = 0
            correctCount = 0
            answeredCount = 0
            selectedChoiceIndex = nil
            revealed = false
            finished = false
            loading = false
        } catch {
            loadError = "\(error.localizedDescription)"
            loading = false
        }
    }

    public func playCurrent() async {
        guard let q = question else { return }
        guard !isPlaybackInProgress else { return }
        isPlaybackInProgress = true
        defer { isPlaybackInProgress = false }
        do {
            if q.mode == "B" || q.questionType == "progression_recognition" {
                try await player.playChordSequence(EarPlaybackMidi.forProgression(q))
            } else if let frets = q.playbackFretsSixToOne, frets.count == 6 {
                try await player.playChordFromFretsSixToOne(frets)
            } else {
                try await player.playChordMidis(EarPlaybackMidi.forSingleChord(q))
            }
            playError = nil
        } catch {
            playError = "播放失败：\(error.localizedDescription)"
        }
    }

    public func playPreviewNote(midi: Int) async {
        do {
            try await player.playSinglePreview(midi: midi)
        } catch {}
    }

    public func selectChoice(_ index: Int) {
        guard !revealed, let q = question, q.options.indices.contains(index) else { return }
        selectedChoiceIndex = index
        submit()
    }

    public func submit() {
        guard let q = question, let idx = selectedChoiceIndex, !revealed else { return }
        let picked = q.options[idx]
        let ok = picked.key == q.correctOptionKey
        if ok {
            correctCount += 1
        }
        answeredCount += 1
        let record = EarMcqAttemptRecord(
            bank: bank,
            title: title,
            questionId: q.id,
            questionType: q.questionType,
            promptZh: q.promptZh,
            optionKeys: q.options.map(\.key),
            optionLabels: q.options.map(\.label),
            selectedIndex: idx,
            selectedKey: picked.key,
            correctOptionKey: q.correctOptionKey,
            wasCorrect: ok,
            pageIndex: pageIndex,
            chordDifficultyRaw: bank == "A" ? chordDifficulty.rawValue : nil
        )
        revealed = true
        let store = historyStore
        Task { await store.appendAttempt(record) }
    }

    public func nextOrFinish() {
        if bank == "A", maxQuestions == nil {
            let avoid = Self.chordAvoidPair(from: question)
            pageIndex += 1
            selectedChoiceIndex = nil
            revealed = false
            question = EarChordMcqGenerator.makeQuestion(
                difficulty: chordDifficulty,
                avoid: avoid,
                using: &chordRng
            )
            return
        }
        if pageIndex >= session.count - 1 {
            finished = true
            return
        }
        pageIndex += 1
        question = session[pageIndex]
        selectedChoiceIndex = nil
        revealed = false
    }

    public var summaryText: String {
        let pct = answeredCount == 0 ? 0 : Int((Double(correctCount) / Double(answeredCount) * 100).rounded())
        if bank == "A", maxQuestions == nil {
            return "累计 \(answeredCount) 题 · 答对 \(correctCount) · 正确率 \(pct)%"
        }
        return "共 \(session.count) 题 · 答对 \(correctCount) / \(answeredCount) · 正确率 \(pct)%"
    }

    private static func chordAvoidPair(from item: EarBankItem?) -> (root: String, quality: EarChordQuality)? {
        guard let item,
              let r = item.root,
              let tok = item.targetQuality,
              let qual = EarChordQuality(targetQualityToken: tok)
        else { return nil }
        return (r, qual)
    }
}
