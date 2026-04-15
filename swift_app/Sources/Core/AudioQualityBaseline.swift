import Foundation

public struct AudioQualitySnapshot: Sendable {
    public let startCount: Int
    public let stopCount: Int
    public let underrunCount: Int
    public let callbackCount: Int
    public let averageCallbackIntervalMs: Double
    public let averageRenderCostMs: Double

    public init(
        startCount: Int,
        stopCount: Int,
        underrunCount: Int,
        callbackCount: Int,
        averageCallbackIntervalMs: Double,
        averageRenderCostMs: Double
    ) {
        self.startCount = startCount
        self.stopCount = stopCount
        self.underrunCount = underrunCount
        self.callbackCount = callbackCount
        self.averageCallbackIntervalMs = averageCallbackIntervalMs
        self.averageRenderCostMs = averageRenderCostMs
    }
}

public final class AudioQualityBaseline: @unchecked Sendable {
    private var startCount = 0
    private var stopCount = 0
    private var underrunCount = 0
    private var callbackCount = 0
    private var intervalSumMs = 0.0
    private var renderCostSumMs = 0.0
    private var lastCallbackNanos: UInt64?
    private let lock = NSLock()

    public init() {}

    public func markStart() {
        lock.lock()
        defer { lock.unlock() }
        startCount += 1
    }

    public func markStop() {
        lock.lock()
        defer { lock.unlock() }
        stopCount += 1
    }

    public func markUnderrun() {
        lock.lock()
        defer { lock.unlock() }
        underrunCount += 1
    }

    public func markCallback(renderCostMs: Double) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        callbackCount += 1
        renderCostSumMs += renderCostMs
        if let last = lastCallbackNanos {
            intervalSumMs += Double(now - last) / 1_000_000
        }
        lastCallbackNanos = now
    }

    public func snapshot() -> AudioQualitySnapshot {
        lock.lock()
        defer { lock.unlock() }
        let intervalDenominator = max(callbackCount - 1, 1)
        let callbackDenominator = max(callbackCount, 1)
        return AudioQualitySnapshot(
            startCount: startCount,
            stopCount: stopCount,
            underrunCount: underrunCount,
            callbackCount: callbackCount,
            averageCallbackIntervalMs: intervalSumMs / Double(intervalDenominator),
            averageRenderCostMs: renderCostSumMs / Double(callbackDenominator)
        )
    }
}

