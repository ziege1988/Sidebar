import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@main
enum SidebarMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

/// Ziel für Menüeinträge mit Closure.
final class MenuAction: NSObject {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor @objc func fire(_ sender: Any?) {
        handler()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: ConfigStore!
    private var sidebar: SidebarController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ConfigStore.shared
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        let actions = SidebarActions(
            open: { [weak self] item, mode in
                guard let self else { return }
                self.sidebar.hideFlyout()
                LinkOpener.open(item, mode: mode, settings: self.store.config.settings)
            },
            openSettings: { [weak self] in
                self?.showSettings()
            },
            editItem: { [weak self] id in
                self?.showSettings(request: .edit(id))
            },
            addLink: { [weak self] containerID in
                self?.showSettings(request: .add(containerID))
            },
            chooseIcon: { [weak self] id in
                self?.chooseIcon(for: id)
            },
            toggleFlyout: { [weak self] id in
                self?.sidebar.toggleFlyout(id)
            },
            installUpdate: {
                if let release = Updater.shared.availableRelease {
                    Updater.shared.promptToInstall(release)
                }
            },
            openSearch: { [weak self] in
                self?.sidebar.showInput(.google)
            },
            triggerAction: { [weak self] action in
                self?.runAction(action, text: nil)
            },
            submitAction: { [weak self] action, text in
                self?.runAction(action, text: text)
            },
            drag: { [weak self] phase, point in
                self?.sidebar.handleDrag(phase, at: point)
            }
        )
        sidebar = SidebarController(store: store, updater: Updater.shared, actions: actions)
        setupStatusItem()

        Updater.shared.startAutomaticChecks { [weak self] in
            self?.store.config.settings.autoCheckUpdates ?? false
        }

        // Eingabefeld neben KI/Google: ↩ führt aus
        HoverInputController.shared.onSubmit = { [weak self] text, action in
            MainActor.assumeIsolated { self?.runAction(action, text: text) }
        }

        // Benachrichtigungen: Klick auf eine Mitteilung öffnet das App-Fenster
        SystemNotifier.shared.setUp()
        SystemNotifier.shared.onOpen = { [weak self] id in
            MainActor.assumeIsolated {
                guard let self, let item = self.store.item(id: id) else { return }
                LinkOpener.open(item, mode: .appWindow, settings: self.store.config.settings)
            }
        }

