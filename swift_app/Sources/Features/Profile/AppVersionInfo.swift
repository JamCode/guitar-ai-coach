import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct AppVersionInfo: Sendable {
    public let version: String
    public let buildNumber: String
    public let releaseChannel: String
    public let platformLabel: String

    public var displayVersion: String { "v\(version) (\(buildNumber))" }
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
        UIPasteboard.general.string = "AI吉他 \(info.displayVersion) / \(info.releaseChannel) / \(info.platformLabel)"
#endif
    }
}
