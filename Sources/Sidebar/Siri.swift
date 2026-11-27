import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Siri-Knopf an der Uhr
//
// Kleine, animierte Farbkugel (rot → magenta → violett → blau) am unteren linken Rand der Uhr (Sidebar oben bzw. unten).
// Ein Klick startet Siri, öffnet bei eingeschaltetem „Tippen für Siri“ das Eingabefeld und versucht, das Siri-Fenster
// in die Mitte des Hauptbildschirms zu legen. Das offizielle Siri-Symbol gehört Apple und wird nicht nachgebaut –
// die Kugel ist eine eigene Zeichnung.

enum SiriButtonLayout {
    /// Unter dieser Uhrgröße wird der Knopf ausgeblendet (zu wenig Platz neben Rüdiger und der Leiste)
    static let minClock: CGFloat = 120

    /// Mittelpunkt und Größe des Knopfes in den Koordinaten der Sidebar (Ursprung oben links). `nil` = nicht sichtbar.
    /// `size` = Größe des Leistenfensters (für Leiste unten nötig).
    /// „In der Kurve“: in der Mulde zwischen Uhr und Leiste, solange Rüdiger dort nicht sitzt; sonst am Uhrrand.
    static func layout(_ s: SidebarSettings, size: CGSize? = nil) -> (center: CGPoint, diameter: CGFloat)? {
        guard s.siriPlacement != .off, s.showClock, !s.edge.isVertical, CGFloat(s.clockSize) >= minClock else { return nil }
        if s.siriPlacement == .curve, !catDocked(s) {
            // Innerhalb der Glasfläche: im Winkel zwischen Uhr und Leiste, links unterhalb der Lupe des Google-Felds
            let panel = ClockLayout.panelSize(s)
            let bar = CGFloat(s.collapsedThickness)
            let size = size ?? CGSize(width: 10_000, height: panel.height)
            let diameter: CGFloat = 22
            let along = panel.width + 2, cross = bar - 3
            let p: CGPoint
            switch s.edge {
            case .bottom: p = CGPoint(x: along, y: size.height - cross)
            default: p = CGPoint(x: along, y: cross)
            }
            return (p, diameter)
        }
        let panel = ClockLayout.panelSize(s)
        let radius = CGFloat(s.clockSize) / 2
        let diameter = min(32, max(22, radius * 0.34))
        let d = radius * 0.7071
        // Mitte der Uhr im Uhrfeld; der Knopf sitzt am Rand, etwas nach unten gerückt (nicht mehr so sehr in der Uhr):
        // links unten (Leiste oben) bzw. links oben (Leiste unten)
        let cx = panel.width / 2, cy = panel.height / 2
        let y = s.edge == .top ? cy + d * 1.12 : cy - d * 1.12
        return (CGPoint(x: cx - d * 0.95, y: y), diameter)
    }

    /// Rüdiger sitzt gerade in der Mulde
    static func catDocked(_ s: SidebarSettings) -> Bool {
        !s.catFloating && CatGeometry.make(s, clockOn: s.showClock) != nil
    }
}

struct SiriOrbButton: View {
    let diameter: CGFloat
    @ObservedObject private var power = PowerState.shared
    @State private var hovering = false
    @State private var pressed = false

    /// Pastellig und leicht entsättigt: rosé → flieder → himmelblau
    private static let colors: [Color] = [
        Color(red: 0.96, green: 0.55, blue: 0.62), Color(red: 0.96, green: 0.63, blue: 0.78),
        Color(red: 0.78, green: 0.64, blue: 0.94), Color(red: 0.58, green: 0.67, blue: 0.96),
        Color(red: 0.62, green: 0.82, blue: 0.95), Color(red: 0.72, green: 0.68, blue: 0.96),
        Color(red: 0.96, green: 0.55, blue: 0.62),
    ]

    var body: some View {
        // Ruhig: 20 Bilder pro Sekunde, eine Umdrehung in 6 Sekunden; pausiert, wenn niemand hinsieht
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: power.paused)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                AngularGradient(colors: Self.colors, center: .center, angle: .degrees(t * 60))
                    .scaleEffect(1.5)
                    .blur(radius: diameter * 0.14)
                    .clipShape(Circle())
                Circle().fill(RadialGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0)],
                                             center: UnitPoint(x: 0.35, y: 0.28), startRadius: 0, endRadius: diameter * 0.45))
                Circle().fill(RadialGradient(colors: [Color.black.opacity(0.32), Color.black.opacity(0)],
                                             center: UnitPoint(x: 0.7, y: 0.85), startRadius: 0, endRadius: diameter * 0.55))
                Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.2)
            }
            .brightness(pressed ? 0.25 : 0)
            .shadow(color: Color(red: 0.62, green: 0.55, blue: 0.95).opacity(hovering ? 0.6 : 0.3), radius: hovering ? 8 : 5)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(hovering ? 1.12 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .onTapGesture {
            pressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pressed = false }
            SiriLauncher.shared.open()
        }
        .help("Siri fragen")
    }
}

