import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Was in die Sidebar gezogen wurde.
enum DropPayload {
    /// Ein Link aus der Sidebar selbst (z. B. aus einem Ordner in die Favoriten)
    case internalItem(UUID)
    /// Ein Ordner aus der Leiste (zum Umsortieren)
    case internalGroup(UUID)
    /// Eine Webadresse (aus der Adressleiste, ein Link von einer Webseite, eine .webloc-Datei)
    case url(URL)
    /// Eine Bilddatei (wird als eigenes Icon verwendet)
    case image(URL)
}

enum DropSupport {
    static let types: [UTType] = [.fileURL, .url, .utf8PlainText, .plainText]
    static let internalPrefix = "sidebar-item:"
    static let groupPrefix = "sidebar-group:"

    static func provider(forGroup group: LinkGroup) -> NSItemProvider {
        let provider = NSItemProvider(object: (groupPrefix + group.id.uuidString) as NSString)
        provider.suggestedName = group.name
        return provider
    }

    /// Für Links aus der Sidebar: intern als ID, nach außen (Browser) als Webadresse.
    static func provider(for item: LinkItem) -> NSItemProvider {
        let provider = NSItemProvider(object: (internalPrefix + item.id.uuidString) as NSString)
        if let url = item.url {
            provider.registerObject(url as NSURL, visibility: .all)
        }
        provider.suggestedName = item.displayName
        return provider
    }

    private final class Collector {
        var payloads: [DropPayload] = []
        let lock = NSLock()
        func add(_ payload: DropPayload?) {
            guard let payload else { return }
            lock.lock()
            payloads.append(payload)
            lock.unlock()
        }
    }

    /// Liest die gezogenen Inhalte aus und meldet sie auf dem Hauptthread.
    static func load(_ providers: [NSItemProvider], completion: @escaping @MainActor ([DropPayload]) -> Void) {
        let collector = Collector()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    collector.add(url.flatMap(payload(forFile:)))
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    collector.add(text.flatMap(payload(forText:)))
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    collector.add(url.flatMap(payload(forWebURL:)))
                    group.leave()
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let result = collector.payloads
            MainActor.assumeIsolated { completion(result) }
        }
    }

    private static func payload(forText text: String) -> DropPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(internalPrefix),
           let id = UUID(uuidString: String(trimmed.dropFirst(internalPrefix.count))) {
            return .internalItem(id)
        }
        if trimmed.hasPrefix(groupPrefix),
           let id = UUID(uuidString: String(trimmed.dropFirst(groupPrefix.count))) {
            return .internalGroup(id)
        }
        // Bei mehrzeiligem Text die erste Adresse verwenden
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        // Nur echte Adressen akzeptieren (mit Schema oder Domain mit Punkt), keinen beliebigen Text
        guard !firstLine.contains(" "),
              let url = LinkItem.normalizedURL(from: firstLine),
              firstLine.contains("://") || (url.host ?? "").contains(".") else { return nil }
        return payload(forWebURL: url)
    }

    private static func payload(forWebURL url: URL) -> DropPayload? {
        if url.isFileURL { return payload(forFile: url) }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return .url(url)
    }

    private static func payload(forFile url: URL) -> DropPayload? {
        let ext = url.pathExtension.lowercased()
        // Internet-Verknüpfungen aus Safari/Finder
        if ext == "webloc",
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let string = plist["URL"] as? String,
           let web = URL(string: string) {
            return payload(forWebURL: web)
        }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
            return .image(url)
        }
        return nil
    }
}

extension View {
    /// Nimmt Links, Webadressen und Bilder per Drag & Drop an.
    func linkDropTarget(isTargeted: Binding<Bool>? = nil,
                        perform: @escaping @MainActor ([DropPayload]) -> Void) -> some View {
        onDrop(of: DropSupport.types, isTargeted: isTargeted) { providers in
            DropSupport.load(providers, completion: perform)
            return true
        }
    }
}
