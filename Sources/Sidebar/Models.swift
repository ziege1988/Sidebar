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
    /// Dateiname eines eigenen Bildes in `…/Sidebar/Icons` (`nil` = Favicon der Seite)
    var customIcon: String?
    /// Im Hintergrund geladen halten, damit Benachrichtigungen ankommen (nur integriertes App-Fenster)
    var keepAlive: Bool?

    var url: URL? { LinkItem.normalizedURL(from: urlString) }
    var host: String? { url?.host }

    /// Programm, Datei oder Ordner auf dem Mac (statt Webadresse)
    var isLocal: Bool { url?.isFileURL == true }

    /// Webadresse bzw. Pfad auf dem Mac – zum Anzeigen
    var location: String {
        if isLocal, let url { return url.path }
        return urlString
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let url, url.isFileURL { return LinkItem.suggestedName(for: url) }
        if let host { return LinkItem.prettyHost(host) }
        return urlString
    }

    /// Ergänzt fehlendes `https://` und prüft, ob ein Host vorhanden ist.
    /// Pfade auf dem Mac (`file://…`, `/Applications/…`, `~/…`) werden ebenfalls akzeptiert.
    static func normalizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("file://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func prettyHost(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func suggestedName(for url: URL) -> String {
        if url.isFileURL {
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        if let host = url.host { return prettyHost(host) }
        return url.absoluteString
    }
}

/// Eine Schnellnotiz.
struct QuickNote: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var date = Date()
}

/// Untergruppe, z. B. „Fotografie“ oder „ADS“.
struct LinkGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
    var items: [LinkItem] = []

    /// Fester Bezeichner für die Favoritenleiste (wird wie eine Gruppe adressiert).
    static let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-00000000FA00")!
    /// Fester Bezeichner für das Ablagefach (öffnet sich wie ein Ordner)
    static let shelfID = UUID(uuidString: "00000000-0000-0000-0000-00000000AB1A")!
}

/// Wo Fragen an die KI geöffnet werden.
enum AITarget: String, Codable, CaseIterable, Identifiable {
    /// Webseite des Anbieters in einem Seitenfenster neben der Sidebar
    case sidePanel
    /// Desktop-App des Anbieters
    case desktopApp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sidePanel: return "Seitenfenster neben der Sidebar"
        case .desktopApp: return "Desktop-App"
        }
    }
}

/// Welche KI hinter dem KI-Knopf steckt.
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case chatgpt, claude
    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        }
    }

    /// Bundle-ID der Mac-App
    var bundleID: String {
        switch self {
        case .chatgpt: return "com.openai.chat"
        case .claude: return "com.anthropic.claudefordesktop"
        }
    }

    var homeURL: String {
        switch self {
        case .chatgpt: return "https://chatgpt.com/"
        case .claude: return "https://claude.ai/new"
        }
    }

    /// Webadresse, die die Frage ins Eingabefeld übernimmt (inoffiziell, nicht dokumentiert)
    func webURL(query: String?) -> URL? {
        guard let query, !query.isEmpty else { return URL(string: homeURL) }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return URL(string: homeURL + "?q=" + encoded)
    }
}

/// Hell (Pastell-Salbei), Dunkel (Pastell-Graphit) oder automatisch wie macOS.
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Automatisch (wie macOS)"
        case .light: return "Hell (Pastell)"
        case .dark: return "Dunkel (Graphit)"
        }
    }
}

