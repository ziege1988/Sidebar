import AppKit
import ApplicationServices
import Combine
import QuickLookThumbnailing
import SwiftUI
import WebKit

// MARK: - Messenger & Programme

extension LinkItem {
    /// Bekannte Messenger/Chat-Dienste – laufen auf Wunsch automatisch im Hintergrund.
    static let messengerHosts = [
        "web.whatsapp.com", "whatsapp.com", "messenger.com", "instagram.com",
        "web.telegram.org", "discord.com", "app.slack.com", "teams.microsoft.com",
        "teams.live.com", "chat.google.com", "linkedin.com",
    ]

    var isMessenger: Bool {
        guard !isLocal, let host = host?.lowercased() else { return false }
        return LinkItem.messengerHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Läuft unsichtbar im Hintergrund (eigene Einstellung am Link, sonst automatisch bei Messengern).
    func runsInBackground(autoMessengers: Bool) -> Bool {
        guard !isLocal else { return false }
        return keepAlive ?? (autoMessengers && isMessenger)
    }

    private static var bundleIDCache: [String: String] = [:]

    /// Bundle-ID, wenn der Link ein Programm auf dem Mac ist (z. B. WhatsApp, Mail).
    var appBundleID: String? {
        guard let url, url.isFileURL, url.pathExtension.lowercased() == "app" else { return nil }
        if let cached = LinkItem.bundleIDCache[url.path] { return cached }
        guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        LinkItem.bundleIDCache[url.path] = id
        return id
    }
}

// MARK: - Mitteilungs-Einstellungen (Ruhemodus, Aufleuchten, Vorschau)

/// Spiegelt die Mitteilungs-Einstellungen für alle Ansichten und prüft den Ruhemodus.
final class AlertState: ObservableObject {
    static let shared = AlertState()

    @Published private(set) var quiet = false
    @Published private(set) var pulse = true
    @Published private(set) var messagePreview = true
    private var settings = SidebarSettings()
    private var timer: Timer?

    private init() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func apply(_ settings: SidebarSettings) {
        self.settings = settings
        refresh()
    }

    private func refresh() {
        let quietNow = Self.isQuiet(settings, at: Date())
        if quiet != quietNow { quiet = quietNow }
        if pulse != settings.badgePulse { pulse = settings.badgePulse }
        if messagePreview != settings.messagePreview { messagePreview = settings.messagePreview }
    }

    static func isQuiet(_ settings: SidebarSettings, at date: Date) -> Bool {
        if settings.quietMode { return true }
        guard settings.quietScheduled else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        let from = settings.quietFrom, to = settings.quietTo
        if from == to { return false }
        // über Mitternacht (z. B. 22 – 7 Uhr) oder innerhalb eines Tages (z. B. 13 – 15 Uhr)
        return from < to ? (hour >= from && hour < to) : (hour >= from || hour < to)
    }
}

// MARK: - Zähler von Mac-Programmen (wie im Dock)

/// Liest die roten Dock-Zahlen von Programmen (WhatsApp, Mail, Nachrichten, Slack …).
/// Drei Wege, die Ergebnisse werden zusammengeführt (höchste Zahl gewinnt):
/// 1. direkt bei macOS (LaunchServices – derselbe Weg wie das Werkzeug `lsappinfo`), ohne Sonderrechte
/// 2. über das Werkzeug `lsappinfo` (Ersatz, falls 1 nicht geht)
/// 3. direkt aus dem Dock über die Bedienungshilfen (nur, wenn der Zugriff erlaubt wurde)
/// Keiner dieser Wege ist offiziell von Apple dokumentiert.
final class DockBadgeWatcher: ObservableObject {
    static let shared = DockBadgeWatcher()

    struct Status: Equatable {
        var name: String
        var running: Bool
        var count: Int
        var sources: [String]
    }

    /// Zustand je Programm (für die Anzeige in den Einstellungen)
    @Published private(set) var statuses: [String: Status] = [:]
    /// Zugriff aufs Dock (Bedienungshilfen)
    enum AccessState: Equatable {
        /// nicht erlaubt (oder abgelehnt)
        case off
        /// Systemeinstellungen geöffnet, Freigabe steht noch aus
        case waiting
        /// erlaubt und funktioniert
        case active
        /// erlaubt, greift aber erst nach einem Neustart der Sidebar
        case needsRestart
    }

