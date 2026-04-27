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

    func testSaveResult_persistsRelativePathAndResolvesToExistingFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let media = root.appendingPathComponent("demo.m4a")
        try Data([1, 2, 3]).write(to: media)

        let store = TranscriptionHistoryStore(rootOverride: root)
        let entry = try await store.saveResult(
            sourceURL: media,
            sourceType: .files,
            fileName: "demo.m4a",
            customName: "我的练习歌",
            durationMs: 120_000,
            originalKey: "E",
            segments: [
                TranscriptionSegment(startMs: 0, endMs: 4_000, chord: "E")
            ],
            displaySegments: [
                TranscriptionSegment(startMs: 0, endMs: 4_000, chord: "E")
            ],
            chordChartSegments: [
                TranscriptionSegment(startMs: 0, endMs: 4_000, chord: "E")
            ],
            backend: "remote",
            waveform: [0.1, 0.4, 0.2]
        )

        XCTAssertFalse(entry.storedMediaPath.hasPrefix("/"))
        XCTAssertTrue(entry.storedMediaPath.hasPrefix("\(TranscriptionMediaPathResolver.mediaDirectoryName)/"))

        let resolved = try await store.resolveMediaURL(for: entry)
        XCTAssertNotNil(resolved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved!.path))
    }

    func testResolver_legacyAbsolutePathStillReadable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyDir = root.appendingPathComponent("legacy-external", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyFile = legacyDir.appendingPathComponent("clip.m4a")
        try Data([9]).write(to: legacyFile)

        let resolved = TranscriptionMediaPathResolver.resolve(
            storedMediaPath: legacyFile.path,
            docsRoot: root
        )
        XCTAssertEqual(resolved?.path, legacyFile.path)
    }

    func testResolver_healsWhenLegacyAbsoluteMissingButFileInCurrentMediaDir() throws {
        let docsRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let mediaDir = docsRoot.appendingPathComponent(TranscriptionMediaPathResolver.mediaDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let fileName = "healed-\(UUID().uuidString).m4a"
        let actualFile = mediaDir.appendingPathComponent(fileName)
        try Data([7]).write(to: actualFile)

        let bogusAbsolute = "/var/mobile/Containers/Data/Application/DEAD-BEEF/Documents/transcription_media/\(fileName)"

        let resolved = TranscriptionMediaPathResolver.resolve(
            storedMediaPath: bogusAbsolute,
            docsRoot: docsRoot
        )
        XCTAssertEqual(resolved?.path, actualFile.path)
    }

    func testRemove_deletesFileResolvedViaLastPathComponentAfterCorruptingStoredPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("in.m4a")
        try Data([1, 2]).write(to: source)

        let store = TranscriptionHistoryStore(rootOverride: root)
        let entry = try await store.saveResult(
            sourceURL: source,
            sourceType: .files,
            fileName: "in.m4a",
            customName: "我的练习歌",
            durationMs: 1_000,
            originalKey: "C",
            segments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "C")],
            displaySegments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "C")],
            chordChartSegments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "C")],
            backend: "remote",
            waveform: [0.2]
        )

        let indexURL = root.appendingPathComponent("transcription_history.json")
        let raw = try Data(contentsOf: indexURL)
        var list = try JSONDecoder().decode([TranscriptionHistoryEntry].self, from: raw)
        XCTAssertEqual(list.count, 1)
        let lastName = (list[0].storedMediaPath as NSString).lastPathComponent
        list[0] = TranscriptionHistoryEntry(
            id: list[0].id,
            sourceType: list[0].sourceType,
            fileName: list[0].fileName,
            customName: list[0].customName,
            storedMediaPath: "/nonexistent/old-container/Documents/transcription_media/\(lastName)",
            durationMs: list[0].durationMs,
            originalKey: list[0].originalKey,
            createdAtMs: list[0].createdAtMs,
            segments: list[0].segments,
            displaySegments: list[0].displaySegments,
            chordChartSegments: list[0].chordChartSegments,
            backend: list[0].backend,
            waveform: list[0].waveform
        )
        try JSONEncoder().encode(list).write(to: indexURL, options: .atomic)

        let loaded = await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, entry.id)
        XCTAssertEqual(loaded.first?.segments, entry.segments)
        XCTAssertEqual(loaded.first?.displayName, "我的练习歌")
        let healed = try await store.resolveMediaURL(for: loaded[0])
        XCTAssertNotNil(healed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: healed!.path))

        try await store.remove(id: entry.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: healed!.path))
        let afterRemove = await store.loadAll()
        XCTAssertTrue(afterRemove.isEmpty)
    }
}
