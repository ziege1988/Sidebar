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

    /// Legt eine Kopie des Links in die Favoritenleiste (max. `SidebarConfig.maxFavorites`).
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

    /// Verarbeitet abgelegte Inhalte – Hinzufügen, Verschieben und Umsortieren.
    /// - Parameters:
    ///   - containerID: Ordner oder `LinkGroup.favoritesID`
    ///   - targetItem: Link, auf den gezogen wurde (Position bzw. eigenes Bild)
    ///   - index: Einfügeposition (Lücke vor diesem Index), z. B. aus einer Liste in den Einstellungen
    @discardableResult
    func handleDrop(_ payloads: [DropPayload], into containerID: UUID,
                    targetItem: UUID? = nil, at index: Int? = nil) -> Bool {
        var cfg = config
        guard Self.items(in: cfg, containerID) != nil else { return false }
        var changed = false
        var pendingIcon: (UUID, URL)?

        // Einfügeposition für neue Links: vor dem Ziel-Link bzw. am angegebenen Index
        var insertAt: Int? = index
        if insertAt == nil, let target = targetItem {
            insertAt = Self.items(in: cfg, containerID)?.firstIndex { $0.id == target }
        }

        func insert(_ item: LinkItem) {
            Self.mutateItems(&cfg, containerID) { items in
                let position = min(max(insertAt ?? items.count, 0), items.count)
                items.insert(item, at: position)
            }
            if let current = insertAt { insertAt = current + 1 }
        }

        /// Neuen Link einfügen (Favoriten: höchstens 6).
        func insertNew(_ item: LinkItem) -> Bool {
            if containerID == LinkGroup.favoritesID && cfg.favorites.count >= SidebarConfig.maxFavorites {
                NSSound.beep()
                return false
            }
            insert(item)
            return true
        }

        for payload in payloads {
            switch payload {
            case .image(let url):
                if let target = targetItem {
                    pendingIcon = (target, url) // Bild auf einen Link → eigenes Icon
                } else {
                    changed = insertNew(LinkItem(name: LinkItem.suggestedName(for: url), urlString: url.absoluteString)) || changed
                }

            case .file(let url):
                changed = insertNew(LinkItem(name: LinkItem.suggestedName(for: url), urlString: url.absoluteString)) || changed

            case .internalGroup:
                continue // Ordner werden über moveGroup sortiert

            case .internalItem(let id):
                guard let source = Self.container(in: cfg, of: id),
                      let original = Self.items(in: cfg, source)?.first(where: { $0.id == id }) else { continue }

                if source == containerID {
                    // Umsortieren innerhalb derselben Liste
                    Self.mutateItems(&cfg, containerID) { items in
                        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
                        let gap: Int
                        if let index {
                            gap = index
                        } else if let target = targetItem, let to = items.firstIndex(where: { $0.id == target }) {
                            gap = from < to ? to + 1 : to
                        } else {
                            gap = items.count
                        }
                        Self.move(&items, from: from, toGap: gap)
                    }
                    changed = true
                    continue
                }

                if containerID == LinkGroup.favoritesID {
                    // Schon als Favorit vorhanden → nur an die neue Stelle schieben
                    if let existing = cfg.favorites.firstIndex(where: { $0.urlString == original.urlString }) {
                        let gap = insertAt ?? cfg.favorites.count
                        Self.move(&cfg.favorites, from: existing, toGap: gap)
                        changed = true
                        continue
                    }
                    guard cfg.favorites.count < SidebarConfig.maxFavorites else {
                        NSSound.beep()
                        continue
                    }
                }

                var newItem = original
                if containerID == LinkGroup.favoritesID || source == LinkGroup.favoritesID {
                    newItem.id = UUID() // Favoriten sind Verknüpfungen: Original bleibt erhalten
                } else {
                    Self.mutateItems(&cfg, source) { $0.removeAll { $0.id == id } } // zwischen Ordnern verschieben
                }
                insert(newItem)
                changed = true

            case .url(let url):
                changed = insertNew(LinkItem(name: LinkItem.suggestedName(for: url), urlString: url.absoluteString)) || changed
            }
        }

        if changed { config = cfg }
        if let pending = pendingIcon, let image = NSImage(contentsOf: pending.1) {
            setCustomIcon(itemID: pending.0, image: image)
            changed = true
        }
        return changed
    }

    /// Ordner in der Leiste per Drag & Drop umsortieren.
    func moveGroup(_ id: UUID, onto target: UUID) {
        guard id != target,
              let from = config.groups.firstIndex(where: { $0.id == id }),
              let to = config.groups.firstIndex(where: { $0.id == target }) else { return }
        var groups = config.groups
        Self.move(&groups, from: from, toGap: from < to ? to + 1 : to)
        config.groups = groups
    }

    private static func items(in cfg: SidebarConfig, _ container: UUID) -> [LinkItem]? {
        if container == LinkGroup.favoritesID { return cfg.favorites }
        return cfg.groups.first(where: { $0.id == container })?.items
    }

    private static func container(in cfg: SidebarConfig, of id: UUID) -> UUID? {
        if cfg.favorites.contains(where: { $0.id == id }) { return LinkGroup.favoritesID }
        return cfg.groups.first(where: { group in group.items.contains { $0.id == id } })?.id
    }

    private static func mutateItems(_ cfg: inout SidebarConfig, _ container: UUID,
                                    _ change: (inout [LinkItem]) -> Void) {
        if container == LinkGroup.favoritesID {
            change(&cfg.favorites)
        } else if let gi = cfg.groups.firstIndex(where: { $0.id == container }) {
            change(&cfg.groups[gi].items)
        }
    }

    /// Verschiebt ein Element in die Lücke vor `gap` (Index bezogen auf die Liste vor dem Entfernen).
    private static func move<T>(_ array: inout [T], from: Int, toGap gap: Int) {
        guard array.indices.contains(from) else { return }
        let element = array.remove(at: from)
        let destination = from < gap ? gap - 1 : gap
        array.insert(element, at: min(max(destination, 0), array.count))
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