    @Published private(set) var accessState: AccessState = .off
    private var requestedAt: Date?
    private var accessTimer: Timer?
    private var activeObserver: NSObjectProtocol?

    private init() {
        refreshAccess()
        // Zurück aus den Systemeinstellungen → sofort neu prüfen
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAccess() }
    }

    private var bundleIDs: [String] = []
    private var timer: Timer?
    private let queue = DispatchQueue(label: "sidebar.dockbadges", qos: .utility)
    private var running = false

    @MainActor
    func update(items: [LinkItem], enabled: Bool) {
        let ids = enabled ? Array(Set(items.compactMap(\.appBundleID))).sorted() : []
        let removed = Set(bundleIDs).subtracting(ids)
        bundleIDs = ids
        for id in removed {
            BadgeStore.shared.setApp(0, bundleID: id)
            statuses[id] = nil
        }
        if ids.isEmpty {
            timer?.invalidate()
            timer = nil
            return
        }
        if timer == nil {
            let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        poll()
    }

    /// Fragt nach dem Zugriff über die Bedienungshilfen (macOS zeigt dazu einen Hinweis).
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        requestedAt = Date()
        refreshAccess()
        // jede Sekunde nachsehen, ob der Schalter umgelegt wurde (höchstens 3 Minuten)
        accessTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.refreshAccess()
            if self.accessState == .active || Date().timeIntervalSince(self.requestedAt ?? .distantPast) > 180 {
                timer.invalidate()
                self.accessTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessTimer = timer
    }

    /// Alte Freigabe löschen (z. B. von einer früheren Version, die nicht mehr passt) und neu anfragen.
    func resetAndRequestAccessibility() {
        if let bundleID = Bundle.main.bundleIdentifier {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            try? process.run()
            process.waitUntilExit()
        }
        requestAccessibility()
    }

    /// Prüft, ob der Zugriff erlaubt ist und tatsächlich funktioniert.
    func refreshAccess() {
        let state: AccessState
        if AXIsProcessTrusted() {
            state = Self.dockReachable() ? .active : .needsRestart
        } else if let requestedAt, Date().timeIntervalSince(requestedAt) < 180 {
            state = .waiting
        } else {
            state = .off
        }
        if accessState != state { accessState = state }
    }

    private static func dockReachable() -> Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return false }
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        return AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value) == .success
    }

    func poll() {
        guard !running else { return }
        running = true
        let ids = bundleIDs
        var targets: [(id: String, name: String, pid: pid_t, url: URL?)] = []
        var names: [String: String] = [:]
        for id in ids {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                let name = app.localizedName ?? id
                targets.append((id, name, app.processIdentifier, app.bundleURL))
                names[id] = name
            }
        }
        let trusted = AXIsProcessTrusted()
        queue.async { [weak self] in
            var results: [String: Status] = [:]
            let dockLabels = trusted ? Self.dockLabels() : []
            for target in targets {
                var counts: [Int] = []
                var sources: [String] = []
                if let label = Self.launchServicesLabel(pid: target.pid) {
                    counts.append(Self.count(from: label))
                    sources.append("macOS")
                }
                if let label = Self.lsappinfoLabel(name: target.name, pid: target.pid) {
                    counts.append(Self.count(from: label))
                    sources.append("lsappinfo")
                }
                let clean = Self.cleanName(target.name)
                if let dock = dockLabels.first(where: { entry in
                    (target.url != nil && entry.url?.standardizedFileURL.path == target.url?.standardizedFileURL.path)
                        || Self.cleanName(entry.title) == clean
                }) {
                    counts.append(Self.count(from: dock.label))
                    sources.append("Dock")
                }
                results[target.id] = Status(name: target.name, running: true,
                                            count: counts.max() ?? 0, sources: sources)
            }
            for id in ids where results[id] == nil {
                results[id] = Status(name: names[id] ?? id, running: false, count: 0, sources: [])
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for (id, status) in results {
                    // Zahl gestiegen → Text der Mitteilung aus dem macOS-Banner holen
                    if let old = self.statuses[id], old.running, status.count > old.count {
                        self.fetchBanner(bundleID: id, appName: status.name)
                    }
                    BadgeStore.shared.setApp(status.count, bundleID: id)
                }
                if self.statuses != results { self.statuses = results }
                self.refreshAccess()
                self.running = false
            }
        }
    }

    /// Unsichtbare Zeichen (z. B. vor „‎WhatsApp“) entfernen
    static func cleanName(_ name: String) -> String {
        name.unicodeScalars.filter { !CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202C}").contains($0) }
            .map(String.init).joined().trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func count(from label: String) -> Int {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        // Kein Zahlenwert (z. B. „•“ oder „!“) → als 1 anzeigen
        return Int(trimmed.filter(\.isNumber)) ?? 1
    }

    // MARK: 1. LaunchServices

    private typealias ASNCreate = @convention(c) (CFAllocator?, pid_t) -> Unmanaged<CFTypeRef>?
    private typealias CopyInfoItem = @convention(c) (Int32, CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?

    private static let launchServices: (ASNCreate, CopyInfoItem)? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY),
              let create = dlsym(handle, "_LSASNCreateWithPid"),
              let copy = dlsym(handle, "_LSCopyApplicationInformationItem") else { return nil }
        return (unsafeBitCast(create, to: ASNCreate.self), unsafeBitCast(copy, to: CopyInfoItem.self))
    }()

    /// `nil` = nicht lesbar, "" = keine Zahl
    private static func launchServicesLabel(pid: pid_t) -> String? {
        guard let (create, copy) = launchServices,
              let asn = create(kCFAllocatorDefault, pid)?.takeRetainedValue() else { return nil }
        // -2 = aktuelle Anmeldung (kLSDefaultSessionID)
        guard let value = copy(-2, asn, "StatusLabel" as CFString)?.takeRetainedValue() else { return "" }
        if let dict = value as? [String: Any] {
            return (dict["label"] as? String) ?? ""
        }
        return (value as? String) ?? ""
    }

    // MARK: 2. lsappinfo

    private static func lsappinfoLabel(name: String, pid: pid_t) -> String? {
        for arguments in [["info", "-only", "StatusLabel", name],
                          ["-all", "info", "-only", "StatusLabel", name]] {
            let output = run(arguments)
            guard output.contains("StatusLabel") else { continue }
            return parseLabel(output) ?? ""
        }
        return nil
    }

    static func parseLabel(_ output: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #""label"\s*=\s*"([^"]*)""#),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[range])
    }

    private static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: Text der Mitteilung (aus dem Banner oben rechts)

    /// Liest Absender und Text aus dem gerade sichtbaren macOS-Banner des Programms.
    /// Braucht den Zugriff über die Bedienungshilfen. Ohne Text: „Neue Nachricht“.
    private func fetchBanner(bundleID: String, appName: String) {
        let key = BadgeStore.appKey(bundleID)
        guard AXIsProcessTrusted() else {
            BadgeStore.shared.setMessage(title: Self.cleanDisplayName(appName), body: "", key: key)
            return
        }
        func attempt(_ delays: [Double]) {
            guard let delay = delays.first else {
                DispatchQueue.main.async {
                    BadgeStore.shared.setMessage(title: Self.cleanDisplayName(appName), body: "", key: key)
                }
                return
            }
            queue.asyncAfter(deadline: .now() + delay) {
                if let (title, body) = Self.bannerText(appName: appName) {
                    DispatchQueue.main.async { BadgeStore.shared.setMessage(title: title, body: body, key: key) }
                } else {
                    attempt(Array(delays.dropFirst()))
                }
            }
        }
        attempt([0.2, 0.6, 1.0])
    }

    static func cleanDisplayName(_ name: String) -> String {
        name.unicodeScalars.filter { !CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202C}").contains($0) }
            .map(String.init).joined().trimmingCharacters(in: .whitespaces)
    }

    private static func bannerText(appName: String) -> (String, String)? {
        guard let center = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.notificationcenterui").first else { return nil }
        let root = AXUIElementCreateApplication(center.processIdentifier)
        let app = cleanName(appName)
        var best: [String]?

        func texts(in element: AXUIElement, depth: Int) -> [String] {
            guard depth < 8 else { return [] }
            var result: [String] = []
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == "AXStaticText", let value = attribute(element, kAXValueAttribute) as? String, !value.isEmpty {
                result.append(value)
            }
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                result += texts(in: child, depth: depth + 1)
            }
            return result
        }

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 14 else { return }
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == "AXGroup" || role == "AXButton" {
                var found = texts(in: element, depth: 0)
                if let description = attribute(element, kAXDescriptionAttribute) as? String, !description.isEmpty {
                    found.append(contentsOf: description.components(separatedBy: ", "))
                }
                if found.contains(where: { cleanName($0) == app }), found.count >= 2,
                   best == nil || found.count < best!.count {
                    best = found
                }
            }
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)

        guard let found = best else { return nil }
        // Programmname und Zeitangaben („jetzt“, „vor 1 Min.“, „12:30“) weglassen, doppelte Zeilen entfernen
        let time = try? NSRegularExpression(pattern: #"^(jetzt|now|gerade eben|vor .*|\d+\s?(min|std|h|m)\.?.*|\d{1,2}:\d{2}.*)$"#,
                                            options: [.caseInsensitive])
        var lines: [String] = []
        for line in found {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, cleanName(trimmed) != app, !lines.contains(trimmed) else { continue }
            if let time, time.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { continue }
            lines.append(trimmed)
        }
        guard let title = lines.first else { return nil }
        return (title, lines.dropFirst().joined(separator: " "))
    }

    // MARK: 3. Dock (Bedienungshilfen)

    private struct DockEntry {
        var title: String
        var url: URL?
        var label: String
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func dockLabels() -> [DockEntry] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let children = attribute(app, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        var entries: [DockEntry] = []
        for list in children {
            guard (attribute(list, kAXRoleAttribute) as? String) == "AXList",
                  let items = attribute(list, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            for item in items {
                guard let label = attribute(item, "AXStatusLabel") as? String else { continue }
                let title = (attribute(item, kAXTitleAttribute) as? String) ?? ""
                let url = attribute(item, kAXURLAttribute) as? URL
                entries.append(DockEntry(title: title, url: url, label: label))
            }
        }
        return entries
    }
}

// MARK: - Aufleuchten bei neuen Nachrichten

/// Lässt ein Icon sanft pulsieren, sobald sein Zähler steigt.
struct BadgePulse: ViewModifier {
    let count: Int
    @ObservedObject private var alerts = AlertState.shared
    @State private var glowing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(glowing ? 1.12 : 1)
            .shadow(color: Color(hex: 0xFF3B30).opacity(glowing ? 0.75 : 0), radius: glowing ? 7 : 0)
            .onChange(of: count) { old, new in
                guard new > old, alerts.pulse, !alerts.quiet else { return }
                withAnimation(.easeInOut(duration: 0.38).repeatCount(4, autoreverses: true)) {
                    glowing = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                    withAnimation(.easeOut(duration: 0.3)) { glowing = false }
                }
            }
    }
}

