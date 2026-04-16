import Foundation
import Core
import AVFoundation
#if os(iOS)
import AVFAudio
#endif

@MainActor
public final class TunerViewModel: ObservableObject {
    /// `nil` 表示尚未选择目标弦（进入调音器时不预选）。
    @Published public var selectedStringIndex: Int?
    @Published public var frequencyHz: Double?
    @Published public var smoothedHz: Double?
    @Published public var isListening = false
    @Published public var statusMessage = "轻点下方弦钮开始调音"
    @Published public var errorText: String?

    private let openStringHz = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]
    private let audio: AudioEngineServing
    private let detector: PitchDetecting
    private let emaAlpha = 0.18

    public init(audio: AudioEngineServing = AudioEngineService(), detector: PitchDetecting = TunerPitchDetector()) {
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

    public var cents: Double {
        guard let hz = smoothedHz ?? frequencyHz, let target = targetHz else { return 0 }
        return PitchMath.centsBetween(actualHz: hz, targetHz: target)
    }

    public func setSelectedString(_ index: Int) {
        let i = max(0, min(5, index))
        selectedStringIndex = i
        guard let hz = targetHz else { return }
        do {
            try audio.playSine(frequencyHz: hz, durationSec: 0.20)
        } catch {
            errorText = "参考音播放失败：\(error.localizedDescription)"
        }
    }

    /// 点选弦钮：切换目标弦并播放短参考音；若尚未监听麦克风则自动开始监听。
    public func selectStringForTuning(_ index: Int) async {
        setSelectedString(index)
        guard !isListening else { return }
        await start()
    }

    public func start() async {
        do {
            #if os(iOS)
            try await ensureMicrophonePermission()
            #endif
            try audio.start()
            try detector.start { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    self.consume(result)
                }
            }
            isListening = true
            statusMessage = "监听中…"
            errorText = nil
        } catch {
            errorText = "启动音频失败：\(error.localizedDescription)"
        }
    }

    public func stop() {
        detector.stop()
        audio.stop()
        isListening = false
        statusMessage = "已停止监听"
    }

    public func updateFrequencySample(_ hz: Double) {
        frequencyHz = hz
        if let old = smoothedHz {
            smoothedHz = old * (1 - emaAlpha) + hz * emaAlpha
        } else {
            smoothedHz = hz
        }
    }

    private func consume(_ result: PitchFrameResult) {
        switch result {
        case let .pitch(frequencyHz, _, rms):
            updateFrequencySample(frequencyHz)
            statusMessage = "RMS \(String(format: "%.3f", rms)) · 已锁定基频"
        case let .silent(reason):
            statusMessage = reason
        case let .rejected(reason):
            statusMessage = reason
        }
    }

    #if os(iOS)
    /// 使用异步 API，避免在 `MainActor` 上 `semaphore.wait()` 与系统在主线程派发权限回调时互相死锁导致闪退。
    private func ensureMicrophonePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw NSError(domain: "Tuner", code: 1001, userInfo: [NSLocalizedDescriptionKey: "需要麦克风权限"])
        case .undetermined:
            break
        @unknown default:
            break
        }
        let granted = await AVAudioApplication.requestRecordPermission()
        if !granted {
            throw NSError(domain: "Tuner", code: 1002, userInfo: [NSLocalizedDescriptionKey: "需要麦克风权限"])
        }
    }
    #endif
}

