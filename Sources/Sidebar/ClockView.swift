import AppKit
import SwiftUI

/// Größe des Uhr-Bereichs oben an der Leiste.
enum ClockLayout {
    static let padding: CGFloat = 10
    static let searchHeight: CGFloat = 30
    static let gap: CGFloat = 4

    static func panelSize(_ s: SidebarSettings) -> CGSize {
        guard s.showClock || s.showSearch else { return .zero }
        let thickness = CGFloat(s.collapsedThickness)
        let clock = CGFloat(s.clockSize)
        let width = s.showClock ? max(thickness, clock + 2 * padding) : thickness
        var height: CGFloat = 0
        if s.showClock { height += clock + 2 * padding }
        if s.showSearch { height += searchHeight + (s.showClock ? 0 : padding * 2) }
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

/// Bereich mit analoger Uhr und Such-Knopf, der oben aus der Leiste heraussteht.
struct ClockPanelView: View {
    @ObservedObject var store: ConfigStore
    let actions: SidebarActions
    @Environment(\.colorScheme) private var scheme

    private var settings: SidebarSettings { store.config.settings }

    var body: some View {
        let palette = Palette.resolve(settings.colorTheme, scheme)
        let shape = EdgeShape.shape(for: settings.edge, radius: 16)
        VStack(spacing: 0) {
            if settings.showClock {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    AnalogClock(date: context.date, showSeconds: settings.clockShowSeconds, palette: palette)
                }
                .frame(width: CGFloat(settings.clockSize), height: CGFloat(settings.clockSize))
                .padding(ClockLayout.padding)
                .contentShape(Rectangle())
                .onTapGesture {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                }
                .help(Date().formatted(date: .complete, time: .omitted) + " – Klick öffnet den Kalender")
            }
            if settings.showSearch {
                SearchButton(compact: !settings.showClock || settings.clockSize < 80,
                             palette: palette, action: actions.openSearch)
                    .frame(height: ClockLayout.searchHeight)
                    .padding(.bottom, settings.showClock ? 6 : ClockLayout.padding)
                    .padding(.top, settings.showClock ? 0 : ClockLayout.padding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectBackground()
                (settings.gradient ? palette.gradientTop : palette.background).opacity(0.95)
            }
        )
        .clipShape(shape)
        .overlay(shape.stroke(palette.border, lineWidth: 1))
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
                    .font(.system(size: 12, weight: .semibold))
                if !compact {
                    Text("Suchen")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(palette.clockHands)
            .padding(.horizontal, compact ? 8 : 12)
            .frame(height: 24)
            .background(Capsule().fill(palette.clockFace.opacity(0.92)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Google-Suche oder Claude fragen")
    }
}

/// Gut lesbare analoge Uhr: helles Zifferblatt, kräftige Zeiger.
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

            func line(from: CGPoint, to: CGPoint, width: CGFloat, color: Color) {
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            // Zifferblatt
            let faceRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: faceRect), with: .color(palette.clockFace))
            context.stroke(Path(ellipseIn: faceRect.insetBy(dx: 0.5, dy: 0.5)),
                           with: .color(palette.clockHands.opacity(0.15)), lineWidth: 1)

            // Striche: Stunden kräftig, Minuten fein (nur bei größerer Uhr)
            for index in 0..<60 {
                let isHour = index % 5 == 0
                if !isHour && radius < 45 { continue }
                let isQuarter = index % 15 == 0
                let outer = radius * 0.92
                let inner = radius * (isQuarter ? 0.76 : isHour ? 0.82 : 0.88)
                let width = isQuarter ? radius * 0.06 : isHour ? radius * 0.035 : max(0.6, radius * 0.012)
                line(from: point(Double(index) / 60, inner), to: point(Double(index) / 60, outer),
                     width: width, color: palette.clockHands.opacity(isHour ? 0.85 : 0.45))
            }

            // Ziffern 12 · 3 · 6 · 9 ab mittlerer Größe
            if radius >= 34 {
                let font = Font.system(size: radius * 0.22, weight: .semibold, design: .rounded)
                for (label, fraction) in [("12", 0.0), ("3", 0.25), ("6", 0.5), ("9", 0.75)] {
                    context.draw(Text(label).font(font).foregroundColor(palette.clockHands),
                                 at: point(fraction, radius * 0.58))
                }
            }

            // Zeiger
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let seconds = Double(parts.second ?? 0)
            let minutes = Double(parts.minute ?? 0) + seconds / 60
            let hours = Double((parts.hour ?? 0) % 12) + minutes / 60

            line(from: point(hours / 12 + 0.5, radius * 0.1), to: point(hours / 12, radius * 0.5),
                 width: radius * 0.085, color: palette.clockHands)
            line(from: point(minutes / 60 + 0.5, radius * 0.1), to: point(minutes / 60, radius * 0.78),
                 width: radius * 0.055, color: palette.clockHands)
            if showSeconds {
                line(from: point(seconds / 60 + 0.5, radius * 0.16), to: point(seconds / 60, radius * 0.84),
                     width: max(1, radius * 0.022), color: Color(hex: 0xD9534F))
            }
            let dot = radius * 0.07
            context.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)),
                         with: .color(showSeconds ? Color(hex: 0xD9534F) : palette.clockHands))
        }
    }
}
