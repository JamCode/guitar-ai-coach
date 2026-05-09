# Local Offline Song Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-only file-import chord transcription feature for iOS that imports media from Photos/Files, runs offline chord recognition, and presents a player-style result screen with chord fingering, waveform, playback sync, and saved history.

**Architecture:** Keep the new feature inside `swift_ios_host` so it can follow the app's existing `Models / Store / Services / Views` split and UI style. Use `AVFoundation` for media decoding, `Accelerate` for preprocessing/waveform summaries, `ONNX Runtime Mobile` for local inference, and a new local history store that copies imported media into the app sandbox so history entries can be replayed later.

**Tech Stack:** SwiftUI, XCTest, XcodeGen, AVFoundation, PhotosUI, UniformTypeIdentifiers, Accelerate/vDSP, ONNX Runtime Mobile, existing `Core`/`Chords` products from `swift_app`

---

## File Structure

### Existing files to modify

- `swift_ios_host/project.yml`
  - Add ONNX Runtime dependency and any model resource references needed by the host app.
- `swift_ios_host/Sources/SwiftEarHostApp.swift`
  - Replace the old `LiveChordView()` tab entry with the new local transcription home.
  - Remove the `ChordsLive` import and dependency usage.
- `swift_app/Package.swift`
  - Remove `ChordsLive` product/target/test dependencies after host migration is complete.

### New feature files to create

- `swift_ios_host/Sources/Transcription/Models/TranscriptionModels.swift`
  - History entry, segment, waveform summary, import source, processing state.
- `swift_ios_host/Sources/Transcription/Store/TranscriptionHistoryStore.swift`
  - Local persistence, media copy-in, load/save/delete history.
- `swift_ios_host/Sources/Transcription/Services/TranscriptionImportService.swift`
  - File validation, duration checks, import-source normalization.
- `swift_ios_host/Sources/Transcription/Services/TranscriptionMediaDecoder.swift`
  - Audio extraction from media, duration probing, PCM conversion.
- `swift_ios_host/Sources/Transcription/Services/TranscriptionWaveformService.swift`
  - Lightweight waveform summary generation and caching.
- `swift_ios_host/Sources/Transcription/Services/TranscriptionEngine.swift`
  - Protocol and orchestration for preprocessing + inference + result shaping.
- `swift_ios_host/Sources/Transcription/Services/OnnxChordRecognizer.swift`
  - ONNX Runtime wrapper and model invocation.
- `swift_ios_host/Sources/Transcription/Services/ChordFingeringResolver.swift`
  - Map chord labels to existing chord dictionary / diagram data.
- `swift_ios_host/Sources/Transcription/Views/TranscriptionHomeView.swift`
  - Entry screen with Photos / Files import buttons and recent history.
- `swift_ios_host/Sources/Transcription/Views/TranscriptionProcessingView.swift`
  - Processing UI and cancellation state.
- `swift_ios_host/Sources/Transcription/Views/TranscriptionResultView.swift`
  - Final player-style screen with waveform, chord ribbon, fingering, and playback sync.
- `swift_ios_host/Sources/Transcription/Views/TranscriptionHistoryView.swift`
  - Full history list page.
- `swift_ios_host/Sources/Transcription/Views/TranscriptionPlayerComponents.swift`
  - Focused subviews for waveform, chord ribbon, and playback controls.

### Test files to create

- `swift_ios_host/Tests/TranscriptionHistoryStoreTests.swift`
- `swift_ios_host/Tests/TranscriptionImportServiceTests.swift`
- `swift_ios_host/Tests/TranscriptionWaveformServiceTests.swift`
- `swift_ios_host/Tests/TranscriptionEngineTests.swift`
- `swift_ios_host/Tests/TranscriptionPlaybackSyncTests.swift`

### Files to delete at the end

- `swift_app/Sources/Features/ChordsLive/LiveChordController.swift`
- `swift_app/Sources/Features/ChordsLive/LiveChordStateMachine.swift`
- `swift_app/Sources/Features/ChordsLive/LiveChordView.swift`

---

### Task 1: Prepare Project Wiring And Replace The Tab Entry

