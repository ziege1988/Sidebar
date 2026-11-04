import AppKit
import Combine
import Foundation

/// Lädt und speichert die Konfiguration als JSON unter
/// `~/Library/Application Support/Sidebar/config.json`.
@MainActor
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published var config: SidebarConfig {
        didSet { save() }
    }

    let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = ConfigStore.supportDirectory
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("config.json")
        config = ConfigStore.load(from: fileURL)
        if !fm.fileExists(atPath: fileURL.path) { save() }
    }

    nonisolated static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sidebar", isDirectory: true)
    }

    private static func load(from url: URL) -> SidebarConfig {
        guard let data = try? Data(contentsOf: url) else { return .sample }
        do {
            return try JSONDecoder().decode(SidebarConfig.self, from: data)
        } catch {
            // Defekte Datei nicht überschreiben, sondern sichern.
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("config-defekt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            NSLog("Sidebar: Konfiguration konnte nicht gelesen werden (\(error)). Sicherung: \(backup.path)")
            return .sample
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(config).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Sidebar: Konfiguration konnte nicht gespeichert werden: \(error)")
        }
    }

    // MARK: - Gruppen

    @discardableResult
    func addGroup(name: String = "Neue Gruppe", symbol: String = "folder") -> LinkGroup {
        let group = LinkGroup(name: name, symbol: symbol)
        config.groups.append(group)
        return group
    }

    func deleteGroup(id: UUID) {
        config.groups.removeAll { $0.id == id }
    }

    func updateGroup(_ id: UUID, _ change: (inout LinkGroup) -> Void) {
        guard let index = config.groups.firstIndex(where: { $0.id == id }) else { return }
        var groups = config.groups
        change(&groups[index])
        config.groups = groups
    }

    // MARK: - Links

    func deleteItem(id: UUID) {
        var groups = config.groups
        for i in groups.indices {
            groups[i].items.removeAll { $0.id == id }
        }
        config.groups = groups
    }

    /// Fügt einen Link hinzu oder aktualisiert ihn – inkl. Verschieben in eine andere Gruppe.
    func upsert(_ item: LinkItem, into groupID: UUID) {
        var groups = config.groups
        var foundGroup: Int?
        var foundItem: Int?
        for gi in groups.indices {
            if let ii = groups[gi].items.firstIndex(where: { $0.id == item.id }) {
                foundGroup = gi
                foundItem = ii
                break
            }
        }
        if let gi = foundGroup, let ii = foundItem, groups[gi].id == groupID {
            groups[gi].items[ii] = item
        } else {
            if let gi = foundGroup, let ii = foundItem {
                groups[gi].items.remove(at: ii)
            }
            guard let target = groups.firstIndex(where: { $0.id == groupID }) else { return }
            groups[target].items.append(item)
        }
        config.groups = groups
    }

    /// URLs, die per Drag & Drop (z. B. aus der Browser-Adressleiste) auf eine Gruppe gezogen werden.
    func addDroppedURLs(_ urls: [URL], to groupID: UUID) -> Bool {
        let items = urls
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
            .map { LinkItem(name: LinkItem.suggestedName(for: $0), urlString: $0.absoluteString) }
        guard !items.isEmpty else { return false }
        updateGroup(groupID) { $0.items.append(contentsOf: items) }
        return true
    }

    // MARK: - Position

    func setScreen(_ screen: NSScreen?) {
        var s = config.settings
        s.screenID = screen?.displayID
        s.screenName = screen?.localizedName
        config.settings = s
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
