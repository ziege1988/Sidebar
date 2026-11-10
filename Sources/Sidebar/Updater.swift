import AppKit
import Combine
import Foundation

struct ReleaseInfo: Equatable {
    let version: String
    let notes: String
    let downloadURL: URL
    let pageURL: URL
}

enum UpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Prüft GitHub-Releases auf eine neuere Version und installiert sie per Klick.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repository = "ziege1988/Sidebar"
    static let assetName = "Sidebar.zip"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastCheck: Date?

    private var timer: Timer?
    private var promptedVersion: String?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var availableRelease: ReleaseInfo? {
        if case .available(let release) = status { return release }
        return nil
    }

    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    // MARK: - Automatische Prüfung

    /// Prüft kurz nach dem Start und danach alle 6 Stunden.
    func startAutomaticChecks(enabled: @escaping @MainActor () -> Bool) {
        timer?.invalidate()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, enabled() else { return }
            await self.check(userInitiated: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, enabled() else { return }
                await self.check(userInitiated: false)
            }
        }
    }

    // MARK: - Prüfen

    /// - Parameter userInitiated: `true`, wenn der Nutzer selbst geklickt hat
    ///   (dann gibt es auch eine Rückmeldung „Du bist aktuell“ bzw. eine Fehlermeldung).
    func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        status = .checking
        do {
            let release = try await fetchLatestRelease()
            lastCheck = Date()
            if Self.isNewer(release.version, than: currentVersion) {
                status = .available(release)
                if userInitiated || promptedVersion != release.version {
                    promptedVersion = release.version
                    promptToInstall(release)
                }
            } else {
                status = .upToDate
                if userInitiated {
                    showInfo("Sidebar ist aktuell", "Du verwendest die neueste Version (\(currentVersion)).")
                }
            }
        } catch {
            status = .failed(error.localizedDescription)
            if userInitiated {
                showInfo("Update-Prüfung fehlgeschlagen", error.localizedDescription)
            }
        }
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else {
            throw UpdateError.message("Ungültige Update-Adresse.")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sidebar-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.message("Keine Antwort vom Update-Server.")
        }
        if http.statusCode == 404 {
            throw UpdateError.message("Es wurde noch keine Version veröffentlicht.")
        }
        guard http.statusCode == 200 else {
            throw UpdateError.message("Update-Server antwortet mit Fehler \(http.statusCode).")
        }

        struct GitHubRelease: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadUrl: URL
            }
            let tagName: String
            let body: String?
            let htmlUrl: URL
            let assets: [Asset]
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name == Self.assetName }) else {
            throw UpdateError.message("Die neueste Version enthält keine App-Datei.")
        }
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        return ReleaseInfo(version: version,
                           notes: release.body ?? "",
                           downloadURL: asset.browserDownloadUrl,
                           pageURL: release.htmlUrl)
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    // MARK: - Dialoge

    func promptToInstall(_ release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "Sidebar \(release.version) ist verfügbar"
        var text = "Installiert ist Version \(currentVersion)."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            text += "\n\nNeu:\n" + String(notes.prefix(800))
        }
        text += "\n\nDie App startet dabei kurz neu. Deine Gruppen und Links bleiben erhalten."
        alert.informativeText = text
        alert.addButton(withTitle: "Jetzt aktualisieren")
        alert.addButton(withTitle: "Später")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await self.install(release) }
        }
    }

    private func showInfo(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    // MARK: - Installieren

    func install(_ release: ReleaseInfo) async {
        guard !isBusy else { return }
        let fm = FileManager.default
        let target = Bundle.main.bundleURL
        let staged = target.deletingLastPathComponent().appendingPathComponent("Sidebar.app.update")

        do {
            guard target.pathExtension == "app" else {
                throw UpdateError.message("Updates funktionieren nur mit der installierten App (Sidebar.app).")
            }
            guard fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UpdateError.message("Keine Schreibrechte im Ordner „\(target.deletingLastPathComponent().path)“.")
            }

            // 1. Herunterladen
            status = .downloading
            let work = fm.temporaryDirectory.appendingPathComponent("SidebarUpdate-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let (downloaded, response) = try await URLSession.shared.download(from: release.downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.message("Download fehlgeschlagen.")
            }
            let zip = work.appendingPathComponent(Self.assetName)
            try fm.moveItem(at: downloaded, to: zip)

            // 2. Entpacken und prüfen
            status = .installing
            try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent("Sidebar.app")
            guard let bundle = Bundle(url: newApp),
                  bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError.message("Die heruntergeladene Datei ist keine gültige Sidebar-App.")
            }
            try await Self.run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])
            try? await Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

            // 3. Neben die alte App kopieren (die alte bleibt bis zum Tausch unangetastet)
            try? fm.removeItem(at: staged)
            try await Self.run("/usr/bin/ditto", [newApp.path, staged.path])

            // 4. Nach dem Beenden austauschen und neu starten
            try relaunch(replacing: target, with: staged, cleanup: work)
        } catch {
            try? fm.removeItem(at: staged)
            status = .failed(error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = "Update fehlgeschlagen"
            alert.informativeText = error.localizedDescription + "\n\nDu kannst die neue Version auch manuell von der Download-Seite laden."
            alert.addButton(withTitle: "Download-Seite öffnen")
            alert.addButton(withTitle: "Schließen")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    /// Startet ein kleines Hilfsskript, das wartet, bis die App beendet ist,
    /// dann die App austauscht und neu öffnet. Schlägt der Tausch fehl, bleibt die alte Version.
    private func relaunch(replacing target: URL, with staged: URL, cleanup: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        OLD="$1.old"
        rm -rf "$OLD"
        if mv "$1" "$OLD"; then
          if mv "$2" "$1"; then
            rm -rf "$OLD"
          else
            mv "$OLD" "$1"
          fi
        fi
        rm -rf "$2" "$3"
        /usr/bin/open "$1"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sidebar-update", target.path, staged.path, cleanup.path]
        try process.run()
        // Sofort und sicher beenden: ohne Rüdigers Abschied, und falls das Beenden aus irgendeinem Grund
        // hängen bleibt, nach 4 Sekunden hart – sonst wartet das Hilfsskript ewig („wird installiert“).
        Self.restarting = true
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) { exit(0) }
        NSApp.terminate(nil)
    }

    /// Die App wird gerade für ein Update beendet (kein Abschied, kein Warten)
    nonisolated(unsafe) static var restarting = false

    nonisolated private static func run(_ path: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            // Bleibt ein Schritt hängen, nach 2 Minuten abbrechen – dann gibt es eine Fehlermeldung statt Stillstand
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
                if process.isRunning { process.terminate() }
            }
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let tool = (path as NSString).lastPathComponent
                    continuation.resume(throwing: UpdateError.message("\(tool) ist fehlgeschlagen (Code \(proc.terminationStatus))."))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
