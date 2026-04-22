import Foundation

/// 应用启动后的后台预热：把参考音播放链路尽早拉起，减少首次点弦时等待 SF2 + `AVAudioEngine` 冷启动。
public final class AudioStartupWarmup: @unchecked Sendable {
    public static let shared = AudioStartupWarmup()

    private let queue: DispatchQueue
    private let warmup: @Sendable () -> Void
    private let lock = NSLock()
    private var hasScheduled = false

    public init(
        queue: DispatchQueue = DispatchQueue(
            label: "guitar-ai-coach.audio-startup-warmup",
            qos: .userInitiated
        ),
        warmup: @escaping @Sendable () -> Void = {
            AudioEngineService.shared.prepareForPlaybackWarmup()
        }
    ) {
        self.queue = queue
        self.warmup = warmup
    }

    /// 幂等调度：同一进程内最多安排一次后台预热，避免重复拉起共享音频图。
    public func scheduleIfNeeded() {
        lock.lock()
        let shouldSchedule = !hasScheduled
        if shouldSchedule {
            hasScheduled = true
        }
        lock.unlock()

        guard shouldSchedule else { return }
        queue.async { [warmup] in
            warmup()
        }
    }
}