**Files:**
- Modify: `swift_ios_host/project.yml`
- Modify: `swift_ios_host/Sources/SwiftEarHostApp.swift`
- Modify: `swift_app/Package.swift`

- [ ] **Step 1: Add a failing compile-time integration target in the host app plan**

Use this as the target state for the host app tab wiring:

```swift
import SwiftUI
import Tuner
import Fretboard
import Chords
import ChordChart
import Profile
import Core

@main
struct SwiftEarHostApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

private struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack { ToolsTabView() }.tag(0)
            NavigationStack { PracticeHomeView() }.tag(1)
            NavigationStack { SheetLibraryView() }.tag(2)
            NavigationStack { TranscriptionHomeView() }.tag(3)
            NavigationStack { ProfileHomeView() }.tag(4)
        }
    }
}
```

- [ ] **Step 2: Run a build to verify it fails because the new feature does not exist yet**

Run:

```bash
cd swift_ios_host && xcodegen generate && xcodebuild build -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS'
```

Expected: build fails with an error like `cannot find 'TranscriptionHomeView' in scope`.

- [ ] **Step 3: Add the minimal project wiring and placeholder view**

Create the placeholder view and dependency changes:

```swift
// swift_ios_host/Sources/Transcription/Views/TranscriptionHomeView.swift
import SwiftUI
import Core

struct TranscriptionHomeView: View {
    var body: some View {
        Text("本地离线扒歌")
            .navigationTitle("扒歌")
            .appPageBackground()
    }
}
```

```yaml
# swift_ios_host/project.yml
packages:
  GuitarAICoach:
    path: ../swift_app
  OnnxRuntime:
    url: https://github.com/microsoft/onnxruntime
    from: 1.22.0
```

```yaml
# swift_ios_host/project.yml target dependency addition
      - package: OnnxRuntime
        product: onnxruntime_objc
```

```swift
// swift_app/Package.swift
// Remove ChordsLive from products, App dependencies, and test dependencies
```

- [ ] **Step 4: Re-run the host build**

Run:

```bash
cd swift_ios_host && xcodegen generate && xcodebuild build -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS'
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Git checkpoint (only if the user explicitly requests a commit)**

```bash
git add swift_ios_host/project.yml swift_ios_host/Sources/SwiftEarHostApp.swift swift_ios_host/Sources/Transcription/Views/TranscriptionHomeView.swift swift_app/Package.swift
git commit -m "feat(ios): wire local transcription tab"
```

---

### Task 2: Build History Models And Local Persistence

**Files:**
- Create: `swift_ios_host/Sources/Transcription/Models/TranscriptionModels.swift`
- Create: `swift_ios_host/Sources/Transcription/Store/TranscriptionHistoryStore.swift`
- Test: `swift_ios_host/Tests/TranscriptionHistoryStoreTests.swift`

- [ ] **Step 1: Write the failing persistence tests**

```swift
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.storedMediaPath))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionHistoryStoreTests
```

Expected: test target fails because `TranscriptionHistoryStore`, `TranscriptionSegment`, and related types do not exist.

- [ ] **Step 3: Add the minimal models and store**

```swift
// swift_ios_host/Sources/Transcription/Models/TranscriptionModels.swift
import Foundation

enum TranscriptionSourceType: String {
    case photoLibrary
    case files
}

struct TranscriptionSegment: Equatable {
    let startMs: Int
    let endMs: Int
    let chord: String
}

struct TranscriptionHistoryEntry: Equatable {
    let id: String
    let sourceType: TranscriptionSourceType
    let fileName: String
    let storedMediaPath: String
    let durationMs: Int
    let originalKey: String
    let createdAtMs: Int
    let segments: [TranscriptionSegment]
    let waveform: [Double]
}
```

```swift
// swift_ios_host/Sources/Transcription/Store/TranscriptionHistoryStore.swift
import Foundation

