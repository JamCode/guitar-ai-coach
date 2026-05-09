import XCTest
@testable import SwiftEarHost

final class StemSeparationEngineTests: XCTestCase {
    func testSeparate_usesRunnerStitchesAndReportsProgress() async throws {
        let media = DecodedTranscriptionMedia(
            fileName: "demo song.m4a",
            durationMs: 1_000,
            pcmSamples: Array(repeating: 0.25, count: 100),
            sampleRate: 100
        )
        let writer = CapturingStemWriter()
        let engine = StemSeparationEngine(
            configuration: StemSeparationConfiguration(
                targetSampleRate: 100,
                chunkDurationSec: 0.4,
                overlapRatio: 0.5,
                stems: [.vocals, .accompaniment]
            ),
            modelRunner: GainStemRunner(),
            writer: writer
        )
        var progress: [StemSeparationProgress] = []

        let result = try await engine.separate(
            media: media,
            outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        ) { progress.append($0) }

        XCTAssertEqual(result.fileName, "demo song.m4a")
        XCTAssertEqual(result.sampleRate, 100)
        XCTAssertNotNil(result.stems[.vocals])
        XCTAssertNotNil(result.stems[.accompaniment])
        XCTAssertEqual(progress.first?.stage, .preparing)
        XCTAssertTrue(progress.contains { $0.stage == .separating && $0.fraction == 1 })
        XCTAssertEqual(progress.last?.stage, .completed)
        let vocals = try XCTUnwrap(writer.lastSamples[.vocals])
        let accompaniment = try XCTUnwrap(writer.lastSamples[.accompaniment])
        XCTAssertEqual(vocals.count, 100)
        XCTAssertEqual(accompaniment.count, 100)
        XCTAssertEqual(vocals[0], Float(0.25), accuracy: 0.0001)
        XCTAssertEqual(accompaniment[0], Float(-0.25), accuracy: 0.0001)
    }
}

final class StemSeparationStoreTests: XCTestCase {
    func testSaveLoadAndRemove() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StemSeparationStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outputDirectory = root.appendingPathComponent("demo-output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let vocalURL = outputDirectory.appendingPathComponent("vocals.wav")
        let accompanimentURL = outputDirectory.appendingPathComponent("accompaniment.wav")
        try Data([1, 2, 3]).write(to: vocalURL)
        try Data([4, 5, 6]).write(to: accompanimentURL)

        let store = StemSeparationStore(rootURL: root)
        let result = StemSeparationResult(
            id: "demo",
            fileName: "song.m4a",
            durationMs: 1_000,
            sampleRate: 16_000,
            createdAtMs: 100,
            stems: [
                .vocals: vocalURL.path,
                .accompaniment: accompanimentURL.path,
            ]
        )

        try await store.save(result)
        let loaded = await store.loadAll()
        XCTAssertEqual(loaded, [result])

        try await store.remove(id: "demo")
        let remaining = await store.loadAll()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vocalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: accompanimentURL.path))
    }

    func testRenameUpdatesCustomNameAndKeepsAudioFiles() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StemSeparationStoreRenameTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outputDirectory = root.appendingPathComponent("demo-output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let vocalURL = outputDirectory.appendingPathComponent("vocals.wav")
        let accompanimentURL = outputDirectory.appendingPathComponent("accompaniment.wav")
        try Data([1, 2, 3]).write(to: vocalURL)
        try Data([4, 5, 6]).write(to: accompanimentURL)

        let store = StemSeparationStore(rootURL: root)
        let result = StemSeparationResult(
            id: "demo",
            fileName: "song.m4a",
            durationMs: 1_000,
            sampleRate: 16_000,
            createdAtMs: 100,
            stems: [
                .vocals: vocalURL.path,
                .accompaniment: accompanimentURL.path,
            ]
        )

        try await store.save(result)
        try await store.rename(id: "demo", customName: "  新名字  ")

        let loaded = await store.loadAll()
        let renamed = try XCTUnwrap(loaded.first)
        XCTAssertEqual(renamed.customName, "新名字")
        XCTAssertEqual(renamed.fileName, "song.m4a")
        XCTAssertEqual(renamed.stems[.vocals], vocalURL.path)
        XCTAssertEqual(renamed.stems[.accompaniment], accompanimentURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vocalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: accompanimentURL.path))
    }
}

final class StemSeparationTaskStoreTests: XCTestCase {
    func testCreateMarkLoadResumableAndRemove() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StemSeparationTaskStoreTests-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("source.m4a")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([7, 8, 9]).write(to: sourceURL)

        let store = StemSeparationTaskStore(rootURL: root.appendingPathComponent("tasks", isDirectory: true))
        let task = try await store.createTask(
            from: sourceURL,
            customName: "待恢复歌曲",
            originalFileName: "source.m4a"
        )

        let inputURL = await store.inputURL(for: task)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inputURL.path))
        XCTAssertEqual(try Data(contentsOf: inputURL), Data([7, 8, 9]))
        var resumableIDs = await store.loadResumable().map(\.id)
        XCTAssertEqual(resumableIDs, [task.id])

        try await store.mark(id: task.id, state: .running)
        let loadedRunning = await store.load(id: task.id)
        let running = try XCTUnwrap(loadedRunning)
        XCTAssertEqual(running.state, .running)
        resumableIDs = await store.loadResumable().map(\.id)
        XCTAssertEqual(resumableIDs, [task.id])

        try await store.mark(id: task.id, state: .failed, errorMessage: "model failed")
        let loadedFailed = await store.load(id: task.id)
        let failed = try XCTUnwrap(loadedFailed)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.errorMessage, "model failed")
        let resumableAfterFailure = await store.loadResumable()
        XCTAssertTrue(resumableAfterFailure.isEmpty)

        try await store.remove(id: task.id)
        let removed = await store.load(id: task.id)
        XCTAssertNil(removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inputURL.path))
    }
}

private struct GainStemRunner: StemSeparationModelRunning {
    let stems: [StemKind] = [.vocals, .accompaniment]

    func separate(samples: [Float], sampleRate _: Double) async throws -> [StemKind: [Float]] {
        [
            .vocals: samples,
            .accompaniment: samples.map { -$0 },
        ]
    }
}

private final class CapturingStemWriter: StemAudioFileWriting {
    private(set) var lastSamples: [StemKind: [Float]] = [:]

    func write(
        stems: [StemKind: [Float]],
        sampleRate _: Double,
        outputDirectory: URL,
        baseName: String
    ) throws -> [StemKind: URL] {
        lastSamples = stems
        return Dictionary(
            uniqueKeysWithValues: stems.keys.map {
                ($0, outputDirectory.appendingPathComponent("\(baseName)-\($0.rawValue).wav"))
            }
        )
    }
}
