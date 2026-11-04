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

/// Favicon eines Links, mit Buchstaben-Fallback.
struct FaviconView: View {
    let item: LinkItem
    var size: CGFloat = 24

    @ObservedObject private var favicons = FaviconStore.shared

    var body: some View {
        ZStack {
            if let host = item.host, let image = favicons.image(for: host) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
                Text(String(item.displayName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .task(id: item.host) {
            if let host = item.host {
                await favicons.load(host: host)
            }
        }
    }
}