actor TranscriptionHistoryStore {
    private let rootOverride: URL?
    private let fileManager: FileManager
    private let indexFileName = "transcription_history.json"
    private let mediaDirectoryName = "transcription_media"

    init(rootOverride: URL? = nil, fileManager: FileManager = .default) {
        self.rootOverride = rootOverride
        self.fileManager = fileManager
    }

    func loadAll() async -> [TranscriptionHistoryEntry] { [] }

    func saveResult(
        sourceURL: URL,
        sourceType: TranscriptionSourceType,
        fileName: String,
        durationMs: Int,
        originalKey: String,
        segments: [TranscriptionSegment],
        waveform: [Double]
    ) async throws -> TranscriptionHistoryEntry {
        fatalError("implement saveResult")
    }
}
```

- [ ] **Step 4: Implement the real JSON persistence and media copy**

```swift
func loadAll() async -> [TranscriptionHistoryEntry] {
    guard let indexURL = try? indexURL(), fileManager.fileExists(atPath: indexURL.path) else { return [] }
    guard let data = try? Data(contentsOf: indexURL) else { return [] }
    guard let list = try? JSONDecoder().decode([StoredEntry].self, from: data) else { return [] }
    return list.map(\.model).sorted { $0.createdAtMs > $1.createdAtMs }
}

