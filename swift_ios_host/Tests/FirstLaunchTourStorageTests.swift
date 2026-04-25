import XCTest
@testable import SwiftEarHost

final class FirstLaunchTourStorageTests: XCTestCase {
    func testCompletedKey_roundTripInSuite() {
        let name = "test.firstLaunchTour.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            XCTFail("suite UserDefaults unavailable")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertFalse(FirstLaunchTourStorage.isCompleted(in: defaults))
        FirstLaunchTourStorage.markCompleted(in: defaults)
        XCTAssertTrue(FirstLaunchTourStorage.isCompleted(in: defaults))
        FirstLaunchTourStorage.resetForTesting(in: defaults)
        XCTAssertFalse(FirstLaunchTourStorage.isCompleted(in: defaults))
    }
}
