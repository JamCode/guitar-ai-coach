import XCTest
@testable import Core
@testable import Tuner
@testable import Fretboard
@testable import ChordChart
@testable import Chords

final class ToolsIntegrationTests: XCTestCase {
    @MainActor
    func testTunerStartStopFlow() async {
        let detector = TestPitchDetector()
        let viewModel = TunerViewModel(audio: TestAudioEngine(), detector: detector)
        XCTAssertFalse(viewModel.isListening)
        await viewModel.start()
        XCTAssertTrue(viewModel.isListening)
        detector.push(.pitch(frequencyHz: 110, peakCorrelation: 0.8, rms: 0.1))
        let exp = expectation(description: "pitch update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(viewModel.noteName, "A")
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 1.0)
        viewModel.stop()
        XCTAssertFalse(viewModel.isListening)
    }

    @MainActor
    func testTunerSelectStringStartsListening() async {
        let detector = TestPitchDetector()
        let viewModel = TunerViewModel(audio: TestAudioEngine(), detector: detector)
        XCTAssertNil(viewModel.selectedStringIndex)
        XCTAssertFalse(viewModel.isListening)
        await viewModel.selectStringForTuning(3)
        XCTAssertTrue(viewModel.isListening)
        XCTAssertEqual(viewModel.selectedStringIndex, 3)
        viewModel.stop()
        XCTAssertFalse(viewModel.isListening)
    }

    func testChordChartHasSections() {
        XCTAssertFalse(ChordChartData.sections.isEmpty)
    }

    func testChordChartEveryEntryHasDrawableSixStringDiagram() {
        for section in ChordChartData.sections {
            for entry in section.entries {
                XCTAssertEqual(entry.frets.count, 6, entry.symbol)
                let cfg = ChordDiagramLayout.config(for: entry.frets)
                XCTAssertGreaterThanOrEqual(cfg.endFret, cfg.startFret, entry.symbol)
            }
        }
    }
}

private final class TestAudioEngine: AudioEngineServing {
    let quality = AudioQualityBaseline()
    func start() throws { quality.markStart() }
    func stop() { quality.markStop() }
    func playSine(frequencyHz: Double, durationSec: Double) throws {
        quality.markCallback(renderCostMs: 0.1)
    }

    func playPluckedGuitarString(frequencyHz: Double, durationSec: Double) throws {
        quality.markCallback(renderCostMs: 0.12)
    }
}

private final class TestPitchDetector: PitchDetecting {
    private var callback: ((PitchFrameResult) -> Void)?
    func start(callback: @escaping (PitchFrameResult) -> Void) throws {
        self.callback = callback
    }
    func stop() {
        callback = nil
    }
    func push(_ result: PitchFrameResult) {
        callback?(result)
    }
}

