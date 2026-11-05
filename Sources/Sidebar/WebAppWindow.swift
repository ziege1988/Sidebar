import AppKit
import WebKit

/// Verwaltet die integrierten App-Fenster (ein Fenster pro Link).
@MainActor
final class WebAppManager {
    static let shared = WebAppManager()
    private var controllers: [UUID: WebAppController] = [:]

    func open(item: LinkItem, url: URL) {
        controller(for: item, url: url).show()
    }

    /// Feste Fenster-IDs je KI (Position und Größe werden pro Anbieter gemerkt)
    static func aiWindowID(_ provider: AIProvider) -> UUID {
        switch provider {
        case .claude: return UUID(uuidString: "00000000-0000-0000-0000-00000000C1AD")!
        case .chatgpt: return UUID(uuidString: "00000000-0000-0000-0000-00000000C6B7")!
        }
    }

    /// KI als Seitenfenster neben der Sidebar (Weg 1: Webseite mit deinem Konto).
    /// - Parameter query: Frage, die ins Eingabefeld übernommen wird (zusätzlich in der Zwischenablage)
    func openAI(_ provider: AIProvider, query: String?, beside bar: NSRect, edge: ScreenEdge) {
        if let query, !query.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(query, forType: .string)
        }
        guard let url = provider.webURL(query: query) else { return }
        let id = Self.aiWindowID(provider)
        let item = LinkItem(id: id, name: provider.title, urlString: provider.homeURL)
        let isNew = controllers[id] == nil
        let controller = controller(for: item, url: url)
        if !isNew { controller.load(url) }
        if !controller.hasSavedFrame, isNew,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(bar) }) {
            // Beim ersten Mal direkt neben die Sidebar setzen
            let area = screen.visibleFrame
            let width: CGFloat = 480
            var frame = NSRect(x: 0, y: area.minY + 12, width: width, height: area.height - 24)
            switch edge {
            case .left: frame.origin.x = bar.maxX + 8
            case .right: frame.origin.x = bar.minX - 8 - width
            case .top, .bottom: frame.origin.x = area.maxX - width - 12
            }
            controller.window.setFrame(frame, display: true)
        }
        controller.show()
    }

    /// Hält Web-Apps mit „Im Hintergrund aktiv“ unsichtbar geladen, damit Benachrichtigungen ankommen.
    func syncBackgroundApps(_ items: [LinkItem]) {
        let wanted = Set(items.map(\.id))
        for item in items where controllers[item.id] == nil {
            guard let url = item.url, !url.isFileURL else { continue }
            _ = controller(for: item, url: url)
        }
        for (id, controller) in controllers where !wanted.contains(id) {
            controller.keepAlive = false
            if !controller.window.isVisible && !controller.window.isMiniaturized {
                controller.window.close()
            }
        }
    }

    private func controller(for item: LinkItem, url: URL) -> WebAppController {
        if let existing = controllers[item.id] { return existing }
        let controller = WebAppController(item: item, url: url)
        let id = item.id
        controller.onClose = { [weak self] in
            self?.controllers[id] = nil
        }
        controllers[id] = controller
        return controller
    }
}

/// Leitet Nachrichten aus der Webseite weiter, ohne den Controller festzuhalten.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebAppController?

    init(_ target: WebAppController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated {
            target?.handleWebNotification(body)
        }
    }
}