        // Web-Apps mit „Im Hintergrund aktiv“ (und Messenger) unsichtbar geladen halten
        store.$config
            .map { config in
                (config.favorites + config.groups.flatMap(\.items)).filter {
                    $0.runsInBackground(autoMessengers: config.settings.messengerBackground)
                }
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { items in
                WebAppManager.shared.syncBackgroundApps(items)
            }
            .store(in: &cancellables)

        // Mitteilungs-Einstellungen (Ruhemodus, Aufleuchten, Vorschau) und Dock-Zahlen von Programmen
        store.$config
            .receive(on: RunLoop.main)
            .sink { config in
                MainActor.assumeIsolated {
                    AlertState.shared.apply(config.settings)
                    DockBadgeWatcher.shared.update(items: config.favorites + config.groups.flatMap(\.items),
                                                   enabled: config.settings.dockBadges)
                }
            }
            .store(in: &cancellables)

        // Dock-Symbol wieder ausblenden, sobald das letzte Fenster geschlossen ist.
        _ = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in DockPresence.update() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - Einstellungen

    @objc func showSettingsAction(_ sender: Any?) {
        showSettings()
    }

    func showSettings(request: SettingsRouter.Request? = nil) {
        sidebar?.hideFlyout()
        if let request {
            SettingsRouter.shared.request = request
        }
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(store: store, updater: Updater.shared,
                                                                  router: SettingsRouter.shared))
            host.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: host)
            window.title = "Sidebar – Einstellungen"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 820, height: 580))
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            settingsWindow = window
        }
        if let settingsWindow {
            DockPresence.present(settingsWindow)
        }
    }

    // MARK: - KI & Google

    /// Klick auf KI/Google (ohne Text) bzw. ↩ im Eingabefeld (mit Text).
    private func runAction(_ action: ActionButton, text: String?) {
        let settings = store.config.settings
        if text == nil { sidebar.suppressHoverInput(action) }
        switch action {
        case .note:
            if let text {
                store.addNote(text)
            } else {
                NotesController.shared.show(store: store, anchor: sidebar.anchor(for: .note),
                                            edge: settings.edge, theme: settings.colorTheme)
            }
        case .google:
            if let text {
                QuickSearchController.run(text, target: .google)
            } else if let url = URL(string: "https://www.google.com") {
                NSWorkspace.shared.open(url)
            }
        case .ai:
            let provider = settings.aiProvider
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: provider.bundleID)
            guard settings.aiTarget == .desktopApp, let appURL else {
                // Seitenfenster (oder Desktop-App nicht installiert)
                WebAppManager.shared.openAI(provider, query: text, beside: sidebar.barFrame, edge: settings.edge)
                return
            }
            if let text {
                // Frage in die Zwischenablage – in der App mit ⌘V einfügen, falls sie nicht übernommen wird
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                if provider == .claude {
                    QuickSearchController.run(text, target: .claude)
                    return
                }
            }
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Eigenes Bild als Icon

    private func chooseIcon(for itemID: UUID) {
        sidebar.hideFlyout()
        let panel = NSOpenPanel()
        panel.title = "Bild für das Icon wählen"
        panel.message = "Das Bild wird quadratisch zugeschnitten."
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        store.setCustomIcon(itemID: itemID, image: image)
    }

    // MARK: - Menüleisten-Symbol

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Sidebar")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = store.config.settings

        menu.addItem(menuItem("Google Suche …") { [weak self] in self?.sidebar.showInput(.google) })
        menu.addItem(menuItem("KI fragen …") { [weak self] in self?.sidebar.showInput(.ai) })
        menu.addItem(menuItem("Schnellnotizen …") { [weak self] in self?.runAction(.note, text: nil) })
        menu.addItem(menuItem("Einstellungen …", key: ",") { [weak self] in self?.showSettings() })
        menu.addItem(.separator())

        let quiet = menuItem("Ruhemodus (keine Zahlen, Töne, Banner)") { [weak self] in
            self?.store.config.settings.quietMode.toggle()
        }
        quiet.state = settings.quietMode ? .on : .off
        menu.addItem(quiet)

        let visible = sidebar.isVisible
        menu.addItem(menuItem(visible ? "Sidebar ausblenden" : "Sidebar einblenden") { [weak self] in
            self?.sidebar.setVisible(!visible)
        })

        let onTop = menuItem("Immer im Vordergrund") { [weak self] in
            self?.store.config.settings.alwaysOnTop.toggle()
        }
        onTop.state = settings.alwaysOnTop ? .on : .off
        menu.addItem(onTop)

        let autoHide = menuItem("Automatisch ausblenden") { [weak self] in
            self?.store.config.settings.autoHide.toggle()
        }
        autoHide.state = settings.autoHide ? .on : .off
        menu.addItem(autoHide)

        let appearanceMenu = NSMenu()
        for mode in AppearanceMode.allCases {
            let item = menuItem(mode.title) { [weak self] in
                self?.store.config.settings.appearance = mode
            }
            item.state = settings.appearance == mode ? .on : .off
            appearanceMenu.addItem(item)
        }
        let appearanceItem = NSMenuItem(title: "Farben", action: nil, keyEquivalent: "")
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)
        menu.addItem(.separator())

        // Seite
        let edgeMenu = NSMenu()
        for edge in ScreenEdge.allCases {
            let item = menuItem(edge.title) { [weak self] in
                self?.store.config.settings.edge = edge
            }
            item.state = settings.edge == edge ? .on : .off
            edgeMenu.addItem(item)
        }
        let edgeItem = NSMenuItem(title: "Seite", action: nil, keyEquivalent: "")
        edgeItem.submenu = edgeMenu
        menu.addItem(edgeItem)

        // Bildschirm
        let screenMenu = NSMenu()
        let current = sidebar.currentScreen
        for screen in NSScreen.screens {
            let item = menuItem(screen.localizedName) { [weak self] in
                self?.store.setScreen(screen)
            }
            item.state = screen == current ? .on : .off
            screenMenu.addItem(item)
        }
        let screenItem = NSMenuItem(title: "Bildschirm", action: nil, keyEquivalent: "")
        screenItem.submenu = screenMenu
        menu.addItem(screenItem)

        menu.addItem(.separator())
        let updater = Updater.shared
        if let release = updater.availableRelease {
            menu.addItem(menuItem("Update auf \(release.version) installieren …") {
                updater.promptToInstall(release)
            })
        } else {
            let check = menuItem("Nach Updates suchen …") {
                Task { await updater.check(userInitiated: true) }
            }
            check.isEnabled = !updater.isBusy
            menu.addItem(check)
        }
        let versionItem = NSMenuItem(title: "Version \(updater.currentVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("Sidebar neu starten") { [weak self] in self?.relaunch() })
        menu.addItem(menuItem("Sidebar beenden", key: "q") { NSApp.terminate(nil) })
    }

    /// Startet die App neu (falls einmal etwas hängt).
    private func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$1\"", "sidebar-restart", path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func menuItem(_ title: String, key: String = "", action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let target = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire(_:)), keyEquivalent: key)
        item.target = target
        item.representedObject = target // hält das Ziel am Leben
        return item
    }

    // MARK: - Hauptmenü (für ⌘C/⌘V/⌘W … in Einstellungen und App-Fenstern)

    private func installMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Einstellungen …", action: #selector(showSettingsAction(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sidebar beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editMenu = NSMenu(title: "Bearbeiten")
        editMenu.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewMenu = NSMenu(title: "Darstellung")
        viewMenu.addItem(withTitle: "Neu laden", action: #selector(WKWebViewActions.reload(_:)), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Zurück", action: #selector(WKWebViewActions.goBack(_:)), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "Vor", action: #selector(WKWebViewActions.goForward(_:)), keyEquivalent: "]")
        let viewItem = NSMenuItem()
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let windowMenu = NSMenu(title: "Fenster")
        windowMenu.addItem(withTitle: "Schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Im Dock ablegen", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}

/// Selektoren, die WKWebView über die Responder-Kette beantwortet.
@objc protocol WKWebViewActions {
    func reload(_ sender: Any?)
    func goBack(_ sender: Any?)
    func goForward(_ sender: Any?)
}
