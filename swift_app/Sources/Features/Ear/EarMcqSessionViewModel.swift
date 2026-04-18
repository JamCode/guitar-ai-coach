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
    public let totalQuestions: Int
    /// 仅 `bank == "A"`（和弦听辨）时使用：程序化出题难度。
    public let chordDifficulty: EarChordMcqDifficulty

    private let loader: EarSeedLoader
    private let player: EarChordPlaying
    private let historyStore: any EarMcqHistoryStoring
    private var chordRng = SystemRandomNumberGenerator()

    public init(
        title: String,
        bank: String,
        totalQuestions: Int = 10,
        chordDifficulty: EarChordMcqDifficulty = .初级,
        loader: EarSeedLoader = .shared,
        player: EarChordPlaying = EarChordPlayer(),
        historyStore: any EarMcqHistoryStoring = EarMcqFileHistoryStore.shared
    ) {
        self.title = title
        self.bank = bank
        self.totalQuestions = max(1, totalQuestions)
        self.chordDifficulty = chordDifficulty
        self.loader = loader
        self.player = player
        self.historyStore = historyStore
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
            session = EarChordMcqGenerator.buildSession(
                count: totalQuestions,
                difficulty: chordDifficulty,
                using: &chordRng
            )
            question = session.first
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
            session = Array(pool.shuffled().prefix(min(totalQuestions, pool.count)))
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
        return "共 \(session.count) 题 · 答对 \(correctCount) / \(answeredCount) · 正确率 \(pct)%"
    }
}
