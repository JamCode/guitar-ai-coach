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

public struct SightSingingPitchGraphPoint: Sendable, Identifiable {
    public let id: UUID
    /// Seconds since the current rolling window started.
    public let t: Double
    /// Signed cents on the graph Y axis.
    /// - User series: cents relative to the nearest target note among `SightSingingQuestion.targetNotes`.
    /// - Target series: expected cents offset within the same reference frame (usually 0, or +interval during preview).
    public let cents: Double

    public init(id: UUID = UUID(), t: Double, cents: Double) {
        self.id = id
        self.t = t
        self.cents = cents
    }
}

@MainActor
public final class SightSingingSessionViewModel: ObservableObject {
    @Published public private(set) var loading = true
    @Published public private(set) var errorText: String?
    @Published public private(set) var question: SightSingingQuestion?
    @Published public private(set) var sessionId: String?
    @Published public private(set) var evaluating = false
    @Published public private(set) var previewing = false
    @Published public private(set) var currentHz: Double?
    @Published public private(set) var lastScore: SightSingingScore?
    @Published public private(set) var resultText: String?
    @Published public private(set) var finalResult: SightSingingResult?

    /// Whether the user has completed at least one graded attempt in this session (`submitAnswer` succeeded).
    @Published public private(set) var hasGradedAnyQuestion = false

    @Published public private(set) var userPitchGraph: [SightSingingPitchGraphPoint] = []
    @Published public private(set) var targetLowGraph: [SightSingingPitchGraphPoint] = []
    @Published public private(set) var targetHighGraph: [SightSingingPitchGraphPoint] = []

    private let repository: SightSingingRepository
    private let pitchTracker: SightSingingPitchTracking
    private let intervalPreview: IntervalTonePlaying?
    private let pitchRange: String
    private let includeAccidental: Bool
    private let questionCount: Int
    private let exerciseKind: SightSingingExerciseKind

    private let sampleStepMs = 120
    private let warmupMs = 800
    private let evalMs = 2000

    private let graphTickMs = 33
    private let graphWindowSeconds: Double = 6

    private var graphWindowStart: Date?
    // These tasks are cancelled from `deinit`; keep them `nonisolated(unsafe)` so teardown doesn't require MainActor.
    nonisolated(unsafe) private var monitoringTask: Task<Void, Never>?
    nonisolated(unsafe) private var previewGraphTask: Task<Void, Never>?

    // Keep aligned with `IntervalTonePlayer` (preview / sampled gates).
    private let sampledGateSec: Double = 1.1
    private let silenceAfterFirstGateSec: Double = 0.28
    private let releaseTailAfterSecondGateSec: Double = 0.22
    private let previewGateSec: Double = 0.52
    private let previewTailSec: Double = 0.18

    public init(
        repository: SightSingingRepository,
        pitchTracker: SightSingingPitchTracking,
        intervalPreview: IntervalTonePlaying? = IntervalTonePlayer(),
        pitchRange: String,
        includeAccidental: Bool,
        questionCount: Int,
        exerciseKind: SightSingingExerciseKind
    ) {
        self.repository = repository
        self.pitchTracker = pitchTracker
        self.intervalPreview = intervalPreview
        self.pitchRange = pitchRange
        self.includeAccidental = includeAccidental
        self.questionCount = questionCount
        self.exerciseKind = exerciseKind
    }

    deinit {
        monitoringTask?.cancel()
        monitoringTask = nil
        previewGraphTask?.cancel()
        previewGraphTask = nil
        pitchTracker.stop()
    }

    public func bootstrap() async {
        do {
            try pitchTracker.start()
            let start = try await repository.startSession(
                pitchRange: pitchRange,
                includeAccidental: includeAccidental,
                questionCount: questionCount,
                exerciseKind: exerciseKind
            )
            sessionId = start.sessionId
            question = start.question
            loading = false
            errorText = nil
            hasGradedAnyQuestion = false

            resetGraphsForNewQuestion()
            startPitchMonitoringIfNeeded()
        } catch {
            loading = false
            errorText = error.localizedDescription
        }
    }

