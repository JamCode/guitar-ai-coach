public struct AppEnvironment {
    public let apiBaseURL: String

    public init(apiBaseURL: String = "http://localhost:18080/api") {
        self.apiBaseURL = apiBaseURL
    }
}

