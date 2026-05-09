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
            editedChordChartSegments: list[0].editedChordChartSegments,
            editedChordChartRowSizes: list[0].editedChordChartRowSizes,
            editedAtMs: list[0].editedAtMs,
            timingVariants: list[0].timingVariants,
            timingVariantStats: list[0].timingVariantStats,
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

    func testRename_updatesCustomNameAndKeepsDisplayFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let media = root.appendingPathComponent("rename-demo.m4a")
        try Data([3, 4, 5]).write(to: media)

        let store = TranscriptionHistoryStore(rootOverride: root)
        let entry = try await store.saveResult(
            sourceURL: media,
            sourceType: .files,
            fileName: "rename-demo.m4a",
            customName: "旧名字",
            durationMs: 1_000,
            originalKey: "G",
            segments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "G")],
            displaySegments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "G")],
            chordChartSegments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "G")],
            backend: "remote",
            waveform: [0.1]
        )

        try await store.rename(id: entry.id, customName: "新名字")
        let renamed = await store.loadAll().first(where: { $0.id == entry.id })
        XCTAssertEqual(renamed?.customName, "新名字")
        XCTAssertEqual(renamed?.displayName, "新名字")

        try await store.rename(id: entry.id, customName: "   ")
        let unchanged = await store.loadAll().first(where: { $0.id == entry.id })
        XCTAssertEqual(unchanged?.customName, "新名字")
    }

    func testUpdateEditedChordChartSegments_persistsEditedChartAndCanBeCleared() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let media = root.appendingPathComponent("edited-demo.m4a")
        try Data([8, 9, 0]).write(to: media)

        let store = TranscriptionHistoryStore(rootOverride: root)
        let entry = try await store.saveResult(
            sourceURL: media,
            sourceType: .files,
            fileName: "edited-demo.m4a",
            customName: "演员",
            durationMs: 1_000,
            originalKey: "B",
            segments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "B")],
            displaySegments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "B")],
            chordChartSegments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "B")],
            backend: "remote",
            waveform: [0.4]
        )

        let edited = [
            TranscriptionSegment(startMs: 0, endMs: 500, chord: "B"),
            TranscriptionSegment(startMs: 500, endMs: 1_000, chord: "F#"),
        ]
        try await store.updateEditedChordChartSegments(id: entry.id, segments: edited, rowSizes: [1, 1])

        let saved = await store.load(id: entry.id)
        XCTAssertEqual(saved?.editedChordChartSegments, edited)
        XCTAssertEqual(saved?.editedChordChartRowSizes, [1, 1])
        XCTAssertNotNil(saved?.editedAtMs)

        try await store.clearEditedChordChartSegments(id: entry.id)
        let cleared = await store.load(id: entry.id)
        XCTAssertNil(cleared?.editedChordChartSegments)
        XCTAssertNil(cleared?.editedChordChartRowSizes)
        XCTAssertNil(cleared?.editedAtMs)
        XCTAssertEqual(cleared?.chordChartSegments, entry.chordChartSegments)
    }

    func testRename_preservesEditedChordChartSegments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let media = root.appendingPathComponent("rename-edited-demo.m4a")
        try Data([1, 3, 5]).write(to: media)

        let store = TranscriptionHistoryStore(rootOverride: root)
        let entry = try await store.saveResult(
            sourceURL: media,
            sourceType: .files,
            fileName: "rename-edited-demo.m4a",
            customName: "旧名字",
            durationMs: 1_000,
            originalKey: "E",
            segments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "E")],
            displaySegments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "E")],
            chordChartSegments: [TranscriptionSegment(startMs: 0, endMs: 500, chord: "E")],
            backend: "remote",
            waveform: [0.2]
        )
        let edited = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, chord: "E")
        ]
        try await store.updateEditedChordChartSegments(id: entry.id, segments: edited, rowSizes: [1])

        try await store.rename(id: entry.id, customName: "新名字")
        let renamed = await store.load(id: entry.id)
        XCTAssertEqual(renamed?.customName, "新名字")
        XCTAssertEqual(renamed?.editedChordChartSegments, edited)
        XCTAssertEqual(renamed?.editedChordChartRowSizes, [1])
        XCTAssertNotNil(renamed?.editedAtMs)
    }

    func testChordChartEditing_rename_onlyUpdatesChordNameWithinSameRow() {
        let rows = [
            [
                TranscriptionSegment(startMs: 0, endMs: 1_000, chord: "E"),
                TranscriptionSegment(startMs: 1_000, endMs: 2_000, chord: "B"),
            ],
            [
                TranscriptionSegment(startMs: 2_000, endMs: 3_000, chord: "C#m")
            ]
        ]

        let updated = TranscriptionChordChartEditing.rename(
            rows: rows,
            at: ChordRowPosition(rowIndex: 0, chordIndex: 1),
            to: "C#m"
        )

        XCTAssertEqual(
            updated,
            [
                [
                    TranscriptionSegment(startMs: 0, endMs: 1_000, chord: "E"),
                    TranscriptionSegment(startMs: 1_000, endMs: 2_000, chord: "C#m"),
                ],
                [
                    TranscriptionSegment(startMs: 2_000, endMs: 3_000, chord: "C#m")
                ]
            ]
        )
    }

    func testChordChartEditing_delete_keepsLaterRowsInPlace() {
        let rows = [
            [
                TranscriptionSegment(startMs: 0, endMs: 1_000, chord: "E"),
                TranscriptionSegment(startMs: 1_000, endMs: 2_000, chord: "B"),
                TranscriptionSegment(startMs: 2_000, endMs: 3_000, chord: "C#m"),
                TranscriptionSegment(startMs: 3_000, endMs: 4_000, chord: "A"),
            ],
            [
                TranscriptionSegment(startMs: 4_000, endMs: 5_000, chord: "F#")
            ]
        ]

        let updated = TranscriptionChordChartEditing.delete(
            rows: rows,
            at: ChordRowPosition(rowIndex: 0, chordIndex: 1)
        )

        XCTAssertEqual(
            updated,
            [
                [
                    TranscriptionSegment(startMs: 0, endMs: 1_000, chord: "E"),
                    TranscriptionSegment(startMs: 2_000, endMs: 3_000, chord: "C#m"),
                    TranscriptionSegment(startMs: 3_000, endMs: 4_000, chord: "A"),
                ],
                [
                    TranscriptionSegment(startMs: 4_000, endMs: 5_000, chord: "F#")
                ]
            ]
        )
    }

    func testChordChartEditing_mergeBehaviors_stayWithinCurrentRow() {
        let rows = [
            [
                TranscriptionSegment(startMs: 0, endMs: 1_000, chord: "E"),
                TranscriptionSegment(startMs: 1_000, endMs: 2_500, chord: "B"),
            ],
            [
                TranscriptionSegment(startMs: 2_500, endMs: 3_500, chord: "C#m")
            ]
        ]

        let backward = TranscriptionChordChartEditing.mergeBackward(
            rows: rows,
            at: ChordRowPosition(rowIndex: 0, chordIndex: 1)
        )
        XCTAssertEqual(
            backward,
            [
                [
                    TranscriptionSegment(startMs: 0, endMs: 2_500, chord: "E")
                ],
                [
                    TranscriptionSegment(startMs: 2_500, endMs: 3_500, chord: "C#m")
                ]
            ]
        )

        let forward = TranscriptionChordChartEditing.mergeForward(
            rows: rows,
            at: ChordRowPosition(rowIndex: 0, chordIndex: 0)
        )
        XCTAssertEqual(
            forward,
            [
                [
                    TranscriptionSegment(startMs: 0, endMs: 2_500, chord: "B")
                ],
                [
                    TranscriptionSegment(startMs: 2_500, endMs: 3_500, chord: "C#m")
                ]
            ]
        )

        XCTAssertNil(
            TranscriptionChordChartEditing.mergeBackward(
                rows: rows,
                at: ChordRowPosition(rowIndex: 1, chordIndex: 0)
            )
        )
        XCTAssertNil(
            TranscriptionChordChartEditing.mergeForward(
                rows: rows,
                at: ChordRowPosition(rowIndex: 0, chordIndex: 1)
            )
        )
    }

    func testChordChartRowLayout_rebuildRows_preservesSavedRowSizes() {
        let flattened = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, chord: "E"),
            TranscriptionSegment(startMs: 1_000, endMs: 2_000, chord: "B"),
            TranscriptionSegment(startMs: 2_000, endMs: 3_000, chord: "C#m"),
            TranscriptionSegment(startMs: 3_000, endMs: 4_000, chord: "A"),
        ]

        let rebuilt = TranscriptionChordChartRowLayout.rebuildRows(
            from: flattened,
            rowSizes: [3, 1]
        )

        XCTAssertEqual(rebuilt.map(\.count), [3, 1])
        XCTAssertEqual(TranscriptionChordChartRowLayout.flattenRows(rebuilt), flattened)
    }

    func testChordChartRowLayout_rebuildRows_fallsBackToDefaultChunkingWhenRowSizesMissing() {
        let flattened = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, chord: "E"),
            TranscriptionSegment(startMs: 1_000, endMs: 2_000, chord: "B"),
            TranscriptionSegment(startMs: 2_000, endMs: 3_000, chord: "C#m"),
            TranscriptionSegment(startMs: 3_000, endMs: 4_000, chord: "A"),
            TranscriptionSegment(startMs: 4_000, endMs: 5_000, chord: "F#"),
        ]

        let rebuilt = TranscriptionChordChartRowLayout.rebuildRows(from: flattened, rowSizes: nil)

        XCTAssertEqual(rebuilt.map(\.count), [4, 1])
        XCTAssertEqual(TranscriptionChordChartRowLayout.flattenRows(rebuilt), flattened)
    }
}
