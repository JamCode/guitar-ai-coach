import Foundation

enum StemSeparationTaskState: String, Codable, Equatable {
    case pending
    case running
    case failed
}

struct StemSeparationPendingTask: Codable, Equatable, Identifiable {
    let id: String
    let customName: String
    let originalFileName: String
    let inputRelativePath: String
    let createdAtMs: Int
    let updatedAtMs: Int
    let state: StemSeparationTaskState
    let errorMessage: String?

    func withState(_ nextState: StemSeparationTaskState, errorMessage: String? = nil) -> StemSeparationPendingTask {
        StemSeparationPendingTask(
            id: id,
            customName: customName,
            originalFileName: originalFileName,
            inputRelativePath: inputRelativePath,
            createdAtMs: createdAtMs,
            updatedAtMs: Int(Date().timeIntervalSince1970 * 1000),
            state: nextState,
            errorMessage: errorMessage
        )
    }
}

actor StemSeparationTaskStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private let indexFileName = "stem_separation_tasks.json"

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func loadAll() async -> [StemSeparationPendingTask] {
        let url = rootURL.appendingPathComponent(indexFileName)
        guard fileManager.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else {
            return []
        }
        let list = (try? JSONDecoder().decode([StemSeparationPendingTask].self, from: data)) ?? []
        return list.sorted { $0.createdAtMs < $1.createdAtMs }
    }

    func load(id: String) async -> StemSeparationPendingTask? {
        await loadAll().first { $0.id == id }
    }

    func loadResumable() async -> [StemSeparationPendingTask] {
        await loadAll().filter { $0.state == .pending || $0.state == .running }
    }

    func createTask(from sourceURL: URL, customName: String, originalFileName: String) async throws -> StemSeparationPendingTask {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let taskDirectory = rootURL.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: taskDirectory, withIntermediateDirectories: true)

        let sourceExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let inputURL = taskDirectory.appendingPathComponent("input").appendingPathExtension(sourceExtension)
        if fileManager.fileExists(atPath: inputURL.path) {
            try fileManager.removeItem(at: inputURL)
        }
        try fileManager.copyItem(at: sourceURL, to: inputURL)

        let now = Int(Date().timeIntervalSince1970 * 1000)
        let task = StemSeparationPendingTask(
            id: id,
            customName: customName,
            originalFileName: originalFileName,
            inputRelativePath: "\(id)/\(inputURL.lastPathComponent)",
            createdAtMs: now,
            updatedAtMs: now,
            state: .pending,
            errorMessage: nil
        )
        var all = await loadAll().filter { $0.id != id }
        all.append(task)
        try writeAll(all)
        return task
    }

    func mark(id: String, state: StemSeparationTaskState, errorMessage: String? = nil) async throws {
        var all = await loadAll()
        guard let idx = all.firstIndex(where: { $0.id == id }) else { return }
        all[idx] = all[idx].withState(state, errorMessage: errorMessage)
        try writeAll(all)
    }

    func remove(id: String) async throws {
        let all = await loadAll()
        let remaining = all.filter { $0.id != id }
        try? fileManager.removeItem(at: rootURL.appendingPathComponent(id, isDirectory: true))
        try writeAll(remaining)
    }

    func inputURL(for task: StemSeparationPendingTask) -> URL {
        rootURL.appendingPathComponent(task.inputRelativePath)
    }

    private func writeAll(_ tasks: [StemSeparationPendingTask]) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(tasks.sorted { $0.createdAtMs < $1.createdAtMs })
        try data.write(to: rootURL.appendingPathComponent(indexFileName), options: .atomic)
    }
}
