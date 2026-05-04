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

    func testStoreLoadAll_toleratesBrokenIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let index = root.appendingPathComponent("sheets_index.json")
        try "{not json".write(to: index, atomically: true, encoding: .utf8)
        let store = SheetLibraryStore(rootOverride: root)
        let loaded = await store.loadAll()
        XCTAssertEqual(loaded, [])
    }

    func testRename_updatesDisplayNameWithoutTouchingStoredFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.jpg")
        try Data([1, 2, 3]).write(to: source)

        let store = SheetLibraryStore(rootOverride: root)
        let entry = try await store.importSheetPages(sources: [source], displayName: "旧谱名")

        try await store.rename(id: entry.id, displayName: " 新谱名 ")
        let renamed = await store.loadAll().first(where: { $0.id == entry.id })
        XCTAssertEqual(renamed?.displayName, "新谱名")
        XCTAssertEqual(renamed?.storedFileNames, entry.storedFileNames)

        try await store.rename(id: entry.id, displayName: "   ")
        let unchanged = await store.loadAll().first(where: { $0.id == entry.id })
        XCTAssertEqual(unchanged?.displayName, "新谱名")
    }
}