extension View {
    func badgePulse(_ count: Int) -> some View { modifier(BadgePulse(count: count)) }
}

// MARK: - Mini-Vorschau einer Seite

/// Bilder für die Mini-Vorschau: laufende App-Fenster live, sonst zwischengespeichert.
final class PreviewStore: ObservableObject {
    static let shared = PreviewStore()

    @Published private(set) var images: [UUID: NSImage] = [:]
    @Published private(set) var loading: Set<UUID> = []
    private var dates: [UUID: Date] = [:]
    private let directory: URL
    private var renderer: OffscreenRenderer?
    private var queue: [LinkItem] = []

    private init() {
        directory = ConfigStore.supportDirectory.appendingPathComponent("Previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".png") }

    /// Programme haben keine Vorschau.
    static func supports(_ item: LinkItem) -> Bool {
        guard let url = item.url else { return false }
        if url.isFileURL {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return exists && url.pathExtension.lowercased() != "app"
        }
        return true
    }

    @MainActor
    func request(_ item: LinkItem) {
        guard let url = item.url else { return }
        loadFromDisk(item.id)

        if url.isFileURL {
            guard images[item.id] == nil else { return }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 300, height: 190),
                                                       scale: 2, representationTypes: .thumbnail)
            loading.insert(item.id)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                let image = representation?.nsImage
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.loading.remove(item.id)
                        if let image { self.images[item.id] = image }
                    }
                }
            }
            return
        }

        // Läuft die Seite schon im App-Fenster (sichtbar oder im Hintergrund)? → aktuelles Bild
        if let webView = WebAppManager.shared.webView(for: item.id) {
            if webView.window?.isVisible == true || images[item.id] == nil {
                snapshot(of: webView, for: item.id)
            }
            return
        }
        // Messenger nie zusätzlich unsichtbar laden (würde die laufende Sitzung stören)
        if item.isMessenger { return }
        if let date = dates[item.id], Date().timeIntervalSince(date) < 30 * 60 { return }
        if !queue.contains(where: { $0.id == item.id }) { queue.append(item) }
        renderNext()
    }

    /// Bild eines App-Fensters festhalten (z. B. bevor es ausgeblendet wird).
    @MainActor
    func snapshot(of webView: WKWebView, for id: UUID) {
        guard webView.bounds.width > 0 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 640
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            MainActor.assumeIsolated {
                guard let self, let image else { return }
                self.store(image, for: id)
            }
        }
    }

    @MainActor
    private func store(_ image: NSImage, for id: UUID) {
        images[id] = image
        dates[id] = Date()
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: file(for: id), options: .atomic)
        }
    }

    @MainActor
    private func loadFromDisk(_ id: UUID) {
        guard images[id] == nil else { return }
        let url = file(for: id)
        guard let image = NSImage(contentsOf: url) else { return }
        images[id] = image
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        dates[id] = date ?? .distantPast
    }

    @MainActor
    func forget(_ id: UUID) {
        images[id] = nil
        dates[id] = nil
        try? FileManager.default.removeItem(at: file(for: id))
    }

    @MainActor
    private func renderNext() {
        guard renderer == nil, !queue.isEmpty else { return }
        let item = queue.removeFirst()
        guard let url = item.url else { return renderNext() }
        loading.insert(item.id)
        let id = item.id
        renderer = OffscreenRenderer(url: url) { [weak self] image in
            guard let self else { return }
            self.loading.remove(id)
            if let image { self.store(image, for: id) }
            self.renderer = nil
            self.renderNext()
        }
    }
}

