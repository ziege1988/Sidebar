import AppKit
import Combine
import SwiftUI
import UserNotifications

/// Zähler für ungelesene Benachrichtigungen je Webseite (z. B. „(3) Instagram“).
/// Funktioniert für Links, die im integrierten App-Fenster laufen.
final class BadgeStore: ObservableObject {
    static let shared = BadgeStore()

    @Published private(set) var counts: [String: Int] = [:]
    /// Letzte Nachricht je Seite (Absender + erste Zeile) für die Vorschau
    @Published private(set) var messages: [String: LastMessage] = [:]

    struct LastMessage: Equatable {
        var title: String
        var body: String
        var date: Date
    }

    static func key(for item: LinkItem) -> String? {
        if item.isLocal {
            // Programme: Zahl aus dem Dock
            guard let bundleID = item.appBundleID else { return nil }
            return appKey(bundleID)
        }
        guard let host = item.host else { return nil }
        return LinkItem.prettyHost(host).lowercased()
    }

    static func appKey(_ bundleID: String) -> String { "app:" + bundleID.lowercased() }

    /// Zahl eines Mac-Programms (aus dem Dock) setzen.
    func setApp(_ count: Int, bundleID: String) {
        let key = Self.appKey(bundleID)
        if count <= 0 {
            if counts[key] != nil { counts[key] = nil }
        } else if counts[key] != count {
            counts[key] = count
        }
    }

    func message(for item: LinkItem) -> LastMessage? {
        guard let key = Self.key(for: item) else { return nil }
        return messages[key]
    }

    func setMessage(title: String, body: String, for item: LinkItem) {
        guard let key = Self.key(for: item) else { return }
        messages[key] = LastMessage(title: title, body: body, date: Date())
    }

    func clearMessage(for item: LinkItem) {
        guard let key = Self.key(for: item), messages[key] != nil else { return }
        messages[key] = nil
    }

    func count(for item: LinkItem) -> Int {
        guard let key = Self.key(for: item) else { return 0 }
        return counts[key] ?? 0
    }

    func count(for group: LinkGroup) -> Int {
        // Jede Seite nur einmal zählen
        let keys = Set(group.items.compactMap(Self.key(for:)))
        return keys.reduce(0) { $0 + (counts[$1] ?? 0) }
    }

    func set(_ count: Int, for item: LinkItem) {
        guard let key = Self.key(for: item) else { return }
        if count <= 0 {
            if counts[key] != nil { counts[key] = nil }
        } else if counts[key] != count {
            counts[key] = count
        }
        updateDockBadge()
    }

    func increment(for item: LinkItem) {
        set(count(for: item) + 1, for: item)
    }

    private func updateDockBadge() {
        // nur eigene Web-Apps, nicht die gespiegelten Zahlen anderer Programme
        let total = counts.filter { !$0.key.hasPrefix("app:") }.values.reduce(0, +)
        DispatchQueue.main.async {
            NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
        }
    }

    /// Liest eine Zahl aus dem Seitentitel, z. B. „(3) Instagram“ oder „Posteingang (12) – Gmail“.
    static func count(fromTitle title: String) -> Int {
        let pattern = #"[\(\[](\d{1,4})\+?[\)\]]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else { return 0 }
        return Int(title[range]) ?? 0
    }
}

/// Kleiner Zähler-Punkt an Icons.
struct BadgeView: View {
    let count: Int
    @ObservedObject private var alerts = AlertState.shared

    var body: some View {
        // Im Ruhemodus ausgeblendet – danach erscheinen die Zahlen wieder
        let visible = count > 0 && !alerts.quiet
        ZStack {
            if visible {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4.5)
                    .frame(minWidth: 17, minHeight: 17)
                    .background(
                        Capsule().fill(LinearGradient(colors: [Color(hex: 0xFF5A4F), Color(hex: 0xE0281D)],
                                                      startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
                    .shadow(color: Color(hex: 0xFF3B30).opacity(0.45), radius: 3, y: 1)
                    .fixedSize()
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: visible)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: count)
    }
}

/// macOS-Mitteilungen für Web-Apps (Banner oben rechts).
final class SystemNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()
    private var authorized = false
    /// Wird beim Klick auf eine Mitteilung mit der ID des Links aufgerufen
    var onOpen: ((UUID) -> Void)?

    func setUp() {
        UNUserNotificationCenter.current().delegate = self
    }

    func post(title: String, body: String, itemID: UUID) {
        let center = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["itemID": itemID.uuidString]
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
        if authorized {
            send()
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            self.authorized = granted
            if granted { send() }
        }
    }

    // Auch anzeigen, wenn die Sidebar-App gerade aktiv ist
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Klick auf die Mitteilung → App-Fenster öffnen
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let string = info["itemID"] as? String, let id = UUID(uuidString: string) {
            let handler = onOpen
            DispatchQueue.main.async { handler?(id) }
        }
        completionHandler()
    }
}
