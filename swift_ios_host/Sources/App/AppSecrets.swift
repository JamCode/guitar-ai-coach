import Foundation

enum AppSecrets {
    static var chordOnnxAppToken: String {
        Bundle.main.object(forInfoDictionaryKey: "CHORD_ONNX_APP_TOKEN") as? String ?? ""
    }
}
