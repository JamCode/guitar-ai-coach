import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct AppVersionInfo: Sendable {
    public let version: String
    public let buildNumber: String
    public let releaseChannel: String
    public let platformLabel: String

    /// 仅用户可见的营销版本号（`CFBundleShortVersionString`），不含 build。
    public var displayVersion: String { version }
}

public enum AppVersionInfoLoader {
    /// Read app version from bundle and provide safe fallback.
    public static func load(bundle: Bundle = .main) -> AppVersionInfo {
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
#if DEBUG
        let channel = "Debug"
#else
        let channel = "Release"
#endif
        return AppVersionInfo(
            version: version,
            buildNumber: buildNumber,
            releaseChannel: channel,
            platformLabel: "iOS"
        )
    }

    public static func copySummary(_ info: AppVersionInfo) {
#if canImport(UIKit)
        UIPasteboard.general.string = "玩乐吉他 \(info.version) (\(info.buildNumber)) / \(info.releaseChannel) / \(info.platformLabel)"
#endif
    }
}
