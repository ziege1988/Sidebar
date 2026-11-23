import AppKit

// MARK: - Fenster der Link-Apps nie unter der Sidebar
//
// Die Sidebar liegt über allen Fenstern. Sitzt sie z. B. oben und ein Link-Fenster reicht bis unter sie, liegen
// dessen Schließen-Knopf und Symbolleiste hinter der Leiste – ein Klick dort trifft die Sidebar. Deshalb werden
// Fenster der Link-Apps (und ihre Popups) beim Öffnen und beim Verschieben aus dem Bereich der Leiste und der
// Uhr herausgehalten.

enum SidebarKeepOut {
    /// Abstand zur Leiste
    static let gap: CGFloat = 4

    /// Verschiebt (und kürzt nur wenn nötig) `frame` so, dass es weder die Leiste noch die Uhr berührt.
    /// - Parameters:
    ///   - strip: Rahmen der Leiste, `clock`: Rahmen der Uhr (ragt bei oben/unten/links/rechts in den Bildschirm hinein)
    ///   - area: sichtbarer Bildschirmbereich
    static func adjust(_ frame: NSRect, strip: NSRect, clock: NSRect?, edge: ScreenEdge, area: NSRect) -> NSRect {
        var f = frame
        // 1. Leiste
        switch edge {
        case .top:
            let limit = strip.minY - gap
            if f.maxY > limit {
                f.origin.y = limit - f.height
                if f.minY < area.minY { f.origin.y = area.minY; f.size.height = max(120, limit - area.minY) }
            }
        case .bottom:
            let limit = strip.maxY + gap
            if f.minY < limit {
                f.origin.y = limit
                if f.maxY > area.maxY { f.size.height = max(120, area.maxY - limit) }
            }
        case .left:
            let limit = strip.maxX + gap
            if f.minX < limit {
                f.origin.x = limit
                if f.maxX > area.maxX { f.size.width = max(160, area.maxX - limit) }
            }
        case .right:
            let limit = strip.minX - gap
            if f.maxX > limit {
                f.origin.x = limit - f.width
                if f.minX < area.minX { f.origin.x = area.minX; f.size.width = max(160, limit - area.minX) }
            }
        }
        // 2. Uhr (ragt über die Leiste hinaus): erst zur Seite ausweichen, sonst darunter bzw. darüber
        if let clock, f.intersects(clock) {
            switch edge {
            case .right:
                let x = clock.minX - gap - f.width
                if x >= area.minX { f.origin.x = x } else { f = below(f, clock: clock, area: area, fromTop: true) }
            case .bottom:
                let x = clock.maxX + gap
                if x + f.width <= area.maxX { f.origin.x = x } else { f = below(f, clock: clock, area: area, fromTop: false) }
            default:
                let x = clock.maxX + gap
                if x + f.width <= area.maxX { f.origin.x = x } else { f = below(f, clock: clock, area: area, fromTop: true) }
            }
        }
        return f
    }

    /// Unter (Leiste oben) bzw. über (Leiste unten) der Uhr
    private static func below(_ frame: NSRect, clock: NSRect, area: NSRect, fromTop: Bool) -> NSRect {
        var f = frame
        if fromTop {
            let limit = clock.minY - gap
            if f.maxY > limit {
                f.origin.y = limit - f.height
                if f.minY < area.minY { f.origin.y = area.minY; f.size.height = max(120, limit - area.minY) }
            }
        } else {
            let limit = clock.maxY + gap
            if f.minY < limit {
                f.origin.y = limit
                if f.maxY > area.maxY { f.size.height = max(120, area.maxY - limit) }
            }
        }
        return f
    }

    /// Nach dem Verschieben: Der Schließen-Knopf (obere linke Ecke des Fensters) darf nicht unter der Leiste oder
    /// der Uhr liegen. Verschiebt das Fenster nur so weit wie nötig – und nur, wenn diese Ecke auf dem Bildschirm
    /// der Sidebar liegt (wer ein Fenster auf einen anderen Bildschirm zieht, wird nie zurückgeholt).
    static func reachable(_ frame: NSRect, strip: NSRect, clock: NSRect?, edge: ScreenEdge, area: NSRect) -> NSRect {
        var f = frame
        func corner() -> NSRect { NSRect(x: f.minX, y: f.maxY - 36, width: 90, height: 36) }
        guard area.insetBy(dx: -2, dy: -2).contains(CGPoint(x: corner().midX, y: corner().midY)) else { return frame }
        if corner().intersects(strip) {
            switch edge {
            case .top: f.origin.y -= corner().maxY - (strip.minY - gap)
            case .bottom: f.origin.y += (strip.maxY + gap) - corner().minY
            case .left: f.origin.x += (strip.maxX + gap) - corner().minX
            case .right: f.origin.x -= corner().maxX - (strip.minX - gap)
            }
        }
        if let clock, corner().intersects(clock) {
            switch edge {
            case .right: f.origin.x -= corner().maxX - (clock.minX - gap)
            case .bottom: f.origin.x += (clock.maxX + gap) - corner().minX
            default: f.origin.x += (clock.maxX + gap) - corner().minX
            }
        }
        return f
    }

    @MainActor
    static func reachableForCurrentSidebar(_ frame: NSRect) -> NSRect {
        guard let info = SidebarController.current?.windowKeepOut() else { return frame }
        return reachable(frame, strip: info.strip, clock: info.clock, edge: info.edge, area: info.area)
    }

    /// Für die laufende Sidebar (nur, wenn das Fenster auf ihrem Bildschirm liegt)
    @MainActor
    static func adjustedForCurrentSidebar(_ frame: NSRect) -> NSRect {
        guard let info = SidebarController.current?.windowKeepOut(),
              info.area.insetBy(dx: -2, dy: -2).contains(CGPoint(x: frame.midX, y: frame.midY)) else { return frame }
        return adjust(frame, strip: info.strip, clock: info.clock, edge: info.edge, area: info.area)
    }
}
