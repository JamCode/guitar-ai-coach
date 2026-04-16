import XCTest
@testable import SwiftEarHost

final class SheetsStoreAndParserTests: XCTestCase {
    func testSheetEntryFromJSON_acceptsLegacyStoredFileName() {
        let raw: [String: Any] = [
            "id": "s1",
            "displayName": "Test",
            "storedFileName": "a.jpg",
            "addedAtMs": 123,
            "parseStatus": "rawOnly"
        ]
        let entry = SheetEntry.fromJSON(raw)
        XCTAssertEqual(entry?.storedFileNames, ["a.jpg"])
    }

    func testOcrParser_splitsChordMelodyLyric() {
        let input = [
            OcrLineCandidate(text: "C Dm G7 C", centerY: 10),
            OcrLineCandidate(text: "1234 5- 67", centerY: 20),
            OcrLineCandidate(text: "我爱吉他", centerY: 30)
        ]
        let out = SheetOcrParser.parseCandidates(input)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].chords, ["C", "Dm", "G7", "C"])
        XCTAssertEqual(out[0].melody, "1234 5- 67")
        XCTAssertEqual(out[0].lyrics, "我爱吉他")
    }

    func testStoreLoadAll_toleratesBrokenIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let index = root.appendingPathComponent("sheets_index.json")
        try "{not json".write(to: index, atomically: true, encoding: .utf8)
        let store = SheetLibraryStore(rootOverride: root)
        let loaded = await store.loadAll()
        XCTAssertEqual(loaded, [])
    }
}
