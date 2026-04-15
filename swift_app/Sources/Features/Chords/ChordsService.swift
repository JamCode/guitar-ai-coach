import Core

public struct ChordsService {
    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func healthMessage() -> String {
        "Chords module ready (\(environment.apiBaseURL))"
    }
}

