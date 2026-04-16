import Foundation

public struct EarMcqOption: Decodable, Hashable, Sendable {
    public let key: String
    public let label: String
}

public struct EarBankItem: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let mode: String
    public let questionType: String
    public let promptZh: String
    public let options: [EarMcqOption]
    public let correctOptionKey: String
    public let root: String?
    public let targetQuality: String?
    public let musicKey: String?
    public let progressionRoman: String?
    public let hintZh: String?

    enum CodingKeys: String, CodingKey {
        case id
        case mode
        case questionType = "question_type"
        case promptZh = "prompt_zh"
        case options
        case correctOptionKey = "correct_option_key"
        case root
        case targetQuality = "target_quality"
        case musicKey = "music_key"
        case progressionRoman = "progression_roman"
        case hintZh = "hint_zh"
    }
}

public struct EarSeedDocument: Decodable, Sendable {
    public let bankA: [EarBankItem]
    public let bankB: [EarBankItem]

    private struct Banks: Decodable {
        let A: [EarBankItem]?
        let B: [EarBankItem]?
    }

    private enum CodingKeys: String, CodingKey {
        case banks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let banks = try container.decode(Banks.self, forKey: .banks)
        bankA = banks.A ?? []
        bankB = banks.B ?? []
    }
}
