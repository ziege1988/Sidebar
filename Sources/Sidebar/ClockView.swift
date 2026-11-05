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
            ? LinearGradient(colors: [palette.gradientTop, palette.gradientColor(at: state.clockGradientEnd)],
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
        .background(fill)
        .clipShape(shape)
    }
}

/// Edle analoge Uhr: helles Zifferblatt in der Farbwelt, schwarze römische Ziffern,
/// filigrane goldene Zeiger, kein Rahmen.
struct AnalogClock: View {
    let date: Date
    let showSeconds: Bool
    let palette: Palette

    private static let romans = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            func point(_ fraction: Double, _ length: CGFloat) -> CGPoint {
                let angle = fraction * 2 * .pi
                return CGPoint(x: center.x + CGFloat(sin(angle)) * length,
                               y: center.y - CGFloat(cos(angle)) * length)
            }

            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }

            /// Schlanker, spitz zulaufender Zeiger (wie bei klassischen Uhren)
            func hand(_ fraction: Double, length: CGFloat, width: CGFloat, tail: CGFloat) {
                let angle = fraction * 2 * .pi
                let dir = CGPoint(x: CGFloat(sin(angle)), y: -CGFloat(cos(angle)))
                let normal = CGPoint(x: -dir.y, y: dir.x)
                let half = width / 2
                let tip = CGPoint(x: center.x + dir.x * length, y: center.y + dir.y * length)
                let back = CGPoint(x: center.x - dir.x * tail, y: center.y - dir.y * tail)
                let shoulder = CGPoint(x: center.x + dir.x * length * 0.18, y: center.y + dir.y * length * 0.18)
                var path = Path()
                path.move(to: back)
                path.addLine(to: CGPoint(x: shoulder.x + normal.x * half, y: shoulder.y + normal.y * half))
                path.addLine(to: tip)
                path.addLine(to: CGPoint(x: shoulder.x - normal.x * half, y: shoulder.y - normal.y * half))
                path.closeSubpath()
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [Palette.goldLight, Palette.gold, Palette.goldDark]),
                    startPoint: CGPoint(x: shoulder.x + normal.x * half, y: shoulder.y + normal.y * half),
                    endPoint: CGPoint(x: shoulder.x - normal.x * half, y: shoulder.y - normal.y * half)))
            }

            // Zifferblatt – ohne Rahmen
            context.fill(circle(radius), with: .color(palette.clockFace))

            // Feine Minutenstriche, Stunden als goldene Punkte
            for index in 0..<60 {
                let fraction = Double(index) / 60
                if index % 5 == 0 {
                    let dot = point(fraction, radius * 0.9)
                    let r = max(0.8, radius * 0.022)
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)),
                                 with: .color(Palette.gold))
                } else if radius >= 40 {
                    var path = Path()
                    path.move(to: point(fraction, radius * 0.88))
                    path.addLine(to: point(fraction, radius * 0.92))
                    context.stroke(path, with: .color(palette.clockNumerals.opacity(0.28)),
                                   lineWidth: max(0.4, radius * 0.008))
                }
            }

            // Schwarze römische Ziffern in Serifenschrift
            let allNumerals = radius >= 46
            if radius >= 28 {
                let fontSize = radius * (allNumerals ? 0.15 : 0.18)
                let font = Font.system(size: fontSize, weight: .regular, design: .serif)
                for hour in 0..<12 where allNumerals || hour % 3 == 0 {
                    context.draw(Text(Self.romans[hour]).font(font).foregroundColor(palette.clockNumerals),
                                 at: point(Double(hour) / 12, radius * (allNumerals ? 0.7 : 0.66)))
                }
            }

            // Filigrane goldene Zeiger
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let seconds = Double(parts.second ?? 0)
            let minutes = Double(parts.minute ?? 0) + seconds / 60
            let hours = Double((parts.hour ?? 0) % 12) + minutes / 60

            hand(hours / 12, length: radius * 0.5, width: max(2, radius * 0.06), tail: radius * 0.1)
            hand(minutes / 60, length: radius * 0.76, width: max(1.6, radius * 0.045), tail: radius * 0.12)
            if showSeconds {
                var path = Path()
                path.move(to: point(seconds / 60 + 0.5, radius * 0.18))
                path.addLine(to: point(seconds / 60, radius * 0.84))
                context.stroke(path, with: .color(Palette.gold),
                               style: StrokeStyle(lineWidth: max(0.6, radius * 0.012), lineCap: .round))
            }
            context.fill(circle(max(1.6, radius * 0.045)), with: .color(Palette.gold))
            context.fill(circle(max(0.6, radius * 0.018)), with: .color(Palette.goldDark))
        }
    }
}