@MainActor
final class SiriLauncher {
    static let shared = SiriLauncher()
    private var logLines: [String] = []
    private static let hintKey = "Sidebar.SiriTypeHintShown"

    private func log(_ text: String) {
        logLines.append("\(Date().formatted(date: .omitted, time: .standard))  \(text)")
        if logLines.count > 30 { logLines.removeFirst(logLines.count - 30) }
    }

    /// Text für „Diagnose kopieren“
    func report() -> String {
        var out = ["Siri", "Bedienungshilfen: " + (AXIsProcessTrusted() ? "erlaubt" : "NICHT erlaubt")]
        out.append("Siri-Programm: " + (FileManager.default.fileExists(atPath: "/System/Applications/Siri.app") ? "vorhanden" : "nicht gefunden"))
        out.append("Tippen für Siri: " + typeToSiriDescription)
        out.append(contentsOf: logLines.suffix(15).map { "  " + $0 })
        return out.joined(separator: "\n")
    }

    private var typeToSiri: Bool? {
        UserDefaults(suiteName: "com.apple.Siri")?.object(forKey: "TypeToSiriEnabled") as? Bool
    }

    private var typeToSiriDescription: String {
        switch typeToSiri {
        case .some(true): return "an"
        case .some(false): return "aus"
        case .none: return "unbekannt"
        }
    }

    func open() {
        let url = URL(fileURLWithPath: "/System/Applications/Siri.app")
        guard FileManager.default.fileExists(atPath: url.path) else {
            log("Siri.app nicht gefunden")
            let alert = NSAlert()
            alert.messageText = "Siri wurde nicht gefunden"
            alert.informativeText = "Auf diesem Mac gibt es kein Siri-Programm. Prüfe in den Systemeinstellungen, ob Siri eingeschaltet ist."
            alert.addButton(withTitle: "OK")
            NSApp.activate()
            alert.runModal()
            return
        }
        log("Siri wird gestartet (Tippen für Siri: \(typeToSiriDescription))")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in self?.log("Start fehlgeschlagen: \(error.localizedDescription)") }
        }
        // Eingabefeld: nur sinnvoll, wenn „Tippen für Siri“ eingeschaltet ist – sonst einmal erklären
        if typeToSiri == false, !UserDefaults.standard.bool(forKey: Self.hintKey) {
            UserDefaults.standard.set(true, forKey: Self.hintKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.explainTypeToSiri() }
        }
        // Siri-Fenster in die Mitte des Hauptbildschirms legen (mehrere Versuche: das Fenster erscheint etwas später)
        for delay in [0.5, 0.9, 1.4, 2.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.centerSiriWindow() }
        }
    }

    private func explainTypeToSiri() {
        let alert = NSAlert()
        alert.messageText = "Zum Schreiben: „Tippen für Siri“ einschalten"
        alert.informativeText = "Damit Siri ein Eingabefeld zeigt, schaltest du in den Systemeinstellungen unter „Siri“ (bzw. „Apple Intelligence & Siri“) die Option „Tippen für Siri“ ein. Ohne sie hört Siri nur zu. Diese Erklärung kommt nur einmal."
        alert.addButton(withTitle: "Systemeinstellungen öffnen")
        alert.addButton(withTitle: "Später")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Fenster in die Mitte (Bedienungshilfen, falls macOS es zulässt)

    private func centerSiriWindow() {
        guard AXIsProcessTrusted() else { log("Fenster nicht verschoben: Bedienungshilfen nicht erlaubt"); return }
        let area = SidebarController.current?.windowKeepOut()?.area ?? NSScreen.screens.first?.visibleFrame ?? .zero
        guard area != .zero else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var moved = 0, seen = 0
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier?.hasPrefix("com.apple.Siri") == true
            || app.bundleIdentifier?.hasPrefix("com.apple.siri") == true {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                var sizeValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
                      let sizeRef = sizeValue, CFGetTypeID(sizeRef) == AXValueGetTypeID() else { continue }
                var size = CGSize.zero
                guard AXValueGetValue(sizeRef as! AXValue, .cgSize, &size), size.width > 60, size.height > 30 else { continue }
                seen += 1
                // Mitte des Hauptbildschirms (AppKit-Koordinaten → Koordinaten der Bedienungshilfen, y nach unten)
                var position = CGPoint(x: area.midX - size.width / 2, y: primaryHeight - (area.midY + size.height / 2))
                if let v = AXValueCreate(.cgPoint, &position),
                   AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v) == .success { moved += 1 }
            }
        }
        log(seen == 0 ? "kein Siri-Fenster zum Verschieben gefunden" : "Siri-Fenster verschoben: \(moved) von \(seen)")
    }
}
