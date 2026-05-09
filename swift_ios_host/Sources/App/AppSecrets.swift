import Foundation

enum AppSecrets {
    private static let fallbackChordOnnxAppToken = "wang"

    static var chordOnnxAppToken: String {
        let bundleValue = (Bundle.main.object(forInfoDictionaryKey: "CHORD_ONNX_APP_TOKEN") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !bundleValue.isEmpty {
            return bundleValue
        }
        return fallbackChordOnnxAppToken
    }
}
