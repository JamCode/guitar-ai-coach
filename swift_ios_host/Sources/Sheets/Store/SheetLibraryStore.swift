import Foundation

enum SheetLibraryError: Error, LocalizedError {
    case emptySources
    case invalidDocumentsRoot
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .emptySources:
            return "sources must not be empty"
        case .invalidDocumentsRoot:
            return "无法访问本地文档目录"
        case .encodingFailed:
            return "编码失败"
        }
    }
}

actor SheetLibraryStore {
    private let indexFileName = "sheets_index.json"
    private let sheetsSubdir = "sheets"
    private let rootOverride: URL?
    private let fileManager: FileManager

    init(rootOverride: URL? = nil, fileManager: FileManager = .default) {
        self.rootOverride = rootOverride
        self.fileManager = fileManager
    }

    func loadAll() async -> [SheetEntry] {
        guard let indexURL = try? indexFileURL() else { return [] }
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: indexURL)
            let any = try JSONSerialization.jsonObject(with: data, options: [])
            guard let list = any as? [Any] else { return [] }
            var entries = list.compactMap(SheetEntry.fromJSON)
            entries.sort { $0.addedAtMs > $1.addedAtMs }
            return entries
        } catch {
            return []
        }
    }

    func importSheetPages(sources: [URL], displayName: String) async throws -> SheetEntry {
        if sources.isEmpty { throw SheetLibraryError.emptySources }
        let dir = try sheetsDirURL()
        let id = UUID().uuidString
        var names: [String] = []
        for (idx, src) in sources.enumerated() {
            var ext = src.pathExtension.lowercased()
            if ext.isEmpty { ext = "jpg" }
            let filename = "\(id)_\(idx).\(ext)"
            let dst = dir.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: dst.path) {
                try fileManager.removeItem(at: dst)
            }
            try fileManager.copyItem(at: src, to: dst)
            names.append(filename)
        }

        let entry = SheetEntry(
            id: id,
            displayName: displayName,
            storedFileNames: names,
            addedAtMs: Int(Date().timeIntervalSince1970 * 1000),
            serverPageCount: nil,
            parseStatus: SheetParseStatus.rawOnly.rawValue,
            parsedUpdatedAtMs: nil
        )
        var all = await loadAll()
        all.append(entry)
        try writeAll(entries: all)
        return entry
    }

    func remove(id: String) async throws {
        let all = await loadAll()
        var keep: [SheetEntry] = []
        var victim: SheetEntry?
        for e in all {
            if e.id == id {
                victim = e
            } else {
                keep.append(e)
            }
        }
        if let victim {
            let dir = try sheetsDirURL()
            for name in victim.storedFileNames {
                let file = dir.appendingPathComponent(name)
                if fileManager.fileExists(atPath: file.path) {
                    try? fileManager.removeItem(at: file)
                }
            }
            let parsed = try parsedFileURL(sheetId: victim.id)
            if fileManager.fileExists(atPath: parsed.path) {
                try? fileManager.removeItem(at: parsed)
            }
        }
        try writeAll(entries: keep)
    }

    func loadParsed(sheetId: String) async -> SheetParsedData? {
        guard let f = try? parsedFileURL(sheetId: sheetId) else { return nil }
        guard fileManager.fileExists(atPath: f.path) else { return nil }
        do {
            let data = try Data(contentsOf: f)
            let any = try JSONSerialization.jsonObject(with: data, options: [])
            return SheetParsedData.fromJSON(any)
        } catch {
            return nil
        }
    }

    func saveParsed(_ parsed: SheetParsedData) async throws {
        let f = try parsedFileURL(sheetId: parsed.sheetId)
        let raw = try parsed.toJSONString()
        try raw.write(to: f, atomically: true, encoding: .utf8)

        let all = await loadAll()
        let updated = all.map { e -> SheetEntry in
            guard e.id == parsed.sheetId else { return e }
            var copy = e
            copy.parseStatus = parsed.parseStatus.rawValue
            copy.parsedUpdatedAtMs = parsed.updatedAtMs
            return copy
        }
        try writeAll(entries: updated)
    }

    func resolveStoredFiles(_ entry: SheetEntry) async throws -> [URL] {
        let dir = try sheetsDirURL()
        return entry.storedFileNames
            .map { dir.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    func resolveFirstStoredFile(_ entry: SheetEntry) async throws -> URL? {
        let files = try await resolveStoredFiles(entry)
        return files.first
    }

    private func writeAll(entries: [SheetEntry]) throws {
        let arr = entries.map { $0.toJSON() }
        let data = try JSONSerialization.data(withJSONObject: arr, options: [])
        guard let raw = String(data: data, encoding: .utf8) else {
            throw SheetLibraryError.encodingFailed
        }
        try raw.write(to: try indexFileURL(), atomically: true, encoding: .utf8)
    }

    private func docsRoot() throws -> URL {
        if let rootOverride { return rootOverride }
        guard let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw SheetLibraryError.invalidDocumentsRoot
        }
        return dir
    }

    private func indexFileURL() throws -> URL {
        try docsRoot().appendingPathComponent(indexFileName)
    }

    private func sheetsDirURL() throws -> URL {
        let dir = try docsRoot().appendingPathComponent(sheetsSubdir, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func parsedFileURL(sheetId: String) throws -> URL {
        try sheetsDirURL().appendingPathComponent("\(sheetId)_parsed.json")
    }
}
