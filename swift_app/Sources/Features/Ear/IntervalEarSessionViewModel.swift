import Foundation

@MainActor
public final class IntervalEarSessionViewModel: ObservableObject {
    @Published public private(set) var pageIndex = 0
    @Published public private(set) var correctCount = 0
    @Published public private(set) var question: IntervalQuestion?
    @Published public var selectedChoiceIndex: Int?
    @Published public private(set) var revealed = false
    @Published public private(set) var finished = false
    @Published public private(set) var playError: String?

    public let totalQuestions: Int
    public let difficulty: IntervalEarDifficulty
    private let player: IntervalTonePlaying
    private var rng: SystemRandomNumberGenerator

    public init(
        totalQuestions: Int = 5,
        difficulty: IntervalEarDifficulty = .初级,
        player: IntervalTonePlaying = IntervalTonePlayer()
    ) {
        self.totalQuestions = max(1, totalQuestions)
        self.difficulty = difficulty
        self.player = player
        self.rng = SystemRandomNumberGenerator()
        self.question = IntervalQuestionGenerator.next(difficulty: difficulty, antiAbsolutePitch: nil, using: &rng)
    }

    public func playPair() async {
        guard let q = question else { return }
        do {
            try await player.playAscendingPair(lowMidi: q.lowMidi, highMidi: q.highMidi)
            playError = nil
        } catch {
            playError = "播放失败：\(error.localizedDescription)"
        }
    }

    public func submit() {
        guard let q = question, let idx = selectedChoiceIndex, !revealed else { return }
        if q.choices[idx].semitones == q.answer.semitones {
            correctCount += 1
        }
        revealed = true
    }

    public func nextOrFinish() {
        if pageIndex >= totalQuestions - 1 {
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
        "音程 \(totalQuestions) 题 · 答对 \(correctCount) 题"
    }
}
