import Foundation

/// 将 `TranscriptionHistoryEntry.storedMediaPath` 解析为可访问的媒体文件 URL。
/// 新数据存相对路径 `transcription_media/<uuid>.<ext>`；旧数据可能为绝对路径。
enum TranscriptionMediaPathResolver {
    static let mediaDirectoryName = "transcription_media"

    static func resolve(
        storedMediaPath: String,
        docsRoot: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard !storedMediaPath.isEmpty else { return nil }

        if storedMediaPath.hasPrefix("/") {
            let legacy = URL(fileURLWithPath: storedMediaPath)
            if fileManager.fileExists(atPath: legacy.path) {
                return legacy
            }
            let fallback = docsRoot
                .appendingPathComponent(mediaDirectoryName, isDirectory: true)
                .appendingPathComponent(legacy.lastPathComponent)
            if fileManager.fileExists(atPath: fallback.path) {
                return fallback
            }
            return nil
        }

        var fromRelative = docsRoot
        for component in storedMediaPath.split(separator: "/") where !component.isEmpty {
            fromRelative = fromRelative.appendingPathComponent(String(component))
        }
        if fileManager.fileExists(atPath: fromRelative.path) {
            return fromRelative
        }

        let last = (storedMediaPath as NSString).lastPathComponent
        guard !last.isEmpty, last != "." else { return nil }
        let healed = docsRoot
            .appendingPathComponent(mediaDirectoryName, isDirectory: true)
            .appendingPathComponent(last)
        if fileManager.fileExists(atPath: healed.path) {
            return healed
        }
        return nil
    }
}

enum TranscriptionHistoryStoreError: LocalizedError {
    case invalidDocumentsRoot

    var errorDescription: String? {
        switch self {
        case .invalidDocumentsRoot:
            return "无法访问本地文档目录"
        }
    }
}

actor TranscriptionHistoryStore {
    private let rootOverride: URL?
    private let fileManager: FileManager
    private let indexFileName = "transcription_history.json"
    private var mediaDirectoryName: String { TranscriptionMediaPathResolver.mediaDirectoryName }

    init(rootOverride: URL? = nil, fileManager: FileManager = .default) {
        self.rootOverride = rootOverride
        self.fileManager = fileManager
    }

    func loadAll() async -> [TranscriptionHistoryEntry] {
        guard let indexURL = try? indexURL(), fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }
        guard let data = try? Data(contentsOf: indexURL) else {
            return []
        }
        guard let list = try? JSONDecoder().decode([TranscriptionHistoryEntry].self, from: data) else {
            return []
        }
        return list.sorted { $0.createdAtMs > $1.createdAtMs }
    }

    func saveResult(
        sourceURL: URL,
        sourceType: TranscriptionSourceType,
        fileName: String,
        customName: String,
        durationMs: Int,
        originalKey: String,
        segments: [TranscriptionSegment],
        displaySegments: [TranscriptionSegment],
        chordChartSegments: [TranscriptionSegment],
        backend: String,
        waveform: [Double]
    ) async throws -> TranscriptionHistoryEntry {
        let mediaDir = try mediaDirectoryURL()
        let id = UUID().uuidString
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension.lowercased()
        let destination = mediaDir.appendingPathComponent("\(id).\(ext)")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)

        let relativeStoredPath = "\(mediaDirectoryName)/\(id).\(ext)"
        let entry = TranscriptionHistoryEntry(
            id: id,
            sourceType: sourceType,
            fileName: fileName,
            customName: customName,
            storedMediaPath: relativeStoredPath,
            durationMs: durationMs,
            originalKey: originalKey,
            createdAtMs: Int(Date().timeIntervalSince1970 * 1000),
            segments: segments,
            displaySegments: displaySegments,
            chordChartSegments: chordChartSegments,
            backend: backend,
            waveform: waveform
        )

        var all = await loadAll()
        all.append(entry)
        try writeAll(all)
        return entry
    }

    func remove(id: String) async throws {
        let all = await loadAll()
        var remaining: [TranscriptionHistoryEntry] = []
        var victim: TranscriptionHistoryEntry?
        for entry in all {
            if entry.id == id {
                victim = entry
            } else {
                remaining.append(entry)
            }
        }

        if let victim, let fileURL = try? resolveMediaURL(for: victim) {
            try? fileManager.removeItem(at: fileURL)
        }
        try writeAll(remaining)
    }

    /// 将索引中的 `storedMediaPath` 解析为当前沙盒下可访问的绝对 URL（含旧数据兼容）。
    func resolveMediaURL(for entry: TranscriptionHistoryEntry) throws -> URL? {
        let root = try docsRoot()
        return TranscriptionMediaPathResolver.resolve(
            storedMediaPath: entry.storedMediaPath,
            docsRoot: root,
            fileManager: fileManager
        )
    }

    private func writeAll(_ entries: [TranscriptionHistoryEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: try indexURL(), options: .atomic)
    }

    private func docsRoot() throws -> URL {
        if let rootOverride {
            return rootOverride
        }
        guard let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw TranscriptionHistoryStoreError.invalidDocumentsRoot
        }
        return dir
    }

    private func indexURL() throws -> URL {
        try docsRoot().appendingPathComponent(indexFileName)
    }

    private func mediaDirectoryURL() throws -> URL {
        let dir = try docsRoot().appendingPathComponent(mediaDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
