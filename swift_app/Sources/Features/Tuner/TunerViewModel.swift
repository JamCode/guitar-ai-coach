import Foundation
import Core
import AVFoundation

@MainActor
public final class TunerViewModel: ObservableObject {
    @Published public var selectedStringIndex = 0
    @Published public var frequencyHz: Double?
    @Published public var smoothedHz: Double?
    @Published public var isListening = false
    @Published public var statusMessage = "点击开始监听"
    @Published public var errorText: String?

    private let openStringHz = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]
    private let audio: AudioEngineServing
    private let detector: PitchDetecting
    private let emaAlpha = 0.18

    public init(audio: AudioEngineServing = AudioEngineService(), detector: PitchDetecting = TunerPitchDetector()) {
        self.audio = audio
        self.detector = detector
    }

    public var targetHz: Double { openStringHz[selectedStringIndex] }

    public var noteName: String {
        guard let hz = smoothedHz ?? frequencyHz else { return "--" }
        return PitchMath.midiToNoteName(PitchMath.frequencyToMidi(hz))
    }

    public var cents: Double {
        guard let hz = smoothedHz ?? frequencyHz else { return 0 }
        return PitchMath.centsBetween(actualHz: hz, targetHz: targetHz)
    }

    public func setSelectedString(_ index: Int) {
        selectedStringIndex = max(0, min(5, index))
        do {
            try audio.playSine(frequencyHz: targetHz, durationSec: 0.20)
        } catch {
            errorText = "参考音播放失败：\(error.localizedDescription)"
        }
    }

    public func start() {
        do {
            #if os(iOS)
            try ensureMicrophonePermission()
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
    private func ensureMicrophonePermission() throws {
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission == .granted { return }
        if session.recordPermission == .denied {
            throw NSError(domain: "Tuner", code: 1001, userInfo: [NSLocalizedDescriptionKey: "需要麦克风权限"])
        }
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        session.requestRecordPermission { ok in
            granted = ok
            semaphore.signal()
        }
        semaphore.wait()
        if !granted {
            throw NSError(domain: "Tuner", code: 1002, userInfo: [NSLocalizedDescriptionKey: "需要麦克风权限"])
        }
    }
    #endif
}