/// Lädt eine Seite unsichtbar (außerhalb des Bildschirms) und macht ein Bild davon.
@MainActor
final class OffscreenRenderer: NSObject, WKNavigationDelegate {
    private let window: NSWindow
    private let webView: WKWebView
    private var completion: (@MainActor (NSImage?) -> Void)?
    private var finished = false

    init(url: URL, completion: @escaping @MainActor (NSImage?) -> Void) {
        self.completion = completion
        let frame = NSRect(x: -30000, y: -30000, width: 1280, height: 800)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // gleiche Logins wie die App-Fenster
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: configuration)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.contentView = webView
        window.setFrameOrigin(frame.origin)
        window.orderBack(nil)
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
        // Spätestens nach 15 Sekunden aufgeben
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.capture()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // kurz warten, bis Bilder und Schriften da sind
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.capture()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    private func capture() {
        guard !finished else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 640
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            MainActor.assumeIsolated { self?.finish(image) }
        }
    }

    private func finish(_ image: NSImage?) {
        guard !finished else { return }
        finished = true
        webView.stopLoading()
        webView.navigationDelegate = nil
        window.orderOut(nil)
        window.contentView = nil
        let completion = completion
        self.completion = nil
        completion?(image)
    }
}

/// Inhalt des Vorschau-Fensters.
struct LinkPreviewView: View {
    let item: LinkItem
    let theme: ColorTheme
    @ObservedObject private var previews = PreviewStore.shared
    @ObservedObject private var badges = BadgeStore.shared
    @ObservedObject private var alerts = AlertState.shared
    @Environment(\.colorScheme) private var scheme

