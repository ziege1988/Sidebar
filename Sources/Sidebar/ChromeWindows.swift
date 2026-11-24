import AppKit

// MARK: - Chrome-App-Fenster (--app=…)
//
// Diese Fenster gehören Chrome, nicht der Sidebar. Über die Automation-Schnittstelle von macOS („Apple Events“)
// kann die Sidebar sie trotzdem
//   • beim Öffnen an die zuletzt benutzte Stelle (Bildschirm, Lage, Größe) setzen und die Lage merken,
//   • aus dem Bereich der Leiste und der Uhr herausholen (sonst liegt der Schließen-Knopf dahinter),
//   • auf Wunsch zurückholen oder schließen (Rechtsklick auf den Eintrag).
// Dafür fragt macOS beim ersten Mal einmalig: „Sidebar möchte Google Chrome steuern“.

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

    struct Info {
        let id: Int
        let url: String
        /// Cocoa-Koordinaten
        let frame: NSRect
    }

    private struct Tracked {
        let itemID: UUID
        var lastFrame: NSRect?
        var lastNudge: Date?
    }

    private var tracked: [Int: Tracked] = [:]
    private var timer: Timer?
    private var bundleID = "com.google.Chrome"
    private var warnedDenied = false
    private(set) var denied = false

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
        var out = ["Chrome-Fenster-Diagnose", "Browser: \(bundleID)", "Automation: " + (denied ? "VERWEIGERT" : "nicht verweigert")]
        out.append("Hauptbildschirm-Höhe: \(Int(primaryHeight))")
        for (i, screen) in NSScreen.screens.enumerated() {
            out.append("Bildschirm \(i): \(f(screen.frame))  sichtbar \(f(screen.visibleFrame))")
        }
        if let info = SidebarController.current?.windowKeepOut() {
            out.append("Sidebar: Seite \(info.edge.rawValue), Leiste \(f(info.strip)), Uhr \(info.clock.map(f) ?? "–"), Bereich \(f(info.area))")
        }
        let raw = run("""
        set out to ""
        repeat with w in windows
          try
            set b to bounds of w
            set out to out & (id of w) & "|" & (item 1 of b) & "|" & (item 2 of b) & "|" & (item 3 of b) & "|" & (item 4 of b) & "|" & (URL of active tab of w) & linefeed
          end try
        end repeat
        return out
        """)
        out.append(raw == nil ? "Fensterliste: nicht lesbar (Chrome aus oder keine Erlaubnis)" : "Chrome-Fenster:")
        for w in ChromeBounds.parse(raw ?? "") {
            let cocoa = ChromeBounds.cocoa(w, primaryHeight: primaryHeight)
            out.append("  #\(w.id) AppleScript [\(Int(w.left)),\(Int(w.top)),\(Int(w.right)),\(Int(w.bottom))] → \(f(cocoa))  \(w.url.prefix(60))\(tracked[w.id] != nil ? "  (beobachtet)" : "")")
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

    // MARK: AppleScript

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func validBundleID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    private func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Führt ein Skript aus. Ohne Erlaubnis (Automation) wird einmal erklärt, wie man sie gibt.
    @discardableResult
    private func run(_ body: String) -> String? {
        guard Self.validBundleID(bundleID), isRunning() else { return nil }
        let source = """
        tell application id "\(bundleID)"
          with timeout of 4 seconds
            \(body)
          end timeout
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                denied = true
                explainPermission()
            }
            return nil
        }
        denied = false
        return result.stringValue ?? ""
    }

    private func explainPermission() {
        guard !warnedDenied else { return }
        warnedDenied = true
        let alert = NSAlert()
        alert.messageText = "Sidebar darf Chrome nicht steuern"
        alert.informativeText = "Damit die Sidebar Chrome-App-Fenster an ihren Platz setzen, zurückholen und schließen kann, muss sie in den Systemeinstellungen unter „Datenschutz & Sicherheit → Automation“ bei Sidebar den Browser einschalten."
        alert.addButton(withTitle: "Systemeinstellungen öffnen")
        alert.addButton(withTitle: "Später")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Alle Fenster des Browsers (Cocoa-Koordinaten)
    func windows() -> [Info] {
        let text = run("""
        set out to ""
        repeat with w in windows
          try
            set b to bounds of w
            set out to out & (id of w) & "|" & (item 1 of b) & "|" & (item 2 of b) & "|" & (item 3 of b) & "|" & (item 4 of b) & "|" & (URL of active tab of w) & linefeed
          end try
        end repeat
        return out
        """) ?? ""
        let height = primaryHeight
        return ChromeBounds.parse(text).map { Info(id: $0.id, url: $0.url, frame: ChromeBounds.cocoa($0, primaryHeight: height)) }
    }

    private func setFrame(_ frame: NSRect, windowID: Int) {
        let b = ChromeBounds.script(frame, primaryHeight: primaryHeight)
        run("set bounds of (first window whose id is \(windowID)) to {\(b.l), \(b.t), \(b.r), \(b.b)}")
    }

    // MARK: Öffnen (aus dem LinkOpener)

    private var idsBeforeLaunch: Set<Int> = []

    /// Vor dem Start des App-Fensters: welche Fenster gibt es schon?
    func prepareLaunch(bundleID: String) {
        self.bundleID = bundleID
        idsBeforeLaunch = isRunning() ? Set(windows().map(\.id)) : []
    }

    /// Nach dem Start: das neue Fenster finden, an die gemerkte Stelle setzen und ab jetzt beobachten
    func adopt(item: LinkItem) {
        let before = idsBeforeLaunch
        let host = item.url?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0.lowercased() }
        var attempts = 0
        func poll() {
            attempts += 1
            let fresh = self.windows().filter { !before.contains($0.id) && self.tracked[$0.id] == nil }
            let match = fresh.first { host != nil && ChromeBounds.host(of: $0.url) == host } ?? (fresh.count == 1 ? fresh.first : nil)
            if let match {
                self.tracked[match.id] = Tracked(itemID: item.id, lastFrame: nil)
                self.place(match, for: item.id)
                self.startTimer()
            } else if attempts < 24, !self.denied {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { MainActor.assumeIsolated { poll() } }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { poll() } }
    }

    /// Neues Fenster: Chrome hat es schon irgendwo hingesetzt. Ist eine Lage gemerkt und liegt sie auf einem angeschlossenen
    /// Bildschirm, wandert es dorthin; sonst bleibt es, wo es ist. Nur wenn es unter der Leiste/Uhr der Sidebar läge
    /// (oder auf gar keinem Bildschirm), wird es verschoben.
    private func place(_ window: Info, for itemID: UUID) {
        let screens = NSScreen.screens.map(\.frame)
        let visible = NSScreen.screens.map(\.visibleFrame)
        let info = SidebarController.current?.windowKeepOut()
        let preferred = info?.area ?? (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? window.frame
        let saved = remembered(itemID)
        let wanted = saved ?? window.frame
        var target = ChromeBounds.sanitized(wanted, screens: screens, visible: visible, preferred: preferred)
        target = SidebarKeepOut.reachableForCurrentSidebar(target)
        log("öffnen #\(window.id): Chrome \(f(window.frame)), gemerkt \(saved.map(f) ?? "–"), Ziel \(f(target))")
        if target != window.frame { setFrame(target, windowID: window.id) }
        remember(target, for: itemID)
        tracked[window.id]?.lastFrame = target
    }

    // MARK: Beobachten (Lage merken, Schließen-Knopf erreichbar halten)

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard !tracked.isEmpty, !denied else { timer?.invalidate(); timer = nil; return }
        let all = Dictionary(uniqueKeysWithValues: windows().map { ($0.id, $0) })
        // Geschlossene Fenster vergessen (nur wenn die Abfrage nicht an der Erlaubnis gescheitert ist)
        if !denied {
            for id in tracked.keys where all[id] == nil { tracked[id] = nil }
        }
        if NSEvent.pressedMouseButtons & 1 != 0 { return }
        for (id, entry) in tracked {
            guard let window = all[id] else { continue }
            // Nur wenn das Fenster zur Ruhe gekommen ist (gleiche Lage wie beim letzten Mal), sonst wird gerade gezogen
            guard let last = entry.lastFrame, last.equalTo(window.frame) else {
                tracked[id]?.lastFrame = window.frame
                continue
            }
            let fixed = SidebarKeepOut.reachableForCurrentSidebar(window.frame)
            if fixed != window.frame, Date().timeIntervalSince(entry.lastNudge ?? .distantPast) > 20 {
                log("Schließen-Knopf verdeckt #\(id): \(f(window.frame)) → \(f(fixed))")
                setFrame(fixed, windowID: id)
                tracked[id]?.lastFrame = fixed
                tracked[id]?.lastNudge = Date()
                remember(fixed, for: entry.itemID)
            } else if remembered(entry.itemID) != window.frame {
                log("Lage gemerkt #\(id): \(f(window.frame))")
                remember(window.frame, for: entry.itemID)
            }
        }
        if tracked.isEmpty { timer?.invalidate(); timer = nil }
    }

    // MARK: Rechtsklick: Fenster schließen / zurückholen / Browser beenden

    /// Fenster eines Eintrags: die beobachteten, sonst Fenster mit einem Tab und passender Adresse
    private func candidates(for item: LinkItem) -> [Info] {
        let all = windows()
        let mine = all.filter { tracked[$0.id]?.itemID == item.id }
        if !mine.isEmpty { return mine }
        guard let host = item.url?.host.map({ $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0.lowercased() }) else { return [] }
        return all.filter { ChromeBounds.host(of: $0.url) == host }
    }

    func closeWindows(of item: LinkItem, bundleID: String) {
        self.bundleID = bundleID
        let found = candidates(for: item)
        if found.isEmpty { return noWindow(item) }
        for window in found {
            run("close (first window whose id is \(window.id))")
            tracked[window.id] = nil
        }
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
            setFrame(frame, windowID: window.id)
            remember(frame, for: item.id)
            run("set index of (first window whose id is \(window.id)) to 1\nactivate")
        }
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
        guard !denied else { return }
        let alert = NSAlert()
        alert.messageText = "Kein Fenster für „\(item.displayName)“ gefunden"
        alert.informativeText = "Das Chrome-App-Fenster ist nicht (mehr) offen."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
