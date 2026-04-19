import Foundation
import Core
import Tuner
#if canImport(os)
import os
#endif

public protocol SightSingingPitchTracking: AnyObject {
    var currentHz: Double? { get }
    func start() throws
    func stop()
}

public final class DefaultSightSingingPitchTracker: SightSingingPitchTracking {
    private let detector: PitchDetecting
    private(set) public var currentHz: Double?

    public init(detector: PitchDetecting = TunerPitchDetector(config: .sightSinging)) {
        self.detector = detector
    }

    public func start() throws {
        try detector.start { [weak self] frame in
            guard let self else { return }
            switch frame {
            case let .pitch(frequencyHz, _, _):
                Task { @MainActor [weak self] in
                    self?.currentHz = frequencyHz
                }
            case .silent, .rejected:
                Task { @MainActor [weak self] in
                    self?.currentHz = nil
                }
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

/// 判定入口来源（用于日志与后续分析）。
public enum SightSingingEvaluateTrigger: String, Sendable {
    case manual
    case postPreview
}

#if canImport(os)
private let sightSingingEvaluateLogger = Logger(
    subsystem: "com.jamcode.guitar-ai-coach.ear",
    category: "SightSingingEvaluate"
)
#endif

@MainActor
public final class SightSingingSessionViewModel: ObservableObject {
    @Published public private(set) var loading = false
    @Published public private(set) var errorText: String?
    @Published public private(set) var question: SightSingingQuestion?
    @Published public private(set) var sessionId: String?
    @Published public private(set) var evaluating = false
    @Published public private(set) var previewing = false
    /// 用户是否已打开麦克风拾音；进入训练页默认 `false`，不自动监听。
    @Published public private(set) var pitchListeningEnabled = false
    @Published public private(set) var currentHz: Double?
    @Published public private(set) var lastScore: SightSingingScore?
    @Published public private(set) var resultText: String?
    @Published public private(set) var finalResult: SightSingingResult?

    /// Whether the user has completed at least one graded attempt in this session (`submitAnswer` succeeded).
    @Published public private(set) var hasGradedAnyQuestion = false

    @Published public private(set) var userPitchGraph: [SightSingingPitchGraphPoint] = []
    @Published public private(set) var targetLowGraph: [SightSingingPitchGraphPoint] = []
    @Published public private(set) var targetHighGraph: [SightSingingPitchGraphPoint] = []

    /// 最近一次拾音相对参考目标的**有符号**音分偏差（用于实时 HUD）；无有效基频时为 `nil`。
    @Published public private(set) var livePitchCents: Double?
    /// 判定进行中、且为音程题时，曲线与 `livePitchCents` 相对应当前采样的那一个目标音。
    @Published public private(set) var activeEvaluatingTargetIndex: Int?
    /// 拾音样本不足等「未提交得分」时的用户提示；与 `errorText`（网络/权限等）分离。
    @Published public private(set) var evaluateUserHint: String?

    private let repository: SightSingingRepository
    private let pitchTracker: SightSingingPitchTracking
    private let intervalPreview: IntervalTonePlaying?
    private var pitchRange: String
    private var includeAccidental: Bool
    private var questionCount: Int
    private var exerciseKind: SightSingingExerciseKind

    private let warmupMs = 800
    private let evalMs = 2000
    /// 示范扬声器结束后到开始判定（防串音），纳秒。
    private let postPreviewEvaluateDelayNs: UInt64 = 300_000_000
    /// 判定管线输出的绝对音分样本数下限（低于则不调 `submitAnswer`）。
    private let minPipelineAbsCentsSamples = 5
    /// 判定时暂停曲线监控任务，减轻与 `currentHz` 读争用（P2，可改 `false` 做 A/B）。
    private let suspendGraphMonitoringDuringEvaluate = true

    private let graphTickMs = 33
    private let graphWindowSeconds: Double = 6

    private var graphWindowStart: Date?
    /// 换新题后的短窗：不向 UI 写入 `pitchTracker` 的拾音，避免上一题尾音或旧 `currentHz`「粘」在新题上。
    private var livePickupPauseUntil: Date?
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

    public func applySessionConfig(
        pitchRange: String,
        includeAccidental: Bool,
        questionCount: Int,
        exerciseKind: SightSingingExerciseKind
    ) {
        self.pitchRange = pitchRange
        self.includeAccidental = includeAccidental
        self.questionCount = questionCount
        self.exerciseKind = exerciseKind

        // Reset UI/session state before (re)bootstrapping.
        loading = false
        errorText = nil
        sessionId = nil
        question = nil
        evaluating = false
        previewing = false
        pitchListeningEnabled = false
        currentHz = nil
        lastScore = nil
        resultText = nil
        finalResult = nil
        hasGradedAnyQuestion = false
        userPitchGraph = []
        targetLowGraph = []
        targetHighGraph = []
        livePitchCents = nil
        activeEvaluatingTargetIndex = nil
        evaluateUserHint = nil
        graphWindowStart = nil
        livePickupPauseUntil = nil
        monitoringTask?.cancel()
        monitoringTask = nil
        previewGraphTask?.cancel()
        previewGraphTask = nil
        pitchTracker.stop()
    }

    public func currentPreferences() -> SightSingingStoredPreferences {
        SightSingingStoredPreferences(
            pitchRange: pitchRange,
            includeAccidental: includeAccidental,
            questionCount: questionCount,
            exerciseKind: exerciseKind
        )
    }

    /// 写入本地偏好；若已有会话则更新仓库出题参数，**下一题**起生效。
    public func persistAndApplyPreferences(_ preferences: SightSingingStoredPreferences) async {
        pitchRange = preferences.pitchRange
        includeAccidental = preferences.includeAccidental
        questionCount = preferences.questionCount
        exerciseKind = preferences.exerciseKind
        SightSingingPreferencesStore.save(preferences)

        guard let sid = sessionId else { return }
        do {
            try await repository.updateSessionGenerationParameters(
                sessionId: sid,
                pitchRange: preferences.pitchRange,
                includeAccidental: preferences.includeAccidental,
                questionCount: preferences.questionCount,
                exerciseKind: preferences.exerciseKind
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    public func bootstrapIfNeeded() async {
        guard sessionId == nil else { return }
        await bootstrap()
    }

    deinit {
        monitoringTask?.cancel()
        monitoringTask = nil
        previewGraphTask?.cancel()
        previewGraphTask = nil
        pitchTracker.stop()
    }

    public func bootstrap() async {
        loading = true
        errorText = nil
        do {
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
            pitchListeningEnabled = false

            resetGraphsForNewQuestion()
        } catch {
            loading = false
            errorText = error.localizedDescription
        }
    }

    /// 显式开关麦克风拾音；进入页默认关闭，用户点底栏「录音」后再启动 `pitchTracker` 与曲线采样。
    public func setPitchListeningEnabled(_ enabled: Bool) async {
        if enabled {
            guard !pitchListeningEnabled else { return }
            do {
                try await MicrophoneRecordingPermission.ensureGranted()
                try pitchTracker.start()
                pitchListeningEnabled = true
                resetGraphsForNewQuestion()
                startPitchMonitoringIfNeeded()
            } catch {
                pitchListeningEnabled = false
                errorText = error.localizedDescription
            }
        } else {
            guard pitchListeningEnabled else { return }
            pitchListeningEnabled = false
            monitoringTask?.cancel()
            monitoringTask = nil
            currentHz = nil
            livePitchCents = nil
            livePickupPauseUntil = nil
            pitchTracker.stop()
        }
    }

    /// 用户点底栏「判定」或测试入口；与示范播完自动判（`postPreview`）区分。
    public func evaluate() async {
        await evaluate(trigger: .manual)
    }

    public func evaluate(trigger: SightSingingEvaluateTrigger) async {
        guard !evaluating, let q = question, let sid = sessionId else { return }
        guard pitchListeningEnabled else {
            evaluateUserHint = "请先开启底栏「录音」再判定。"
            return
        }
        evaluating = true
        lastScore = nil
        evaluateUserHint = nil
        activeEvaluatingTargetIndex = nil
        if suspendGraphMonitoringDuringEvaluate {
            monitoringTask?.cancel()
            monitoringTask = nil
        }
        pitchTracker.stop()
        defer {
            activeEvaluatingTargetIndex = nil
            if pitchListeningEnabled {
                do {
                    try pitchTracker.start()
                } catch {
                    errorText = error.localizedDescription
                }
            }
            if suspendGraphMonitoringDuringEvaluate, question != nil, sessionId != nil, pitchListeningEnabled {
                startPitchMonitoringIfNeeded()
            }
        }

        let targets = q.targetNotes.isEmpty ? ["C4"] : q.targetNotes
        let maxDurationMs = warmupMs + evalMs * max(1, targets.count)

        let capture: (samples: [Float], sampleRate: Double, wallClockMs: Int)
        do {
            capture = try await SightSingingEvaluateCapture.recordMonoPCM(
                maxDurationMs: maxDurationMs,
                warmupMs: warmupMs
            )
        } catch {
            evaluating = false
            lastScore = nil
            evaluateUserHint = "录音失败，请检查麦克风权限后重试。"
            emitEvaluateLog(
                questionId: q.id,
                trigger: trigger,
                targetsCount: targets.count,
                absCentsCount: 0,
                segments: [],
                outcome: "capture_error"
            )
            return
        }

        let pipeline = await Task.detached(priority: .userInitiated) {
            SightSingingEvaluateAnalysis.run(
                monoPCM: capture.samples,
                inputSampleRate: capture.sampleRate,
                targetNotes: targets
            )
        }.value

        let logSegments: [(index: Int, ticksTotal: Int, ticksAfterWarmup: Int, ticksWithMedian: Int, firstSampleMs: Int?)] = [
            (
                index: 0,
                ticksTotal: pipeline?.absCentsSamples.count ?? 0,
                ticksAfterWarmup: max(0, (pipeline?.absCentsSamples.count ?? 0)),
                ticksWithMedian: pipeline?.absCentsSamples.count ?? 0,
                firstSampleMs: pipeline == nil ? nil : warmupMs
            )
        ]

        guard let pipeline else {
            evaluating = false
            lastScore = nil
            evaluateUserHint = "未稳定拾音，请重试（可先点「示范」再唱）。"
            emitEvaluateLog(
                questionId: q.id,
                trigger: trigger,
                targetsCount: targets.count,
                absCentsCount: 0,
                segments: logSegments,
                outcome: "insufficient_samples"
            )
            return
        }

        if pipeline.absCentsSamples.count < minPipelineAbsCentsSamples {
            evaluating = false
            lastScore = nil
            evaluateUserHint = "未稳定拾音，请重试（可先点「示范」再唱）。"
            emitEvaluateLog(
                questionId: q.id,
                trigger: trigger,
                targetsCount: targets.count,
                absCentsCount: pipeline.absCentsSamples.count,
                segments: logSegments,
                outcome: "insufficient_samples"
            )
            return
        }

        let score = computeSightSingingScore(
            absCentsSamples: pipeline.absCentsSamples,
            sampleStepMs: pipeline.sampleStepMs
        )
        let detected = pipeline.detectedAnswers
        do {
            try await repository.submitAnswer(
                sessionId: sid,
                questionId: q.id,
                answers: detected,
                avgCentsAbs: score.avgCentsAbs,
                stableHitMs: score.stableHitMs,
                durationMs: capture.wallClockMs
            )
            lastScore = score
            hasGradedAnyQuestion = true
            evaluating = false
            emitEvaluateLog(
                questionId: q.id,
                trigger: trigger,
                targetsCount: targets.count,
                absCentsCount: pipeline.absCentsSamples.count,
                segments: logSegments,
                outcome: "submitted"
            )
        } catch {
            evaluating = false
            errorText = error.localizedDescription
            emitEvaluateLog(
                questionId: q.id,
                trigger: trigger,
                targetsCount: targets.count,
                absCentsCount: pipeline.absCentsSamples.count,
                segments: logSegments,
                outcome: "submit_error"
            )
        }
    }

    /// 播完整段示范后短间隔自动判定（保留给测试/实验；产品主路径为「示范仅 `playPreview` + 手动判定」）。
    public func playPreviewAndEvaluate() async {
        guard !previewing, !evaluating else { return }
        let ok = await playPreview()
        guard ok else { return }
        try? await Task.sleep(nanoseconds: postPreviewEvaluateDelayNs)
        await evaluate(trigger: .postPreview)
    }

    /// - Returns: 示范是否完整播完（可用于衔接判定）；`false` 含 guard 失败、无播放器、或播放抛错。
    @discardableResult
    public func playPreview() async -> Bool {
        guard !previewing, !evaluating, let q = question else { return false }
        previewing = true
        defer { previewing = false }

        previewGraphTask?.cancel()

        do {
            if q.targetNotes.count >= 2 {
                guard let player = intervalPreview else { return false }
                let lows = q.targetNotes
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
            } else {
                guard let player = intervalPreview else { return false }
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
            }
        } catch {
            errorText = error.localizedDescription
            previewGraphTask?.cancel()
            previewGraphTask = nil
            return false
        }

        previewGraphTask?.cancel()
        previewGraphTask = nil
        return true
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
            previewGraphTask?.cancel()
            previewGraphTask = nil
            await setPitchListeningEnabled(false)
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
            pitchListeningEnabled = false
            pitchTracker.stop()
        }
    }

    private func startPitchMonitoringIfNeeded() {
        guard pitchListeningEnabled else {
            monitoringTask?.cancel()
            monitoringTask = nil
            return
        }
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
        livePitchCents = nil
        evaluateUserHint = nil
        currentHz = nil
        livePickupPauseUntil = Date().addingTimeInterval(0.4)
    }

    private func emitEvaluateLog(
        questionId: String,
        trigger: SightSingingEvaluateTrigger,
        targetsCount: Int,
        absCentsCount: Int,
        segments: [(index: Int, ticksTotal: Int, ticksAfterWarmup: Int, ticksWithMedian: Int, firstSampleMs: Int?)],
        outcome: String
    ) {
        let segDesc = segments.map { s in
            "(i=\(s.index),ticks=\(s.ticksTotal),postW=\(s.ticksAfterWarmup),med=\(s.ticksWithMedian),firstMs=\(s.firstSampleMs.map(String.init) ?? "nil"))"
        }.joined(separator: ";")
        let line =
            "sightSingingEvaluate questionId=\(questionId) trigger=\(trigger.rawValue) targets=\(targetsCount) absCents=\(absCentsCount) outcome=\(outcome) segments=[\(segDesc)]"
        #if canImport(os)
        sightSingingEvaluateLogger.debug("\(line)")
        #else
        print(line)
        #endif
    }

    private func windowStartOrNow() -> Date {
        if let graphWindowStart {
            return graphWindowStart
        }
        let now = Date()
        graphWindowStart = now
        return now
    }

    /// 复制并裁掉滚动窗外旧点；整段赋值给 `@Published` 数组以触发 SwiftUI 刷新（原地 `append` 可能不刷新）。
    private func prunedGraph(points: [SightSingingPitchGraphPoint], now: Date) -> [SightSingingPitchGraphPoint] {
        var pts = points
        let start = windowStartOrNow()
        let minT = now.timeIntervalSince(start) - graphWindowSeconds
        pts.removeAll { $0.t < minT }
        return pts
    }

    private func graphReferenceTargets(for q: SightSingingQuestion) -> [String] {
        if evaluating, q.targetNotes.count >= 2, let idx = activeEvaluatingTargetIndex, idx >= 0, idx < q.targetNotes.count {
            return [q.targetNotes[idx]]
        }
        return q.targetNotes
    }

    private func appendLiveUserSampleIfPossible() {
        guard let q = question else { return }
        let trackerHz = pitchTracker.currentHz
        if let pause = livePickupPauseUntil {
            if Date() < pause {
                currentHz = nil
            } else {
                livePickupPauseUntil = nil
                currentHz = trackerHz
            }
        } else {
            currentHz = trackerHz
        }

        let now = Date()
        let start = windowStartOrNow()

        appendTargetBaselines(q: q, now: now)

        var user = prunedGraph(points: userPitchGraph, now: now)
        guard let hz = currentHz else {
            userPitchGraph = user
            livePitchCents = nil
            return
        }
        let midi = Double(PitchMath.frequencyToMidi(hz))
        let refs = graphReferenceTargets(for: q)
        let (nearest, _) = nearestTargetMidi(for: midi, targets: refs)
        let cents = (midi - nearest) * 100.0
        let t = now.timeIntervalSince(start)
        user.append(SightSingingPitchGraphPoint(t: t, cents: cents))
        userPitchGraph = user
        livePitchCents = cents
    }

    private func appendTargetBaselines(q: SightSingingQuestion, now: Date) {
        let start = windowStartOrNow()
        let t = now.timeIntervalSince(start)

        var lowG = prunedGraph(points: targetLowGraph, now: now)
        lowG.append(SightSingingPitchGraphPoint(t: t, cents: 0))
        targetLowGraph = lowG

        guard q.targetNotes.count >= 2 else {
            targetHighGraph = prunedGraph(points: targetHighGraph, now: now)
            return
        }

        let low = Double(noteNameToMidi(q.targetNotes[0]))
        let high = Double(noteNameToMidi(q.targetNotes[1]))
        let intervalCents = (high - low) * 100.0

        var highG = prunedGraph(points: targetHighGraph, now: now)
        highG.append(SightSingingPitchGraphPoint(t: t, cents: intervalCents))
        targetHighGraph = highG
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
                var low = self.prunedGraph(points: self.targetLowGraph, now: now)
                if !cents.isNaN {
                    low.append(SightSingingPitchGraphPoint(t: t, cents: cents))
                }
                self.targetLowGraph = low
            })

            await self.runTargetSegments(highSegments, update: { cents in
                let now = Date()
                let start = self.windowStartOrNow()
                let t = now.timeIntervalSince(start)
                var high = self.prunedGraph(points: self.targetHighGraph, now: now)
                if !cents.isNaN {
                    high.append(SightSingingPitchGraphPoint(t: t, cents: cents))
                }
                self.targetHighGraph = high
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

    public func targetMidiDoubles(for question: SightSingingQuestion) -> [Double] {
        question.targetNotes.map { Double(noteNameToMidi($0)) }
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
