import AppKit
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
/// Nutzt das macOS-Werkzeug `lsappinfo` – ohne Sonderrechte. Das ist kein offizieller Weg von Apple,
/// funktioniert aber seit vielen macOS-Versionen.
final class DockBadgeWatcher {
    static let shared = DockBadgeWatcher()
    private var bundleIDs: [String] = []
    private var timer: Timer?
    private let queue = DispatchQueue(label: "sidebar.dockbadges", qos: .utility)
    private var running = false

    @MainActor
    func update(items: [LinkItem], enabled: Bool) {
        let ids = enabled ? Array(Set(items.compactMap(\.appBundleID))).sorted() : []
        let removed = Set(bundleIDs).subtracting(ids)
        bundleIDs = ids
        for id in removed { BadgeStore.shared.setApp(0, bundleID: id) }
        if ids.isEmpty {
            timer?.invalidate()
            timer = nil
            return
        }
        if timer == nil {
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        poll()
    }

    private func poll() {
        guard !running else { return }
        running = true
        let ids = bundleIDs
        // Nur laufende Programme abfragen (andere haben keine Zahl)
        var targets: [(String, String, pid_t)] = []
        for id in ids {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                targets.append((id, app.localizedName ?? id, app.processIdentifier))
            }
        }
        let notRunning = Set(ids).subtracting(targets.map(\.0))
        queue.async { [weak self] in
            var results: [String: Int] = [:]
            for (id, name, pid) in targets {
                results[id] = Self.statusCount(name: name, pid: pid)
            }
            for id in notRunning { results[id] = 0 }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for (id, count) in results { BadgeStore.shared.setApp(count, bundleID: id) }
                }
                self?.running = false
            }
        }
    }

    private static func statusCount(name: String, pid: pid_t) -> Int {
        var output = run(["info", "-only", "StatusLabel", name])
        if !output.contains("StatusLabel") {
            output = run(["info", "-only", "StatusLabel", "pid=\(pid)"])
        }
        return parse(output)
    }

    static func parse(_ output: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #""label"\s*=\s*"([^"]*)""#),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return 0 }
        let label = output[range].trimmingCharacters(in: .whitespaces)
        if label.isEmpty { return 0 }
        let digits = label.filter(\.isNumber)
        // Kein Zahlenwert (z. B. „•“ oder „!“) → als 1 anzeigen
        return Int(digits) ?? 1
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
