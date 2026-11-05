import AppKit
import SwiftUI

/// Größe des Uhr-Bereichs oben an der Leiste.
enum ClockLayout {
    static let padding: CGFloat = 12
    static let searchHeight: CGFloat = 26
    /// Abstand zwischen Uhr und Such-Knopf
    static let searchGap: CGFloat = 14
    static let gap: CGFloat = 2

    static func panelSize(_ s: SidebarSettings) -> CGSize {
        guard s.showClock || s.showSearch else { return .zero }
        let thickness = CGFloat(s.collapsedThickness)
        let clock = CGFloat(s.clockSize)
        let width = s.showClock ? max(thickness, clock + 2 * padding) : thickness
        var height = 2 * padding
        if s.showClock { height += clock }
        if s.showSearch { height += searchHeight + (s.showClock ? searchGap : 0) }
        return CGSize(width: width, height: height)
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

/// Bereich mit analoger Uhr und Such-Knopf – optisch der obere Teil der Leiste.
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

        VStack(spacing: 0) {
            if settings.showClock {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    AnalogClock(date: context.date, showSeconds: settings.clockShowSeconds, palette: palette)
                }
                .frame(width: CGFloat(settings.clockSize), height: CGFloat(settings.clockSize))
                .contentShape(Circle())
                .onTapGesture {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                }
                .help(Date().formatted(date: .complete, time: .omitted) + " – Klick öffnet den Kalender")
            }
            if settings.showSearch {
                SearchButton(compact: !settings.showClock || settings.clockSize < 80,
                             palette: palette, action: actions.openSearch)
                    .frame(height: ClockLayout.searchHeight)
                    .padding(.top, settings.showClock ? ClockLayout.searchGap : 0)
            }
        }
        .padding(.vertical, ClockLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fill)
        .clipShape(shape)
        .environment(\.colorTheme, settings.colorTheme)
    }
}

struct SearchButton: View {
    let compact: Bool
    let palette: Palette
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.gold)
                if !compact {
                    Text("Suchen")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.clockNumerals)
                }
            }
            .padding(.horizontal, compact ? 8 : 12)
            .frame(height: 24)
            .background(Capsule().fill(palette.clockFace))
            .overlay(Capsule().stroke(Palette.gold.opacity(0.55), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Google Suche oder Claude fragen")
    }
}

/// Edle analoge Uhr: Zifferblatt in der Farbwelt, römische Ziffern, goldene Zeiger.
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

            func line(from: CGPoint, to: CGPoint, width: CGFloat, color: Color) {
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }

            // Zifferblatt mit goldenem Rand
            context.fill(circle(radius), with: .color(palette.clockFace))
            context.stroke(circle(radius - radius * 0.02), with: .color(Palette.gold),
                           lineWidth: max(1, radius * 0.04))

            // Minutenstriche fein, Stundenstriche in Gold
            for index in 0..<60 {
                let isHour = index % 5 == 0
                if !isHour && radius < 40 { continue }
                let outer = radius * 0.9
                let inner = radius * (isHour ? 0.82 : 0.86)
                line(from: point(Double(index) / 60, inner), to: point(Double(index) / 60, outer),
                     width: isHour ? max(1, radius * 0.03) : max(0.5, radius * 0.01),
                     color: isHour ? Palette.gold : palette.clockNumerals.opacity(0.35))
            }

            // Römische Ziffern: alle zwölf bei größerer Uhr, sonst XII · III · VI · IX
            let allNumerals = radius >= 46
            if radius >= 28 {
                let fontSize = radius * (allNumerals ? 0.17 : 0.2)
                let font = Font.system(size: fontSize, weight: .medium, design: .serif)
                for hour in 0..<12 where allNumerals || hour % 3 == 0 {
                    context.draw(Text(Self.romans[hour]).font(font).foregroundColor(palette.clockNumerals),
                                 at: point(Double(hour) / 12, radius * (allNumerals ? 0.66 : 0.62)))
                }
            }

            // Goldene Zeiger (mit dunklerer Kontur für Tiefe)
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let seconds = Double(parts.second ?? 0)
            let minutes = Double(parts.minute ?? 0) + seconds / 60
            let hours = Double((parts.hour ?? 0) % 12) + minutes / 60

            func hand(_ fraction: Double, length: CGFloat, width: CGFloat) {
                let start = point(fraction + 0.5, radius * 0.08)
                let end = point(fraction, length)
                line(from: start, to: end, width: width + max(1, radius * 0.02), color: Palette.goldDark)
                line(from: start, to: end, width: width, color: Palette.gold)
            }
            hand(hours / 12, length: radius * 0.47, width: radius * 0.07)
            hand(minutes / 60, length: radius * 0.72, width: radius * 0.045)
            if showSeconds {
                line(from: point(seconds / 60 + 0.5, radius * 0.16), to: point(seconds / 60, radius * 0.8),
                     width: max(0.8, radius * 0.016), color: Palette.gold)
            }
            context.fill(circle(radius * 0.075), with: .color(Palette.goldDark))
            context.fill(circle(radius * 0.05), with: .color(Palette.gold))
        }
    }
}
