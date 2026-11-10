import AppKit
import CryptoKit
import Foundation
import IOKit
import Security
import SwiftUI

// MARK: - Postfach (Microsoft 365 / Outlook) direkt abfragen

/// Fragt den Posteingang über die offizielle Microsoft-Schnittstelle (Microsoft Graph) ab:
/// echte Zahl ungelesener Mails am Icon und eine Einblendung bei jeder neuen Mail.
/// Anmeldung per Gerätecode auf der Microsoft-Seite – die Sidebar sieht kein Passwort.
/// Nur Leserecht (Mail.Read). Der Anmeldeschlüssel liegt im macOS-Schlüsselbund.
@MainActor
final class MailWatcher: ObservableObject {
    static let shared = MailWatcher()
    /// Der alte Schlüsselbund-Eintrag wurde schon (im Hintergrund) abgefragt
    private var legacyChecked = false

    struct Mail: Identifiable, Equatable {
        let id: String
        let sender: String
        let subject: String
        let received: Date
    }

    enum Phase: Equatable {
        case signedOut
        /// Code auf der Microsoft-Seite eingeben
        case signingIn(code: String, url: URL)
        case signedIn
        case failed(String)
    }

    @Published private(set) var phase: Phase = .signedOut
    @Published private(set) var account: String?
    @Published private(set) var unread = 0
    /// Die neuesten ungelesenen Mails (für die Vorschau)
    @Published private(set) var recent: [Mail] = []
    @Published private(set) var lastCheck: Date?
    /// Letzter Fehler beim Abfragen (z. B. offline) – Anmeldung bleibt bestehen
    @Published private(set) var lastError: String?

    private var settings = SidebarSettings()
    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var seen: Set<String> = []
    private var primed = false
    private var timer: Timer?
    private var signInTask: Task<Void, Never>?
    private var polling = false

    private static let scope = "offline_access User.Read Mail.Read"

    /// Icon in der Sidebar, an dem Zahl und Einblendung erscheinen
    var itemID: UUID? { settings.mailEnabled ? settings.mailItemID : nil }

