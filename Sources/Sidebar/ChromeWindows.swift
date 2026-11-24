import AppKit
import ApplicationServices

// MARK: - Chrome-App-Fenster (--app=…)
//
// Diese Fenster gehören Chrome, nicht der Sidebar. Über die Bedienungshilfen von macOS (dieselbe Freigabe wie für die
// Benachrichtigungen) kann die Sidebar sie trotzdem
//   • beim Öffnen an die zuletzt benutzte Stelle (Bildschirm, Lage, Größe) setzen und die Lage merken,
//   • aus dem Bereich der Leiste und der Uhr herausholen (sonst liegt der Schließen-Knopf dahinter),
//   • auf Wunsch zurückholen oder schließen (Rechtsklick auf den Eintrag).
// Voraussetzung: Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → „Sidebar“ eingeschaltet.

/// Reine Rechen- und Textfunktionen (ohne Chrome) – damit sie beim Bau getestet werden können.
enum ChromeBounds {
    struct Raw: Equatable {
        let id: Int
        let url: String
        /// Rahmen in den Koordinaten von AppleScript (Ursprung oben links am Hauptbildschirm)
        let left: Double, top: Double, right: Double, bottom: Double
    }

    /// Zeilen der Form `id|links|oben|rechts|unten|adresse`
    static func parse(_ text: String) -> [Raw] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 5, omittingEmptySubsequences: false)
            guard parts.count == 6, let id = Int(parts[0]),
                  let l = Double(parts[1]), let t = Double(parts[2]), let r = Double(parts[3]), let b = Double(parts[4]),
                  r > l, b > t else { return nil }
            return Raw(id: id, url: String(parts[5]), left: l, top: t, right: r, bottom: b)
        }
    }

    /// AppleScript (oben links, y nach unten) → Cocoa (unten links, y nach oben)
    static func cocoa(_ raw: Raw, primaryHeight: CGFloat) -> NSRect {
        NSRect(x: raw.left, y: primaryHeight - raw.bottom, width: raw.right - raw.left, height: raw.bottom - raw.top)
    }

    static func script(_ rect: NSRect, primaryHeight: CGFloat) -> (l: Int, t: Int, r: Int, b: Int) {
        (Int(rect.minX.rounded()), Int((primaryHeight - rect.maxY).rounded()),
         Int(rect.maxX.rounded()), Int((primaryHeight - rect.minY).rounded()))
    }

    /// Gemerkten Rahmen prüfen: Liegt das Fenster (zu mindestens einem Drittel seiner Fläche) auf einem angeschlossenen
    /// Bildschirm, bleibt es genau dort (nur zu große Fenster werden verkleinert). Nur wenn es auf keinem Bildschirm
    /// mehr liegt (Bildschirm abgesteckt), kommt es mittig auf `preferred`.
    /// - Parameters: `screens`: die ganzen Bildschirme, `visible`: deren sichtbare Bereiche (ohne Menüleiste/Dock), gleiche Reihenfolge
    static func sanitized(_ frame: NSRect, screens: [NSRect], visible: [NSRect], preferred: NSRect) -> NSRect {
        var f = frame
        let own = max(f.width * f.height, 1)
        var best: Int?
        var bestShare: CGFloat = 0
        for (i, screen) in screens.enumerated() {
            let overlap = f.intersection(screen)
            guard !overlap.isNull else { continue }
            let share = overlap.width * overlap.height / own
            if share > bestShare { bestShare = share; best = i }
        }
        if let best, bestShare >= 0.33 {
            let area = visible.indices.contains(best) ? visible[best] : screens[best]
            f.size.width = min(f.width, area.width)
            f.size.height = min(f.height, area.height)
            // Titelleiste nie über den sichtbaren Bereich hinaus (Menüleiste) und das Fenster nicht aus dem Bildschirm schieben
            if f.maxY > area.maxY { f.origin.y = area.maxY - f.height }
            if f.minY < area.minY { f.origin.y = area.minY }
            if f.maxX > area.maxX { f.origin.x = area.maxX - f.width }
            if f.minX < area.minX { f.origin.x = area.minX }
            return f
        }
        f.size.width = min(f.width, preferred.width * 0.95)
        f.size.height = min(f.height, preferred.height * 0.95)
        f.origin = CGPoint(x: preferred.midX - f.width / 2, y: preferred.midY - f.height / 2)
        return f
    }

    static func host(of text: String) -> String? {
        guard let host = URL(string: text)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

@MainActor
final class ChromeWindows {
    static let shared = ChromeWindows()

    struct Win {
        let element: AXUIElement
        let title: String
        /// Cocoa-Koordinaten
        let frame: NSRect
    }

    private struct Tracked {
        let element: AXUIElement
        let itemID: UUID
        var lastFrame: NSRect?
        var lastNudge: Date?
    }

    private var tracked: [Tracked] = []
    private var timer: Timer?
    private var bundleID = "com.google.Chrome"
    private var warnedDenied = false

    // MARK: Berechtigung (Bedienungshilfen)

    /// Darf die Sidebar andere Programme über die Bedienungshilfen steuern? Fragt beim ersten Mal nach und erklärt es einmal.
    private func trusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        explainPermission()
        return false
    }

    var denied: Bool { !AXIsProcessTrusted() }

    private func explainPermission() {
        guard !warnedDenied else { return }
        warnedDenied = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        let alert = NSAlert()
        alert.messageText = "Sidebar braucht die Freigabe „Bedienungshilfen“"
        alert.informativeText = "Damit die Sidebar Chrome-App-Fenster an ihren Platz setzen, zurückholen und schließen kann, muss in den Systemeinstellungen unter „Datenschutz & Sicherheit → Bedienungshilfen“ die Sidebar eingeschaltet sein."
        alert.addButton(withTitle: "Systemeinstellungen öffnen")
        alert.addButton(withTitle: "Später")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Protokoll und Diagnose

    private var logLines: [String] = []

    private func log(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        logLines.append("\(stamp)  \(text)")
        if logLines.count > 80 { logLines.removeFirst(logLines.count - 80) }
    }

    private func f(_ r: NSRect) -> String { "x\(Int(r.minX)) y\(Int(r.minY)) \(Int(r.width))×\(Int(r.height))" }

    /// Text für „Chrome-Fenster-Diagnose kopieren“: Bildschirme, Fenster, gemerkte Lagen, letzte Vorgänge
    func report(store: ConfigStore) -> String {
        var out = ["Chrome-Fenster-Diagnose", "Browser: \(bundleID)",
                   "Bedienungshilfen: " + (AXIsProcessTrusted() ? "erlaubt" : "NICHT erlaubt")]
        out.append("Hauptbildschirm-Höhe: \(Int(primaryHeight))")
        for (i, screen) in NSScreen.screens.enumerated() {
            out.append("Bildschirm \(i): \(f(screen.frame))  sichtbar \(f(screen.visibleFrame))")
        }
        if let info = SidebarController.current?.windowKeepOut() {
            out.append("Sidebar: Seite \(info.edge.rawValue), Leiste \(f(info.strip)), Uhr \(info.clock.map(f) ?? "–"), Bereich \(f(info.area))")
        }
        let all = windows(silent: true)
        out.append(all.isEmpty ? "Chrome-Fenster: keine gefunden (Chrome aus oder keine Erlaubnis)" : "Chrome-Fenster:")
        for w in all {
            let mine = tracked.contains { CFEqual($0.element, w.element) }
            out.append("  \(f(w.frame))  „\(w.title.prefix(50))“\(mine ? "  (beobachtet)" : "")")
        }
        out.append("Gemerkte Lagen:")
        for item in store.config.favorites + store.config.groups.flatMap(\.items) {
            if let r = remembered(item.id) { out.append("  \(item.displayName): \(f(r))") }
        }
        out.append("Letzte Vorgänge:")
        out.append(contentsOf: logLines.suffix(40).map { "  " + $0 })
        return out.joined(separator: "\n")
    }

    func copyReport(store: ConfigStore) {
        let text = report(store: store)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Gemerkte Lage

    private static let memoryKey = "Sidebar.ChromeWindowFrames"

    private func remembered(_ id: UUID) -> NSRect? {
        guard let all = UserDefaults.standard.dictionary(forKey: Self.memoryKey) as? [String: [Double]],
              let v = all[id.uuidString], v.count == 4, v[2] > 100, v[3] > 100 else { return nil }
        return NSRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    private func remember(_ frame: NSRect, for id: UUID) {
        var all = (UserDefaults.standard.dictionary(forKey: Self.memoryKey) as? [String: [Double]]) ?? [:]
        all[id.uuidString] = [frame.minX, frame.minY, frame.width, frame.height].map { Double($0) }
        UserDefaults.standard.set(all, forKey: Self.memoryKey)
    }

    // MARK: Bedienungshilfen: Fenster lesen, verschieben, schließen

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func axPoint(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
    }

    private func axSize(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &s) ? s : nil
    }

    /// Alle normalen Fenster des Browsers (Cocoa-Koordinaten)
    func windows(silent: Bool = false) -> [Win] {
        if silent ? !AXIsProcessTrusted() : !trusted() { return [] }
        var result: [Win] = []
        let height = primaryHeight
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            guard let list = attribute(root, kAXWindowsAttribute as String) as? [AXUIElement] else { continue }
            for element in list {
                guard let p = axPoint(attribute(element, kAXPositionAttribute as String)),
                      let s = axSize(attribute(element, kAXSizeAttribute as String)), s.width > 80, s.height > 60 else { continue }
                let title = attribute(element, kAXTitleAttribute as String) as? String ?? ""
                let raw = ChromeBounds.Raw(id: 0, url: title, left: p.x, top: p.y, right: p.x + s.width, bottom: p.y + s.height)
                result.append(Win(element: element, title: title, frame: ChromeBounds.cocoa(raw, primaryHeight: height)))
            }
        }
        return result
    }

    private func setFrame(_ frame: NSRect, of element: AXUIElement) {
        let b = ChromeBounds.script(frame, primaryHeight: primaryHeight)
        var position = CGPoint(x: b.l, y: b.t)
        var size = CGSize(width: b.r - b.l, height: b.b - b.t)
        // Position, Größe, Position noch einmal (die Größe kann die Position verschieben)
        if let v = AXValueCreate(.cgPoint, &position) { AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v) }
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v) }
        if let v = AXValueCreate(.cgPoint, &position) { AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v) }
    }

    private func close(_ element: AXUIElement) {
        if let button = attribute(element, kAXCloseButtonAttribute as String), CFGetTypeID(button) == AXUIElementGetTypeID() {
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
    }

    private func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }

    // MARK: Öffnen (aus dem LinkOpener)

    private var before: [Win] = []

    /// Vor dem Start des App-Fensters: welche Fenster gibt es schon?
    func prepareLaunch(bundleID: String) {
        self.bundleID = bundleID
        // Ohne Rückfrage: der Link soll sich sofort öffnen; die Erklärung zur Freigabe kommt danach
        before = windows(silent: true)
    }

    /// Nach dem Start: das neue Fenster finden, an die gemerkte Stelle setzen und ab jetzt beobachten
    func adopt(item: LinkItem) {
        let known = before
        var attempts = 0
        func poll() {
            attempts += 1
            if !AXIsProcessTrusted() { _ = self.trusted(); return }
            let fresh = self.windows(silent: true).filter { w in
                !known.contains { CFEqual($0.element, w.element) } && !self.tracked.contains { CFEqual($0.element, w.element) }
            }
            let name = item.displayName.lowercased()
            let match = fresh.first { !name.isEmpty && $0.title.lowercased().contains(name) } ?? fresh.first
            if let match {
                self.tracked.append(Tracked(element: match.element, itemID: item.id, lastFrame: nil, lastNudge: nil))
                self.place(match, for: item.id)
                self.startTimer()
            } else if attempts < 30, AXIsProcessTrusted() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { poll() } }
            } else {
                self.log("kein neues Fenster gefunden für „\(item.displayName)“")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { poll() } }
    }

    /// Neues Fenster: Chrome hat es schon irgendwo hingesetzt. Ist eine Lage gemerkt und liegt sie auf einem angeschlossenen
    /// Bildschirm, wandert es dorthin; sonst bleibt es, wo es ist. Nur wenn es unter der Leiste/Uhr der Sidebar läge
    /// (oder auf gar keinem Bildschirm), wird es verschoben.
    private func place(_ window: Win, for itemID: UUID) {
        let screens = NSScreen.screens.map(\.frame)
        let visible = NSScreen.screens.map(\.visibleFrame)
        let info = SidebarController.current?.windowKeepOut()
        let preferred = info?.area ?? (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? window.frame
        let saved = remembered(itemID)
        let wanted = saved ?? window.frame
        var target = ChromeBounds.sanitized(wanted, screens: screens, visible: visible, preferred: preferred)
        target = SidebarKeepOut.reachableForCurrentSidebar(target)
        log("öffnen „\(window.title.prefix(30))“: Chrome \(f(window.frame)), gemerkt \(saved.map(f) ?? "–"), Ziel \(f(target))")
        if target != window.frame { setFrame(target, of: window.element) }
        remember(target, for: itemID)
        if let i = tracked.firstIndex(where: { CFEqual($0.element, window.element) }) { tracked[i].lastFrame = target }
    }

    // MARK: Beobachten (Lage merken, Schließen-Knopf erreichbar halten)

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard !tracked.isEmpty, AXIsProcessTrusted() else { timer?.invalidate(); timer = nil; return }
        let all = windows(silent: true)
        // Geschlossene Fenster vergessen
        tracked.removeAll { entry in !all.contains { CFEqual($0.element, entry.element) } }
        if NSEvent.pressedMouseButtons & 1 != 0 { return }
        for index in tracked.indices {
            let entry = tracked[index]
            guard let window = all.first(where: { CFEqual($0.element, entry.element) }) else { continue }
            // Nur wenn das Fenster zur Ruhe gekommen ist (gleiche Lage wie beim letzten Mal), sonst wird gerade gezogen
            guard let last = entry.lastFrame, last.equalTo(window.frame) else {
                tracked[index].lastFrame = window.frame
                continue
            }
            let fixed = SidebarKeepOut.reachableForCurrentSidebar(window.frame)
            if fixed != window.frame, Date().timeIntervalSince(entry.lastNudge ?? .distantPast) > 20 {
                log("Schließen-Knopf verdeckt: \(f(window.frame)) → \(f(fixed))")
                setFrame(fixed, of: window.element)
                tracked[index].lastFrame = fixed
                tracked[index].lastNudge = Date()
                remember(fixed, for: entry.itemID)
            } else if remembered(entry.itemID) != window.frame {
                log("Lage gemerkt: \(f(window.frame))")
                remember(window.frame, for: entry.itemID)
            }
        }
        if tracked.isEmpty { timer?.invalidate(); timer = nil }
    }

    // MARK: Rechtsklick: Fenster schließen / zurückholen / Browser beenden

    /// Fenster eines Eintrags: die beobachteten, sonst solche, deren Titel zum Namen des Eintrags passt
    private func candidates(for item: LinkItem) -> [Win] {
        let all = windows()
        let mine = all.filter { w in tracked.contains { CFEqual($0.element, w.element) && $0.itemID == item.id } }
        if !mine.isEmpty { return mine }
        let name = item.displayName.lowercased()
        let host = item.url?.host?.lowercased().replacingOccurrences(of: "www.", with: "").split(separator: ".").first.map(String.init)
        return all.filter { w in
            let title = w.title.lowercased()
            return (!name.isEmpty && title.contains(name)) || (host.map { !$0.isEmpty && title.contains($0) } ?? false)
        }
    }

    func closeWindows(of item: LinkItem, bundleID: String) {
        self.bundleID = bundleID
        let found = candidates(for: item)
        if found.isEmpty { return noWindow(item) }
        for window in found {
            close(window.element)
            tracked.removeAll { CFEqual($0.element, window.element) }
        }
        log("geschlossen: \(found.count) Fenster für „\(item.displayName)“")
    }

    func bringBack(item: LinkItem, bundleID: String) {
        self.bundleID = bundleID
        let found = candidates(for: item)
        if found.isEmpty { return noWindow(item) }
        let info = SidebarController.current?.windowKeepOut()
        let area = info?.area ?? (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        for window in found {
            var frame = window.frame
            frame.size.width = min(frame.width, area.width - 40)
            frame.size.height = min(frame.height, area.height - 40)
            frame.origin = NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
            if let info {
                frame = SidebarKeepOut.adjust(frame, strip: info.strip, clock: info.clock, edge: info.edge, area: info.area)
            }
            setFrame(frame, of: window.element)
            remember(frame, for: item.id)
            raise(window.element)
        }
        log("zurückgeholt: \(found.count) Fenster für „\(item.displayName)“")
    }

    /// Notbremse: den Browser ganz beenden (wenn gar nichts anderes mehr geht)
    func quitBrowser(bundleID: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !apps.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Browser beenden?"
        alert.informativeText = "Alle Fenster dieses Browsers werden geschlossen, nicht nur das dieses Eintrags."
        alert.addButton(withTitle: "Beenden")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { apps.forEach { $0.terminate() } }
    }

    private func noWindow(_ item: LinkItem) {
        guard AXIsProcessTrusted() else { return }
        let alert = NSAlert()
        alert.messageText = "Kein Fenster für „\(item.displayName)“ gefunden"
        alert.informativeText = "Das Chrome-App-Fenster ist nicht (mehr) offen, oder sein Titel passt nicht zum Namen des Eintrags."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
