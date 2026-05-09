import AVFoundation
import Core
import Foundation

public enum SightSingingEvaluateCaptureError: Error, Sendable {
    case emptyPCM
    case engineFailed(String)
}

/// 判定阶段独占采集一段单声道 float PCM（与 `TunerPitchDetector` / `DefaultSightSingingPitchTracker` 互斥：调用方须先 `pitchTracker.stop()`）。
public enum SightSingingEvaluateCapture {
    /// - Parameters:
    ///   - maxDurationMs: 硬上限录音时长。
    ///   - warmupMs: 此前样本不参与尾静音提前结束判定。
    ///   - endOnTailSilenceMs: 预热后若尾部 RMS 持续低于峰值比例达该时长则提前停录。
    public static func recordMonoPCM(
        maxDurationMs: Int,
        warmupMs: Int,
        endOnTailSilenceMs: Int = 420,
        tailWindowMs: Int = 100,
        tailRmsVsPeak: Float = 0.028,
        pollIntervalMs: Int = 50
    ) async throws -> (samples: [Float], sampleRate: Double, wallClockMs: Int) {
        #if os(iOS)
        try await MicrophoneRecordingPermission.ensureGranted()
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        #endif

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // 必须在会话已 `setActive` 后再取 `inputFormat`；否则采样率可能为 0，引擎启动易报 -10851。
        let format = input.inputFormat(forBus: 0)
        let sampleRate = max(8_000.0, format.sampleRate)

        let accumulator = PCMFloatAccumulator()
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            let slice = UnsafeBufferPointer(start: ch, count: n)
            accumulator.append(slice)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SightSingingEvaluateCaptureError.engineFailed(error.localizedDescription)
        }

        let wallStart = Date()
        var consecutiveQuietMs = 0
        let tailWinSamples = max(128, Int(sampleRate * Double(tailWindowMs) / 1000.0))

        while true {
            let elapsedMs = Int(Date().timeIntervalSince(wallStart) * 1000.0)
            if elapsedMs >= maxDurationMs { break }

            try await Task.sleep(nanoseconds: UInt64(pollIntervalMs) * 1_000_000)

            guard elapsedMs >= warmupMs else { continue }

            let snap = accumulator.snapshot()
            guard snap.samples.count >= tailWinSamples else { continue }
            let tail = snap.samples.suffix(tailWinSamples)
            var energy: Float = 0
            for v in tail {
                energy += v * v
            }
            let rms = sqrt(energy / Float(tailWinSamples))
            let peak = max(snap.peakMagnitude, 1e-7)
            if rms < peak * tailRmsVsPeak {
                consecutiveQuietMs += pollIntervalMs
                if consecutiveQuietMs >= endOnTailSilenceMs { break }
            } else {
                consecutiveQuietMs = 0
            }
        }

        input.removeTap(onBus: 0)
        engine.stop()

        let wallClockMs = Int(Date().timeIntervalSince(wallStart) * 1000.0)
        let samples = accumulator.snapshot().samples
        guard !samples.isEmpty else { throw SightSingingEvaluateCaptureError.emptyPCM }
        return (samples, sampleRate, wallClockMs)
    }
}

// MARK: - Accumulator

private final class PCMFloatAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [Float] = []
    private var peakMagnitude: Float = 0

    func append(_ slice: UnsafeBufferPointer<Float>) {
        guard !slice.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var localPeak = peakMagnitude
        for v in slice {
            let a = abs(v)
            if a > localPeak { localPeak = a }
        }
        peakMagnitude = localPeak
        data.append(contentsOf: slice)
    }

    func snapshot() -> (samples: [Float], peakMagnitude: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (data, peakMagnitude)
    }
}
