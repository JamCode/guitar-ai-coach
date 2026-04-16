import XCTest
@testable import Core
@testable import Chords

final class CoreAndChordsTests: XCTestCase {
    func testEnvironmentDefaultBaseURL() {
        let env = AppEnvironment()
        XCTAssertEqual(env.apiBaseURL, "http://localhost:18080/api")
    }

    func testChordsServiceHealthMessageContainsBaseURL() {
        let env = AppEnvironment(apiBaseURL: "https://example.com/api")
        let service = ChordsService(environment: env)
        XCTAssertTrue(service.healthMessage().contains("https://example.com/api"))
    }

    func testChordDiagramLayoutOpenCChordShowsNutAndFourFrets() {
        let c = [-1, 3, 2, 0, 1, 0]
        let cfg = ChordDiagramLayout.config(for: c)
        XCTAssertTrue(cfg.showsNut)
        XCTAssertNil(cfg.positionLabel)
        XCTAssertEqual(cfg.startFret, 1)
        XCTAssertEqual(cfg.endFret, 4)
    }

    func testChordDiagramLayoutHighBarreNoNut() {
        let bar = [5, 5, 7, 7, 7, 5]
        let cfg = ChordDiagramLayout.config(for: bar)
        XCTAssertFalse(cfg.showsNut)
        XCTAssertEqual(cfg.positionLabel, 5)
        XCTAssertEqual(cfg.startFret, 5)
        XCTAssertEqual(cfg.endFret, 8)
    }
}

