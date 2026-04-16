import XCTest
@testable import ChordsLive
@testable import Core

final class LiveChordIntegrationTests: XCTestCase {
    @MainActor
    func testControllerStartStopAndModeSwitch() async {
        let source = FakeLiveAudioSource()
        let controller = LiveChordController(audioSource: source)
        XCTAssertFalse(controller.state.isListening)
        await controller.start()
        XCTAssertTrue(controller.state.isListening)
        await controller.setMode(.fast)
        XCTAssertEqual(controller.state.mode, .fast)
        await controller.stop()
        XCTAssertFalse(controller.state.isListening)
        XCTAssertEqual(controller.state.status, "已暂停")
    }
}

private final class FakeLiveAudioSource: LiveAudioSource {
    var callback: (([Float]) -> Void)?

    func hasPermission() async -> Bool { true }

    func start(sampleRate: Int, onChunk: @escaping ([Float]) -> Void) throws {
        callback = onChunk
        let sine = (0..<4096).map { i in Float(sin(Double(i) * 2 * .pi * 220 / Double(sampleRate))) * 0.2 }
        onChunk(sine)
    }

    func stop() async {
        callback = nil
    }
}

