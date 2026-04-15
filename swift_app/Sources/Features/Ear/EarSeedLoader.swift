import Foundation

public enum EarSeedLoaderError: Error, LocalizedError {
    case seedFileNotFound
    case invalidDocument

    public var errorDescription: String? {
        switch self {
        case .seedFileNotFound:
            return "ear_seed_v1.json not found"
        case .invalidDocument:
            return "ear seed banks missing or empty"
        }
    }
}

public actor EarSeedLoader {
    public static let shared = EarSeedLoader()
    private var cached: EarSeedDocument?

    public init() {}

    public func load() async throws -> EarSeedDocument {
        if let cached {
            return cached
        }
        let data = try loadRawData()
        let decoder = JSONDecoder()
        let doc = try decoder.decode(EarSeedDocument.self, from: data)
        if doc.bankA.isEmpty && doc.bankB.isEmpty {
            throw EarSeedLoaderError.invalidDocument
        }
        cached = doc
        return doc
    }

    public func clearCacheForTest() {
        cached = nil
    }

    private func loadRawData() throws -> Data {
        if let bundleURL = Bundle.module.url(forResource: "ear_seed_v1", withExtension: "json") {
            return try Data(contentsOf: bundleURL)
        }
        throw EarSeedLoaderError.seedFileNotFound
    }
}
