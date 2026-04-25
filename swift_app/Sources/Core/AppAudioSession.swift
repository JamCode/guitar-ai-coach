import AVFoundation
import Foundation

/// 全应用共用的 `AVAudioSession` 配置。
///
/// 此前各模块对会话「各自为政」：`AudioEngineService` 使用 `.measurement`、
/// `MetronomeEngine` 使用 `.default` + `mixWithOthers`、
/// 调音器/视唱也各自 `setCategory`，在切换功能或冷启动时易导致
/// `AVAudioEngine` 在 `start` 时抛出 -10851（`kAudioUnitErr_InvalidPropertyValue`）。
/// 通过单一入口把类别/模式/选项对齐，并在 iOS 17+ 使用可取代已弃用 `allowBluetooth` 的蓝牙选项。
public enum AppAudioSession {
    public static func configureSharedForPlaybackAndRecording() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [
                .defaultToSpeaker,
                .mixWithOthers,
                .allowBluetoothA2DP,
                .allowBluetoothHFP
            ]
        )
        try session.setPreferredSampleRate(44_100)
        try session.setPreferredIOBufferDuration(0.0058)
        try session.setActive(true, options: [])
        #endif
    }
}
