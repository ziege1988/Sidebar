import AppKit

// MARK: - Server beim Start verbinden
//
// Programme wie Photoshop listen einen Netzwerk-Server (NAS) erst, wenn er einmal verbunden war. Einträge mit
// „Beim Start automatisch verbinden“ werden deshalb kurz nach dem Start der Sidebar verbunden – ohne ein
// Finder-Fenster zu öffnen. Falls das Netzwerk noch nicht da ist, wird es nach einer Weile noch einmal versucht.
// Fragt der Server nach dem Passwort (z. B. nach der Änderung alle zwei Wochen), erscheint das normale
// macOS-Fenster – mit „Im Schlüsselbund sichern“ passiert das dann nur einmal.

enum ServerTarget {
    /// Server-Adresse eines Eintrags (smb://…): direkt, aus einer Internetadress-Datei oder aus einem Alias
    case address(URL)
    /// Alias auf den (schon verbundenen oder zu verbindenden) Server
    case alias(URL)
    case none
}

@MainActor
final class ServerMounter {
    static let shared = ServerMounter()

    /// Manuell („Nur verbinden“): ein Versuch, ohne Wiederholung
    func connectNow(_ item: LinkItem, store: ConfigStore) {
        Task { _ = await Self.connect(item) }
    }

    // MARK: Verbinden

    enum Result { case connected, cancelled, failed }

    /// Welche Server-Adresse steckt hinter dem Eintrag?
    static func target(for item: LinkItem) -> ServerTarget {
        guard let url = item.url else { return .none }
        if LinkOpener.isServerAddress(url) { return .address(url) }
        guard url.isFileURL else { return .none }
        let ext = url.pathExtension.lowercased()
        if ["inetloc", "smbloc", "afploc", "ftploc", "nfsloc", "vncloc"].contains(ext) {
            if let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let text = plist["URL"] as? String, let target = URL(string: text), LinkOpener.isServerAddress(target) {
                return .address(target)
            }
            return .none
        }
        if LinkOpener.isFinderAlias(url) { return .alias(url) }
        return .none
    }

    /// Ist der Server schon verbunden? (Vergleich mit den eingehängten Laufwerken)
    nonisolated static func isMounted(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let share = url.pathComponents.dropFirst().first?.lowercased() ?? ""
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeURLForRemountingKey],
                                                            options: []) ?? []
        for volume in volumes {
            guard let remount = (try? volume.resourceValues(forKeys: [.volumeURLForRemountingKey]))?.volumeURLForRemounting,
                  let remoteHost = remount.host?.lowercased() else { continue }
            let remoteShare = remount.pathComponents.dropFirst().first?.lowercased() ?? ""
            let sameHost = remoteHost == host || remoteHost.hasPrefix(host + ".") || host.hasPrefix(remoteHost + ".")
            if sameHost && (share.isEmpty || remoteShare == share) { return true }
        }
        return false
    }

    /// Verbindet im Hintergrund (das Passwortfenster von macOS kann dabei erscheinen).
    static func connect(_ item: LinkItem) async -> Result {
        switch target(for: item) {
        case .none:
            return .failed
        case .alias(let alias):
            return await Task.detached {
                // Alias wie der Finder auflösen (mit Oberfläche): verbindet den Server
                guard let resolved = try? URL(resolvingAliasFileAt: alias, options: []) else { return Result.failed }
                return FileManager.default.fileExists(atPath: resolved.path) ? Result.connected : Result.failed
            }.value
        case .address(let url):
            return await Task.detached { mount(url) }.value
        }
    }

    /// `mount volume` (AppleScript, läuft in osascript – ohne Fremdsteuerung anderer Programme)
    nonisolated private static func mount(_ url: URL) -> Result {
        if isMounted(url) { return .connected }
        let escaped = url.absoluteString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "mount volume \"\(escaped)\""]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        do { try process.run() } catch { return .failed }
        process.waitUntilExit()
        if process.terminationStatus == 0 { return .connected }
        let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // -128: Passwortfenster abgebrochen → nicht erneut fragen
        if text.contains("-128") || text.localizedCaseInsensitiveContains("canceled") { return .cancelled }
        return isMounted(url) ? .connected : .failed
    }

    /// Gibt es für den Eintrag etwas zu verbinden? (für das Rechtsklick-Menü)
    static func canConnect(_ item: LinkItem) -> Bool {
        if case .none = target(for: item) { return false }
        return true
    }
}


// MARK: - Beim Start der Sidebar ausführen
//
// Pro Eintrag einstellbar („Beim Start der Sidebar“): nichts tun, einen Server verbinden (ohne Fenster) oder öffnen
// (Programm, Ordner, Link). Etwa 8 Sekunden nach dem Start, die Einträge nacheinander. Ist das Ziel noch nicht da
// (Netzwerk, NAS), versucht es die Sidebar später noch bis zu dreimal. Nach einem Update-Neustart werden Einträge mit
// „Öffnen“ nicht noch einmal geöffnet.

@MainActor
final class StartupRunner {
    static let shared = StartupRunner()
    private var started = false
    private static let delays: [Double] = [8, 25, 60, 120]

    /// Alle Einträge, die beim Start etwas tun sollen
    static func startItems(in config: SidebarConfig) -> [LinkItem] {
        (config.favorites + config.groups.flatMap(\.items)).filter { $0.startMode != .none }
    }

    func start(store: ConfigStore) {
        guard !started else { return }
        started = true
        let afterUpdate = FileManager.default.fileExists(atPath: UpdateLog.pendingURL.path)
        for (index, item) in Self.startItems(in: store.config).enumerated() {
            if afterUpdate && item.startMode == .open { continue }
            attempt(id: item.id, store: store, index: 0, stagger: Double(index) * 1.5)
        }
    }

    private func attempt(id: UUID, store: ConfigStore, index: Int, stagger: Double = 0) {
        guard index < Self.delays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delays[index] + (index == 0 ? stagger : 0)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let item = store.item(id: id) else { return }
                switch item.startMode {
                case .none:
                    return
                case .connect:
                    Task { @MainActor in
                        if await ServerMounter.connect(item) == .failed {
                            self.attempt(id: id, store: store, index: index + 1)
                        }
                    }
                case .open:
                    if !Self.openQuietly(item, settings: store.config.settings) {
                        self.attempt(id: id, store: store, index: index + 1)
                    }
                }
            }
        }
    }

    /// `true`: geöffnet (oder nichts zu tun). `false`: das Ziel ist noch nicht da (z. B. Laufwerk nicht verbunden) –
    /// dann später noch einmal, ohne Fehlermeldung.
    static func openQuietly(_ item: LinkItem, settings: SidebarSettings) -> Bool {
        guard let url = item.url else { return true }
        if url.isFileURL, !LinkOpener.isFinderAlias(url), !LinkOpener.isServerShortcut(url),
           !FileManager.default.fileExists(atPath: url.path) {
            return false
        }
        LinkOpener.open(item, mode: nil, settings: settings)
        return true
    }
}
