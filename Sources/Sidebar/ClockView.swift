import AppKit
import SwiftUI

/// Größe des Uhr-Bereichs oben an der Leiste.
enum ClockLayout {
    static let padding: CGFloat = 12
    static let gap: CGFloat = 2

    static func panelSize(_ s: SidebarSettings) -> CGSize {
        guard s.showClock else { return .zero }
        let clock = CGFloat(s.clockSize)
        return CGSize(width: max(CGFloat(s.collapsedThickness), clock + 2 * padding),
                      height: clock + 2 * padding)
    }

    /// So viel Platz lässt die Leiste am Anfang frei (Uhr liegt darüber).
    static func inset(_ s: SidebarSettings) -> CGFloat {
        let size = panelSize(s)
        guard size != .zero else { return 0 }
        return (s.edge.isVertical ? size.height : size.width) + gap
    }
}

/// Form mit abgerundeten Ecken nur zur Bildschirmmitte hin.
enum EdgeShape {
    static func shape(for edge: ScreenEdge, radius r: CGFloat) -> UnevenRoundedRectangle {
        switch edge {
        case .left:
            return UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
        case .right:
            return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, style: .continuous)
        case .top:
            return UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .continuous)
        case .bottom:
            return UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r, style: .continuous)
        }
    }
}

/// Bereich mit der analogen Uhr – optisch der obere Teil der Leiste.
struct ClockPanelView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: SidebarState
    let actions: SidebarActions
    @Environment(\.colorScheme) private var scheme

    private var settings: SidebarSettings { store.config.settings }

    var body: some View {
        let palette = Palette.resolve(settings.colorTheme, scheme)
        let shape = EdgeShape.shape(for: settings.edge, radius: 16)
        // Verlauf genau so fortsetzen wie in der Leiste darunter → keine sichtbare Kante
        let fill: LinearGradient = settings.gradient
            ? LinearGradient(colors: [palette.gradientTop, palette.clockEndColor],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [palette.background, palette.background], startPoint: .top, endPoint: .bottom)

        TimelineView(.periodic(from: .now, by: 1)) { context in
            AnalogClock(date: context.date, showSeconds: settings.clockShowSeconds, palette: palette)
        }
        .frame(width: CGFloat(settings.clockSize), height: CGFloat(settings.clockSize))
        .contentShape(Circle())
        .onTapGesture {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
        .help(Date().formatted(date: .complete, time: .omitted) + " – Klick öffnet den Kalender")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassFill(fill: fill, intensity: settings.glassIntensity))
        .clipShape(shape)
        .overlay(
            GlassRim(shape: shape, intensity: settings.glassIntensity)
                .mask(ClockJunctionMask(edge: settings.edge, thickness: CGFloat(settings.collapsedThickness)))
        )
    }
}

/// Edle analoge Uhr (Minimal-Luxus): Sonnenschliff-Zifferblatt in der Farbwelt,
/// goldene Stab-Markierungen an jeder Stunde, facettierte Dauphine-Zeiger, kein Rahmen.
struct AnalogClock: View {
    let date: Date
    let showSeconds: Bool
    let palette: Palette

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            func point(_ fraction: Double, _ length: CGFloat) -> CGPoint {
                let angle = fraction * 2 * .pi
                return CGPoint(x: center.x + CGFloat(sin(angle)) * length,
                               y: center.y - CGFloat(cos(angle)) * length)
            }

            func circle(_ r: CGFloat, at c: CGPoint? = nil) -> Path {
                let m = c ?? center
                return Path(ellipseIn: CGRect(x: m.x - r, y: m.y - r, width: r * 2, height: r * 2))
            }

            func line(_ from: CGPoint, _ to: CGPoint, width: CGFloat, color: Color) {
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            /// Dauphine-Zeiger: spitz, in der Mitte geteilt in helles und dunkles Gold (wirkt geschliffen)
            func dauphine(_ fraction: Double, length: CGFloat, width: CGFloat) {
                let angle = fraction * 2 * .pi
                let dir = CGPoint(x: CGFloat(sin(angle)), y: -CGFloat(cos(angle)))
                let normal = CGPoint(x: -dir.y, y: dir.x)
                let base = CGPoint(x: center.x - dir.x * length * 0.08, y: center.y - dir.y * length * 0.08)
                let widest = CGPoint(x: center.x + dir.x * length * 0.3, y: center.y + dir.y * length * 0.3)
                let tip = CGPoint(x: center.x + dir.x * length, y: center.y + dir.y * length)
                let left = CGPoint(x: widest.x + normal.x * width / 2, y: widest.y + normal.y * width / 2)
                let right = CGPoint(x: widest.x - normal.x * width / 2, y: widest.y - normal.y * width / 2)
                var light = Path()
                light.move(to: base); light.addLine(to: left); light.addLine(to: tip); light.closeSubpath()
                var dark = Path()
                dark.move(to: base); dark.addLine(to: right); dark.addLine(to: tip); dark.closeSubpath()
                context.fill(light, with: .color(Palette.goldLight))
                context.fill(dark, with: .color(Palette.goldDark))
            }

            // Zifferblatt mit Sonnenschliff: Mitte heller, Rand etwas dunkler, feine Strahlen
            let faceHex = palette.clockFaceHex
            context.fill(circle(radius), with: .radialGradient(
                Gradient(colors: [Color(hex: Palette.mix(faceHex, 0xFFFFFF, 0.45)),
                                  Color(hex: faceHex),
                                  Color(hex: Palette.mix(faceHex, 0x000000, 0.08))]),
                center: CGPoint(x: center.x, y: center.y - radius * 0.16),
                startRadius: 0, endRadius: radius * 1.15))
            if radius >= 30 {
                for ray in 0..<120 {
                    line(point(Double(ray) / 120, radius * 0.1), point(Double(ray) / 120, radius * 0.97),
                         width: max(0.4, radius * 0.01),
                         color: Color.white.opacity(ray % 2 == 0 ? 0.09 : 0.035))
                }
            }

            // Feine Minutenpunkte
            if radius >= 36 {
                for minute in 0..<60 where minute % 5 != 0 {
                    context.fill(circle(max(0.35, radius * 0.008), at: point(Double(minute) / 60, radius * 0.92)),
                                 with: .color(Color.black.opacity(0.4)))
                }
            }

            // Goldene Stab-Markierungen an jeder Stunde
            for hour in 0..<12 {
                let fraction = Double(hour) / 12
                let inner = point(fraction, radius * 0.72)
                let outer = point(fraction, radius * 0.87)
                line(inner, outer, width: max(1.4, radius * 0.034), color: Palette.goldDark)
                line(inner, outer, width: max(0.8, radius * 0.022), color: Palette.gold)
            }

            // Zeiger
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let seconds = Double(parts.second ?? 0)
            let minutes = Double(parts.minute ?? 0) + seconds / 60
            let hours = Double((parts.hour ?? 0) % 12) + minutes / 60

            dauphine(hours / 12, length: radius * 0.52, width: max(3, radius * 0.085))
            dauphine(minutes / 60, length: radius * 0.8, width: max(2.4, radius * 0.065))
            if showSeconds {
                line(point(seconds / 60 + 0.5, radius * 0.2), point(seconds / 60, radius * 0.9),
                     width: max(0.6, radius * 0.01), color: Palette.gold)
            }
            context.fill(circle(max(1.6, radius * 0.045)), with: .color(Palette.goldDark))
            context.fill(circle(max(0.7, radius * 0.02)), with: .color(Palette.goldLight))
        }
    }
}
