import Foundation

public struct IntervalKind: Hashable, Sendable {
    public let semitones: Int
    public let nameZh: String

    public static let trainingPool: [IntervalKind] = [
        .init(semitones: 1, nameZh: "小二度"),
        .init(semitones: 2, nameZh: "大二度"),
        .init(semitones: 3, nameZh: "小三度"),
        .init(semitones: 4, nameZh: "大三度"),
        .init(semitones: 5, nameZh: "纯四度"),
        .init(semitones: 6, nameZh: "三全音"),
        .init(semitones: 7, nameZh: "纯五度"),
        .init(semitones: 8, nameZh: "小六度"),
        .init(semitones: 9, nameZh: "大六度"),
        .init(semitones: 10, nameZh: "小七度"),
        .init(semitones: 11, nameZh: "大七度"),
        .init(semitones: 12, nameZh: "纯八度")
    ]
}

public struct IntervalQuestion: Sendable {
    public let lowMidi: Int
    public let highMidi: Int
    public let answer: IntervalKind
    public let choices: [IntervalKind]
}

public enum IntervalQuestionGenerator {
    private static let rootLo = 48
    private static let rootHi = 72

    public static func next(using rng: inout some RandomNumberGenerator) -> IntervalQuestion {
        let pool = IntervalKind.trainingPool
        let answer = pool.randomElement(using: &rng) ?? pool[0]
        let maxRoot = rootHi - answer.semitones
        let root = Int.random(in: rootLo...max(rootLo, maxRoot), using: &rng)
        let wrong = pool.filter { $0.semitones != answer.semitones }.shuffled(using: &rng)
        let picks = Array(wrong.prefix(3))
        let choices = ([answer] + picks).shuffled(using: &rng)
        return IntervalQuestion(
            lowMidi: root,
            highMidi: root + answer.semitones,
            answer: answer,
            choices: choices
        )
    }
}