/// Ein schlankes Browser-Fenster für eine einzelne Web-App.
/// Cookies/Logins werden dauerhaft gespeichert (gemeinsam für alle App-Fenster).
@MainActor
final class WebAppController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let window: NSWindow
    let webView: WKWebView
    var onClose: (@MainActor () -> Void)?
    /// Beim Schließen nur ausblenden (Benachrichtigungen laufen weiter)
    var keepAlive: Bool

    private let item: LinkItem
    private var titleCount = 0
    /// Fenster hatte schon eine gespeicherte Position/Größe
    private(set) var hasSavedFrame = false
    private let appName: String
    private var titleObservation: NSKeyValueObservation?
    private var popupWindows: [NSWindow] = []
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    /// Ersetzt `window.Notification` der Webseite, damit Mitteilungen als macOS-Banner erscheinen.
    private static let notificationShim = """
    (function () {
      function post(title, options) {
        try {
          window.webkit.messageHandlers.sidebarNotify.postMessage({
            title: String(title || ''),
            body: String((options && options.body) || '')
          });
        } catch (e) {}
      }
      function SidebarNotification(title, options) { post(title, options); this.title = title; }
      SidebarNotification.permission = 'granted';
      SidebarNotification.requestPermission = function (callback) {
        if (callback) { callback('granted'); }
        return Promise.resolve('granted');
      };
      SidebarNotification.prototype.close = function () {};
      SidebarNotification.prototype.addEventListener = function () {};
      window.Notification = SidebarNotification;
    })();
    """

    init(item: LinkItem, url: URL) {
        self.item = item
        appName = item.displayName
        keepAlive = item.keepAlive == true

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Wie Safari auftreten – manche Dienste (z. B. Google-Login) blockieren sonst eingebettete Browser.
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true

        let frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init()

        window.title = appName
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentView = webView
        window.delegate = self
        window.center()
        let autosaveName = "WebApp-\(item.id.uuidString)"
        window.setFrameAutosaveName(autosaveName)
        hasSavedFrame = window.setFrameUsingName(autosaveName)
        installToolbarButtons()

        webView.navigationDelegate = self
        webView.uiDelegate = self

        let contentController = webView.configuration.userContentController
        contentController.addUserScript(WKUserScript(source: Self.notificationShim,
                                                     injectionTime: .atDocumentStart,
                                                     forMainFrameOnly: false))
        contentController.add(WeakScriptHandler(self), name: "sidebarNotify")

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateTitle() }
        }

        webView.load(URLRequest(url: url))
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func show() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        DockPresence.present(window)
        // Gesehen: nur noch den Zähler aus dem Seitentitel anzeigen
        BadgeStore.shared.set(titleCount, for: item)
    }

    /// Mitteilung aus der Webseite (über window.Notification)
    func handleWebNotification(_ body: Any) {
        guard let dict = body as? [String: Any] else { return }
        let title = (dict["title"] as? String) ?? ""
        let text = (dict["body"] as? String) ?? ""
        SystemNotifier.shared.post(title: title.isEmpty ? appName : "\(appName): \(title)",
                                   body: text, itemID: item.id)
        // Seiten ohne Zähler im Titel: selbst mitzählen, solange das Fenster nicht vorne ist
        if titleCount == 0 && !(window.isKeyWindow && NSApp.isActive) {
            BadgeStore.shared.increment(for: item)
        }
    }

    // MARK: - Titelleiste

    private func installToolbarButtons() {
        let buttons = [
            makeButton("chevron.left", "Zurück", #selector(goBack)),
            makeButton("chevron.right", "Vor", #selector(goForward)),
            makeButton("arrow.clockwise", "Neu laden", #selector(reloadPage)),
            makeButton("safari", "Im Standard-Browser öffnen", #selector(openInBrowser)),
        ]
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 10)
        stack.setFrameSize(NSSize(width: stack.fittingSize.width, height: 28))

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = stack
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
    }

    private func makeButton(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.toolTip = label
        return button
    }

    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func reloadPage() { webView.reload() }
    @objc private func openInBrowser() {
        if let url = webView.url { NSWorkspace.shared.open(url) }
    }

    private func updateTitle() {
        let title = webView.title ?? ""
        window.subtitle = title
        let count = BadgeStore.count(fromTitle: title)
        if count != titleCount {
            titleCount = count
            BadgeStore.shared.set(count, for: item)
        }
    }

    // Fenster mit „Im Hintergrund aktiv“ nur ausblenden statt schließen
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window, keepAlive else { return true }
        window.orderOut(nil)
        Task { @MainActor in DockPresence.update() }
        return false
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === window {
            let popups = popupWindows
            popupWindows.removeAll()
            popups.forEach { $0.close() }
            titleObservation = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "sidebarNotify")
            BadgeStore.shared.set(0, for: item)
            webView.stopLoading()
            onClose?()
        } else {
            popupWindows.removeAll { $0 === closing }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // mailto:, tel:, zoommtg: … an das zuständige Programm übergeben
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: - WKDownloadDelegate (Downloads landen im Ordner „Downloads“)

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let destination = Self.uniqueDownloadURL(for: suggestedFilename)
        downloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) {
            // Lässt den Downloads-Stapel im Dock hüpfen.
            DistributedNotificationCenter.default().post(
                name: Notification.Name("com.apple.DownloadFileFinished"),
                object: destination.path
            )
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        NSLog("Sidebar: Download fehlgeschlagen: \(error.localizedDescription)")
    }

    private static func uniqueDownloadURL(for filename: String) -> URL {
        let fm = FileManager.default
        let folder = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = filename.isEmpty ? "Download" : filename
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    // MARK: - WKUIDelegate

    /// Neue Fenster: Links mit target="_blank" → Standard-Browser.
    /// Per Skript geöffnete Fenster (z. B. Login-Popups) → eigenes Popup-Fenster,
    /// damit die Verbindung zum Hauptfenster erhalten bleibt.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            return nil
        }

        let width = windowFeatures.width?.doubleValue ?? 1000
        let height = windowFeatures.height?.doubleValue ?? 760
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let popup = WKWebView(frame: rect, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self

        let popupWindow = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        popupWindow.isReleasedWhenClosed = false
        popupWindow.title = appName
        popupWindow.contentView = popup
        popupWindow.delegate = self
        popupWindow.center()
        popupWindow.makeKeyAndOrderFront(nil)
        popupWindows.append(popupWindow)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let host = webView.window {
            host.close()
        }
    }

    /// Datei-Upload (z. B. Bilder hochladen)
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        completionHandler(panel.runModal() == .OK ? panel.urls : nil)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = appName
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = appName
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Abbrechen")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}