    static let width: CGFloat = 320
    static let imageHeight: CGFloat = 186

    static func height(hasMessage: Bool) -> CGFloat {
        12 + 34 + 8 + imageHeight + (hasMessage ? 58 : 0) + 12 + 8
    }

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        let message = alerts.messagePreview && !alerts.quiet ? badges.message(for: item) : nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                FaviconView(item: item, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Text(item.isLocal ? (item.url?.lastPathComponent ?? "") : LinkItem.prettyHost(item.host ?? ""))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                BadgeView(count: badges.count(for: item))
            }
            .frame(height: 34)

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.5))
                if let image = previews.images[item.id] {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Self.width - 24, height: Self.imageHeight, alignment: .top)
                        .clipped()
                } else if previews.loading.contains(item.id) {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Vorschau wird geladen …")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                    }
                } else {
                    VStack(spacing: 8) {
                        FaviconView(item: item, size: 44)
                        Text(item.isMessenger ? "Vorschau erscheint, sobald die Seite einmal geöffnet war"
                                              : "Keine Vorschau verfügbar")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .frame(width: Self.width - 24, height: Self.imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(palette.border, lineWidth: 1))

            if let message {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Text(message.body.isEmpty ? "Neue Nachricht" : message.body)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .frame(width: Self.width - 24, height: 50, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(scheme == .dark ? 0.16 : 0.42))
                )
            }
        }
        .padding(12)
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.panelFill(gradient: true))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(4)
        .environment(\.colorTheme, theme)
    }
}

