import AppKit
import SwiftUI

/// Glas-Effekt: Unschärfe des Hintergrunds, darüber die Farbe der Sidebar.
/// Auch bei voller Stärke bleibt die Farbe gut erkennbar (mindestens 40 % deckend).
enum Glass {
    /// Deckkraft der Farbschicht für eine Glas-Stärke (0 … 1)
    static func tintOpacity(_ intensity: Double) -> Double {
        1 - 0.6 * min(max(intensity, 0), 1)
    }

    /// Helligkeit des Glasrands
    static func rimStrength(_ intensity: Double) -> Double {
        intensity <= 0 ? 0 : 0.35 + 0.65 * min(intensity, 1)
    }
}

/// Hintergrund mit Glas: unscharfer Schreibtisch + Farbverlauf der Sidebar.
struct GlassFill: View {
    let fill: LinearGradient
    let intensity: Double

    var body: some View {
        ZStack {
            if intensity > 0 {
                VisualEffectBackground()
            }
            Rectangle()
                .fill(fill)
                .opacity(Glass.tintOpacity(intensity))
            if intensity > 0 {
                // leichter Schimmer von oben, wie eine Glasscheibe
                LinearGradient(colors: [Color.white.opacity(0.14 * intensity), .clear],
                               startPoint: .top, endPoint: .center)
            }
        }
    }
}

/// Heller Glasrand entlang der Kanten.
struct GlassRim<S: Shape>: View {
    let shape: S
    let intensity: Double

    var body: some View {
        let k = Glass.rimStrength(intensity)
        shape
            .stroke(LinearGradient(colors: [Color.white.opacity(0.85 * k), Color.white.opacity(0.25 * k)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.2)
            .opacity(k > 0 ? 1 : 0)
            .allowsHitTesting(false)
    }
}

/// Blendet den Glasrand der Uhr dort aus, wo sie in die Leiste übergeht (keine Trennlinie).
struct ClockJunctionMask: View {
    let edge: ScreenEdge
    let thickness: CGFloat

    var body: some View {
        ZStack(alignment: alignment) {
            Rectangle()
            Rectangle()
                .frame(width: edge.isVertical ? thickness : 4, height: edge.isVertical ? 4 : thickness)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }

    private var alignment: Alignment {
        switch edge {
        case .left: return .bottomLeading
        case .right: return .bottomTrailing
        case .top: return .topTrailing
        case .bottom: return .bottomTrailing
        }
    }
}
