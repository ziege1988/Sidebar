import AppKit
import WebKit

/// Verwaltet die integrierten App-Fenster (ein Fenster pro Link).
@MainActor
final class WebAppManager {
    static let shared = WebAppManager()
    private var controllers: [UUID: WebAppController] = [:]

    func open(item: LinkItem, url: URL) {
        if let existing = controllers[item.id] {
            existing.show()
            return
        }
        let controller = WebAppController(item: item, url: url)
        let id = item.id
        controller.onClose = { [weak self] in
            self?.controllers[id] = nil
        }
        controllers[id] = controller
        controller.show()
    }
}

/// Ein schlankes Browser-Fenster für eine einzelne Web-App.
/// Cookies/Logins werden dauerhaft gespeichert (gemeinsam für alle App-Fenster).
@MainActor
final class WebAppController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let window: NSWindow
    let webView: WKWebView
    var onClose: (@MainActor () -> Void)?

    private let appName: String
    private var titleObservation: NSKeyValueObservation?
    private var popupWindows: [NSWindow] = []
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    init(item: LinkItem, url: URL) {
        appName = item.displayName

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
        window.setFrameUsingName(autosaveName)
        installToolbarButtons()

        webView.navigationDelegate = self
        webView.uiDelegate = self

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateTitle() }
        }

        webView.load(URLRequest(url: url))
    }

    func show() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        DockPresence.present(window)
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
        window.subtitle = webView.title ?? ""
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === window {
            let popups = popupWindows
            popupWindows.removeAll()
            popups.forEach { $0.close() }
            titleObservation = nil
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
