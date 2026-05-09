import Foundation

actor StemSeparationStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private let indexFileName = "stem_separation_history.json"

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func loadAll() async -> [StemSeparationResult] {
        let url = rootURL.appendingPathComponent(indexFileName)
        guard fileManager.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else {
            return []
        }
        let list = (try? JSONDecoder().decode([StemSeparationResult].self, from: data)) ?? []
        return list.sorted { $0.createdAtMs > $1.createdAtMs }
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
        for path in victim.stems.values {
            try? fileManager.removeItem(atPath: path)
        }
        let rootPath = rootURL.standardizedFileURL.path
        let parentDirs = Set(
            victim.stems.values
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
        all[idx] = StemSeparationResult(
            id: old.id,
            fileName: old.fileName,
            customName: trimmed,
            durationMs: old.durationMs,
            sampleRate: old.sampleRate,
            createdAtMs: old.createdAtMs,
            stems: old.stems
        )
        let data = try JSONEncoder().encode(all.sorted { $0.createdAtMs > $1.createdAtMs })
        try data.write(to: rootURL.appendingPathComponent(indexFileName), options: .atomic)
    }
}
