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

/// Die analoge Uhr im oberen Teil der Sidebar (Klick öffnet den Kalender).
struct ClockFace: View {
    let settings: SidebarSettings
    let palette: Palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            AnalogClock(date: context.date, showSeconds: settings.clockShowSeconds,
                        showDate: settings.clockShowDate, palette: palette)
        }
        .frame(width: CGFloat(settings.clockSize), height: CGFloat(settings.clockSize))
        .contentShape(Circle())
        .onTapGesture {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
        .help(Date().formatted(date: .complete, time: .omitted) + " – Klick öffnet den Kalender")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Edle analoge Uhr (Minimal-Luxus): Sonnenschliff-Zifferblatt in der Farbwelt,
/// goldene Stab-Markierungen an jeder Stunde, facettierte Dauphine-Zeiger, kein Rahmen.
struct AnalogClock: View {
    let date: Date
    let showSeconds: Bool
    var showDate = false
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

            // Datum: drei kleine Klapptafeln (Tag / Monat / Jahr) zwischen Uhrmitte und unteren Stundenstrichen.
            // Alles wird direkt in diesen einen Zeichenkontext gemalt (kein verschachtelter Ebenen-Kontext) –
            // die Durchsichtigkeit steckt in den Farben.
            if showDate && radius >= 40 {
                let day = Calendar.current.dateComponents([.day, .month, .year], from: date)
                let texts = [String(format: "%02d", day.day ?? 1), String(format: "%02d", day.month ?? 1),
                             String(format: "%02d", (day.year ?? 2000) % 100)]
                let alpha = 0.78
                let h = radius * 0.18
                let w = h * 0.98
                let gap = h * 0.42
                let total = w * 3 + gap * 2
                let top = center.y + radius * 0.26
                let mid = top + h / 2
                var x = center.x - total / 2
                let font = Font.custom("AvenirNextCondensed-Regular", size: h * 0.66)
                let slashFont = Font.custom("AvenirNextCondensed-Regular", size: h * 0.7)
                for (index, text) in texts.enumerated() {
                    let r = h * 0.09
                    let upper = Path(roundedRect: CGRect(x: x, y: top, width: w, height: h / 2), cornerRadius: r)
                    let lower = Path(roundedRect: CGRect(x: x, y: mid, width: w, height: h / 2), cornerRadius: r)
                    context.fill(upper, with: .linearGradient(
                        Gradient(colors: [Color(hex: 0x3B3C3F).opacity(alpha), Color(hex: 0x2D2E30).opacity(alpha)]),
                        startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: mid)))
                    context.fill(lower, with: .linearGradient(
                        Gradient(colors: [Color(hex: 0x262729).opacity(alpha), Color(hex: 0x303134).opacity(alpha)]),
                        startPoint: CGPoint(x: x, y: mid), endPoint: CGPoint(x: x, y: top + h)))
                    context.stroke(Path(roundedRect: CGRect(x: x, y: top, width: w, height: h), cornerRadius: r),
                                   with: .color(Color(hex: 0x151618).opacity(alpha)), lineWidth: max(0.5, h * 0.025))
                    context.draw(context.resolve(Text(text).font(font)
                                                    .foregroundColor(Color(hex: 0xF1EFE9).opacity(alpha))),
                                 at: CGPoint(x: x + w / 2, y: mid + h * 0.02), anchor: .center)
                    line(CGPoint(x: x, y: mid), CGPoint(x: x + w, y: mid), width: max(0.5, h * 0.03),
                         color: Color(hex: 0x141517).opacity(alpha))
                    // Scharnier-Klammern an den Seiten
                    let cw = h * 0.08, ch = h * 0.2
                    for sx in [x - cw * 0.7, x + w - cw * 0.3] {
                        context.fill(Path(roundedRect: CGRect(x: sx, y: mid - ch / 2, width: cw, height: ch),
                                          cornerRadius: cw * 0.4), with: .color(Color(hex: 0x1D1E20).opacity(alpha)))
                    }
                    x += w
                    if index < 2 {
                        context.draw(context.resolve(Text("/").font(slashFont)
                                                        .foregroundColor(Color(hex: 0x3A3B3E).opacity(alpha))),
                                     at: CGPoint(x: x + gap / 2, y: mid), anchor: .center)
                        x += gap
                    }
                }
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
