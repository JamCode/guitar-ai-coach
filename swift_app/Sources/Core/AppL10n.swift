import Foundation

/// Resolves `String` values from the **host application** `Localizable` String Catalog.
/// The catalog files must be compiled into the main app target (`Bundle.main`), not into individual frameworks.
public enum AppL10n {
    @inline(__always)
    public static func t(_ key: String) -> String {
        String(
            localized: String.LocalizationValue(key),
            bundle: .main,
            locale: .autoupdatingCurrent
        )
    }
}
