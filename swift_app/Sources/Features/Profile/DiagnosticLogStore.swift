import Foundation

public actor DiagnosticLogStore {
    public static let shared = DiagnosticLogStore()

    private let subDirName = "diagnostics"
    private let fileName = "app_diagnostic.log"
    private var initialized = false
    private var logURL: URL?

    public init() {}

    public func ensureInitialized() async {
        guard !initialized else { return }
        initialized = true
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = base.appendingPathComponent(subDirName, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let path = dir.appendingPathComponent(fileName, isDirectory: false)
            if !FileManager.default.fileExists(atPath: path.path) {
                FileManager.default.createFile(atPath: path.path, contents: Data())
            }
            logURL = path
        } catch {
            logURL = nil
        }
    }

    public func fileURL() -> URL? { logURL }

    public func byteLength() async -> Int {
        guard let url = logURL else { return 0 }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    public func clear() async {
        guard let url = logURL else { return }
        try? Data().write(to: url, options: .atomic)
    }

    public func append(header: String, body: String) async {
        guard let url = logURL else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\n======== \(stamp) =========\n[\(header)]\n\(body)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: url) {
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
            try? fh.close()
        }
    }
}
