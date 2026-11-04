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
        if let group = config.groups.first(where: { $0.id == id }) {
            group.items.forEach { IconStore.shared.delete($0.customIcon) }
        }
        config.groups.removeAll { $0.id == id }
    }

    func updateGroup(_ id: UUID, _ change: (inout LinkGroup) -> Void) {
        guard let index = config.groups.firstIndex(where: { $0.id == id }) else { return }
        var groups = config.groups
        change(&groups[index])
        config.groups = groups
    }

    // MARK: - Links: Abfragen

    var favoritesFull: Bool { config.favorites.count >= SidebarConfig.maxFavorites }

    func item(id: UUID) -> LinkItem? {
        if let fav = config.favorites.first(where: { $0.id == id }) { return fav }
        for group in config.groups {
            if let item = group.items.first(where: { $0.id == id }) { return item }
        }
        return nil
    }

    /// Gruppe (oder `LinkGroup.favoritesID`), in der ein Link liegt.
    func container(of id: UUID) -> UUID? {
        if config.favorites.contains(where: { $0.id == id }) { return LinkGroup.favoritesID }
        return config.groups.first(where: { group in group.items.contains { $0.id == id } })?.id
    }

    func isFavorite(_ id: UUID) -> Bool {
        config.favorites.contains { $0.id == id }
    }

    // MARK: - Links: Ändern

    func updateItem(id: UUID, _ change: (inout LinkItem) -> Void) {
        var cfg = config
        if let i = cfg.favorites.firstIndex(where: { $0.id == id }) {
            change(&cfg.favorites[i])
        } else {
            for gi in cfg.groups.indices {
                if let ii = cfg.groups[gi].items.firstIndex(where: { $0.id == id }) {
                    change(&cfg.groups[gi].items[ii])
                    break
                }
            }
        }
        config = cfg
    }

    func deleteItem(id: UUID) {
        let icon = item(id: id)?.customIcon
        var cfg = config
        cfg.favorites.removeAll { $0.id == id }
        for i in cfg.groups.indices {
            cfg.groups[i].items.removeAll { $0.id == id }
        }
        config = cfg
        if let icon, !iconInUse(icon) { IconStore.shared.delete(icon) }
    }

    /// Fügt einen Link hinzu oder aktualisiert ihn – inkl. Verschieben in eine andere Gruppe
    /// bzw. in/aus den Favoriten.
    func upsert(_ item: LinkItem, into containerID: UUID) {
        var cfg = config
        let previousIcon = self.item(id: item.id)?.customIcon

        var replaced = false
        if containerID == LinkGroup.favoritesID {
            if let i = cfg.favorites.firstIndex(where: { $0.id == item.id }) {
                cfg.favorites[i] = item
                replaced = true
            }
        } else if let gi = cfg.groups.firstIndex(where: { $0.id == containerID }),
                  let ii = cfg.groups[gi].items.firstIndex(where: { $0.id == item.id }) {
            cfg.groups[gi].items[ii] = item
            replaced = true
        }

        if !replaced {
            cfg.favorites.removeAll { $0.id == item.id }
            for gi in cfg.groups.indices {
                cfg.groups[gi].items.removeAll { $0.id == item.id }
            }
            if containerID == LinkGroup.favoritesID {
                guard cfg.favorites.count < SidebarConfig.maxFavorites else {
                    NSSound.beep()
                    return
                }
                cfg.favorites.append(item)
            } else if let gi = cfg.groups.firstIndex(where: { $0.id == containerID }) {
                cfg.groups[gi].items.append(item)
            } else {
                return
            }
        }
        config = cfg

        if let previousIcon, previousIcon != item.customIcon, !iconInUse(previousIcon) {
            IconStore.shared.delete(previousIcon)
        }
    }

    // MARK: - Favoriten

    /// Legt eine Kopie des Links in die Favoritenleiste (max. 6).
    @discardableResult
    func addToFavorites(itemID: UUID) -> Bool {
        guard !isFavorite(itemID), let source = item(id: itemID) else { return false }
        guard !favoritesFull else {
            NSSound.beep()
            return false
        }
        var copy = source
        copy.id = UUID()
        config.favorites.append(copy)
        return true
    }

    func removeFromFavorites(id: UUID) {
        deleteItem(id: id)
    }

    // MARK: - Eigene Icons

    func setCustomIcon(itemID: UUID, image: NSImage) {
        guard let file = IconStore.shared.save(image) else {
            NSSound.beep()
            return
        }
        let old = item(id: itemID)?.customIcon
        updateItem(id: itemID) { $0.customIcon = file }
        if let old, !iconInUse(old) { IconStore.shared.delete(old) }
    }

    func removeCustomIcon(itemID: UUID) {
        let old = item(id: itemID)?.customIcon
        updateItem(id: itemID) { $0.customIcon = nil }
        if let old, !iconInUse(old) { IconStore.shared.delete(old) }
    }

    private func iconInUse(_ file: String) -> Bool {
        config.favorites.contains { $0.customIcon == file }
            || config.groups.contains { group in group.items.contains { $0.customIcon == file } }
    }

    // MARK: - Drag & Drop

    /// Verarbeitet abgelegte Inhalte.
    /// - Parameters:
    ///   - containerID: Gruppe oder `LinkGroup.favoritesID`
    ///   - targetItem: Link, auf den gezogen wurde (für eigene Bilder)
    @discardableResult
    func handleDrop(_ payloads: [DropPayload], into containerID: UUID, targetItem: UUID? = nil) -> Bool {
        var changed = false
        for payload in payloads {
            switch payload {
            case .image(let url):
                guard let target = targetItem, let image = NSImage(contentsOf: url) else { continue }
                setCustomIcon(itemID: target, image: image)
                changed = true

            case .internalItem(let id):
                guard let source = container(of: id), let original = item(id: id) else { continue }
                if containerID == LinkGroup.favoritesID {
                    changed = addToFavorites(itemID: id) || changed
                } else if source == LinkGroup.favoritesID {
                    // Favorit in einen Ordner ziehen → Kopie, Favorit bleibt erhalten
                    var copy = original
                    copy.id = UUID()
                    updateGroup(containerID) { $0.items.append(copy) }
                    changed = true
                } else if source != containerID {
                    upsert(original, into: containerID) // zwischen Ordnern verschieben
                    changed = true
                }

            case .url(let url):
                let newItem = LinkItem(name: LinkItem.suggestedName(for: url), urlString: url.absoluteString)
                if containerID == LinkGroup.favoritesID {
                    guard !favoritesFull else {
                        NSSound.beep()
                        continue
                    }
                    config.favorites.append(newItem)
                } else {
                    updateGroup(containerID) { $0.items.append(newItem) }
                }
                changed = true
            }
        }
        return changed
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
