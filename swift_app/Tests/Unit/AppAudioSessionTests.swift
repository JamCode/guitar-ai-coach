import XCTest
@testable import Core

#if os(iOS)
import AVFoundation
import Metronome

/// 回归：多路音频各自 `setCategory` 或先读 `inputFormat` 再配会话，可能导致 -10851（`kAudioUnitErr_InvalidPropertyValue`）。
/// 用统一 `AppAudioSession` + 典型引擎启动作烟测，防止后续再拆散配置。
@available(iOS 17, *)
final class AppAudioSessionTests: XCTestCase {
    func testConfigureShared_doesNotThrow() throws {
        try AppAudioSession.configureSharedForPlaybackAndRecording()
    }

    func testConfigureShared_isIdempotent() throws {
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        try AppAudioSession.configureSharedForPlaybackAndRecording()
    }

    func testConfigureShared_sessionMatchesContract() throws {
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .playAndRecord)
        XCTAssertEqual(session.mode, .default)
        let opts = session.categoryOptions
        XCTAssertTrue(opts.contains(.defaultToSpeaker))
        XCTAssertTrue(opts.contains(.mixWithOthers))
        XCTAssertTrue(opts.contains(.allowBluetoothA2DP))
        XCTAssertTrue(opts.contains(.allowBluetoothHFP))
    }

    /// 在统一会话后启动裸 `AVAudioEngine`，可尽早暴露 I/O 图与 -10851 不兼容的会话状态。
    func testMinimalAVAudioEngineStartsAfterSharedSession() throws {
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        let engine = AVAudioEngine()
        engine.prepare()
        try engine.start()
        engine.stop()
    }

    func testAudioEngineServiceStartsAfterSharedSession() throws {
        guard GuitarSoundBank.steelStringSF2URL != nil else {
            throw XCTSkip("无 SF2 时跳过，避免误报为会话问题。")
        }
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        let audio = AudioEngineService()
        try audio.start()
        audio.stop()
    }

    /// 与真实节拍器同路径：先 `AppAudioSession` 再 `MetronomeEngine.start`。
    func testMetronomeEngineStartsAfterSharedSession() throws {
        try AppAudioSession.configureSharedForPlaybackAndRecording()
        let metronome = MetronomeEngine()
        try metronome.start(bpm: 120, beatsPerMeasure: 4, volume: 0.5, sound: .click)
        metronome.stop()
    }
}

#else

/// 在 iOS 模拟器/设备上由 `GuitarAICoachUnitTests` 跑完整用例；`swift test` 在 macOS 上无 `AVAudioSession`。
@available(iOS 17, *)
final class AppAudioSessionTests: XCTestCase {
    func test_iOSHostOnly() throws {
        throw XCTSkip("AppAudioSession 与 AVAudioSession 契约需 iOS 环境（在 macOS swift test 中跳过）。")
    }
}

#endif
