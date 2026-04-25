import Foundation
import SwiftUI

/// 连接 `MetronomeConfig` 与 `MetronomeEngine`；UI 只观察本类型。
@MainActor
public final class MetronomeViewModel: ObservableObject {
    @Published public private(set) var config: MetronomeConfig
    @Published public private(set) var transport: MetronomeTransportState = .stopped
    /// 当前小节内拍位（1...beatsPerMeasure），停止时为 `nil`。
    @Published public private(set) var currentBeatIndex: Int?
    @Published public var errorMessage: String?

    private let engine: MetronomeEngineing

    public init(config: MetronomeConfig = MetronomeConfig(), engine: MetronomeEngineing = MetronomeEngine()) {
        self.config = config
        self.engine = engine
        self.engine.onBeat = { [weak self] index, _ in
            Task { @MainActor in
                self?.currentBeatIndex = index
            }
        }
    }

    public var beatsPerMeasure: Int {
        config.timeSignature.beatsPerMeasure
    }

    public func setBPM(_ value: Int) {
        config.bpm = MetronomeConfig.clampBPM(value)
        if engine.isRunning {
            restartEngineKeepingTransport()
        }
    }

    public func adjustBPM(delta: Int) {
        setBPM(config.bpm + delta)
    }

    public func setTimeSignature(_ sig: MetronomeTimeSignature) {
        config.timeSignature = sig
        if engine.isRunning {
            restartEngineKeepingTransport()
        } else {
            currentBeatIndex = nil
        }
    }

    public func setVolume(_ value: Double) {
        config.volume = MetronomeConfig.clampUnit(value)
        if engine.isRunning {
            restartEngineKeepingTransport()
        }
    }

    public func setSoundPreset(_ preset: MetronomeSoundPreset) {
        config.soundPreset = preset
        if engine.isRunning {
            restartEngineKeepingTransport()
        }
    }

    public func start() {
        errorMessage = nil
        do {
            try engine.start(
                bpm: config.bpm,
                beatsPerMeasure: beatsPerMeasure,
                volume: config.volume,
                sound: config.soundPreset
            )
            transport = .running
        } catch {
            errorMessage = "无法启动节拍器：\(error.localizedDescription)"
            transport = .stopped
        }
    }

    public func pause() {
        engine.pause()
        transport = .paused
    }

    public func stop() {
        engine.stop()
        transport = .stopped
        currentBeatIndex = nil
    }

    public func toggleStartPause() {
        switch transport {
        case .running:
            pause()
        case .paused, .stopped:
            start()
        }
    }

    private func restartEngineKeepingTransport() {
        guard transport == .running else { return }
        engine.stop()
        errorMessage = nil
        do {
            try engine.start(
                bpm: config.bpm,
                beatsPerMeasure: beatsPerMeasure,
                volume: config.volume,
                sound: config.soundPreset
            )
        } catch {
            errorMessage = "参数更新失败：\(error.localizedDescription)"
            transport = .stopped
        }
    }
}

public enum MetronomeTransportState: String, Sendable {
    case stopped
    case running
    case paused
}
