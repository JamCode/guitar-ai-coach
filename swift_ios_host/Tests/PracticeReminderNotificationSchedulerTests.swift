import XCTest
import UserNotifications
@testable import SwiftEarHost

final class PracticeReminderNotificationSchedulerTests: XCTestCase {
    func testDailyReminderRequest_usesExpectedIdentifierAndTime() {
        let request = PracticeReminderNotificationScheduler.makeDailyReminderRequest()

        XCTAssertEqual(request.identifier, PracticeReminderNotificationScheduler.dailyReminderIdentifier)

        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
            XCTFail("Expected calendar notification trigger")
            return
        }

        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 20)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }
}
