import Foundation

/// 单次「音程识别」作答落盘模型（与入口无关，凡经 `IntervalEarSessionViewModel` 判分即写入）。
public struct IntervalEarAttemptRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// 判分时刻（本地时区写入 ISO8601 于 JSON）。
    public var occurredAt: Date
    public var difficultyRaw: String
    public var lowMidi: Int
    public var highMidi: Int
    public var answerSemitones: Int
    public var answerNameZh: String
    /// 用户点选的格子下标（0...3）。
    public var selectedIndex: Int
    public var selectedSemitones: Int
    public var selectedNameZh: String
    public var wasCorrect: Bool
    /// 本题四选项半音（与 UI 顺序一致）。
    public var choiceSemitones: [Int]
    /// 本题四选项中文名（与 `choiceSemitones` 对齐）。
    public var choiceLabelsZh: [String]
    /// 本会话内第几题（从 0 起，与 `pageIndex` 一致）。
    public var pageIndex: Int

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        difficultyRaw: String,
        lowMidi: Int,
        highMidi: Int,
        answerSemitones: Int,
        answerNameZh: String,
        selectedIndex: Int,
        selectedSemitones: Int,
        selectedNameZh: String,
        wasCorrect: Bool,
        choiceSemitones: [Int],
        choiceLabelsZh: [String],
        pageIndex: Int
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.difficultyRaw = difficultyRaw
        self.lowMidi = lowMidi
        self.highMidi = highMidi
        self.answerSemitones = answerSemitones
        self.answerNameZh = answerNameZh
        self.selectedIndex = selectedIndex
        self.selectedSemitones = selectedSemitones
        self.selectedNameZh = selectedNameZh
        self.wasCorrect = wasCorrect
        self.choiceSemitones = choiceSemitones
        self.choiceLabelsZh = choiceLabelsZh
        self.pageIndex = pageIndex
    }
}

/// 音程练耳历史持久化抽象（便于单测注入 mock）。
public protocol IntervalEarHistoryStoring: Sendable {
    func appendAttempt(_ record: IntervalEarAttemptRecord) async
}
