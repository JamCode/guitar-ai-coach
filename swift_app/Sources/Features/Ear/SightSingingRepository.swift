import Foundation
import Core

public protocol SightSingingRepository: Sendable {
    func startSession(
        pitchRange: String,
        includeAccidental: Bool,
        questionCount: Int,
        exerciseKind: SightSingingExerciseKind
    ) async throws -> SightSingingSessionStart

    func submitAnswer(
        sessionId: String,
        questionId: String,
        answers: [String],
        avgCentsAbs: Double,
        stableHitMs: Int,
        durationMs: Int
    ) async throws

    func nextQuestion(sessionId: String) async throws -> SightSingingQuestion?
    func fetchResult(sessionId: String) async throws -> SightSingingResult
}

public enum SightSingingRepositoryError: Error, LocalizedError {
    case sessionNotFound
    case questionOutOfDate

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "训练会话不存在，请重新开始"
        case .questionOutOfDate:
            return "题目状态已变化，请重新开始本题"
        }
    }
}

public actor LocalSightSingingRepository: SightSingingRepository {
    private final class LocalSession: @unchecked Sendable {
        let config: SightSingingConfig
        let questionTargets: [[String]]
        var currentIndex = 0
        var answered = 0
        var correct = 0

        init(config: SightSingingConfig, questionTargets: [[String]]) {
            self.config = config
            self.questionTargets = questionTargets
        }
    }

    private var sessions: [String: LocalSession] = [:]
    private var rng = SystemRandomNumberGenerator()

    public init() {}

    public func startSession(
        pitchRange: String,
        includeAccidental: Bool,
        questionCount: Int,
        exerciseKind: SightSingingExerciseKind
    ) async throws -> SightSingingSessionStart {
        let range = noteRange(for: pitchRange)
        let config = SightSingingConfig(
            minNote: range.minNote,
            maxNote: range.maxNote,
            questionCount: questionCount,
            includeAccidental: includeAccidental,
            exerciseKind: exerciseKind
        )
        let targets = buildQuestionTargets(config: config)
        let sessionId = UUID().uuidString.lowercased()
        let session = LocalSession(config: config, questionTargets: targets)
        sessions[sessionId] = session
        return SightSingingSessionStart(
            sessionId: sessionId,
            config: config,
            question: question(for: session, index: 0)
        )
    }

    public func submitAnswer(
        sessionId: String,
        questionId: String,
        answers: [String],
        avgCentsAbs: Double,
        stableHitMs: Int,
        durationMs: Int
    ) async throws {
        guard let session = sessions[sessionId] else {
            throw SightSingingRepositoryError.sessionNotFound
        }
        if questionId != "q-\(session.currentIndex + 1)" {
            throw SightSingingRepositoryError.questionOutOfDate
        }
        let isCorrect = avgCentsAbs <= 30 && stableHitMs >= 700
        session.answered += 1
        if isCorrect {
            session.correct += 1
        }
    }

    public func nextQuestion(sessionId: String) async throws -> SightSingingQuestion? {
        guard let session = sessions[sessionId] else {
            throw SightSingingRepositoryError.sessionNotFound
        }
        session.currentIndex += 1
        guard session.currentIndex < session.questionTargets.count else {
            return nil
        }
        return question(for: session, index: session.currentIndex)
    }

    public func fetchResult(sessionId: String) async throws -> SightSingingResult {
        guard let session = sessions.removeValue(forKey: sessionId) else {
            throw SightSingingRepositoryError.sessionNotFound
        }
        let total = session.questionTargets.count
        let answered = min(total, max(0, session.answered))
        let correct = min(answered, max(0, session.correct))
        let accuracy = answered == 0 ? 0 : Double(correct) / Double(answered)
        return SightSingingResult(answered: answered, correct: correct, total: total, accuracy: accuracy)
    }

    private func question(for session: LocalSession, index: Int) -> SightSingingQuestion {
        SightSingingQuestion(
            id: "q-\(index + 1)",
            index: index + 1,
            totalQuestions: session.questionTargets.count,
            targetNotes: session.questionTargets[index]
        )
    }

    private func buildQuestionTargets(config: SightSingingConfig) -> [[String]] {
        switch config.exerciseKind {
        case .singleNoteMimic:
            let singles = buildSingleQuestionNotes(config: config)
            return singles.map { [$0] }
        case .intervalMimic:
            return buildIntervalQuestionPairs(config: config)
        }
    }

    private func buildSingleQuestionNotes(config: SightSingingConfig) -> [String] {
        let minMidi = noteNameToMidi(config.minNote)
        let maxMidi = noteNameToMidi(config.maxNote)
        let lo = min(minMidi, maxMidi)
        let hi = max(minMidi, maxMidi)
        var candidates: [String] = []
        for midi in lo...hi {
            let note = midiToNoteName(midi)
            if !config.includeAccidental && note.contains("#") {
                continue
            }
            candidates.append(note)
        }
        guard !candidates.isEmpty else {
            return Array(repeating: "C4", count: config.questionCount)
        }
        return (0..<config.questionCount).map { _ in candidates.randomElement(using: &rng) ?? "C4" }
    }

    private func buildIntervalQuestionPairs(config: SightSingingConfig) -> [[String]] {
        let minMidi = noteNameToMidi(config.minNote)
        let maxMidi = noteNameToMidi(config.maxNote)
        let lo = min(minMidi, maxMidi)
        let hi = max(minMidi, maxMidi)
        var candidates: [String] = []
        for midi in lo...hi {
            let note = midiToNoteName(midi)
            if !config.includeAccidental && note.contains("#") {
                continue
            }
            candidates.append(note)
        }
        guard candidates.count >= 2 else {
            return Array(repeating: ["C4", "D4"], count: config.questionCount)
        }

        return (0..<config.questionCount).map { _ in
            // 随机上行两音（允许同音不同八度，但不允许完全同 MIDI）。
            for _ in 0..<48 {
                let aName = candidates.randomElement(using: &rng) ?? "C4"
                let bName = candidates.randomElement(using: &rng) ?? "D4"
                let a = noteNameToMidi(aName)
                let b = noteNameToMidi(bName)
                if a == b { continue }
                let lowMidi = min(a, b)
                let highMidi = max(a, b)
                return [midiToNoteName(lowMidi), midiToNoteName(highMidi)]
            }
            // 兜底：选一个相邻半音对，保证可判定。
            let base = noteNameToMidi(candidates.randomElement(using: &rng) ?? "C4")
            let low = max(lo, min(base, hi - 1))
            let high = min(hi, low + 1)
            return [midiToNoteName(low), midiToNoteName(high)]
        }
    }

    private func noteRange(for pitchRange: String) -> (minNote: String, maxNote: String) {
        switch pitchRange {
        case "low":
            return ("C3", "B3")
        case "wide":
            return ("C3", "B4")
        default:
            return ("C4", "B4")
        }
    }

    private func noteNameToMidi(_ note: String) -> Int {
        let upper = note.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let regex = try? NSRegularExpression(pattern: "^([A-G])(#?)(\\d)$")
        let range = NSRange(location: 0, length: upper.utf16.count)
        guard
            let match = regex?.firstMatch(in: upper, range: range),
            match.numberOfRanges == 4,
            let n1 = Range(match.range(at: 1), in: upper),
            let n2 = Range(match.range(at: 2), in: upper),
            let n3 = Range(match.range(at: 3), in: upper)
        else {
            return 60
        }
        let name = String(upper[n1]) + String(upper[n2])
        let octave = Int(upper[n3]) ?? 4
        let names = PitchMath.noteNames
        let idx = names.firstIndex(of: name) ?? 0
        return (octave + 1) * 12 + idx
    }

    private func midiToNoteName(_ midi: Int) -> String {
        let note = PitchMath.noteNames[((midi % 12) + 12) % 12]
        let octave = midi / 12 - 1
        return "\(note)\(octave)"
    }
}
