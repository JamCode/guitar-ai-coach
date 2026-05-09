import XCTest
import Metronome

final class MetronomeConfigTests: XCTestCase {
    func testClampBPM() {
        XCTAssertEqual(MetronomeConfig.clampBPM(30), 40)
        XCTAssertEqual(MetronomeConfig.clampBPM(300), 240)
        XCTAssertEqual(MetronomeConfig.clampBPM(100), 100)
    }

    func testBeatInterval() {
        var c = MetronomeConfig(bpm: 120)
        XCTAssertEqual(c.beatIntervalSeconds, 0.5, accuracy: 0.0001)
        c.bpm = 60
        XCTAssertEqual(c.beatIntervalSeconds, 1.0, accuracy: 0.0001)
    }

    func testTimeSignatureBeats() {
        XCTAssertEqual(MetronomeTimeSignature.twoFour.beatsPerMeasure, 2)
        XCTAssertEqual(MetronomeTimeSignature.threeFour.beatsPerMeasure, 3)
        XCTAssertEqual(MetronomeTimeSignature.fourFour.beatsPerMeasure, 4)
        XCTAssertEqual(MetronomeTimeSignature.sixEight.beatsPerMeasure, 6)
    }
}
