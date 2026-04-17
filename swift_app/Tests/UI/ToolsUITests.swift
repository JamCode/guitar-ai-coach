import XCTest
@testable import Tuner
@testable import Fretboard
@testable import Chords
@testable import ChordsLive
@testable import ChordChart
@testable import Profile
@testable import Ear
@testable import Practice

final class ToolsUITests: XCTestCase {
    func testViewsCanBeConstructed() {
        _ = TunerView()
        _ = FretboardView()
        _ = ChordLookupView()
        _ = ChordDiagramView(frets: [-1, 3, 2, 0, 1, 0])
        _ = LiveChordView()
        _ = ChordChartView()
        _ = ProfileHomeView()
        _ = HelpFeedbackView()
        _ = AppVersionView()
        _ = AccountSecurityView()
        _ = DiagnosticLogsView()
        _ = EarHomeView()
        _ = TraditionalCrawlPracticeView()
        _ = IntervalEarView()
        _ = EarMcqSessionView(title: "和弦听辨", bank: "A")
        _ = SightSingingSetupView()
        _ = SightSingingSessionView(
            repository: LocalSightSingingRepository(),
            pitchRange: "mid",
            includeAccidental: false,
            questionCount: 10,
            pitchTracker: DefaultSightSingingPitchTracker()
        )
    }
}

