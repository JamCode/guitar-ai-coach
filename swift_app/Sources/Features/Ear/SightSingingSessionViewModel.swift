import Foundation
import Core
import Tuner

public protocol SightSingingPitchTracking: AnyObject {
    var currentHz: Double? { get }
    func start() throws
    func stop()
}

public final class DefaultSightSingingPitchTracker: SightSingingPitchTracking {
    private let detector: PitchDetecting
    private(set) public var currentHz: Double?

    public init(detector: PitchDetecting = TunerPitchDetector()) {
        self.detector = detector
    }

    public func start() throws {
        try detector.start { [weak self] frame in
            guard let self else { return }
            if case let .pitch(frequencyHz, _, _) = frame {
                self.currentHz = frequencyHz
            }
        }
    }

    public func stop() {
        detector.stop()
    }
}

@MainActor
public final class SightSingingSessionViewModel: ObservableObject {
    @Published public private(set) var loading = true
    @Published public private(set) var errorText: String?
    @Published public private(set) var question: SightSingingQuestion?
    @Published public private(set) var sessionId: String?
    @Published public private(set) var evaluating = false
    @Published public private(set) var currentHz: Double?
    @Published public private(set) var lastScore: SightSingingScore?
    @Published public private(set) var resultText: String?

    private let repository: SightSingingRepository
    private let pitchTracker: SightSingingPitchTracking
    private let pitchRange: String
    private let includeAccidental: Bool
    private let questionCount: Int

    private let sampleStepMs = 120
    private let warmupMs = 800
    private let evalMs = 2000

    public init(
        repository: SightSingingRepository,
        pitchTracker: SightSingingPitchTracking,
        pitchRange: String,
        includeAccidental: Bool,
        questionCount: Int
    ) {
        self.repository = repository
        self.pitchTracker = pitchTracker
        self.pitchRange = pitchRange
        self.includeAccidental = includeAccidental
        self.questionCount = questionCount
    }

    deinit {
        pitchTracker.stop()
    }

    public func bootstrap() async {
        do {
            try pitchTracker.start()
            let start = try await repository.startSession(
                pitchRange: pitchRange,
                includeAccidental: includeAccidental,
                questionCount: questionCount
            )
            sessionId = start.sessionId
            question = start.question
            loading = false
            errorText = nil
        } catch {
            loading = false
            errorText = error.localizedDescription
        }
    }

    public func evaluate() async {
        guard !evaluating, let q = question, let sid = sessionId else { return }
        evaluating = true
        lastScore = nil
        let target = q.targetNotes.first ?? "C4"
        let targetMidi = noteNameToMidi(target)
        var elapsed = 0
        var absCents: [Double] = []
        while elapsed < warmupMs + evalMs {
            try? await Task.sleep(nanoseconds: UInt64(sampleStepMs) * 1_000_000)
            elapsed += sampleStepMs
            currentHz = pitchTracker.currentHz
            if elapsed > warmupMs, let hz = currentHz {
                let cents = abs(Double(PitchMath.frequencyToMidi(hz) - targetMidi) * 100)
                absCents.append(cents)
            }
        }
        let score = computeSightSingingScore(absCentsSamples: absCents, sampleStepMs: sampleStepMs)
        let detected = currentHz.map { [PitchMath.midiToNoteName(PitchMath.frequencyToMidi($0))] } ?? []
        do {
            try await repository.submitAnswer(
                sessionId: sid,
                questionId: q.id,
                answers: detected,
                avgCentsAbs: score.avgCentsAbs,
                stableHitMs: score.stableHitMs,
                durationMs: evalMs
            )
            lastScore = score
            evaluating = false
        } catch {
            evaluating = false
            errorText = error.localizedDescription
        }
    }

    public func nextOrFinish() async -> Bool {
        guard let sid = sessionId else { return false }
        do {
            if let next = try await repository.nextQuestion(sessionId: sid) {
                question = next
                lastScore = nil
                return false
            }
            let result = try await repository.fetchResult(sessionId: sid)
            resultText = "共 \(result.total) 题，答对 \(result.correct) 题，准确率 \((result.accuracy * 100).formatted(.number.precision(.fractionLength(0))))%"
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    private func noteNameToMidi(_ note: String) -> Int {
        let normalized = note.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let regex = try? NSRegularExpression(pattern: "^([A-G])(#?)(\\d)$")
        let range = NSRange(location: 0, length: normalized.utf16.count)
        guard
            let m = regex?.firstMatch(in: normalized, range: range),
            let r1 = Range(m.range(at: 1), in: normalized),
            let r2 = Range(m.range(at: 2), in: normalized),
            let r3 = Range(m.range(at: 3), in: normalized)
        else {
            return 60
        }
        let name = String(normalized[r1]) + String(normalized[r2])
        let octave = Int(normalized[r3]) ?? 4
        let idx = PitchMath.noteNames.firstIndex(of: name) ?? 0
        return (octave + 1) * 12 + idx
    }
}