    public func evaluate() async {
        guard !evaluating, let q = question, let sid = sessionId else { return }
        evaluating = true
        lastScore = nil
        let targets = q.targetNotes.isEmpty ? ["C4"] : q.targetNotes
        var absCents: [Double] = []
        var detectedNotes: [String] = []

        for target in targets {
            let targetMidi = Double(noteNameToMidi(target))
            var elapsed = 0
            while elapsed < warmupMs + evalMs {
                try? await Task.sleep(nanoseconds: UInt64(sampleStepMs) * 1_000_000)
                elapsed += sampleStepMs
                currentHz = pitchTracker.currentHz
                if elapsed > warmupMs, let hz = currentHz {
                    let midi = Double(PitchMath.frequencyToMidi(hz))
                    let cents = abs((midi - targetMidi) * 100.0)
                    absCents.append(cents)
                }
            }
            if let hz = currentHz {
                detectedNotes.append(PitchMath.midiToNoteName(PitchMath.frequencyToMidi(hz)))
            }
        }

        let score = computeSightSingingScore(absCentsSamples: absCents, sampleStepMs: sampleStepMs)
        let detected = detectedNotes
        do {
            try await repository.submitAnswer(
                sessionId: sid,
                questionId: q.id,
                answers: detected,
                avgCentsAbs: score.avgCentsAbs,
                stableHitMs: score.stableHitMs,
                durationMs: evalMs * targets.count
            )
            lastScore = score
            hasGradedAnyQuestion = true
            evaluating = false
        } catch {
            evaluating = false
            errorText = error.localizedDescription
        }
    }

    public func playPreview() async {
        guard !previewing, !evaluating, let q = question else { return }
        previewing = true
        defer { previewing = false }

        previewGraphTask?.cancel()

        do {
            switch exerciseKind {
            case .singleNoteMimic:
                guard let player = intervalPreview else { return }
                let midi = noteNameToMidi(q.targetNotes.first ?? "C4")
                startTargetGraphRecording(
                    lowSegments: [
                        .init(duration: previewGateSec + previewTailSec, cents: 0)
                    ],
                    highSegments: []
                )
                let graphTask = Task { await self.previewGraphTask?.value }
                try await player.playSinglePreview(midi: midi)
                await graphTask.value
            case .intervalMimic:
                guard let player = intervalPreview else { return }
                let lows = q.targetNotes
                guard lows.count >= 2 else { return }
                let lowMidi = noteNameToMidi(lows[0])
                let highMidi = noteNameToMidi(lows[1])
                let intervalCents = Double(highMidi - lowMidi) * 100.0
                startTargetGraphRecording(
                    lowSegments: [
                        .init(duration: sampledGateSec, cents: 0),
                        .init(duration: silenceAfterFirstGateSec + sampledGateSec + releaseTailAfterSecondGateSec, cents: .nan)
                    ],
                    highSegments: [
                        .init(duration: sampledGateSec, cents: .nan),
                        .init(duration: silenceAfterFirstGateSec, cents: .nan),
                        .init(duration: sampledGateSec, cents: intervalCents),
                        .init(duration: releaseTailAfterSecondGateSec, cents: .nan)
                    ]
                )
                let graphTask = Task { await self.previewGraphTask?.value }
                try await player.playAscendingPair(lowMidi: lowMidi, highMidi: highMidi)
                await graphTask.value
            }
        } catch {
            // 试听失败不应阻塞训练主流程。
            errorText = error.localizedDescription
        }

        previewGraphTask?.cancel()
        previewGraphTask = nil
    }

