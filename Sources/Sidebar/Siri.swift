import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Siri-Knopf an der Uhr
//
// Kleine, animierte Farbkugel (rosé → flieder → blau) mitten im Zifferblatt, zwischen 12 Uhr und Zeigerachse.
// Ein Klick startet Siri, öffnet bei eingeschaltetem „Tippen für Siri“ das Eingabefeld und versucht, das Siri-Fenster
// in die Mitte des Hauptbildschirms zu legen. Das offizielle Siri-Symbol gehört Apple und wird nicht nachgebaut –
// die Kugel ist eine eigene Zeichnung.

enum SiriButtonLayout {
    /// Unter dieser Uhrgröße wird der Knopf ausgeblendet (zu wenig Platz im Zifferblatt)
    static let minClock: CGFloat = 120

    static func visible(_ s: SidebarSettings) -> Bool {
        s.showSiriButton && s.showClock && CGFloat(s.clockSize) >= minClock
    }

    /// Größe des Knopfes: ein Drittel größer als zuvor
    static func diameter(_ s: SidebarSettings) -> CGFloat {
        min(43, max(29, CGFloat(s.clockSize) / 2 * 0.45))
    }

    /// Abstand des Knopfmittelpunkts von der Uhrmitte nach oben: mittig zwischen 12-Uhr-Strich und Zeigerachse
    static func offsetUp(_ s: SidebarSettings) -> CGFloat {
        CGFloat(s.clockSize) / 2 * 0.42
    }
}

struct SiriOrbButton: View {
    let diameter: CGFloat
    @ObservedObject private var power = PowerState.shared
    @State private var hovering = false
    @State private var pressed = false

    /// Pastellig und deutlich entsättigt: rosé → flieder → himmelblau (je 35 % zum Grau gemischt)
    private static func soft(_ r: Double, _ g: Double, _ b: Double) -> Color {
        let l = 0.3 * r + 0.59 * g + 0.11 * b, k = 0.35
        return Color(red: r + (l - r) * k, green: g + (l - g) * k, blue: b + (l - b) * k)
    }
    private static let colors: [Color] = [
        soft(0.96, 0.55, 0.62), soft(0.96, 0.63, 0.78), soft(0.78, 0.64, 0.94), soft(0.58, 0.67, 0.96),
        soft(0.62, 0.82, 0.95), soft(0.72, 0.68, 0.96), soft(0.96, 0.55, 0.62),
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
