import XCTest
@testable import Core

/// Guards `AudioEngineService.stop()` invalidating sampler-backed state so a later `start()` reloads the SF2
/// (regression: leaving Tuner called `stop()` while `isSampledGuitarAvailable` stayed true → corrupt / buzzy playback in ear training).
final class AudioEngineServiceLifecycleTests: XCTestCase {
    func testStopClearsSampledGuitarFlagSoSecondStartReloads() throws {
        guard GuitarSoundBank.steelStringSF2URL != nil else {
            throw XCTSkip("SteelString SF2 not in bundle; cannot assert sampler lifecycle.")
        }

        let audio = AudioEngineService()
        try audio.start()
        let loadedAfterFirstStart = audio.isSampledGuitarAvailable
        audio.stop()

        if loadedAfterFirstStart {
            XCTAssertFalse(
                audio.isSampledGuitarAvailable,
                "After engine stop, sampled-guitar readiness must be false so the next start reloads the sound bank."
            )
        }

        try audio.start()
        if loadedAfterFirstStart {
            XCTAssertTrue(
                audio.isSampledGuitarAvailable,
                "Second cold start after stop must load SF2 again when the first start succeeded."
            )
        }

        audio.stop()
    }
}
