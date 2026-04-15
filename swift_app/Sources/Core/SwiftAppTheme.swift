import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum SwiftAppTheme {
    // Keep aligned with Flutter `AppTheme` colors.
    public enum Palette {
        // Light
        public static let bgLight = Color(hex: 0xFFF7F8FA)
        public static let surfaceLight = Color(hex: 0xFFFFFFFF)
        public static let surfaceSoftLight = Color(hex: 0xFFF3F4F7)
        public static let textLight = Color(hex: 0xFF2A2633)
        public static let mutedLight = Color(hex: 0xFF71717A)
        public static let lineLight = Color(hex: 0xFFEBECEF)
        public static let brandLight = Color(hex: 0xFFFF2442)
        public static let brandSoftLight = Color(hex: 0xFFFFE9ED)
        public static let successLight = Color(hex: 0xFF22A06B)

        // Dark
        public static let bgDark = Color(hex: 0xFF111216)
        public static let surfaceDark = Color(hex: 0xFF1A1B20)
        public static let surfaceSoftDark = Color(hex: 0xFF14151A)
        public static let textDark = Color(hex: 0xFFD8DCE6)
        public static let mutedDark = Color(hex: 0xFF9CA3AF)
        public static let lineDark = Color(hex: 0xFF2A2C34)
        public static let brandDark = Color(hex: 0xFFFF4D67)
        public static let brandSoftDark = Color(hex: 0xFF3A1E26)
    }

    public static var bg: Color { dynamic(Palette.bgLight, Palette.bgDark) }
    public static var surface: Color { dynamic(Palette.surfaceLight, Palette.surfaceDark) }
    public static var surfaceSoft: Color { dynamic(Palette.surfaceSoftLight, Palette.surfaceSoftDark) }
    public static var text: Color { dynamic(Palette.textLight, Palette.textDark) }
    public static var muted: Color { dynamic(Palette.mutedLight, Palette.mutedDark) }
    public static var line: Color { dynamic(Palette.lineLight, Palette.lineDark) }
    public static var brand: Color { dynamic(Palette.brandLight, Palette.brandDark) }
    public static var brandSoft: Color { dynamic(Palette.brandSoftLight, Palette.brandSoftDark) }

    public static let cardRadius: CGFloat = 14
    public static let pagePadding: CGFloat = 16
}

public extension View {
    func appPageBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(SwiftAppTheme.bg.ignoresSafeArea())
            .tint(SwiftAppTheme.brand)
    }

    func appCard() -> some View {
        self
            .padding(14)
            .background(SwiftAppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SwiftAppTheme.cardRadius, style: .continuous)
                    .stroke(SwiftAppTheme.line, lineWidth: 1)
            )
    }
}

public extension Color {
    init(hex: UInt32) {
        let a = Double((hex >> 24) & 0xFF) / 255.0
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

#if canImport(UIKit)
private extension SwiftAppTheme {
    static func platformDynamicColor(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
#elseif canImport(AppKit)
private extension SwiftAppTheme {
    static func platformDynamicColor(light: Color, dark: Color) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }
}
#else
private extension SwiftAppTheme {
    static func platformDynamicColor(light: Color, dark: Color) -> Color { light }
}
#endif

public extension SwiftAppTheme {
    static func dynamic(_ light: Color, _ dark: Color) -> Color {
        platformDynamicColor(light: light, dark: dark)
    }
}
