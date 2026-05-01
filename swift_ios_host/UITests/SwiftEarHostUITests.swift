import XCTest

final class SwiftEarHostUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
        ]
        addSystemPermissionHandlers()
        app.launch()
        XCTAssertTrue(waitForElement(id: "screen.practice", timeout: 10))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testMainTabsLoad() {
        openTab(id: "tab.practice", labels: ["练习", "Practice"])
        XCTAssertTrue(waitForElement(id: "screen.practice"))

        openTab(id: "tab.sheets", labels: ["我的谱", "My sheets"])
        XCTAssertTrue(waitForElement(id: "screen.sheets.library"))

        openTab(id: "tab.transcription", labels: ["扒歌", "Transcribe"])
        XCTAssertTrue(waitForElement(id: "screen.transcription.home"))

        openTab(id: "tab.tools", labels: ["工具", "Tools"])
        XCTAssertTrue(waitForElement(id: "screen.tools"))
    }

    func testPracticeEntryPointsOpen() {
        openTab(id: "tab.practice", labels: ["练习", "Practice"])

        openPracticeEntry(id: "practice.intervalEar", expectedTexts: ["音程识别", "Interval"])
        openPracticeEntry(id: "practice.chordEar", expectedTexts: ["和弦听辨", "Chord"])
        openPracticeEntry(id: "practice.progressionEar", expectedTexts: ["和弦进行", "Progression"])
        openPracticeEntry(id: "practice.chord-switch", expectedTexts: ["和弦切换练习", "Chord"])
        openPracticeEntry(id: "practice.rhythm-strum", expectedTexts: ["扫弦", "Rhythm"])
        openPracticeEntry(id: "practice.scale-walk", expectedTexts: ["爬格子热身", "Scale warmup"])
    }

    func testToolsEntryPointsOpen() {
        openTab(id: "tab.tools", labels: ["工具", "Tools"])

        openToolEntry(id: "tools.metronome", expectedTexts: ["节拍器", "Metronome"])
        openToolEntry(id: "tools.tuner", expectedTexts: ["调音器", "Tuner"])
        openToolEntry(id: "tools.fretboard", expectedTexts: ["吉他指板", "Fretboard"])
        openToolEntry(id: "tools.chordLookup", expectedTexts: ["常用和弦", "和弦速查", "Chord"])
    }

    func testTranscriptionLockedPurchaseEntryPoints() {
        openTab(id: "tab.transcription", labels: ["扒歌", "Transcribe"])
        XCTAssertTrue(waitForElement(id: "screen.transcription.home"))

        let unlockButton = element(id: "transcription.unlockButton")
        if unlockButton.waitForExistence(timeout: 8) {
            unlockButton.tap()
        } else {
            tapElement(id: "transcription.importFiles")
        }

        XCTAssertTrue(waitForElement(id: "screen.purchase", timeout: 8))
        XCTAssertTrue(element(id: "purchase.restoreButton").waitForExistence(timeout: 5))
        XCTAssertTrue(element(id: "purchase.buyButton").waitForExistence(timeout: 5))
        closePresentedSheet()
    }

    func testSheetsAddEntryPointOpensSystemPicker() {
        openTab(id: "tab.sheets", labels: ["我的谱", "My sheets"])
        XCTAssertTrue(waitForElement(id: "screen.sheets.library"))

        tapElement(id: "sheets.addFromAlbum")
        app.tap()
        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 5)
                || app.sheets.firstMatch.waitForExistence(timeout: 5)
                || app.buttons["取消"].waitForExistence(timeout: 5)
                || app.buttons["Cancel"].waitForExistence(timeout: 5)
        )
    }

    private func openPracticeEntry(id: String, expectedTexts: [String]) {
        tapElement(id: id)
        assertAnyTextExists(expectedTexts, timeout: 8)
        navigateBack()
        XCTAssertTrue(waitForElement(id: "screen.practice"))
    }

    private func openToolEntry(id: String, expectedTexts: [String]) {
        tapElement(id: id)
        app.tap()
        assertAnyTextExists(expectedTexts, timeout: 8)
        navigateBack()
        XCTAssertTrue(waitForElement(id: "screen.tools"))
    }

    private func openTab(id: String, labels: [String]) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))

        let byId = tabBar.buttons[id]
        if byId.exists {
            byId.tap()
            return
        }

        for label in labels {
            let byLabel = tabBar.buttons[label]
            if byLabel.exists {
                byLabel.tap()
                return
            }
        }

        XCTFail("Missing tab: \(id) / \(labels.joined(separator: ", "))")
    }

    private func tapElement(id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = tappableElement(id: id)
        if !target.waitForExistence(timeout: 3) {
            for _ in 0..<6 where !target.exists {
                app.swipeUp()
            }
        }
        XCTAssertTrue(target.exists, "Missing element \(id)", file: file, line: line)
        if !target.isHittable {
            app.swipeUp()
        }
        target.tap()
    }

    private func element(id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tappableElement(id: String) -> XCUIElement {
        let button = app.buttons.matching(identifier: id).firstMatch
        if button.exists { return button }
        return element(id: id)
    }

    private func waitForElement(id: String, timeout: TimeInterval = 5) -> Bool {
        element(id: id).waitForExistence(timeout: timeout)
    }

    private func assertAnyTextExists(_ texts: [String], timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for text in texts {
                if app.staticTexts[text].exists
                    || app.navigationBars[text].exists
                    || app.buttons[text].exists
                    || app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists {
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Expected one of texts to exist: \(texts.joined(separator: ", "))")
    }

    private func navigateBack() {
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 5))
        let backButton = navBar.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()
    }

    private func closePresentedSheet() {
        let closeButtons = ["关闭", "Close", "完成", "Done", "取消", "Cancel"]
        for title in closeButtons {
            let button = app.buttons[title]
            if button.exists {
                button.tap()
                return
            }
        }
        if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    private func addSystemPermissionHandlers() {
        addUIInterruptionMonitor(withDescription: "System permissions") { alert in
            for title in ["允许", "好", "OK", "Allow", "允许访问所有照片", "继续"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }
}
