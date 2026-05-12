import Foundation

actor StemSeparationStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private let indexFileName = "stem_separation_history.json"

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    /// Resolve a stored path to an absolute path.
    /// - If the path starts with "/" (absolute), use it directly (backward compatibility with old data).
    /// - If the path is relative, resolve it against `rootURL`.
    private func resolveStemPath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return rootURL.appendingPathComponent(path).path
    }

    func loadAll() async -> [StemSeparationResult] {
        let url = rootURL.appendingPathComponent(indexFileName)
        guard fileManager.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else {
            return []
        }
        let list = (try? JSONDecoder().decode([StemSeparationResult].self, from: data)) ?? []
        // Resolve relative paths to absolute paths so consumers can use them directly.
        let resolved = list.map { result in
            let resolvedStems = Dictionary(uniqueKeysWithValues: result.stems.map { (stem, path) in
                (stem, resolveStemPath(path))
            })
            return StemSeparationResult(
                id: result.id,
                fileName: result.fileName,
                customName: result.customName,
                durationMs: result.durationMs,
                sampleRate: result.sampleRate,
                createdAtMs: result.createdAtMs,
                stems: resolvedStems
            )
        }
        return resolved.sorted { $0.createdAtMs > $1.createdAtMs }
    }

    func save(_ result: StemSeparationResult) async throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var all = await loadAll().filter { $0.id != result.id }
        all.append(result)
        let data = try JSONEncoder().encode(all.sorted { $0.createdAtMs > $1.createdAtMs })
        try data.write(to: rootURL.appendingPathComponent(indexFileName), options: .atomic)
    }

    func remove(id: String) async throws {
        var all = await loadAll()
        guard let victim = all.first(where: { $0.id == id }) else { return }
        all.removeAll { $0.id == id }
        // Resolve paths before attempting deletion (handles both relative and absolute paths).
        for path in victim.stems.values {
            let resolvedPath = resolveStemPath(path)
            try? fileManager.removeItem(atPath: resolvedPath)
        }
        let rootPath = rootURL.standardizedFileURL.path
        let parentDirs = Set(
            victim.stems.values
                .map { resolveStemPath($0) }
                .map { URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL }
                .filter { $0.path != rootPath }
        )
        for dir in parentDirs {
            try? fileManager.removeItem(at: dir)
        }
        let data = try JSONEncoder().encode(all)
        try data.write(to: rootURL.appendingPathComponent(indexFileName), options: .atomic)
    }

    func rename(id: String, customName: String) async throws {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var all = await loadAll()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return }
        let old = all[idx]
        // Re-relative-ize paths before saving so they stay portable across container changes.
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let portableStems = Dictionary(uniqueKeysWithValues: old.stems.map { (stem, path) in
            if path.hasPrefix(rootPath) {
                return (stem, String(path.dropFirst(rootPath.count)))
            }
            return (stem, path)
        })
        all[idx] = StemSeparationResult(
            id: old.id,
            fileName: old.fileName,
            customName: trimmed,
            durationMs: old.durationMs,
            sampleRate: old.sampleRate,
            createdAtMs: old.createdAtMs,
            stems: portableStems
        )
        let data = try JSONEncoder().encode(all.sorted { $0.createdAtMs > $1.createdAtMs })
        try data.write(to: rootURL.appendingPathComponent(indexFileName), options: .atomic)
    }
}
