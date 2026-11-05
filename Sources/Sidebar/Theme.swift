import AppKit
import SwiftUI

/// Farbwelt der Sidebar. Jede gibt es hell (Pastell) und dunkel (Graphit mit Pastell-Akzent).
enum ColorTheme: String, Codable, CaseIterable, Identifiable {
    case sage, lavender, rose, sky, sand, mint, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sage: return "Salbei"
        case .lavender: return "Lavendel"
        case .rose: return "Puder-Rosé"
        case .sky: return "Himmelblau"
        case .sand: return "Sand"
        case .mint: return "Mint"
        case .graphite: return "Graphit"
        }
    }

    /// Grundtöne: heller Hintergrund, kräftiger Akzent (hell) und Pastell-Akzent (dunkel)
    fileprivate var tones: (light: UInt32, lightTop: UInt32, accent: UInt32, darkAccent: UInt32, text: UInt32) {
        switch self {
        case .sage:     return (0xD8E3D2, 0xA9BFA1, 0x6F8F67, 0xB3CBAD, 0x2E3A2C)
        case .lavender: return (0xE2DDF0, 0xB9AFD6, 0x7A6BA8, 0xC4B9E6, 0x312B45)
        case .rose:     return (0xF1DEDF, 0xD9B1B5, 0xA8646C, 0xE6B9BE, 0x45292D)
        case .sky:      return (0xD9E6F0, 0xA9C3D9, 0x5B83A6, 0xAFCBE3, 0x23323F)
        case .sand:     return (0xEEE6D8, 0xD3C3A6, 0x9A7F55, 0xDCC9A6, 0x3B3122)
        case .mint:     return (0xD6ECE6, 0xA3CFC3, 0x4E9384, 0xA9D9CC, 0x1F3A34)
        case .graphite: return (0xE3E4E6, 0xB9BCC2, 0x5E636B, 0xC9CCD2, 0x26282B)
        }
    }
}

/// Farbpalette der Sidebar.
struct Palette {
    let background: Color
    /// Verlauf: oben dunkler, unten heller (hebt die Uhr ab)
    let gradientTop: Color
    let gradientBottom: Color
    let surface: Color
    let hover: Color
    let accent: Color
    let accentSoft: Color
    let onAccent: Color
    let text: Color
    let secondary: Color
    let border: Color
    let dashed: Color
    /// Zifferblatt der Uhr
    let clockFace: Color
    let clockHands: Color

    static func resolve(_ theme: ColorTheme, _ scheme: ColorScheme) -> Palette {
        let t = theme.tones
        if scheme == .dark {
            let accent = Color(hex: t.darkAccent)
            return Palette(
                background: Color(hex: 0x2B2D31),
                gradientTop: Color(hex: 0x1C1D20),
                gradientBottom: Color(hex: 0x383B41),
                surface: Color(hex: 0x35383D),
                hover: Color.white.opacity(0.08),
                accent: accent,
                accentSoft: accent.opacity(0.16),
                onAccent: Color(hex: 0x23251F),
                text: Color(hex: 0xE8EAE5),
                secondary: Color(hex: 0xA2A89E),
                border: Color.white.opacity(0.09),
                dashed: accent.opacity(0.45),
                clockFace: Color(hex: 0xF2F3EF),
                clockHands: Color(hex: 0x1E1F22)
            )
        } else {
            let accent = Color(hex: t.accent)
            let text = Color(hex: t.text)
            return Palette(
                background: Color(hex: t.light),
                gradientTop: Color(hex: t.lightTop),
                gradientBottom: Color(hex: t.light).opacity(0.96),
                surface: Color.white.opacity(0.6),
                hover: accent.opacity(0.16),
                accent: accent,
                accentSoft: accent.opacity(0.18),
                onAccent: Color(hex: 0xF7F8F5),
                text: text,
                secondary: text.opacity(0.68),
                border: text.opacity(0.10),
                dashed: accent.opacity(0.55),
                clockFace: Color(hex: 0xFBFBF8),
                clockHands: text
            )
        }
    }

    /// Hintergrund der Leiste: Verlauf oder einfarbig.
    func backgroundFill(gradient: Bool) -> LinearGradient {
        LinearGradient(colors: gradient ? [gradientTop, gradientBottom] : [background, background],
                       startPoint: .top, endPoint: .bottom)
    }
}

private struct ColorThemeKey: EnvironmentKey {
    static let defaultValue: ColorTheme = .sage
}

extension EnvironmentValues {
    var colorTheme: ColorTheme {
        get { self[ColorThemeKey.self] }
        set { self[ColorThemeKey.self] = newValue }
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
