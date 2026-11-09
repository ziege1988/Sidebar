import AppKit
import Combine
import CoreGraphics

// MARK: - Stromsparen
//
// Bildschirm gesperrt, Bildschirmschoner läuft, Displays schlafen oder ein anderer Benutzer ist angemeldet:
// Dann sieht niemand die Sidebar – Mausabfrage, Rüdigers Animation und sein „Denken“ pausieren.
//
// Damit danach sicher alles wieder anläuft, wird der Zustand nicht nur aus Meldungen von macOS abgeleitet
// (die können verloren gehen), sondern alle 2 Sekunden direkt nachgefragt. Fällt eine Meldung aus,
// läuft spätestens nach 2 Sekunden wieder alles.

@MainActor
final class PowerState: ObservableObject {
    static let shared = PowerState()

    /// gerade sieht niemand den Bildschirm → Arbeit ruht
    @Published private(set) var paused = false

    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private init() {}

    func start() {
        guard timer == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in names {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append((workspace, token))
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.didstart", "com.apple.screensaver.didstop",
                     "com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            let token = distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                // Die Meldung kommt manchmal minimal vor dem neuen Zustand – kurz danach noch einmal prüfen
                MainActor.assumeIsolated {
                    self?.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.refresh() }
                }
            }
            observers.append((distributed, token))
        }
        // Sicherheitsnetz: regelmäßig selbst nachsehen
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        let now = Self.nobodyWatching()
        if paused != now { paused = now }
    }

    private static func nobodyWatching() -> Bool {
        var locked = false
        var onConsole = true
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            locked = (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
            onConsole = (session[kCGSessionOnConsoleKey as String] as? NSNumber)?.boolValue ?? true
        }
        // Alle Bildschirme schlafen (bei einem einzelnen wachen Bildschirm läuft alles weiter)
        let displays = NSScreen.screens.compactMap(\.displayID)
        let displaysAsleep = !displays.isEmpty && displays.allSatisfy { CGDisplayIsAsleep($0) != 0 }
        let screensaver = NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == "com.apple.ScreenSaver.Engine" }
        return locked || !onConsole || displaysAsleep || screensaver
    }
}
