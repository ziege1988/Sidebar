import AppKit
import Combine
import SwiftUI

/// Lädt Favicons und speichert sie im Cache unter
/// `~/Library/Application Support/Sidebar/Favicons`.
final class FaviconStore: ObservableObject {
    static let shared = FaviconStore()

    @Published private(set) var images: [String: NSImage] = [:]
    private var loading: Set<String> = []
    private let directory: URL

    init() {
        directory = ConfigStore.supportDirectory.appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for host: String) -> NSImage? { images[host] }

    @MainActor
    func load(host: String) async {
        guard images[host] == nil, !loading.contains(host) else { return }
        loading.insert(host)
        defer { loading.remove(host) }

        let safeName = host.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? host
        let file = directory.appendingPathComponent(safeName + ".png")

        if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            images[host] = image
            return
        }

        // Favicon-Dienst von Google (liefert zuverlässig hochauflösende Icons).
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(safeName)&sz=64") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data) else { return }
            try? data.write(to: file, options: .atomic)
            images[host] = image
        } catch {
            // Offline o. ä. – Buchstaben-Icon bleibt stehen.
        }
    }
}

/// Eigene Bilder als Icons, gespeichert unter `~/Library/Application Support/Sidebar/Icons`.
final class IconStore {
    static let shared = IconStore()
    private let directory: URL
    private var cache: [String: NSImage] = [:]

    init() {
        directory = ConfigStore.supportDirectory.appendingPathComponent("Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(named file: String) -> NSImage? {
        if let cached = cache[file] { return cached }
        guard let image = NSImage(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        cache[file] = image
        return image
    }

    /// Skaliert das Bild quadratisch auf 128 × 128 px (zentriert zugeschnitten) und speichert es als PNG.
    func save(_ image: NSImage) -> String? {
        let side = 128
        let source = image.size
        guard source.width > 0, source.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        let scale = max(CGFloat(side) / source.width, CGFloat(side) / source.height)
        let width = source.width * scale
        let height = source.height * scale

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: (CGFloat(side) - width) / 2, y: (CGFloat(side) - height) / 2,
                              width: width, height: height),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let file = UUID().uuidString + ".png"
        do {
            try data.write(to: directory.appendingPathComponent(file), options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    /// Rohdaten eines eigenen Icons (für Export).
    func data(named file: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(file))
    }

    /// Eigenes Icon mit festem Namen ablegen (für Import).
    func write(_ data: Data, named file: String) {
        try? data.write(to: directory.appendingPathComponent(file), options: .atomic)
        cache[file] = nil
    }

    func delete(_ file: String?) {
        guard let file else { return }
        cache[file] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
    }
}

/// Icon eines Links: eigenes Bild → Favicon der Seite → Anfangsbuchstabe.
struct FaviconView: View {
    let item: LinkItem
    var size: CGFloat = 24

    @ObservedObject private var favicons = FaviconStore.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        ZStack {
            if let file = item.customIcon, let custom = IconStore.shared.image(named: file) {
                Image(nsImage: custom)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if let url = item.url, url.isFileURL {
                // Programm/Datei vom Mac: Original-Icon von macOS
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if let host = item.host, let image = favicons.image(for: host) {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(Color.white.opacity(scheme == .dark ? 0.9 : 0.75))
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.12)
            } else {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(palette.accentSoft)
                Text(String(item.displayName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .task(id: item.host) {
            if let host = item.host {
                await favicons.load(host: host)
            }
        }
    }
}
