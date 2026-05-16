import Foundation

/// 和弦听辨 / 和弦进行等 `EarMcqSessionView` 单次作答落盘。
public struct EarMcqAttemptRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var occurredAt: Date
    public var bank: String
    public var title: String
    public var questionId: String
    public var questionType: String
    public var promptZh: String
    public var optionKeys: [String]
    public var optionLabels: [String]
    public var selectedIndex: Int
    public var selectedKey: String
    public var correctOptionKey: String
    public var wasCorrect: Bool
    public var pageIndex: Int
    public var chordDifficultyRaw: String?
    /// `bank == "B"`（和弦进行）时写入当前档位，与 `chordDifficultyRaw` 对称。
    public var progressionDifficultyRaw: String?

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        bank: String,
        title: String,
        questionId: String,
        questionType: String,
        promptZh: String,
        optionKeys: [String],
        optionLabels: [String],
        selectedIndex: Int,
        selectedKey: String,
        correctOptionKey: String,
        wasCorrect: Bool,
        pageIndex: Int,
        chordDifficultyRaw: String?,
        progressionDifficultyRaw: String? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.bank = bank
        self.title = title
        self.questionId = questionId
        self.questionType = questionType
        self.promptZh = promptZh
        self.optionKeys = optionKeys
        self.optionLabels = optionLabels
        self.selectedIndex = selectedIndex
        self.selectedKey = selectedKey
        self.correctOptionKey = correctOptionKey
        self.wasCorrect = wasCorrect
        self.pageIndex = pageIndex
        self.chordDifficultyRaw = chordDifficultyRaw
        self.progressionDifficultyRaw = progressionDifficultyRaw
    }
}

public protocol EarMcqHistoryStoring: Sendable {
    func appendAttempt(_ record: EarMcqAttemptRecord) async
}
