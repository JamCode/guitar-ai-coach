import Foundation

#if os(iOS)
import AVFoundation
import AVFAudio

/// 统一麦克风授权（避免在 `MainActor` 上阻塞等待权限回调）。
public enum MicrophoneRecordingPermission {
    public static func ensureGranted() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw NSError(
                domain: "Microphone",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "需要麦克风权限才能拾音"]
            )
        case .undetermined:
            break
        @unknown default:
            break
        }
        let granted = await AVAudioApplication.requestRecordPermission()
        if !granted {
            throw NSError(
                domain: "Microphone",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "需要麦克风权限才能拾音"]
            )
        }
    }
}
#else
/// 非 iOS 平台无系统麦克风授权流程。
public enum MicrophoneRecordingPermission {
    public static func ensureGranted() async throws {}
}
#endif