struct SidebarSettings: Codable, Equatable {
    /// CGDirectDisplayID des gewählten Bildschirms (`nil` = primärer Bildschirm)
    var screenID: UInt32?
    /// Name des Bildschirms als Fallback, falls sich die ID ändert
    var screenName: String?
    var edge: ScreenEdge = .left
    var collapsedThickness: Double = 56
    /// Breite des Ordner-Fensters, das sich beim Hover öffnet
    var expandedThickness: Double = 260
    /// Eingeklappt nur einen schmalen Rand zeigen
    var autoHide: Bool = false
    /// Verzögerung (Sekunden), bevor die Sidebar beim Hover aufklappt
    var hoverDelay: Double = 0.15
    var defaultOpenMode: OpenMode = .defaultBrowser
    var chromiumBundleID: String = "com.google.Chrome"
    var autoCheckUpdates: Bool = true
    /// true = über allen Fenstern, false = normale Fensterebene (kommt beim Hover nach vorne)
    var alwaysOnTop: Bool = true
    var appearance: AppearanceMode = .system
    /// Lupen-Effekt: Icons unter der Maus vergrößern (wie im Dock)
    var magnification: Bool = true
    /// Stärke der Lupe (1,1 = dezent … 1,8 = stark)
    var magnificationStrength: Double = 1.45
    var colorTheme: ColorTheme = .sage
    /// Hintergrund als Verlauf: oben dunkler, unten heller
    var gradient: Bool = true
    /// Glas-Effekt (0 = deckend … 1 = stark durchscheinend, Farbe bleibt erkennbar)
    var glassIntensity: Double = 0.4
    var showClock: Bool = true
    /// Durchmesser der Uhr in Punkten
    var clockSize: Double = 128
    /// Interne Version der Einstellungen (für einmalige Anpassungen nach Updates)
    var revision: Int = 1
    var clockShowSeconds: Bool = true
    /// KI- und Google-Knopf oben in der Leiste
    var showSearch: Bool = true
    var aiTarget: AITarget = .sidePanel
    var aiProvider: AIProvider = .chatgpt
    var showShelf: Bool = true
    var showNotes: Bool = true
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
        autoCheckUpdates = try c.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates) ?? autoCheckUpdates
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? alwaysOnTop
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? appearance
        magnification = try c.decodeIfPresent(Bool.self, forKey: .magnification) ?? magnification
        magnificationStrength = try c.decodeIfPresent(Double.self, forKey: .magnificationStrength) ?? magnificationStrength
        colorTheme = try c.decodeIfPresent(ColorTheme.self, forKey: .colorTheme) ?? colorTheme
        gradient = try c.decodeIfPresent(Bool.self, forKey: .gradient) ?? gradient
        glassIntensity = try c.decodeIfPresent(Double.self, forKey: .glassIntensity) ?? glassIntensity
        showClock = try c.decodeIfPresent(Bool.self, forKey: .showClock) ?? showClock
        clockSize = try c.decodeIfPresent(Double.self, forKey: .clockSize) ?? clockSize
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        clockShowSeconds = try c.decodeIfPresent(Bool.self, forKey: .clockShowSeconds) ?? clockShowSeconds
        showSearch = try c.decodeIfPresent(Bool.self, forKey: .showSearch) ?? showSearch
        aiTarget = try c.decodeIfPresent(AITarget.self, forKey: .aiTarget) ?? aiTarget
        aiProvider = try c.decodeIfPresent(AIProvider.self, forKey: .aiProvider) ?? aiProvider
        showShelf = try c.decodeIfPresent(Bool.self, forKey: .showShelf) ?? showShelf
        showNotes = try c.decodeIfPresent(Bool.self, forKey: .showNotes) ?? showNotes
    }
}

struct SidebarConfig: Codable {
    static let maxFavorites = 10

    var settings = SidebarSettings()
    var favorites: [LinkItem] = []
    var groups: [LinkGroup] = []
    /// Ablagefach: Verweise auf Dateien (file://-Adressen), die Dateien bleiben, wo sie sind
    var shelf: [String] = []
    /// Schnellnotizen (neueste zuerst)
    var notes: [QuickNote] = []
}

extension SidebarConfig {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(SidebarSettings.self, forKey: .settings) ?? settings
        favorites = try c.decodeIfPresent([LinkItem].self, forKey: .favorites) ?? []
        groups = try c.decodeIfPresent([LinkGroup].self, forKey: .groups) ?? []
        shelf = try c.decodeIfPresent([String].self, forKey: .shelf) ?? []
        notes = try c.decodeIfPresent([QuickNote].self, forKey: .notes) ?? []
    }
}

extension SidebarConfig {
    /// Beispielkonfiguration beim ersten Start.
    static var sample: SidebarConfig {
        SidebarConfig(settings: SidebarSettings(), favorites: [], groups: [
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
