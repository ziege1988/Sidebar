import SwiftUI

/// Blase, die beim Darüberfahren vom Bildschirmrand aus um das Icon wächst –
/// oben und unten mit weich nach außen geschwungenen Kurven in den Rand auslaufend.
struct EdgeTab: Shape {
    let edge: ScreenEdge
    /// Länge der nach außen geschwungenen Ausläufe am Bildschirmrand
    var flare: CGFloat = 16
    /// Rundung zur Bildschirmmitte (nil = Halbkreis, so rund wie möglich)
    var radius: CGFloat? = nil

    func path(in rect: CGRect) -> Path {
        let along = edge.isVertical ? rect.height : rect.width
        let cross = edge.isVertical ? rect.width : rect.height

        func map(_ c: CGFloat, _ a: CGFloat) -> CGPoint {
            switch edge {
            case .left: return CGPoint(x: c, y: a)
            case .right: return CGPoint(x: rect.width - c, y: a)
            case .top: return CGPoint(x: a, y: c)
            case .bottom: return CGPoint(x: a, y: rect.height - c)
            }
        }

        let f = min(flare, along / 4)
        let top = f
        let bottom = along - f
        let r = min(radius ?? (bottom - top) / 2, (bottom - top) / 2, cross / 2)

        var path = Path()
        path.move(to: map(0, 0))
        // Auslauf oben: weich vom Rand in die Blase
        path.addArc(tangent1End: map(0, top), tangent2End: map(f, top), radius: f)
        path.addLine(to: map(cross - r, top))
        path.addArc(tangent1End: map(cross, top), tangent2End: map(cross, top + r), radius: r)
        path.addLine(to: map(cross, bottom - r))
        path.addArc(tangent1End: map(cross, bottom), tangent2End: map(cross - r, bottom), radius: r)
        path.addLine(to: map(f, bottom))
        // Auslauf unten
        path.addArc(tangent1End: map(0, bottom), tangent2End: map(0, along), radius: f)
        path.closeSubpath()
        return path
    }
}

/// Zeichnet die Blase an der Stelle des Elements unter der Maus.
struct HoverBubble: View {
    let edge: ScreenEdge
    /// Rahmen des Elements in Leisten-Koordinaten (`nil` = keine Blase)
    let cell: CGRect?
    let barThickness: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            if let cell {
                let flare: CGFloat = 16
                let along = (edge.isVertical ? cell.height : cell.width) + 2 * flare
                let cross = barThickness - 4
                let size = edge.isVertical ? CGSize(width: cross, height: along) : CGSize(width: along, height: cross)
                let center: CGPoint = {
                    switch edge {
                    case .left: return CGPoint(x: cross / 2, y: cell.midY)
                    case .right: return CGPoint(x: proxy.size.width - cross / 2, y: cell.midY)
                    case .top: return CGPoint(x: cell.midX, y: cross / 2)
                    case .bottom: return CGPoint(x: cell.midX, y: proxy.size.height - cross / 2)
                    }
                }()
                EdgeTab(edge: edge, flare: flare)
                    .fill(Color.white.opacity(scheme == .dark ? 0.16 : 0.42))
                    .overlay(
                        EdgeTab(edge: edge, flare: flare)
                            .stroke(Color.white.opacity(scheme == .dark ? 0.22 : 0.6), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                    .frame(width: size.width, height: size.height)
                    .position(center)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: cell)
        .allowsHitTesting(false)
    }
}
