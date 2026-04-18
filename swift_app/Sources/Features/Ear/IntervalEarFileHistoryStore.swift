import Foundation

/// 将 `IntervalEarAttemptRecord` 追加写入 Application Support 下 JSON 数组文件。
public actor IntervalEarFileHistoryStore: IntervalEarHistoryStoring {
    public static let shared = IntervalEarFileHistoryStore()

    /// 防止文件无限膨胀；超出时丢弃最旧记录。
    public static let defaultMaxRecords = 50_000

    private let fileURL: URL
    private let maxRecords: Int
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(fileURL: URL? = nil, maxRecords: Int = 50_000) {
        self.fileURL = fileURL ?? Self.defaultPersistenceURL()
        self.maxRecords = max(100, maxRecords)
    }

    public func appendAttempt(_ record: IntervalEarAttemptRecord) async {
        var list = (try? loadFromDisk()) ?? []
        list.append(record)
        if list.count > maxRecords {
            list = Array(list.suffix(maxRecords))
        }
        try? saveToDisk(list)
    }

    /// 调试用：读取当前文件内全部记录。
    public func loadAllAttempts() async -> [IntervalEarAttemptRecord] {
        (try? loadFromDisk()) ?? []
    }

    private nonisolated static func defaultPersistenceURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("GuitarAICoach", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("interval_ear_attempts.json", isDirectory: false)
    }

    private func loadFromDisk() throws -> [IntervalEarAttemptRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([IntervalEarAttemptRecord].self, from: data)
    }

    private func saveToDisk(_ records: [IntervalEarAttemptRecord]) throws {
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: [.atomic])
    }
}