    private var clientID: String { settings.mailClientID.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tenant: String {
        let id = settings.mailTenantID.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "organizations" : id
    }

    // MARK: Einstellungen

    func apply(_ new: SidebarSettings) {
        let oldItem = itemID
        let accountChanged = new.mailClientID != settings.mailClientID || new.mailTenantID != settings.mailTenantID
        settings = new
        if accountChanged { accessToken = nil }
        if let oldItem, oldItem != itemID { BadgeStore.shared.setExtra(0, itemID: oldItem) }

        guard new.mailEnabled else {
            stopTimer()
            if let oldItem { BadgeStore.shared.setExtra(0, itemID: oldItem) }
            return
        }
        if phase == .signedOut, MailKeychain.read() != nil {
            phase = .signedIn
        } else if phase == .signedOut, !legacyChecked {
            // Alter Eintrag im Schlüsselbund? Einmal im Hintergrund übernehmen (blockiert nie die Oberfläche)
            legacyChecked = true
            MailKeychain.migrateLegacy { found in
                guard found else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let watcher = MailWatcher.shared
                        watcher.apply(watcher.settings)
                    }
                }
            }
        }
        if phase == .signedIn {
            startTimer()
            if let itemID { BadgeStore.shared.setExtra(unread, itemID: itemID) }
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        checkNow()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Anmelden (Gerätecode)

    func signIn() {
        guard !clientID.isEmpty else {
            phase = .failed("Bitte zuerst die Anwendungs-ID (Client-ID) eintragen.")
            return
        }
        signInTask?.cancel()
        signInTask = Task { [weak self] in
            await self?.runDeviceCodeFlow()
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        phase = MailKeychain.read() != nil ? .signedIn : .signedOut
    }

    func signOut() {
        signInTask?.cancel()
        stopTimer()
        MailKeychain.delete()
        accessToken = nil
        account = nil
        unread = 0
        recent = []
        seen = []
        primed = false
        lastCheck = nil
        lastError = nil
        if let itemID { BadgeStore.shared.setExtra(0, itemID: itemID) }
        phase = .signedOut
    }

    private func runDeviceCodeFlow() async {
        let base = "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0"
        do {
            let start = try await Self.post("\(base)/devicecode", ["client_id": clientID, "scope": Self.scope])
            guard let deviceCode = start["device_code"] as? String,
                  let userCode = start["user_code"] as? String,
                  let uriString = start["verification_uri"] as? String,
                  let uri = URL(string: uriString) else {
                throw MailError.message(Self.describe(start) ?? "Anmeldung konnte nicht gestartet werden.")
            }
            phase = .signingIn(code: userCode, url: uri)
            var interval = (start["interval"] as? NSNumber)?.doubleValue ?? 5
            let expires = Date().addingTimeInterval((start["expires_in"] as? NSNumber)?.doubleValue ?? 900)

            while Date() < expires {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                let result = try await Self.post("\(base)/token", [
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "client_id": clientID,
                    "device_code": deviceCode,
                ])
                if store(tokens: result) {
                    phase = .signedIn
                    lastError = nil
                    await loadAccount()
                    if settings.mailEnabled { startTimer() }
                    return
                }
                switch result["error"] as? String {
                case "authorization_pending": continue
                case "slow_down": interval += 5
                default: throw MailError.message(Self.describe(result) ?? "Anmeldung fehlgeschlagen.")
                }
            }
            phase = .failed("Zeit abgelaufen – bitte erneut anmelden.")
        } catch is CancellationError {
            // abgebrochen
        } catch {
            phase = .failed(Self.text(for: error))
        }
    }

    /// Speichert Zugangsschlüssel; `false`, wenn die Antwort keinen enthält.
    private func store(tokens: [String: Any]) -> Bool {
        guard let access = tokens["access_token"] as? String else { return false }
        accessToken = access
        let lifetime = (tokens["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        accessExpiry = Date().addingTimeInterval(lifetime)
        if let refresh = tokens["refresh_token"] as? String {
            MailKeychain.save(refresh)
        }
        return true
    }

    private func validToken() async throws -> String {
        if let accessToken, accessExpiry > Date().addingTimeInterval(60) { return accessToken }
        guard let refresh = MailKeychain.read() else { throw MailError.signedOut }
        let result = try await Self.post("https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/token", [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refresh,
            "scope": Self.scope,
        ])
        if store(tokens: result), let accessToken { return accessToken }
        if (result["error"] as? String) == "invalid_grant" { throw MailError.signedOut }
        throw MailError.message(Self.describe(result) ?? "Anmeldung konnte nicht erneuert werden.")
    }

    // MARK: Abfragen

    func checkNow() {
        guard settings.mailEnabled, phase == .signedIn, !polling else { return }
        polling = true
        Task { [weak self] in
            await self?.poll()
            self?.polling = false
        }
    }

    private func poll() async {
        do {
            let folder = try await graph("/me/mailFolders/inbox", ["$select": "unreadItemCount"])
            let list = try await graph("/me/mailFolders/inbox/messages", [
                "$top": "15",
                "$orderby": "receivedDateTime desc",
                "$select": "id,subject,from,receivedDateTime,isRead",
            ])
            let count = (folder["unreadItemCount"] as? NSNumber)?.intValue ?? 0
            let messages = (list["value"] as? [[String: Any]]) ?? []
            let iso = ISO8601DateFormatter()
            var unreadMails: [Mail] = []
            var ids: Set<String> = []
            for message in messages {
                guard let id = message["id"] as? String else { continue }
                ids.insert(id)
                guard (message["isRead"] as? Bool) == false else { continue }
                let from = (message["from"] as? [String: Any])?["emailAddress"] as? [String: Any]
                let sender = (from?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (from?["address"] as? String) ?? "Unbekannt"
                let subject = (message["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(kein Betreff)"
                let date = (message["receivedDateTime"] as? String).flatMap { iso.date(from: $0) } ?? Date()
                unreadMails.append(Mail(id: id, sender: sender, subject: subject, received: date))
            }

            // Neue Mails seit der letzten Abfrage → Einblendung neben dem Icon
            if primed, let itemID {
                let fresh = unreadMails.filter { !seen.contains($0.id) }
                if let newest = fresh.first {
                    let title = fresh.count > 1 ? "\(fresh.count) neue E-Mails" : "Neue E-Mail · \(newest.sender)"
                    let body = fresh.count > 1 ? "\(newest.sender): \(newest.subject)" : newest.subject
                    BadgeStore.shared.showToast(title: title, body: body, itemID: itemID)
                }
            }
            seen = ids
            primed = true
            unread = count
            recent = Array(unreadMails.prefix(3))
            lastCheck = Date()
            lastError = nil
            if let itemID { BadgeStore.shared.setExtra(count, itemID: itemID) }
            if account == nil { await loadAccount() }
        } catch MailError.signedOut {
            signOut()
            phase = .failed("Die Anmeldung ist abgelaufen – bitte neu anmelden.")
        } catch {
            lastError = Self.text(for: error)
        }
    }

    private func loadAccount() async {
        if let me = try? await graph("/me", ["$select": "userPrincipalName,mail"]) {
            account = (me["mail"] as? String) ?? (me["userPrincipalName"] as? String)
        }
    }

    private func graph(_ path: String, _ query: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0" + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        for attempt in 0..<2 {
            let token = try await validToken()
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && attempt == 0 {
                accessToken = nil
                continue
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard (200..<300).contains(status) else {
                let error = (json["error"] as? [String: Any])?["message"] as? String
                throw MailError.message(error ?? "Microsoft antwortet mit Fehler \(status).")
            }
            return json
        }
        throw MailError.signedOut
    }

    // MARK: Hilfen

    enum MailError: Error {
        case signedOut
        case message(String)
    }

    private static func post(_ url: String, _ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8)
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Verständliche Fehlermeldung aus einer Microsoft-Antwort
    private static func describe(_ json: [String: Any]) -> String? {
        guard let description = json["error_description"] as? String else { return json["error"] as? String }
        // Microsoft hängt Ablaufdaten an („Trace ID: …“) – nur die erste Zeile zeigen
        let first = description.components(separatedBy: CharacterSet.newlines).first ?? description
        if first.contains("AADSTS7000218") {
            return "In Microsoft Entra „Öffentliche Clientflows zulassen“ auf „Ja“ stellen."
        }
        if first.contains("AADSTS700016") {
            return "Die Anwendungs-ID wurde nicht gefunden – bitte prüfen (und die Verzeichnis-ID)."
        }
        if first.contains("AADSTS65001") {
            return "Die Berechtigung „Mail.Read“ wurde noch nicht erteilt – in Entra unter API-Berechtigungen zustimmen."
        }
        return first
    }

    private static func text(for error: Error) -> String {
        if case MailError.message(let text) = error { return text }
        if case MailError.signedOut = error { return "Nicht angemeldet." }
        if (error as? URLError)?.code == .notConnectedToInternet { return "Keine Internetverbindung." }
        return error.localizedDescription
    }
}

/// Anmeldeschlüssel für das Postfach.
///
/// Er liegt verschlüsselt (AES-GCM, Schlüssel aus der Hardware-Kennung dieses Macs) in einer Datei, die nur du lesen
/// kannst. Früher lag er im Schlüsselbund – nach jedem Update fragte macOS dort neu nach, und die Abfrage hielt die
/// Sidebar beim Start an („Programm reagiert nicht“). Ein alter Eintrag im Schlüsselbund wird einmal im Hintergrund
/// übernommen und gelöscht; die Sidebar bleibt dabei bedienbar.
enum MailKeychain {
    private static let service = "app.sidebar.Sidebar.mail"
    private static let account = "microsoft-refresh-token"

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sidebar", isDirectory: true).appendingPathComponent("mail-token")
    }

    private static var key: SymmetricKey {
        var uuid = "sidebar-fallback"
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        if entry != 0 {
            if let value = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String {
                uuid = value
            }
            IOObjectRelease(entry)
        }
        return SymmetricKey(data: SHA256.hash(data: Data((uuid + "|" + service).utf8)))
    }

    static var hasToken: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    static func save(_ value: String) {
        guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: key).combined else { return }
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? sealed.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Liest nur die Datei – nie den Schlüsselbund (der kann blockieren).
    static func read() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
        DispatchQueue.global().async { legacyDelete() }
    }

    /// Alten Eintrag aus dem Schlüsselbund holen (im Hintergrund – hier kann macOS nachfragen).
    static func migrateLegacy(completion: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data, let token = String(data: data, encoding: .utf8) {
                save(token)
                legacyDelete()
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    private static func legacyDelete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Anzeige in den Einstellungen

struct MailSettingsSection: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject private var mail = MailWatcher.shared

    var body: some View {
        Section("E-Mail (Microsoft 365 / Outlook)") {
            Toggle("Posteingang überwachen", isOn: $store.config.settings.mailEnabled)
            if store.config.settings.mailEnabled {
                TextField("Anwendungs-ID (Client-ID)", text: $store.config.settings.mailClientID,
                          prompt: Text("aus Microsoft Entra"))
                TextField("Verzeichnis-ID (Mandanten-ID)", text: $store.config.settings.mailTenantID,
                          prompt: Text("aus Microsoft Entra"))
                Picker("Anzeigen bei", selection: $store.config.settings.mailItemID) {
                    Text("– Icon wählen –").tag(UUID?.none)
                    ForEach(store.config.favorites + store.config.groups.flatMap(\.items)) { item in
                        Text(item.displayName).tag(UUID?.some(item.id))
                    }
                }
                status
                Text("Die Sidebar fragt jede Minute den Posteingang ab – auch wenn Outlook geschlossen ist. Am gewählten Icon steht die Zahl ungelesener Mails, neue Mails erscheinen kurz daneben (Absender und Betreff). Nur Leserecht, die Anmeldung läuft über die Microsoft-Seite, der Schlüssel liegt im macOS-Schlüsselbund.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch mail.phase {
        case .signedOut:
            Button("Bei Microsoft anmelden …") { mail.signIn() }
        case .signingIn(let code, let url):
            VStack(alignment: .leading, spacing: 6) {
                Text("Auf der Microsoft-Seite diesen Code eingeben und mit deinem Konto anmelden:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button("Code kopieren und Anmeldeseite öffnen") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        NSWorkspace.shared.open(url)
                    }
                    Button("Abbrechen") { mail.cancelSignIn() }
                }
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Warte auf Anmeldung …").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .signedIn:
            LabeledContent("Angemeldet") {
                Text(mail.account ?? "…").foregroundStyle(.secondary)
            }
            LabeledContent("Ungelesen im Posteingang") {
                Text(mail.lastCheck == nil ? "wird geprüft …"
                     : "\(mail.unread) · geprüft \(mail.lastCheck!.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
            if let error = mail.lastError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            if store.config.settings.mailItemID == nil {
                Text("Bitte oben bei „Anzeigen bei“ das Outlook-Icon wählen.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Jetzt prüfen") { mail.checkNow() }
                Button("Abmelden") { mail.signOut() }
            }
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
            Button("Erneut anmelden …") { mail.signIn() }
        }
    }
}

/// Liste der neuesten ungelesenen Mails (in der Mini-Vorschau).
struct MailPreviewList: View {
    let palette: Palette
    @ObservedObject private var mail = MailWatcher.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mail.unread == 1 ? "1 ungelesene E-Mail" : "\(mail.unread) ungelesene E-Mails")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondary)
            if mail.recent.isEmpty {
                Spacer(minLength: 0)
                Text("Alles gelesen")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(mail.recent) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(item.sender)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.text)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(item.received.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(palette.secondary)
                        }
                        Text(item.subject)
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(scheme == .dark ? 0.12 : 0.45))
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
