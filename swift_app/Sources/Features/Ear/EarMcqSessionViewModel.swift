import Foundation

@MainActor
public final class EarMcqSessionViewModel: ObservableObject {
    @Published public private(set) var loading = true
    @Published public private(set) var loadError: String?
    @Published public private(set) var session: [EarBankItem] = []
    @Published public private(set) var pageIndex = 0
    @Published public private(set) var correctCount = 0
    @Published public private(set) var question: EarBankItem?
    @Published public var selectedChoiceIndex: Int?
    @Published public private(set) var revealed = false
    @Published public private(set) var finished = false
    @Published public private(set) var playError: String?

    public let title: String
    public let bank: String
    public let totalQuestions: Int
    /// 仅 `bank == "A"`（和弦听辨）时使用：程序化出题难度。
    public let chordDifficulty: EarChordMcqDifficulty

    private let loader: EarSeedLoader
    private let player: EarChordPlaying
    private var chordRng = SystemRandomNumberGenerator()

    public init(
        title: String,
        bank: String,
        totalQuestions: Int = 10,
        chordDifficulty: EarChordMcqDifficulty = .初级,
        loader: EarSeedLoader = .shared,
        player: EarChordPlaying = EarChordPlayer()
    ) {
        self.title = title
        self.bank = bank
        self.totalQuestions = max(1, totalQuestions)
        self.chordDifficulty = chordDifficulty
        self.loader = loader
        self.player = player
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

    public func submit() {
        guard let q = question, let idx = selectedChoiceIndex, !revealed else { return }
        if q.options[idx].key == q.correctOptionKey {
            correctCount += 1
        }
        revealed = true
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
        "共 \(session.count) 题 · 答对 \(correctCount) 题"
    }
}
