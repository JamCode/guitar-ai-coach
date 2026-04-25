import Foundation
import Core
import AVFoundation

@MainActor
public final class TunerViewModel: ObservableObject {
    /// `nil` 表示尚未选择目标弦（进入调音器时不预选）。
    @Published public var selectedStringIndex: Int?
    @Published public var frequencyHz: Double?
    @Published public var smoothedHz: Double?
    @Published public var isListening = false
    @Published public var statusMessage = AppL10n.t("tuner_status_tap_string")
    @Published public var errorText: String?
    /// 指针/文案统一读取的「显示 cents」，经过 cents 维度的一阶低通平滑，避免 UI 硬跳。
    @Published public private(set) var cents: Double = 0
    /// 是否处于「已调准」状态；采用滞回：进入 `inTuneEnterCents`、退出 `inTuneExitCents`，避免临界处反复切换文案。
    @Published public private(set) var isInTune: Bool = false

    private let openStringHz = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]
    private let audio: AudioEngineServing
    private let detector: PitchDetecting
    private let emaAlpha = 0.18
    /// 显示层 cents 的一阶低通系数。采样 ~85ms/帧时，0.3 对应时间常数约 240ms，
    /// 既能压下拨弦瞬态的抖动，又能在调准过程中跟得上手感。
    private let centsDisplayAlpha = 0.3
    /// 「偏高/偏低」切到「已调准」的进入阈值（单位 cent）。
    private let inTuneEnterCents: Double = 5
    /// 「已调准」切回「偏高/偏低」的退出阈值（带宽略宽于进入值，形成滞回）。
    private let inTuneExitCents: Double = 9
    /// 连续帧一致性过滤：两次相邻基频帧若 cents 偏离超过此值，视为瞬态（拨弦 attack 或误识），
    /// 当次不更新显示，下一帧确认后再生效。避免八度错带来的瞬时 ±1200 cent 跳变冲进平滑器。
    private let consistencyWindowCents: Double = 80
    /// 上一次接受的基频 Hz（用于连续帧一致性比较；仅跟踪已被视为可信的采样）。
    private var lastAcceptedHz: Double?
    /// 上一次被拒绝但被当作「候选」的基频 Hz。连续两帧都是同一候选（±窗口内）才正式接纳，
    /// 这样既能过滤瞬态，也不会因为用户真的换了一下音就卡很久。
    private var pendingCandidateHz: Double?

    public init(
        audio: AudioEngineServing = AudioEngineService.shared,
        detector: PitchDetecting = TunerPitchDetector(config: .tunerGuitar)
    ) {
        self.audio = audio
        self.detector = detector
    }

    public var targetHz: Double? {
        guard let i = selectedStringIndex, (0...5).contains(i) else { return nil }
        return openStringHz[i]
    }

    public var noteName: String {
        guard let hz = smoothedHz ?? frequencyHz else { return "--" }
        return PitchMath.midiToNoteName(PitchMath.frequencyToMidi(hz))
    }

    public func setSelectedString(_ index: Int) {
        let i = max(0, min(5, index))
        if selectedStringIndex != i {
            // 切到新目标弦时清掉旧弦的 Hz/cents 平滑状态，否则指针会先显示对新目标的错误偏移；
            // 紧接着一次 `recomputeDisplayCents(resetSmoothing:)` 会把显示 cents 归零并复位「已调准」。
            frequencyHz = nil
            smoothedHz = nil
            lastAcceptedHz = nil
            pendingCandidateHz = nil
        }
        selectedStringIndex = i
        detector.setTargetHz(targetHz)
        recomputeDisplayCents(resetSmoothing: true)
        guard let hz = targetHz else { return }
        let midi = GuitarStandardTuning.openStringMidis[i]
        do {
            try audio.start()
            if audio.isSampledGuitarAvailable {
                try audio.playSampledGuitarNote(midi: midi, velocity: 98, gateDurationSec: 1.28)
            } else {
                try audio.playSine(frequencyHz: hz, durationSec: 0.22)
            }
        } catch {
            errorText = String(format: AppL10n.t("tuner_error_ref_fmt"), error.localizedDescription)
        }
    }

    /// 点选弦钮：切换目标弦并播放短参考音；若尚未监听麦克风则自动开始监听。
    public func selectStringForTuning(_ index: Int) async {
        setSelectedString(index)
        guard !isListening else { return }
        // 先把选中态绘制出来，再启动较重的音频链路，避免首点体感卡顿。
        await Task.yield()
        await start()
    }

    public func start() async {
        do {
            try await MicrophoneRecordingPermission.ensureGranted()
            try audio.start()
            try detector.start { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    self.consume(result)
                }
            }
            isListening = true
            statusMessage = AppL10n.t("tuner_listening")
            errorText = nil
        } catch {
            errorText = String(format: AppL10n.t("tuner_error_start_fmt"), error.localizedDescription)
        }
    }

    public func stop() {
        detector.stop()
        detector.setTargetHz(nil)
        audio.stop()
        isListening = false
        statusMessage = AppL10n.t("tuner_stopped")
        lastAcceptedHz = nil
        pendingCandidateHz = nil
    }

    public func updateFrequencySample(_ hz: Double) {
        guard acceptSample(hz) else { return }
        frequencyHz = hz
        if let old = smoothedHz {
            smoothedHz = old * (1 - emaAlpha) + hz * emaAlpha
        } else {
            smoothedHz = hz
        }
        recomputeDisplayCents(resetSmoothing: false)
    }

    /// 连续帧一致性过滤：与上一次「已接受」的基频偏离过大时，先挂成 `pendingCandidateHz`；
    /// 下一帧仍落在候选附近（同窗口内）才真正接纳。这样能压住拨弦 attack 或偶发八度错的瞬时跳变。
    private func acceptSample(_ hz: Double) -> Bool {
        guard hz > 0 else { return false }
        guard let previous = lastAcceptedHz else {
            // 首帧直接接纳：没有参考点时等 N 帧只会让用户看到「一直无反馈」。
            lastAcceptedHz = hz
            pendingCandidateHz = nil
            return true
        }
        let deltaCents = abs(PitchMath.centsBetween(actualHz: hz, targetHz: previous))
        if deltaCents <= consistencyWindowCents {
            lastAcceptedHz = hz
            pendingCandidateHz = nil
            return true
        }
        if let candidate = pendingCandidateHz {
            let candidateDelta = abs(PitchMath.centsBetween(actualHz: hz, targetHz: candidate))
            if candidateDelta <= consistencyWindowCents {
                // 连续两帧都落在远离旧值的同一簇：用户确实换了音，接纳新值并重置候选。
                lastAcceptedHz = hz
                pendingCandidateHz = nil
                return true
            }
        }
        // 孤立跳变：记录候选，等下一帧确认，本帧不走 UI 链路。
        pendingCandidateHz = hz
        return false
    }

    private func consume(_ result: PitchFrameResult) {
        switch result {
        case let .pitch(frequencyHz, _, rms):
            updateFrequencySample(frequencyHz)
            statusMessage = String(format: AppL10n.t("tuner_status_locked_rms"), String(format: "%.3f", rms))
        case let .silent(reason):
            statusMessage = reason
        case let .rejected(reason):
            statusMessage = reason
        }
    }

    /// 以 cents 维度再做一次低通，替代此前基于 Hz 的派生计算，让 UI 指针平滑跟随。
    /// `resetSmoothing` 为 `true` 时清零平滑器（切换目标弦时必须重置，否则会出现跨弦残留）。
    private func recomputeDisplayCents(resetSmoothing: Bool) {
        guard let hz = smoothedHz ?? frequencyHz, let target = targetHz else {
            cents = 0
            isInTune = false
            return
        }
        let raw = PitchMath.centsBetween(actualHz: hz, targetHz: target)
        if resetSmoothing {
            cents = raw
        } else {
            cents = cents * (1 - centsDisplayAlpha) + raw * centsDisplayAlpha
        }
        let magnitude = abs(cents)
        if isInTune {
            if magnitude > inTuneExitCents { isInTune = false }
        } else {
            if magnitude <= inTuneEnterCents { isInTune = true }
        }
    }
}

