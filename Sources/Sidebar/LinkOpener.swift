import AppKit

@MainActor
enum LinkOpener {
    static func open(_ item: LinkItem, mode: OpenMode?, settings: SidebarSettings) {
        guard let url = item.url else {
            NSSound.beep()
            return
        }
        // Programm, Datei oder Ordner auf dem Mac → mit macOS öffnen
        if url.isFileURL {
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
            } else {
                let alert = NSAlert()
                alert.messageText = "„\(item.displayName)“ wurde nicht gefunden"
                alert.informativeText = "Das Programm bzw. die Datei liegt nicht mehr unter \(url.path). Wurde sie verschoben oder gelöscht?"
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