    public func nextOrFinish() async -> Bool {
        guard let sid = sessionId else { return false }
        do {
            if let next = try await repository.nextQuestion(sessionId: sid) {
                question = next
                lastScore = nil
                resetGraphsForNewQuestion()
                return false
            }

            // 有限题：题库耗尽 -> 拉取结果。
            let result = try await repository.fetchResult(sessionId: sid)
            finalResult = result
            resultText = "本轮完成：共判定 \(result.answered) 题，答对 \(result.correct) 题，准确率 \((result.accuracy * 100).formatted(.number.precision(.fractionLength(0))))%"
            monitoringTask?.cancel()
            monitoringTask = nil
            previewGraphTask?.cancel()
            previewGraphTask = nil
            sessionId = nil
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    public func endTraining() async -> Bool {
        guard let sid = sessionId else { return false }
        do {
            let result = try await repository.endSession(sessionId: sid)
            finalResult = result
            resultText = "训练结束：共判定 \(result.answered) 题，答对 \(result.correct) 题，准确率 \((result.accuracy * 100).formatted(.number.precision(.fractionLength(0))))%"
            cancelActiveWork(stopPitchTracker: true)
            sessionId = nil
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    /// Ends the local repository session without presenting UI (used when leaving the screen early).
    public func discardSessionSilently() async {
        guard let sid = sessionId else { return }
        if finalResult != nil { return }
        do {
            _ = try await repository.endSession(sessionId: sid)
        } catch {
            // Best-effort cleanup; leaving should not surface noisy errors.
        }
        sessionId = nil
    }

    /// Cancel background sampling + any in-flight preview graph recording.
    ///
    /// Note: `IntervalTonePlaying` playback itself can't be hard-stopped without a richer player API,
    /// but cancelling graph tasks prevents UI-driven work from continuing off-screen after navigation.
    public func cancelActiveWork(stopPitchTracker: Bool) {
        monitoringTask?.cancel()
        monitoringTask = nil
        previewGraphTask?.cancel()
        previewGraphTask = nil
        evaluating = false
        previewing = false
        if stopPitchTracker {
            pitchTracker.stop()
        }
    }

    private func startPitchMonitoringIfNeeded() {
        monitoringTask?.cancel()
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(graphTickMs) * 1_000_000)
                await MainActor.run {
                    self.appendLiveUserSampleIfPossible()
                }
            }
        }
    }

    private func resetGraphsForNewQuestion() {
        graphWindowStart = Date()
        userPitchGraph = []
        targetLowGraph = []
        targetHighGraph = []
    }

    private func windowStartOrNow() -> Date {
        if let graphWindowStart {
            return graphWindowStart
        }
        let now = Date()
        graphWindowStart = now
        return now
    }

    private func prune(points: inout [SightSingingPitchGraphPoint], now: Date) {
        let start = windowStartOrNow()
        let minT = now.timeIntervalSince(start) - graphWindowSeconds
        points.removeAll { $0.t < minT }
    }

    private func appendLiveUserSampleIfPossible() {
        guard let q = question else { return }
        let now = Date()
        let start = windowStartOrNow()

        appendTargetBaselines(q: q, now: now)

        guard let hz = currentHz else { return }
        let midi = Double(PitchMath.frequencyToMidi(hz))

        let (nearest, _) = nearestTargetMidi(for: midi, targets: q.targetNotes)
        let cents = (midi - nearest) * 100.0

        prune(points: &userPitchGraph, now: now)
        let t = now.timeIntervalSince(start)
        userPitchGraph.append(SightSingingPitchGraphPoint(t: t, cents: cents))
    }

    private func appendTargetBaselines(q: SightSingingQuestion, now: Date) {
        let start = windowStartOrNow()
        let t = now.timeIntervalSince(start)

        prune(points: &targetLowGraph, now: now)
        targetLowGraph.append(SightSingingPitchGraphPoint(t: t, cents: 0))

        guard q.targetNotes.count >= 2 else {
            prune(points: &targetHighGraph, now: now)
            return
        }

        let low = Double(noteNameToMidi(q.targetNotes[0]))
        let high = Double(noteNameToMidi(q.targetNotes[1]))
        let intervalCents = (high - low) * 100.0

        prune(points: &targetHighGraph, now: now)
        targetHighGraph.append(SightSingingPitchGraphPoint(t: t, cents: intervalCents))
    }

    private func nearestTargetMidi(for midi: Double, targets: [String]) -> (Double, Int) {
        let mids = targets.map { Double(noteNameToMidi($0)) }
        guard let first = mids.first else { return (midi, 60) }
        var best = first
        var bestDist = abs(midi - first)
        for m in mids.dropFirst() {
            let d = abs(midi - m)
            if d < bestDist {
                best = m
                bestDist = d
            }
        }
        return (best, Int(best.rounded()))
    }

    private struct TargetGraphSegment {
        var duration: Double
        /// Use `.nan` to represent silence (no target energy / blank gap).
        var cents: Double
    }

    private func startTargetGraphRecording(lowSegments: [TargetGraphSegment], highSegments: [TargetGraphSegment]) {
        previewGraphTask?.cancel()
        previewGraphTask = Task { [weak self] in
            guard let self else { return }

            await self.runTargetSegments(lowSegments, update: { cents in
                let now = Date()
                let start = self.windowStartOrNow()
                let t = now.timeIntervalSince(start)
                self.prune(points: &self.targetLowGraph, now: now)
                if cents.isNaN { return }
                self.targetLowGraph.append(SightSingingPitchGraphPoint(t: t, cents: cents))
            })

            await self.runTargetSegments(highSegments, update: { cents in
                let now = Date()
                let start = self.windowStartOrNow()
                let t = now.timeIntervalSince(start)
                self.prune(points: &self.targetHighGraph, now: now)
                if cents.isNaN { return }
                self.targetHighGraph.append(SightSingingPitchGraphPoint(t: t, cents: cents))
            })
        }
    }

    private func runTargetSegments(
        _ segments: [TargetGraphSegment],
        update: @escaping @MainActor (Double) -> Void
    ) async {
        for seg in segments {
            if seg.duration <= 0 { continue }
            if seg.cents.isNaN {
                try? await Task.sleep(nanoseconds: UInt64(seg.duration * 1_000_000_000))
                continue
            }
            let end = Date().addingTimeInterval(seg.duration)
            while Date() < end, !Task.isCancelled {
                await MainActor.run {
                    update(seg.cents)
                }
                try? await Task.sleep(nanoseconds: UInt64(graphTickMs) * 1_000_000)
            }
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
