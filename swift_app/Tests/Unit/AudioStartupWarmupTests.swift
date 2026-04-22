import XCTest
@testable import Core

final class AudioStartupWarmupTests: XCTestCase {
    func testPrepareForPlaybackWarmupDoesNotCountAsAudioStart() {
        let quality = AudioQualityBaseline()
        let audio = AudioEngineService(quality: quality)

        audio.prepareForPlaybackWarmup()

        let snapshot = quality.snapshot()
        XCTAssertEqual(snapshot.startCount, 0, "Warmup should preload playback resources without activating the audio session.")
        audio.stop()
    }

    func testScheduleIfNeededRunsWarmupOnlyOnce() {
        let queue = DispatchQueue(label: "guitar-ai-coach.audio-startup-warmup-tests")
        let lock = NSLock()
        var runCount = 0
        let exp = expectation(description: "warmup runs")

        let warmup = AudioStartupWarmup(
            queue: queue,
            warmup: {
                lock.lock()
                runCount += 1
                let currentCount = runCount
                lock.unlock()
                if currentCount == 1 {
                    exp.fulfill()
                }
            }
        )

        warmup.scheduleIfNeeded()
        warmup.scheduleIfNeeded()
        wait(for: [exp], timeout: 1.0)
        queue.sync {}

        lock.lock()
        let finalCount = runCount
        lock.unlock()
        XCTAssertEqual(finalCount, 1, "Warmup should be scheduled only once per process.")
    }
}
