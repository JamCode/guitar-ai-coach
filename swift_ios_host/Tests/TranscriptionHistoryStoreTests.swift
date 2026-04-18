import XCTest
@testable import SwiftEarHost

final class TranscriptionHistoryStoreTests: XCTestCase {
    func testLoadAll_whenIndexMissing_returnsEmpty() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = TranscriptionHistoryStore(rootOverride: root)

        let items = await store.loadAll()

        XCTAssertEqual(items, [])
    }

    func testSaveResult_copiesMediaAndPersistsEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let media = root.appendingPathComponent("demo.m4a")
        try Data([1, 2, 3]).write(to: media)

        let store = TranscriptionHistoryStore(rootOverride: root)
        let entry = try await store.saveResult(
            sourceURL: media,
            sourceType: .files,
            fileName: "demo.m4a",
            durationMs: 120_000,
            originalKey: "E",
            segments: [
                TranscriptionSegment(startMs: 0, endMs: 4_000, chord: "E")
            ],
            waveform: [0.1, 0.4, 0.2]
        )

        let loaded = await store.loadAll()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, entry.id)
        XCTAssertEqual(loaded.first?.segments, entry.segments)
        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.storedMediaPath))
    }
}