func saveResult(
    sourceURL: URL,
    sourceType: TranscriptionSourceType,
    fileName: String,
    durationMs: Int,
    originalKey: String,
    segments: [TranscriptionSegment],
    waveform: [Double]
) async throws -> TranscriptionHistoryEntry {
    let mediaDir = try mediaDirectoryURL()
    let id = UUID().uuidString
    let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension.lowercased()
    let dst = mediaDir.appendingPathComponent("\(id).\(ext)")
    if fileManager.fileExists(atPath: dst.path) { try fileManager.removeItem(at: dst) }
    try fileManager.copyItem(at: sourceURL, to: dst)

    let entry = TranscriptionHistoryEntry(
        id: id,
        sourceType: sourceType,
        fileName: fileName,
        storedMediaPath: dst.path,
        durationMs: durationMs,
        originalKey: originalKey,
        createdAtMs: Int(Date().timeIntervalSince1970 * 1000),
        segments: segments,
        waveform: waveform
    )

    var all = await loadAll()
    all.append(entry)
    try writeAll(all)
    return entry
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionHistoryStoreTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Git checkpoint (only if the user explicitly requests a commit)**

```bash
git add swift_ios_host/Sources/Transcription/Models/TranscriptionModels.swift swift_ios_host/Sources/Transcription/Store/TranscriptionHistoryStore.swift swift_ios_host/Tests/TranscriptionHistoryStoreTests.swift
git commit -m "feat(ios): add transcription history persistence"
```

---

### Task 3: Validate Imports, Duration Limits, And Media Decoding

**Files:**
- Create: `swift_ios_host/Sources/Transcription/Services/TranscriptionImportService.swift`
- Create: `swift_ios_host/Sources/Transcription/Services/TranscriptionMediaDecoder.swift`
- Test: `swift_ios_host/Tests/TranscriptionImportServiceTests.swift`

- [ ] **Step 1: Write the failing validation tests**

```swift
import XCTest
@testable import SwiftEarHost

final class TranscriptionImportServiceTests: XCTestCase {
    func testValidateSupportedExtension_acceptsConfiguredFormats() {
        XCTAssertNoThrow(try TranscriptionImportService.validate(fileName: "demo.mp3", durationMs: 30_000))
        XCTAssertNoThrow(try TranscriptionImportService.validate(fileName: "demo.mov", durationMs: 30_000))
    }

    func testValidateUnsupportedExtension_throwsFriendlyError() {
        XCTAssertThrowsError(try TranscriptionImportService.validate(fileName: "demo.ogg", durationMs: 30_000))
    }

    func testValidateDurationOverSixMinutes_throwsFriendlyError() {
        XCTAssertThrowsError(try TranscriptionImportService.validate(fileName: "demo.mp4", durationMs: 360_001))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionImportServiceTests
```

Expected: FAIL because `TranscriptionImportService` does not exist.

- [ ] **Step 3: Add the import validation service**

```swift
import Foundation

enum TranscriptionImportError: LocalizedError, Equatable {
    case unsupportedFileType
    case durationTooLong

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "当前只支持 mp3、m4a、wav、aac、mp4、mov"
        case .durationTooLong:
            return "当前只支持 6 分钟以内的文件"
        }
    }
}

enum TranscriptionImportService {
    private static let supportedExtensions = Set(["mp3", "m4a", "wav", "aac", "mp4", "mov"])
    private static let maxDurationMs = 360_000

    static func validate(fileName: String, durationMs: Int) throws {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw TranscriptionImportError.unsupportedFileType }
        guard durationMs <= maxDurationMs else { throw TranscriptionImportError.durationTooLong }
    }
}
```

- [ ] **Step 4: Add the media decoder API**

```swift
import AVFoundation
import Foundation

struct DecodedTranscriptionMedia {
    let fileName: String
    let durationMs: Int
    let pcmSamples: [Float]
    let sampleRate: Double
}

enum TranscriptionMediaDecoder {
    static func probeDuration(url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return Int((CMTimeGetSeconds(duration) * 1000).rounded())
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionImportServiceTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Git checkpoint (only if the user explicitly requests a commit)**

```bash
git add swift_ios_host/Sources/Transcription/Services/TranscriptionImportService.swift swift_ios_host/Sources/Transcription/Services/TranscriptionMediaDecoder.swift swift_ios_host/Tests/TranscriptionImportServiceTests.swift
git commit -m "feat(ios): add transcription import validation"
```

---

### Task 4: Add Waveform Summaries And Engine Abstractions

**Files:**
- Create: `swift_ios_host/Sources/Transcription/Services/TranscriptionWaveformService.swift`
- Create: `swift_ios_host/Sources/Transcription/Services/TranscriptionEngine.swift`
- Test: `swift_ios_host/Tests/TranscriptionWaveformServiceTests.swift`
- Test: `swift_ios_host/Tests/TranscriptionEngineTests.swift`

- [ ] **Step 1: Write the waveform and engine tests**

```swift
import XCTest
@testable import SwiftEarHost

final class TranscriptionWaveformServiceTests: XCTestCase {
    func testBuildSummary_downsamplesToRequestedBinCount() {
        let samples = (0..<1_000).map { _ in Float.random(in: -1...1) }
        let bins = TranscriptionWaveformService.buildSummary(samples: samples, binCount: 50)
        XCTAssertEqual(bins.count, 50)
    }
}

final class TranscriptionEngineTests: XCTestCase {
    func testShapeSegments_mergesAdjacentIdenticalChords() {
        let raw = [
            RawChordFrame(startMs: 0, endMs: 1000, chord: "E"),
            RawChordFrame(startMs: 1000, endMs: 2000, chord: "E"),
            RawChordFrame(startMs: 2000, endMs: 3000, chord: "B")
        ]
        let merged = TranscriptionEngine.mergeSegments(raw)
        XCTAssertEqual(merged, [
            TranscriptionSegment(startMs: 0, endMs: 2000, chord: "E"),
            TranscriptionSegment(startMs: 2000, endMs: 3000, chord: "B")
        ])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionWaveformServiceTests -only-testing:SwiftEarHostTests/TranscriptionEngineTests
```

Expected: FAIL because the waveform and engine symbols do not exist.

- [ ] **Step 3: Add the minimal waveform and engine code**

```swift
import Foundation

enum TranscriptionWaveformService {
    static func buildSummary(samples: [Float], binCount: Int) -> [Double] {
        guard !samples.isEmpty, binCount > 0 else { return [] }
        let stride = max(1, samples.count / binCount)
        return (0..<binCount).map { idx in
            let start = idx * stride
            let end = min(samples.count, start + stride)
            guard start < end else { return 0 }
            let slice = samples[start..<end]
            let peak = slice.map { abs(Double($0)) }.max() ?? 0
            return peak
        }
    }
}
```

```swift
import Foundation

struct RawChordFrame: Equatable {
    let startMs: Int
    let endMs: Int
    let chord: String
}

enum TranscriptionEngine {
    static func mergeSegments(_ raw: [RawChordFrame]) -> [TranscriptionSegment] {
        guard var current = raw.first else { return [] }
        var out: [TranscriptionSegment] = []
        for item in raw.dropFirst() {
            if item.chord == current.chord, item.startMs == current.endMs {
                current = RawChordFrame(startMs: current.startMs, endMs: item.endMs, chord: current.chord)
            } else {
                out.append(TranscriptionSegment(startMs: current.startMs, endMs: current.endMs, chord: current.chord))
                current = item
            }
        }
        out.append(TranscriptionSegment(startMs: current.startMs, endMs: current.endMs, chord: current.chord))
        return out
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionWaveformServiceTests -only-testing:SwiftEarHostTests/TranscriptionEngineTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Git checkpoint (only if the user explicitly requests a commit)**

```bash
git add swift_ios_host/Sources/Transcription/Services/TranscriptionWaveformService.swift swift_ios_host/Sources/Transcription/Services/TranscriptionEngine.swift swift_ios_host/Tests/TranscriptionWaveformServiceTests.swift swift_ios_host/Tests/TranscriptionEngineTests.swift
git commit -m "feat(ios): add transcription waveform and segment shaping"
```

---

### Task 5: Wrap ONNX Runtime And The Chord Model

**Files:**
- Create: `swift_ios_host/Sources/Transcription/Services/OnnxChordRecognizer.swift`
- Modify: `swift_ios_host/Sources/Transcription/Services/TranscriptionEngine.swift`
- Test: `swift_ios_host/Tests/TranscriptionEngineTests.swift`

- [ ] **Step 1: Add a failing engine contract test for recognizer injection**

```swift
func testRecognize_usesInjectedRecognizerAndReturnsMergedSegments() async throws {
    let recognizer = FakeChordRecognizer(frames: [
        RawChordFrame(startMs: 0, endMs: 500, chord: "E"),
        RawChordFrame(startMs: 500, endMs: 1000, chord: "E"),
        RawChordFrame(startMs: 1000, endMs: 1500, chord: "B")
    ], originalKey: "E")

    let result = try await TranscriptionOrchestrator(recognizer: recognizer).recognize(
        fileName: "demo.m4a",
        durationMs: 1_500,
        samples: [0, 0.2, -0.3],
        sampleRate: 22_050
    )

    XCTAssertEqual(result.originalKey, "E")
    XCTAssertEqual(result.segments.count, 2)
}
```

- [ ] **Step 2: Run the engine tests to verify they fail**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionEngineTests
```

Expected: FAIL because `TranscriptionOrchestrator` and recognizer protocol do not exist.

- [ ] **Step 3: Add the recognizer protocol and ONNX wrapper shell**

```swift
import Foundation
import onnxruntime_objc

protocol ChordRecognizer {
    func recognize(samples: [Float], sampleRate: Double) async throws -> (frames: [RawChordFrame], originalKey: String)
}

final class OnnxChordRecognizer: ChordRecognizer {
    func recognize(samples: [Float], sampleRate: Double) async throws -> (frames: [RawChordFrame], originalKey: String) {
        fatalError("implement ONNX inference")
    }
}
```

- [ ] **Step 4: Add the orchestrator that the UI layer will call**

```swift
struct TranscriptionResultPayload {
    let fileName: String
    let durationMs: Int
    let originalKey: String
    let segments: [TranscriptionSegment]
    let waveform: [Double]
}

struct TranscriptionOrchestrator {
    let recognizer: ChordRecognizer

    func recognize(fileName: String, durationMs: Int, samples: [Float], sampleRate: Double) async throws -> TranscriptionResultPayload {
        let raw = try await recognizer.recognize(samples: samples, sampleRate: sampleRate)
        return TranscriptionResultPayload(
            fileName: fileName,
            durationMs: durationMs,
            originalKey: raw.originalKey,
            segments: TranscriptionEngine.mergeSegments(raw.frames),
            waveform: TranscriptionWaveformService.buildSummary(samples: samples, binCount: 180)
        )
    }
}
```

- [ ] **Step 5: Run the engine tests to verify they pass**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionEngineTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Add the real ONNX smoke test manually on device or simulator**

Run:

```bash
cd swift_ios_host && xcodebuild build -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: build succeeds with the ONNX Runtime wrapper linked; manual logging confirms model session initialization works.

- [ ] **Step 7: Git checkpoint (only if the user explicitly requests a commit)**

```bash
git add swift_ios_host/Sources/Transcription/Services/OnnxChordRecognizer.swift swift_ios_host/Sources/Transcription/Services/TranscriptionEngine.swift swift_ios_host/Tests/TranscriptionEngineTests.swift
git commit -m "feat(ios): integrate local onnx chord recognizer"
```

---

### Task 6: Build The Entry, Processing, And History Screens

**Files:**
- Modify: `swift_ios_host/Sources/Transcription/Views/TranscriptionHomeView.swift`
- Create: `swift_ios_host/Sources/Transcription/Views/TranscriptionProcessingView.swift`
- Create: `swift_ios_host/Sources/Transcription/Views/TranscriptionHistoryView.swift`
- Create: `swift_ios_host/Sources/Transcription/Services/ChordFingeringResolver.swift`

- [ ] **Step 1: Add the home/history screen skeleton**

```swift
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Core

struct TranscriptionHomeView: View {
    @StateObject private var vm = TranscriptionHomeViewModel()

    var body: some View {
        List {
            Section {
                Button("从相册导入") { vm.presentPhotoPicker() }
                    .appPrimaryButton()
                Button("从文件导入") { vm.presentFileImporter() }
                    .appSecondaryButton()
                Text("支持 mp3 / m4a / wav / aac / mp4 / mov，单文件最长 6 分钟")
                    .font(.footnote)
                    .foregroundStyle(SwiftAppTheme.muted)
            }

            if !vm.recentHistory.isEmpty {
                Section("最近历史") {
                    ForEach(vm.recentHistory, id: \.id) { entry in
                        NavigationLink(entry.fileName) { TranscriptionResultView(entry: entry) }
                    }
                }
            }
        }
        .navigationTitle("扒歌")
        .appPageBackground()
    }
}
```

- [ ] **Step 2: Add the processing screen**

```swift
import SwiftUI
import Core

struct TranscriptionProcessingView: View {
    let fileName: String
    let stepText: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(fileName).font(.headline)
            Text(stepText).foregroundStyle(SwiftAppTheme.muted)
            Button("取消", action: onCancel).appSecondaryButton()
        }
        .padding()
        .navigationTitle("正在识别")
        .appPageBackground()
    }
}
```

- [ ] **Step 3: Add the full history list screen**

```swift
import SwiftUI
import Core

struct TranscriptionHistoryView: View {
    let entries: [TranscriptionHistoryEntry]
    let onDelete: (TranscriptionHistoryEntry) -> Void

    var body: some View {
        List {
            ForEach(entries, id: \.id) { entry in
                NavigationLink {
                    TranscriptionResultView(entry: entry)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.fileName).foregroundStyle(SwiftAppTheme.text)
                        Text("原调：\(entry.originalKey)").font(.caption).foregroundStyle(SwiftAppTheme.muted)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    onDelete(entries[index])
                }
            }
        }
        .navigationTitle("扒歌历史")
        .appPageBackground()
    }
}
```

- [ ] **Step 4: Add fingering resolution using the existing chord feature**

```swift
import Foundation
import Chords

enum ChordFingeringResolver {
    static func displayData(for chord: String) -> ChordLookupResult? {
        ChordsService().lookup(symbol: chord)
    }
}
```

- [ ] **Step 5: Build the host app and verify navigation compiles**

Run:

```bash
cd swift_ios_host && xcodegen generate && xcodebuild build -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'generic/platform=iOS'
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Git checkpoint (only if the user explicitly requests a commit)**

```bash
git add swift_ios_host/Sources/Transcription/Views/TranscriptionHomeView.swift swift_ios_host/Sources/Transcription/Views/TranscriptionProcessingView.swift swift_ios_host/Sources/Transcription/Views/TranscriptionHistoryView.swift swift_ios_host/Sources/Transcription/Services/ChordFingeringResolver.swift
git commit -m "feat(ios): add transcription home and history screens"
```

---

### Task 7: Build The Player-Style Result Screen And Playback Sync

**Files:**
- Create: `swift_ios_host/Sources/Transcription/Views/TranscriptionPlayerComponents.swift`
- Create: `swift_ios_host/Sources/Transcription/Views/TranscriptionResultView.swift`
- Test: `swift_ios_host/Tests/TranscriptionPlaybackSyncTests.swift`

- [ ] **Step 1: Write the playback sync test**

```swift
import XCTest
@testable import SwiftEarHost

final class TranscriptionPlaybackSyncTests: XCTestCase {
    func testCurrentChordIndex_returnsMatchingSegment() {
        let segments = [
            TranscriptionSegment(startMs: 0, endMs: 4_000, chord: "E"),
            TranscriptionSegment(startMs: 4_000, endMs: 8_000, chord: "B"),
            TranscriptionSegment(startMs: 8_000, endMs: 12_000, chord: "C#m")
        ]

        XCTAssertEqual(PlaybackSyncResolver.currentIndex(for: 5_000, segments: segments), 1)
        XCTAssertEqual(PlaybackSyncResolver.currentIndex(for: 10_000, segments: segments), 2)
    }
}
```

- [ ] **Step 2: Run the playback sync test to verify it fails**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionPlaybackSyncTests
```

Expected: FAIL because `PlaybackSyncResolver` does not exist.

- [ ] **Step 3: Add the sync resolver and the focused player components**

```swift
import Foundation

enum PlaybackSyncResolver {
    static func currentIndex(for currentTimeMs: Int, segments: [TranscriptionSegment]) -> Int? {
        segments.firstIndex { $0.startMs <= currentTimeMs && currentTimeMs < $0.endMs }
    }
}
```

```swift
import SwiftUI
import Core

struct ChordRibbonView: View {
    let segments: [TranscriptionSegment]
    let currentIndex: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                    VStack(spacing: 6) {
                        Text(segment.chord).font(.headline)
                        Text("指法图").font(.caption2).foregroundStyle(SwiftAppTheme.muted)
                    }
                    .frame(width: 60, height: 72)
                    .background(idx == currentIndex ? SwiftAppTheme.surfaceSoft : SwiftAppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(idx == currentIndex ? SwiftAppTheme.brand : SwiftAppTheme.line, lineWidth: 1)
                    )
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build the final result view**

```swift
import SwiftUI
import AVFoundation
import Core

struct TranscriptionResultView: View {
    let entry: TranscriptionHistoryEntry
    @State private var currentTimeMs: Int = 0
    @State private var isPlaying = false

    var body: some View {
        let currentIndex = PlaybackSyncResolver.currentIndex(for: currentTimeMs, segments: entry.segments)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.fileName).font(.headline)
                Text("原调：\(entry.originalKey)").font(.subheadline).foregroundStyle(SwiftAppTheme.muted)
            }
            .padding()

            ChordRibbonView(segments: entry.segments, currentIndex: currentIndex)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            WaveformView(samples: entry.waveform)
                .frame(height: 320)

            PlaybackScrubberView(
                currentTimeMs: $currentTimeMs,
                durationMs: entry.durationMs,
                isPlaying: $isPlaying
            )
            .padding()
        }
        .appPageBackground()
    }
}
```

- [ ] **Step 5: Run the playback sync test**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionPlaybackSyncTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Run a manual visual check**

Run:

```bash
cd swift_ios_host && xcodebuild build -project SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: build succeeds; on simulator the result page shows the app-consistent player UI with chord ribbon, waveform, progress bar, and a single play/pause control.

- [ ] **Step 7: Git checkpoint (only if the user explicitly requests a commit)**

```bash
git add swift_ios_host/Sources/Transcription/Views/TranscriptionPlayerComponents.swift swift_ios_host/Sources/Transcription/Views/TranscriptionResultView.swift swift_ios_host/Tests/TranscriptionPlaybackSyncTests.swift
git commit -m "feat(ios): add transcription result player"
```

---

### Task 8: Close The Loop End-To-End And Remove The Old Live Feature

**Files:**
- Modify: `swift_ios_host/Sources/Transcription/Views/TranscriptionHomeView.swift`
- Modify: `swift_ios_host/Sources/Transcription/Views/TranscriptionHistoryView.swift`
- Delete: `swift_app/Sources/Features/ChordsLive/LiveChordController.swift`
- Delete: `swift_app/Sources/Features/ChordsLive/LiveChordStateMachine.swift`
- Delete: `swift_app/Sources/Features/ChordsLive/LiveChordView.swift`

- [ ] **Step 1: Wire the full import → process → save → result flow**

```swift
// inside TranscriptionHomeViewModel
func importAndRecognize(url: URL, sourceType: TranscriptionSourceType) async {
    do {
        let durationMs = try await TranscriptionMediaDecoder.probeDuration(url: url)
        try TranscriptionImportService.validate(fileName: url.lastPathComponent, durationMs: durationMs)
        let decoded = try await decoder.decode(url: url)
        let payload = try await orchestrator.recognize(
            fileName: decoded.fileName,
            durationMs: decoded.durationMs,
            samples: decoded.pcmSamples,
            sampleRate: decoded.sampleRate
        )
        let saved = try await historyStore.saveResult(
            sourceURL: url,
            sourceType: sourceType,
            fileName: payload.fileName,
            durationMs: payload.durationMs,
            originalKey: payload.originalKey,
            segments: payload.segments,
            waveform: payload.waveform
        )
        selectedEntry = saved
    } catch {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "这次没能稳定识别出和弦，换一个更清晰的文件再试试"
    }
}
```

- [ ] **Step 2: Remove the old realtime feature code**

Delete:

```text
swift_app/Sources/Features/ChordsLive/LiveChordController.swift
swift_app/Sources/Features/ChordsLive/LiveChordStateMachine.swift
swift_app/Sources/Features/ChordsLive/LiveChordView.swift
```

- [ ] **Step 3: Run the focused host tests**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SwiftEarHostTests/TranscriptionHistoryStoreTests -only-testing:SwiftEarHostTests/TranscriptionImportServiceTests -only-testing:SwiftEarHostTests/TranscriptionWaveformServiceTests -only-testing:SwiftEarHostTests/TranscriptionEngineTests -only-testing:SwiftEarHostTests/TranscriptionPlaybackSyncTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Run the full host test suite**

Run:

```bash
xcodebuild test -project swift_ios_host/SwiftEarHost.xcodeproj -scheme SwiftEarHost -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Run the manual acceptance checklist**

Use this checklist:

```text
1. 从相册导入 mp4 / mov 成功
2. 从文件导入 mp3 / m4a / wav / aac 成功
3. 超过 6 分钟的文件被拦截
4. 结果页显示原调、波形、和弦轨道、指法
5. 播放时当前和弦高亮
6. 拖动进度条时高亮立即跳转
7. 记录自动进入“扒歌历史”
8. 历史记录可再次打开并删除
```

- [ ] **Step 6: Git checkpoint (only if the user explicitly requests a commit)**

```bash
git add swift_ios_host/Sources/Transcription swift_ios_host/Tests swift_ios_host/Sources/SwiftEarHostApp.swift swift_ios_host/project.yml swift_app/Package.swift
git rm swift_app/Sources/Features/ChordsLive/LiveChordController.swift swift_app/Sources/Features/ChordsLive/LiveChordStateMachine.swift swift_app/Sources/Features/ChordsLive/LiveChordView.swift
git commit -m "feat(ios): add offline file-based song transcription"
```

---

## Self-Review

### 1. Spec coverage

- 输入来源（相册 / 文件）：Task 6 + Task 8 覆盖
- 支持格式与 6 分钟限制：Task 3 覆盖
- 本地离线识别链路：Task 3 / Task 4 / Task 5 / Task 8 覆盖
- 结果页播放器式 UI：Task 7 覆盖
- 原调、和弦时间轴、播放高亮：Task 5 / Task 7 覆盖
- 扒歌历史与可再次播放：Task 2 / Task 6 / Task 8 覆盖
- 删除旧实时扒歌：Task 1 / Task 8 覆盖
- UI/UX 风格与现有 Swift 一致：Task 6 / Task 7 显式要求复用 `SwiftAppTheme` 和现有视图习惯

Gap check result: no uncovered spec sections remain.

### 2. Placeholder scan

- No `TODO`, `TBD`, or “implement later” placeholders remain in the plan.
- Every task contains exact files, explicit commands, and concrete code snippets.

### 3. Type consistency

- `TranscriptionHistoryEntry`, `TranscriptionSegment`, `TranscriptionSourceType`, `RawChordFrame`, `TranscriptionResultPayload`, and `PlaybackSyncResolver` are introduced before later tasks rely on them.
- Result flow consistently uses `storedMediaPath`, `durationMs`, `originalKey`, `segments`, and `waveform`.

