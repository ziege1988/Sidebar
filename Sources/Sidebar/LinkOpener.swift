import AppKit

@MainActor
enum LinkOpener {
    static func open(_ item: LinkItem, mode: OpenMode?, settings: SidebarSettings) {
        guard let url = item.url else {
            NSSound.beep()
            return
        }
        // Server-Adressen (smb://, afp:// …): gehören dem System – der Finder verbindet, fragt das Passwort ab
        // und öffnet den Ordner. (Nicht im Browser-Fenster: dort passiert damit nichts.)
        if isServerAddress(url) {
            openWithSystem(url, name: item.displayName)
            return
        }
        // Programm, Datei oder Ordner auf dem Mac → mit macOS öffnen
        if url.isFileURL {
            if isServerShortcut(url) {
                // Verknüpfung zu einem Server (Alias, .inetloc …): wie ein Doppelklick im Finder – verbindet bei Bedarf
                // erst den Server (mit Passwortabfrage) und öffnet ihn dann
                openServerShortcut(url, name: item.displayName)
            } else if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
            } else {
                let alert = NSAlert()
                alert.messageText = "„\(item.displayName)“ wurde nicht gefunden"
                let onServer = url.path.hasPrefix("/Volumes/")
                alert.informativeText = onServer
                    ? "Das Laufwerk „\(url.pathComponents.dropFirst(2).first ?? "")“ ist nicht verbunden. Trage als Adresse besser den Server ein (z. B. smb://server/freigabe) – dann verbindet die Sidebar ihn selbst."
                    : "Das Programm bzw. die Datei liegt nicht mehr unter \(url.path). Wurde sie verschoben oder gelöscht?"
                alert.addButton(withTitle: "OK")
                NSApp.activate()
                alert.runModal()
            }
            return
        }
        // Im Hintergrund laufende Seiten (z. B. WhatsApp Web) im App-Fenster öffnen – dort ist man angemeldet
        let background = item.runsInBackground(autoMessengers: settings.messengerBackground)
        // Geöffnet = gesehen: Zähler und letzte Nachricht zurücksetzen – egal, wo die Seite aufgeht
        WebAppManager.shared.markSeen(item)
        switch mode ?? item.openMode ?? (background ? .appWindow : settings.defaultOpenMode) {
        case .defaultBrowser:
            NSWorkspace.shared.open(url)
        case .appWindow:
            WebAppManager.shared.open(item: item, url: url)
        case .chromiumApp:
            openChromiumApp(url: url, bundleID: settings.chromiumBundleID)
        }
    }

    // MARK: Server (NAS)

    /// Adressen, die das System öffnet (Netzwerk-Server u. a.) – nie im eingebauten Browser-Fenster
    private static let serverSchemes: Set<String> = ["smb", "cifs", "afp", "nfs", "ftp", "sftp", "vnc", "webdav", "webdavs"]

    static func isServerAddress(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return serverSchemes.contains(scheme)
    }

    /// Verknüpfungen, die der Finder auflösen muss (Alias auf einen Server, Internetadress-Dateien)
    static func isServerShortcut(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        if ["inetloc", "smbloc", "afploc", "ftploc", "nfsloc", "vncloc"].contains(ext) { return true }
        return (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true
    }

    /// Mit dem System öffnen und bei Fehlern eine verständliche Meldung zeigen
    private static func openWithSystem(_ url: URL, name: String) {
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor in showOpenError(name: name, detail: error.localizedDescription) }
        }
    }

    /// Wie ein Doppelklick im Finder: Alias auflösen (verbindet den Server, fragt ggf. das Passwort) und öffnen.
    /// Die Auflösung kann beim Verbinden dauern, deshalb im Hintergrund.
    private static func openServerShortcut(_ url: URL, name: String) {
        Task.detached {
            // Zuerst wie der Finder auflösen (mit Oberfläche, also mit Passwortfenster)
            let resolved = try? URL(resolvingAliasFileAt: url, options: [])
            await MainActor.run {
                if let resolved, resolved != url, FileManager.default.fileExists(atPath: resolved.path) {
                    NSWorkspace.shared.open(resolved)
                } else {
                    // Sonst den Finder selbst bitten – er öffnet die Datei wie bei einem Doppelklick
                    openViaFinder(url, name: name)
                }
            }
        }
    }

    private static func openViaFinder(_ url: URL, name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Finder", url.path]
        process.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                Task { @MainActor in NSWorkspace.shared.open(url) }
            }
        }
        do { try process.run() } catch { NSWorkspace.shared.open(url) }
    }

    private static func showOpenError(name: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = "„\(name)“ konnte nicht geöffnet werden"
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    /// Öffnet die Seite als eigenständiges App-Fenster (ohne Tabs/Adressleiste)
    /// in Chrome/Edge/Brave … – mit den dort vorhandenen Logins.
    static func openChromiumApp(url: URL, bundleID: String) {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
            NSWorkspace.shared.open(url)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", "-b", bundleID, "--args", "--app=\(url.absoluteString)"]
        process.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                Task { @MainActor in NSWorkspace.shared.open(url) }
            }
        }
        do {
            try process.run()
        } catch {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Blendet das Dock-Symbol ein, solange Fenster (Einstellungen, App-Fenster) offen sind,
/// damit sie per ⌘-Tab erreichbar sind. Ohne Fenster läuft die App unsichtbar im Hintergrund.
@MainActor
enum DockPresence {
    static func update() {
        let needsDock = NSApp.windows.contains { window in
            !(window is NSPanel)
                && window.styleMask.contains(.titled)
                && (window.isVisible || window.isMiniaturized)
        }
        let desired: NSApplication.ActivationPolicy = needsDock ? .regular : .accessory
        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
        }
    }

    static func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        update()
        NSApp.activate()
        window.orderFrontRegardless()
    }
}
