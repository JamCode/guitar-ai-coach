import XCTest
@testable import Tuner
@testable import Fretboard
@testable import Chords
@testable import ChordsLive
@testable import Theory
@testable import ChordChart

final class ToolsUITests: XCTestCase {
    func testViewsCanBeConstructed() {
        _ = TunerView()
        _ = FretboardView()
        _ = ChordLookupView()
        _ = LiveChordView()
        _ = TheoryView()
        _ = ChordChartView()
    }
}

