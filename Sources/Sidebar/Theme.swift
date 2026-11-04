import AppKit
import SwiftUI

/// Farbpalette der Sidebar.
/// Hell: Pastell-Salbeigrün · Dunkel: Pastell-Graphit mit Salbei-Akzent.
struct Palette {
    let background: Color
    let surface: Color
    let hover: Color
    let accent: Color
    let accentSoft: Color
    let onAccent: Color
    let text: Color
    let secondary: Color
    let border: Color
    let dashed: Color

    static let sageLight = Palette(
        background: Color(hex: 0xD8E3D2),
        surface: Color(hex: 0xEAF0E6),
        hover: Color(hex: 0x6F8F67).opacity(0.16),
        accent: Color(hex: 0x6F8F67),
        accentSoft: Color(hex: 0x6F8F67).opacity(0.18),
        onAccent: Color(hex: 0xF4F7F2),
        text: Color(hex: 0x2E3A2C),
        secondary: Color(hex: 0x62715D),
        border: Color(hex: 0x2E3A2C).opacity(0.10),
        dashed: Color(hex: 0x6F8F67).opacity(0.55)
    )

    static let graphiteDark = Palette(
        background: Color(hex: 0x2B2D31),
        surface: Color(hex: 0x35383D),
        hover: Color.white.opacity(0.08),
        accent: Color(hex: 0xB3CBAD),
        accentSoft: Color(hex: 0xB3CBAD).opacity(0.16),
        onAccent: Color(hex: 0x23251F),
        text: Color(hex: 0xE8EAE5),
        secondary: Color(hex: 0xA2A89E),
        border: Color.white.opacity(0.09),
        dashed: Color(hex: 0xB3CBAD).opacity(0.45)
    )

    static func forScheme(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .graphiteDark : .sageLight
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension AppearanceMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
