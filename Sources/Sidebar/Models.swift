import Foundation

/// Bildschirmkante, an der die Sidebar angedockt wird.
enum ScreenEdge: String, Codable, CaseIterable, Identifiable {
    case left, right, top, bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Links"
        case .right: return "Rechts"
        case .top: return "Oben"
        case .bottom: return "Unten"
        }
    }

    var symbol: String {
        switch self {
        case .left: return "arrow.left.to.line"
        case .right: return "arrow.right.to.line"
        case .top: return "arrow.up.to.line"
        case .bottom: return "arrow.down.to.line"
        }
    }

    var isVertical: Bool { self == .left || self == .right }
}

/// Wie ein Link geöffnet wird.
enum OpenMode: String, Codable, CaseIterable, Identifiable {
    /// Neuer Tab im Standard-Browser (Safari, Chrome, …)
    case defaultBrowser
    /// Eigenes Fenster innerhalb der Sidebar-App (WebKit), eigene Logins
    case appWindow
    /// Chromium-Browser im „--app“-Modus: eigenes Fenster ohne Tabs/Adressleiste, nutzt die Logins des Browsers
    case chromiumApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultBrowser: return "Standard-Browser (neuer Tab)"
        case .appWindow: return "Integriertes App-Fenster"
        case .chromiumApp: return "Chrome-App-Fenster"
        }
    }

    var shortTitle: String {
        switch self {
        case .defaultBrowser: return "Browser"
        case .appWindow: return "App-Fenster"
        case .chromiumApp: return "Chrome-App"
        }
    }
}

/// Chromium-basierte Browser, die den `--app=<url>`-Modus unterstützen.
struct ChromiumBrowser: Identifiable, Hashable {
    let name: String
    let bundleID: String
    var id: String { bundleID }

    static let all: [ChromiumBrowser] = [
        ChromiumBrowser(name: "Google Chrome", bundleID: "com.google.Chrome"),
        ChromiumBrowser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac"),
        ChromiumBrowser(name: "Brave", bundleID: "com.brave.Browser"),
        ChromiumBrowser(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi"),
        ChromiumBrowser(name: "Chromium", bundleID: "org.chromium.Chromium"),
    ]
}

/// Ein Link / eine „Browser-App“ in der Sidebar.
struct LinkItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var urlString: String
    /// `nil` = Standard aus den Einstellungen verwenden
    var openMode: OpenMode?

    var url: URL? { LinkItem.normalizedURL(from: urlString) }
    var host: String? { url?.host }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let host { return LinkItem.prettyHost(host) }
        return urlString
    }

    /// Ergänzt fehlendes `https://` und prüft, ob ein Host vorhanden ist.
    static func normalizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func prettyHost(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func suggestedName(for url: URL) -> String {
        if let host = url.host { return prettyHost(host) }
        return url.absoluteString
    }
}

/// Untergruppe, z. B. „Fotografie“ oder „ADS“.
struct LinkGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
    var items: [LinkItem] = []
}

struct SidebarSettings: Codable, Equatable {
    /// CGDirectDisplayID des gewählten Bildschirms (`nil` = primärer Bildschirm)
    var screenID: UInt32?
    /// Name des Bildschirms als Fallback, falls sich die ID ändert
    var screenName: String?
    var edge: ScreenEdge = .left
    var collapsedThickness: Double = 56
    var expandedThickness: Double = 260
    /// Eingeklappt nur einen schmalen Rand zeigen
    var autoHide: Bool = false
    /// Verzögerung (Sekunden), bevor die Sidebar beim Hover aufklappt
    var hoverDelay: Double = 0.15
    var defaultOpenMode: OpenMode = .defaultBrowser
    var chromiumBundleID: String = "com.google.Chrome"
}

extension SidebarSettings {
    /// Tolerantes Dekodieren: fehlende Felder (z. B. nach Updates) bekommen Standardwerte.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screenID = try c.decodeIfPresent(UInt32.self, forKey: .screenID)
        screenName = try c.decodeIfPresent(String.self, forKey: .screenName)
        edge = try c.decodeIfPresent(ScreenEdge.self, forKey: .edge) ?? edge
        collapsedThickness = try c.decodeIfPresent(Double.self, forKey: .collapsedThickness) ?? collapsedThickness
        expandedThickness = try c.decodeIfPresent(Double.self, forKey: .expandedThickness) ?? expandedThickness
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? autoHide
        hoverDelay = try c.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? hoverDelay
        defaultOpenMode = try c.decodeIfPresent(OpenMode.self, forKey: .defaultOpenMode) ?? defaultOpenMode
        chromiumBundleID = try c.decodeIfPresent(String.self, forKey: .chromiumBundleID) ?? chromiumBundleID
    }
}

struct SidebarConfig: Codable {
    var settings = SidebarSettings()
    var groups: [LinkGroup] = []
}

extension SidebarConfig {
    /// Beispielkonfiguration beim ersten Start.
    static var sample: SidebarConfig {
        SidebarConfig(settings: SidebarSettings(), groups: [
            LinkGroup(name: "Fotografie", symbol: "camera.aperture", items: [
                LinkItem(name: "Lightroom", urlString: "https://lightroom.adobe.com"),
                LinkItem(name: "Instagram", urlString: "https://www.instagram.com"),
                LinkItem(name: "Pinterest", urlString: "https://www.pinterest.com"),
            ]),
            LinkGroup(name: "ADS", symbol: "megaphone", items: [
                LinkItem(name: "Google Ads", urlString: "https://ads.google.com"),
                LinkItem(name: "Meta Business Suite", urlString: "https://business.facebook.com"),
                LinkItem(name: "Google Analytics", urlString: "https://analytics.google.com"),
            ]),
        ])
    }
}
