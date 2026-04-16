import Foundation
import AVFoundation
import Core

public protocol LiveAudioSource: AnyObject {
    func hasPermission() async -> Bool
    func start(sampleRate: Int, onChunk: @escaping ([Float]) -> Void) throws
    func stop() async
}

public final class AVAudioLiveAudioSource: LiveAudioSource {
    private let engine = AVAudioEngine()
    private var started = false

    public init() {}

    public func hasPermission() async -> Bool {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { ok in continuation.resume(returning: ok) }
            }
        @unknown default: return false
        }
        #else
        return true
        #endif
    }

    public func start(sampleRate: Int, onChunk: @escaping ([Float]) -> Void) throws {
        guard !started else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(Double(sampleRate))
        try session.setActive(true)
        #endif
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            onChunk(Array(UnsafeBufferPointer(start: data, count: count)))
        }
        engine.prepare()
        try engine.start()
        started = true
    }

    public func stop() async {
        guard started else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        started = false
    }
}

@MainActor
public final class LiveChordController: ObservableObject {
    private static let sampleRate = 16_000
    private static let windowSec = 2.0
    private static let hopSec = 0.5

    private let engine: LiveChordEngine
    private let audioSource: LiveAudioSource
    private let stateMachine: LiveChordStateMachine
    private var processing = false

    @Published public private(set) var state: LiveChordUiState = .initial()

    public init(
        engine: LiveChordEngine = LiveChordEngine(),
        audioSource: LiveAudioSource = AVAudioLiveAudioSource(),
        stateMachine: LiveChordStateMachine = LiveChordStateMachine()
    ) {
        self.engine = engine
        self.audioSource = audioSource
        self.stateMachine = stateMachine
    }

    public func start() async {
        if state.isListening { return }
        state = state.copyWith(status: "请求麦克风权限…", error: .some(nil))

        let ok = await audioSource.hasPermission()
        guard ok else {
            state = state.copyWith(isListening: false, status: "需要麦克风权限", error: .some("需要麦克风权限"))
            return
        }

        do {
            engine.configure(
                sampleRate: Self.sampleRate,
                windowSec: Self.windowSec,
                hopSec: Self.hopSec,
                mode: state.mode,
                confidenceThreshold: 0.6
            )
            stateMachine.reset()
            try audioSource.start(sampleRate: Self.sampleRate) { [weak self] chunk in
                Task { @MainActor in
                    await self?.onChunk(chunk)
                }
            }
            state = state.copyWith(isListening: true, status: "🎵 Listening…", error: .some(nil))
        } catch {
            state = state.copyWith(isListening: false, status: "初始化失败", error: .some(error.localizedDescription))
        }
    }

    public func stop() async {
        await audioSource.stop()
        engine.reset()
        stateMachine.reset()
        state = state.copyWith(
            isListening: false,
            status: "已暂停",
            stableChord: "Unknown",
            confidence: 0
        )
    }

    public func setMode(_ mode: LiveChordMode) async {
        if state.mode == mode { return }
        state = state.copyWith(mode: mode)
        if state.isListening {
            engine.configure(
                sampleRate: Self.sampleRate,
                windowSec: Self.windowSec,
                hopSec: Self.hopSec,
                mode: mode,
                confidenceThreshold: 0.6
            )
            engine.reset()
            stateMachine.reset()
        }
    }

    private func onChunk(_ chunk: [Float]) async {
        if !state.isListening || processing { return }
        processing = true
        let frame = engine.process(floatChunk: chunk)
        state = stateMachine.applyFrame(current: state, frame: frame)
        processing = false
    }
}

