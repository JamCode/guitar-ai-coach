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
}