/// Kleines Fenster mit der Mini-Vorschau – erscheint nach längerem Verweilen auf einem Link.
@MainActor
final class LinkPreviewController {
    static let shared = LinkPreviewController()
    private let panel: NSPanel
    private(set) var itemID: UUID?

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    var isVisible: Bool { panel.isVisible }

    /// - Parameters:
    ///   - beside: Fläche, neben der die Vorschau erscheint (Leiste bzw. Ordner-Fenster)
    ///   - anchor: Element, auf dessen Höhe sie ausgerichtet wird
    func show(_ item: LinkItem, beside: NSRect, anchor: NSRect, edge: ScreenEdge, theme: ColorTheme) {
        PreviewStore.shared.request(item)
        itemID = item.id
        let hasMessage = AlertState.shared.messagePreview && BadgeStore.shared.message(for: item) != nil
        let size = NSSize(width: LinkPreviewView.width + 8, height: LinkPreviewView.height(hasMessage: hasMessage))
        let host = NSHostingView(rootView: LinkPreviewView(item: item, theme: theme))
        host.sizingOptions = []
        panel.contentView = host

        let gap: CGFloat = 6
        var origin = NSPoint.zero
        switch edge {
        case .left: origin = NSPoint(x: beside.maxX + gap, y: anchor.midY - size.height / 2)
        case .right: origin = NSPoint(x: beside.minX - gap - size.width, y: anchor.midY - size.height / 2)
        case .top: origin = NSPoint(x: anchor.midX - size.width / 2, y: beside.minY - gap - size.height)
        case .bottom: origin = NSPoint(x: anchor.midX - size.width / 2, y: beside.maxY + gap)
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let area = screen.visibleFrame.insetBy(dx: 6, dy: 6)
            origin.x = min(max(origin.x, area.minX), area.maxX - size.width)
            origin.y = min(max(origin.y, area.minY), area.maxY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard itemID != nil || panel.isVisible else { return }
        itemID = nil
        panel.orderOut(nil)
    }
}

// MARK: - Nachricht kurz neben dem Icon

struct MessageToastView: View {
    let title: String
    let message: String
    let theme: ColorTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color(hex: 0xFF3B30))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(message.isEmpty ? "Neue Nachricht" : message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 240, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.surface)
        )
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.panelFill(gradient: true))
        )
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(Color.white.opacity(scheme == .dark ? 0.22 : 0.7), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        .padding(6)
        .fixedSize()
    }
}

/// Blendet eine neue Nachricht für ein paar Sekunden neben dem Icon ein.
@MainActor
final class MessageToastController {
    static let shared = MessageToastController()
    private let panel: NSPanel
    private let measure = NSHostingController(rootView: MessageToastView(title: "", message: "", theme: .sage))
    private var hideWork: DispatchWorkItem?

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    func show(title: String, message: String, beside bar: NSRect, anchor: NSRect, edge: ScreenEdge,
              theme: ColorTheme, duration: Double) {
        let view = MessageToastView(title: title, message: message, theme: theme)
        measure.rootView = view
        let measured = measure.sizeThatFits(in: CGSize(width: 400, height: 300))
        let size = NSSize(width: ceil(measured.width), height: ceil(measured.height))
        guard size.width > 0, size.height > 0 else { return }
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host

        let gap: CGFloat = 2
        var origin = NSPoint.zero
        switch edge {
        case .left: origin = NSPoint(x: bar.maxX + gap, y: anchor.midY - size.height / 2)
        case .right: origin = NSPoint(x: bar.minX - gap - size.width, y: anchor.midY - size.height / 2)
        case .top: origin = NSPoint(x: anchor.midX - size.width / 2, y: bar.minY - gap - size.height)
        case .bottom: origin = NSPoint(x: anchor.midX - size.width / 2, y: bar.maxY + gap)
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let area = screen.visibleFrame.insetBy(dx: 4, dy: 4)
            origin.x = min(max(origin.x, area.minX), area.maxX - size.width)
            origin.y = min(max(origin.y, area.minY), area.maxY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.panel.animator().alphaValue = 1
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideWork == nil else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}

/// Startet die Sidebar neu (z. B. damit eine neue Freigabe greift).
@MainActor
enum AppRelaunch {
    static func run() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$1\"", "sidebar-restart", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
