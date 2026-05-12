import Foundation

protocol AdaptiveEarTrainingStoring {
    func loadState() async -> AdaptiveEarAbilityState
    func saveState(_ state: AdaptiveEarAbilityState) async
    func loadAttempts() async -> [AdaptiveEarAttemptRecord]
    func appendAttempt(_ record: AdaptiveEarAttemptRecord) async
    func reset() async
}

actor UserDefaultsAdaptiveEarTrainingStore: AdaptiveEarTrainingStoring {
    private let stateKey = "adaptive_ear_ability_state_v1"
    private let attemptsKey = "adaptive_ear_attempts_v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadState() async -> AdaptiveEarAbilityState {
        guard let data = defaults.data(forKey: stateKey) else {
            return .initial
        }
        return (try? JSONDecoder().decode(AdaptiveEarAbilityState.self, from: data)) ?? .initial
    }

    func saveState(_ state: AdaptiveEarAbilityState) async {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }

    func loadAttempts() async -> [AdaptiveEarAttemptRecord] {
        guard let data = defaults.data(forKey: attemptsKey) else {
            return []
        }
        let decoded = (try? JSONDecoder().decode([AdaptiveEarAttemptRecord].self, from: data)) ?? []
        return decoded.sorted { $0.answeredAt < $1.answeredAt }
    }

    func appendAttempt(_ record: AdaptiveEarAttemptRecord) async {
        var all = await loadAttempts()
        all.append(record)
        if all.count > 2_000 {
            all = Array(all.suffix(2_000))
        }
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: attemptsKey)
    }

    func reset() async {
        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: attemptsKey)
    }
}
