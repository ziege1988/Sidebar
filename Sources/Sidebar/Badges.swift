import AppKit
import Combine
import SwiftUI
import UserNotifications

/// Zähler für ungelesene Benachrichtigungen je Webseite (z. B. „(3) Instagram“).
/// Funktioniert für Links, die im integrierten App-Fenster laufen.
final class BadgeStore: ObservableObject {
    static let shared = BadgeStore()

    @Published private(set) var counts: [String: Int] = [:]

    static func key(for item: LinkItem) -> String? {
        guard let host = item.host else { return nil }
        return LinkItem.prettyHost(host).lowercased()
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
        let total = counts.values.reduce(0, +)
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

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(Capsule().fill(Color(hex: 0xE5534B)))
                .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1))
                .fixedSize()
        }
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
