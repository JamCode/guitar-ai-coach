import Foundation

protocol RecommendationHistoryStore {
    func append(_ record: RecommendationHistoryRecord) async
    func loadRecent(now: Date, days: Int) async -> [RecommendationHistoryRecord]
}

actor UserDefaultsRecommendationHistoryStore: RecommendationHistoryStore {
    private let key = "recommendation_history_v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func append(_ record: RecommendationHistoryRecord) async {
        var all = loadAll()
        all.append(record)
        defaults.set(encode(all), forKey: key)
    }

    func loadRecent(now: Date, days: Int = 7) async -> [RecommendationHistoryRecord] {
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: now) ?? now
        return loadAll()
            .filter { $0.occurredAt >= cutoff }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private func loadAll() -> [RecommendationHistoryRecord] {
        let raw = defaults.string(forKey: key) ?? ""
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RecommendationHistoryRecord].self, from: data)) ?? []
    }

    private func encode(_ records: [RecommendationHistoryRecord]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
