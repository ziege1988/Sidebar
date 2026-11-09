import AppKit
import Combine
import SwiftUI

/// Rahmenloses, schwebendes Panel, das die App nicht aktiviert
/// (der Fokus bleibt in der App, mit der du gerade arbeitest).
final class SidebarPanel: NSPanel {
    /// Nur die Leiste selbst (wegen der Eingabefelder) – und nur, wenn ein Feld angeklickt wird
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Hosting-View, die bereits den ersten Klick annimmt (kein „Fokus-Klick“ nötig).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Steuert die Leiste, das Ordner-Fenster und das Verschieben.
///
/// Die Maus wird 20× pro Sekunde abgefragt. Das ist zuverlässiger als Hover-Ereignisse,
/// funktioniert auch während Drag & Drop aus dem Browser und kostet praktisch keine Leistung.
@MainActor
final class SidebarController {
    let state = SidebarState()
    private let store: ConfigStore
    private let geometry = SidebarGeometry()
    private let panel: SidebarPanel
    private let flyoutPanel: SidebarPanel
    private let labelPanel: SidebarPanel
    private let labelHost: NSHostingView<HoverLabel>
    private let labelMeasure: NSHostingController<HoverLabel>
    private var labelItemID: UUID?
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private(set) var isVisible = true

    // Hover-Zustand
    private var candidateGroup: UUID?
    private var candidateSince = Date.distantPast
    private var flyoutLeftAt: Date?
    private var barLeftAt: Date?
    private var barEnteredAt: Date?
    private var anchorRect: NSRect = .zero
    private var isDragging = false
    private var candidateAction: ActionButton?
    /// Nach einem Klick auf KI/Google/Notiz keine Eingabeblase, bis die Maus den Knopf verlässt
    private var suppressedAction: ActionButton?
    private var candidateActionSince = Date.distantPast
    private var inputLeftAt: Date?
    private var lastAutoHide: Bool?
    /// Mini-Vorschau: Link unter der Maus und seit wann
    private var previewCandidate: UUID?
    private var previewSince = Date.distantPast

    /// Breite des sichtbaren Streifens bei „Automatisch ausblenden“
    private static let hiddenThickness: CGFloat = 6

    /// Halbtransparente Vorschau, wo die Sidebar beim Loslassen andockt.
    private lazy var previewPanel: NSPanel = {
        let preview = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        preview.isOpaque = false
        preview.backgroundColor = .clear
        preview.hasShadow = false
        preview.ignoresMouseEvents = true
        preview.isReleasedWhenClosed = false
        preview.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
        view.layer?.borderWidth = 2
        view.layer?.cornerRadius = 12
        preview.contentView = view
        return preview
    }()

    private let updater: Updater
    private let actions: SidebarActions
    private var lastLayoutKey: String?
    private var clickMonitor: Any?

    /// Klicks auf den Notiz-Knopf direkt am Fenster abfangen – zuverlässiger als die SwiftUI-Knöpfe,
    /// die einen Klick verlieren können, wenn sich die Leiste gerade neu zeichnet (Lupe, Blase).
    /// Klicks in die festen Eingabefelder machen die Leiste sofort zum Tastaturfenster.
    private func installClickMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let windowNumber = event.windowNumber
            let point = event.locationInWindow
            let consumed = MainActor.assumeIsolated {
                self?.handleClick(windowNumber: windowNumber, at: point) ?? false
            }
            return consumed ? nil : event
        }
    }

    /// - Returns: `true`, wenn der Klick hier verarbeitet wurde (nicht weiterreichen)
    private func handleClick(windowNumber: Int, at p: CGPoint) -> Bool {
        guard windowNumber == panel.windowNumber else { return false }
        let local = CGPoint(x: p.x, y: panel.frame.height - p.y)
        let frames = geometry.actionFrames
        // Querformat: der ganze rechte Teil des Notizfelds (Knopf + Umgebung) öffnet die Notizen
        let openZone = frames["noteField"].map { field in
            CGRect(x: field.maxX - 46, y: field.minY - 8, width: 54, height: field.height + 16)
        }
        if frames[ActionButton.note.rawValue]?.contains(local) == true
            || frames["noteOpen"]?.contains(local) == true
            || openZone?.contains(local) == true {
            actions.triggerAction(.note)
            return true
        }
        if frames["noteField"]?.contains(local) == true || frames["googleField"]?.contains(local) == true {
            NSApp.activate()
            panel.makeKey()
        }
        return false
    }

    /// Inhalt der Leiste (neu) aufbauen.
    private func installBarContent() {
        let bar = FirstMouseHostingView(rootView: SidebarView(store: store, state: state, updater: updater,
                                                              geometry: geometry, actions: actions))
        bar.sizingOptions = []
        panel.contentView = bar
    }

    /// Nach Änderungen am Aufbau (Uhr an/aus, Seite, Bildschirm, Breite …) die Leiste frisch laden –
    /// wie ein Neustart, nur unsichtbar. Verhindert, dass Teile (z. B. die Uhr) fehlen.
    private func reloadIfLayoutChanged(_ settings: SidebarSettings) {
        let key = [String(settings.showClock), String(Int(settings.clockSize)), settings.edge.rawValue,
                   String(settings.screenID ?? 0), String(Int(settings.collapsedThickness)),
                   String(settings.showSearch), String(settings.showNotes), String(settings.showShelf),
                   String(settings.autoHide)].joined(separator: "|")
        defer { lastLayoutKey = key }
        guard let lastLayoutKey, lastLayoutKey != key else { return }
        geometry.groupFrames = [:]
        geometry.favoriteFrames = [:]
        geometry.actionFrames = [:]
        state.hoveredCell = nil
        state.hoverRect = nil
        hideFlyout()
        installBarContent()
    }

    init(store: ConfigStore, updater: Updater, actions: SidebarActions) {
        self.store = store
        panel = SidebarController.makePanel()
        panel.allowsKey = true
        panel.becomesKeyOnlyIfNeeded = true
        flyoutPanel = SidebarController.makePanel()
        labelPanel = SidebarController.makePanel()
        labelHost = NSHostingView(rootView: HoverLabel(text: ""))
        labelMeasure = NSHostingController(rootView: HoverLabel(text: ""))
        labelPanel.ignoresMouseEvents = true
        labelHost.sizingOptions = []
        labelPanel.contentView = labelHost

        self.updater = updater
        self.actions = actions
        installBarContent()
        installClickMonitor()
        FloatingCat.shared.configure(store: store, openSettings: { actions.openSettings() },
                                     dockRect: { [weak self] in self?.dockedCatRect() },
                                     badgeRect: { [weak self] in self?.homeworkBadgeRect() })
        HomeworkController.shared.store = store

        let flyout = FirstMouseHostingView(rootView: FlyoutView(store: store, state: state, geometry: geometry,
                                                                actions: actions))
        flyout.sizingOptions = []
        flyoutPanel.contentView = flyout


        // Neue Nachricht → kurz neben dem Icon einblenden
        BadgeStore.shared.$toast
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] toast in
                MainActor.assumeIsolated { self?.showToast(toast) }
            }
            .store(in: &cancellables)

        // Einstellungen geändert (Seite, Bildschirm, Breite, Farben …)
        store.$config
            .map(\.settings)
            .removeDuplicates()
            .sink { [weak self] settings in self?.applySettings(settings) }
            .store(in: &cancellables)

        // Inhalt geändert → Ordner-Fenster an neue Höhe anpassen (nach dem Speichern)
        store.$config
            .map { ($0.groups, $0.shelf) }
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshFlyout() }
            }
            .store(in: &cancellables)

        // Stromsparen: beim Pausieren offene Einblendungen schließen, danach alles frisch einrichten
        PowerState.shared.$paused
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] paused in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if paused {
                        self.hideFlyout()
                        self.updateHovered(nil)
                        self.updateLabel(nil)
                        self.updatePreview(nil, now: Date())
                    } else {
                        self.barEnteredAt = nil
                        self.barLeftAt = nil
                        self.applySettings(self.store.config.settings)
                        if self.isVisible { self.panel.orderFrontRegardless() }
                    }
                }
            }
            .store(in: &cancellables)

        // Monitor angeschlossen/entfernt, Auflösung oder Dock geändert
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.hideFlyout()
                self.applySettings(self.store.config.settings)
            }
            .store(in: &cancellables)

        panel.orderFrontRegardless()
        startPolling()
    }

    private static func makePanel() -> SidebarPanel {
        let panel = SidebarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 56, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        return panel
    }

    // MARK: - Öffentliche Steuerung

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            // Frisch starten: eingeklappt bei „Automatisch ausblenden“, sonst voll sichtbar
            state.isRevealed = false
            barEnteredAt = nil
            barLeftAt = nil
            applySettings(store.config.settings)
            panel.orderFrontRegardless()
            panel.contentView?.needsLayout = true
            panel.displayIfNeeded()
        } else {
            hideFlyout()
            panel.orderOut(nil)
        }
    }

    var currentScreen: NSScreen? { targetScreen(for: store.config.settings) }

    func toggleFlyout(_ groupID: UUID) {
        if state.flyoutGroupID == groupID && flyoutPanel.isVisible {
            hideFlyout()
        } else {
            showFlyout(groupID)
        }
    }

    func hideFlyout() {
        LinkPreviewController.shared.hide()
        previewCandidate = nil
        state.flyoutGroupID = nil
        flyoutPanel.orderOut(nil)
        flyoutLeftAt = nil
    }

    // MARK: - Maus-Abfrage

    private func startPolling() {
        // 60× pro Sekunde, damit der Lupen-Effekt flüssig der Maus folgt
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common: läuft auch während Drag & Drop und Scrollen
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func tick() {
        // Niemand sieht hin (gesperrt, Bildschirmschoner, Displays aus) → nichts tun
        if PowerState.shared.paused { return }
        // Schwebender Rüdiger: sichtbar, solange die Sidebar läuft – auch wenn sie eingefahren ist
        FloatingCat.shared.update(sidebarVisible: isVisible)
        guard isVisible, !isDragging else {
            updateHovered(nil)
            updateLabel(nil)
            updatePreview(nil, now: Date())
            return
        }
        let settings = store.config.settings
        let mouse = NSEvent.mouseLocation
        let now = Date()
        // Kontextmenü offen oder Drag aus der Sidebar heraus → nichts schließen
        let tracking = RunLoop.current.currentMode == .eventTracking
        updateClickThrough(mouse: mouse, settings: settings, tracking: tracking)

        let input = HoverInputController.shared
        let inInput = input.isVisible
            && (input.frame.insetBy(dx: -6, dy: -6).contains(mouse)
                || input.anchor.union(input.frame).insetBy(dx: -4, dy: -4).contains(mouse))
        let inClock = clockRect(for: settings)?.contains(mouse) ?? false
        var inBar = stripFrame(for: settings).contains(mouse) || inClock
        // Nicht „immer im Vordergrund“: liegt ein anderes Programm über der Sidebar, reagiert sie dort nicht
        // (keine Namensschilder, keine Ordner durch fremde Fenster hindurch). Fährt die Maus auf einen
        // sichtbaren Teil der Sidebar, kommt sie nach vorne.
        if !settings.alwaysOnTop {
            if inBar && isCovered(at: mouse) {
                inBar = false
            } else if inBar && !broughtForward {
                broughtForward = true
                panel.orderFrontRegardless()
            } else if !inBar && !flyoutPanel.isVisible {
                broughtForward = false
            }
        }
        // Ausgeblendet: großzügiger Auslösebereich bis an den echten Bildschirmrand
        let inRevealZone = settings.autoHide && !state.isRevealed && revealZone(for: settings).contains(mouse)
        let flyoutVisible = flyoutPanel.isVisible
        let flyoutZone = flyoutPanel.frame.insetBy(dx: -8, dy: -8)
        // Korridor zwischen Ordner-Symbol und Ordner-Fenster (diagonale Mausbewegung)
        let corridor = anchorRect.union(flyoutPanel.frame).insetBy(dx: -4, dy: -4)
        let inFlyout = flyoutVisible && (flyoutZone.contains(mouse) || corridor.contains(mouse))
        // Rüdiger hält den Mund, solange du in der Sidebar arbeitest
        CatBrain.shared.sidebarBusy = inBar || inFlyout || input.isVisible || NotesController.shared.isVisible
        updateCatHover(mouse: mouse, now: now)

        // Link im Ordner-Fenster unter der Maus (Lupe + Hervorhebung)
        var row: UUID?
        if flyoutVisible && flyoutPanel.frame.contains(mouse) {
            let frame = flyoutPanel.frame
            let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
            row = geometry.flyoutRowFrames.first(where: { $0.value.contains(local) })?.key
        }
        if state.hoveredRow != row { state.hoveredRow = row }

        // 1. Automatisch ausblenden: Leiste ein-/ausfahren
        if settings.autoHide {
            if inBar || inClock || inRevealZone || inFlyout || tracking || input.isVisible
                || QuickSearchController.shared.isVisible || panel.isKeyWindow
                || NotesController.shared.isVisible {
                barLeftAt = nil
                if !state.isRevealed {
                    if barEnteredAt == nil { barEnteredAt = now }
                    if let entered = barEnteredAt, now.timeIntervalSince(entered) >= settings.hoverDelay {
                        setRevealed(true)
                    }
                }
            } else {
                barEnteredAt = nil
                if state.isRevealed {
                    if barLeftAt == nil { barLeftAt = now }
                    if let left = barLeftAt, now.timeIntervalSince(left) > 0.4 {
                        setRevealed(false)
                    }
                }
            }
        }

        // 2. Ordner-Symbol unter der Maus → Ordner-Fenster öffnen
        let barUsable = !settings.autoHide || state.isRevealed
        let hoveredGroup = (inBar && barUsable) ? groupAt(mouse) : nil
        if let group = hoveredGroup, group != state.flyoutGroupID || !flyoutVisible {
            if candidateGroup != group {
                candidateGroup = group
                candidateSince = now
            }
            let delay = flyoutVisible ? 0.08 : settings.hoverDelay
            if now.timeIntervalSince(candidateSince) >= delay {
                showFlyout(group)
            }
        } else if hoveredGroup == nil {
            candidateGroup = nil
        }

        // Favorit unter der Maus: nur den Namen zeigen, kein Ordner-Fenster
        let hoveredFavorite = (inBar && barUsable) ? favoriteAt(mouse) : nil
        // Mini-Vorschau nach längerem Verweilen (Favorit in der Leiste oder Link im Ordner)
        updatePreview(hoveredFavorite ?? row, now: now)
        // Während die Vorschau zu sehen ist, steht der Name schon darin
        updateLabel(LinkPreviewController.shared.isVisible ? nil : hoveredFavorite)

        // KI/Google unter der Maus → Eingabefeld daneben, sofort lostippen
        let hoveredAction = (inBar && barUsable) ? actionAt(mouse) : nil
        if hoveredAction != suppressedAction { suppressedAction = nil }
        if let action = hoveredAction, action != suppressedAction, !NotesController.shared.isVisible {
            if !(input.isVisible && input.kind == action) {
                if candidateAction != action {
                    candidateAction = action
                    candidateActionSince = now
                }
                // etwas längere Verzögerung, damit beim Vorbeifahren nicht der Fokus springt
                if now.timeIntervalSince(candidateActionSince) >= max(settings.hoverDelay, 0.3),
                   let anchor = screenRect(forAction: action) {
                    input.show(action, anchor: anchor, edge: settings.edge, theme: settings.colorTheme)
                    inputLeftAt = nil
                }
            }
        } else {
            candidateAction = nil
        }
        if input.isVisible {
            if hoveredAction != nil || inInput || input.hasText {
                inputLeftAt = nil
            } else {
                if inputLeftAt == nil { inputLeftAt = now }
                if let left = inputLeftAt, now.timeIntervalSince(left) > 0.8 {
                    input.close(restoreFocus: true)
                    inputLeftAt = nil
                }
            }
        }

        // Lupen-Effekt: genau das Element unter der Maus
        if let favorite = hoveredFavorite {
            updateHovered("fav:\(favorite)")
        } else if let action = hoveredAction {
            updateHovered("action:\(action.rawValue)")
        } else if let group = hoveredGroup {
            updateHovered("group:\(group)")
        } else {
            updateHovered(nil)
        }
        if hoveredFavorite != nil || hoveredAction != nil {
            if flyoutVisible { hideFlyout() }
            return
        }

        // 3. Ordner-Fenster schließen, wenn die Maus es verlassen hat
        if flyoutVisible {
            let keep = inFlyout || hoveredGroup != nil || tracking
            if keep {
                flyoutLeftAt = nil
            } else {
                if flyoutLeftAt == nil { flyoutLeftAt = now }
                if let left = flyoutLeftAt, now.timeIntervalSince(left) > 0.35 {
                    hideFlyout()
                }
            }
        }
    }

    private func updateHovered(_ value: String?) {
        if state.hoveredCell != value { state.hoveredCell = value }
        let rect = rectForHovered(value)
        if state.hoverRect != rect { state.hoverRect = rect }
    }

    /// Rahmen (Leisten-Koordinaten) des Elements unter der Maus.
    private func rectForHovered(_ key: String?) -> CGRect? {
        guard let key else { return nil }
        if key.hasPrefix("fav:"), let id = UUID(uuidString: String(key.dropFirst(4))) {
            return geometry.favoriteFrames[id]
        }
        if key.hasPrefix("group:"), let id = UUID(uuidString: String(key.dropFirst(6))) {
            return geometry.groupFrames[id]
        }
        if key.hasPrefix("action:") {
            return geometry.actionFrames[String(key.dropFirst(7))]
        }
        return nil
    }

    /// KI- bzw. Google-Knopf an einer Bildschirmposition.
    private func actionAt(_ point: NSPoint) -> ActionButton? {
        let frame = panel.frame
        let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        guard let key = geometry.actionFrames.first(where: { $0.value.contains(local) })?.key else { return nil }
        return ActionButton(rawValue: key)
    }

    private func screenRect(forAction action: ActionButton) -> NSRect? {
        guard let rect = geometry.actionFrames[action.rawValue] else { return nil }
        let frame = panel.frame
        return NSRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Bildschirmbereich eines Knopfs (für Fenster, die daneben aufgehen).
    func anchor(for action: ActionButton) -> NSRect {
        if let rect = screenRect(forAction: action) { return rect }
        // Querformat: festes Notizfeld statt Symbol
        if action == .note, let rect = geometry.actionFrames["noteField"] {
            let frame = panel.frame
            return NSRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        return barFrame
    }

    /// Nach einem Klick: Eingabeblase für diesen Knopf unterdrücken (sonst stiehlt sie dem
    /// gerade geöffneten Fenster den Fokus und es schließt sich wieder).
    func suppressHoverInput(_ action: ActionButton) {
        suppressedAction = action
        candidateAction = nil
        if HoverInputController.shared.kind == action {
            HoverInputController.shared.close(restoreFocus: false)
        }
    }

    /// Eingabefeld für Google öffnen (z. B. aus dem Menüleisten-Symbol).
    func showInput(_ action: ActionButton) {
        let settings = store.config.settings
        if let anchor = screenRect(forAction: action), panel.isVisible {
            HoverInputController.shared.show(action, anchor: anchor, edge: settings.edge, theme: settings.colorTheme)
        } else {
            openSearch()
        }
    }

    /// Rahmen der Leiste (für das Claude-Seitenfenster).
    var barFrame: NSRect { stripFrame(for: store.config.settings, forceVisible: true) }

    /// Favorit an einer Bildschirmposition.
    private func favoriteAt(_ point: NSPoint) -> UUID? {
        let frame = panel.frame
        let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        return geometry.favoriteFrames.first(where: { $0.value.contains(local) })?.key
    }

    /// Nachricht neben dem Favoriten (bzw. dem Ordner, in dem der Link liegt) einblenden.
    private func showToast(_ toast: BadgeStore.Toast) {
        let settings = store.config.settings
        guard !AlertState.shared.quiet else { return }
        // Rüdiger liest vor – dann keine Einblendung am Icon
        let brain = CatBrain.shared
        if brain.takesOverMessages {
            let items = store.config.favorites + store.config.groups.flatMap(\.items)
            let item = items.first { item in
                if let id = toast.itemID { return item.id == id }
                return toast.key != nil && BadgeStore.key(for: item) == toast.key
            }
            let app = DockBadgeWatcher.cleanDisplayName(item?.displayName ?? "Neue Nachricht")
            let isMail = item != nil && item?.id == settings.mailItemID && toast.itemID != nil
            var from = toast.title
            if isMail {
                // „Neue E-Mail · Absender“ bzw. „3 neue E-Mails“
                if let range = from.range(of: " · ") { from = String(from[range.upperBound...]) }
            }
            brain.announce(app: app, from: from, text: toast.body, isMail: isMail)
            return
        }
        guard isVisible, settings.messageToast else { return }
        let bar = stripFrame(for: settings, forceVisible: !settings.autoHide || state.isRevealed)
        var local: CGRect?
        func matches(_ item: LinkItem) -> Bool {
            if let id = toast.itemID { return item.id == id }
            return toast.key != nil && BadgeStore.key(for: item) == toast.key
        }
        if let item = store.config.favorites.first(where: matches) {
            local = geometry.favoriteFrames[item.id]
        } else if let group = store.config.groups.first(where: { $0.items.contains(where: matches) }) {
            local = geometry.groupFrames[group.id]
        }
        guard let rect = local else { return }
        let frame = panel.frame
        let anchor = NSRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        MessageToastController.shared.show(title: toast.title, message: toast.body, beside: bar, anchor: anchor,
                                           edge: settings.edge, theme: settings.colorTheme,
                                           duration: settings.messageToastDuration)
    }

    private var catHoverSince: Date?
    /// Sidebar wurde beim Darüberfahren schon nach vorne geholt
    private var broughtForward = false

    /// Liegt an dieser Stelle ein Fenster eines anderen Programms über der Sidebar?
    private func isCovered(at point: NSPoint) -> Bool {
        let top = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard top > 0 else { return false }
        return !NSApp.windows.contains { $0.windowNumber == top }
    }

    /// Versteckter Schalter: 4 Sekunden mit der Maus auf Rüdiger → „Schlummern ein/aus“
    private func updateCatHover(mouse: NSPoint, now: Date) {
        let brain = CatBrain.shared
        updateHomeworkBadge(mouse: mouse)
        guard let cat = catLocation()?.cat, cat.contains(mouse) else {
            catHoverSince = nil
            if brain.showSnoozeControl { brain.showSnoozeControl = false }
            return
        }
        if catHoverSince == nil { catHoverSince = now }
        if let since = catHoverSince, now.timeIntervalSince(since) >= 4, !brain.showSnoozeControl {
            brain.showSnoozeControl = true
        }
    }

    /// Knopf „Text prüfen“: sofort sichtbar, solange die Maus höchstens 40 pt vom Blasenrand entfernt ist
    private func updateHomeworkBadge(mouse: NSPoint) {
        let brain = CatBrain.shared
        var corner: CGPoint?
        var hover = false
        if let location = catLocation(), !brain.teaching, !brain.carried, brain.introDone {
            let cat = location.cat
            let c: CGPoint
            if location.floating {
                // zur Bildschirmmitte hin
                let screen = location.visible
                c = CGPoint(x: cat.midX < screen.midX ? 1 : -1, y: cat.midY > screen.midY ? 1 : -1)
            } else {
                switch location.edge {
                case .left, .top: c = CGPoint(x: 1, y: 1)
                case .right: c = CGPoint(x: -1, y: 1)
                case .bottom: c = CGPoint(x: 1, y: -1)
                }
            }
            let badge = brain.homeworkBadgeRect(for: cat, corner: c)
            let near = hypot(mouse.x - cat.midX, mouse.y - cat.midY) <= cat.width / 2 + HomeworkBadge.radius
            if near || badge.contains(mouse) {
                corner = c
                hover = badge.contains(mouse)
            }
        }
        if brain.homeworkBadge != corner { brain.homeworkBadge = corner }
        if brain.homeworkHover != hover { brain.homeworkHover = hover }
    }

    /// Bereich des Knopfs „Text prüfen“, solange er zu sehen ist
    func homeworkBadgeRect() -> NSRect? {
        let brain = CatBrain.shared
        guard let corner = brain.homeworkBadge, let cat = catLocation()?.cat else { return nil }
        return brain.homeworkBadgeRect(for: cat, corner: corner)
    }

    /// Wo Rüdiger gerade sitzt (Bildschirmkoordinaten) – `nil`, wenn er nicht zu sehen ist.
    func catLocation() -> CatLocation? {
        let settings = store.config.settings
        guard isVisible, settings.catEnabled else { return nil }
        if settings.catFloating {
            // Schwebend: Seite für Gesten = zur Bildschirmmitte hin
            guard let rect = FloatingCat.shared.catRect else { return nil }
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
                ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.screens.first
            let frame = screen?.frame ?? rect
            return CatLocation(cat: rect, strip: rect, edge: rect.midX > frame.midX ? .right : .left,
                               visible: screen?.visibleFrame ?? rect, floating: true)
        }
        guard let rect = dockedCatRect(), let screen = targetScreen(for: settings) else { return nil }
        return CatLocation(cat: rect, strip: stripFrame(for: settings, forceVisible: true),
                           edge: settings.edge, visible: screen.visibleFrame)
    }

    /// Platz im Viertelkreis an der Uhr (Bildschirmkoordinaten) – auch wenn Rüdiger gerade schwebt.
    /// `nil`, wenn die Sidebar eingefahren ist oder dort kein Platz ist (Uhr aus/zu klein).
    func dockedCatRect() -> NSRect? {
        let settings = store.config.settings
        guard isVisible, state.contentVisible,
              let cat = CatGeometry.make(settings, clockOn: settings.showClock) else { return nil }
        let frame = panel.frame
        let p = cat.point(in: frame.size, edge: settings.edge)
        let d = cat.diameter
        return NSRect(x: frame.minX + p.x - d / 2, y: frame.maxY - p.y - d / 2, width: d, height: d)
    }

    /// Das Fenster der Leiste ist so breit wie die Uhr – neben der Leiste (unter der Uhr) ist es aber
    /// durchsichtig. Dort Klicks an den Schreibtisch bzw. die Fenster dahinter durchlassen.
    private func updateClickThrough(mouse: NSPoint, settings: SidebarSettings, tracking: Bool) {
        guard !tracking else { return }
        let inStrip = stripFrame(for: settings).insetBy(dx: -2, dy: -2).contains(mouse)
        let inClock = clockRect(for: settings)?.insetBy(dx: -2, dy: -2).contains(mouse) ?? false
        let inCat = !settings.catFloating && ((catLocation()?.cat.insetBy(dx: -2, dy: -2).contains(mouse) ?? false)
                                              || (homeworkBadgeRect()?.contains(mouse) ?? false))
        let ignore = !(inStrip || inClock || inCat)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    /// Mini-Vorschau zeigen, sobald die Maus lange genug auf demselben Link bleibt.
    private func updatePreview(_ id: UUID?, now: Date) {
        let settings = store.config.settings
        let preview = LinkPreviewController.shared
        guard settings.linkPreview, let id else {
            previewCandidate = nil
            preview.hide()
            return
        }
        if previewCandidate != id {
            previewCandidate = id
            previewSince = now
            preview.hide()
            return
        }
        guard preview.itemID != id,
              now.timeIntervalSince(previewSince) >= settings.linkPreviewDelay,
              let item = store.item(id: id),
              PreviewStore.supports(item) || MailWatcher.shared.itemID == item.id else { return }

        if let rect = geometry.favoriteFrames[id], store.config.favorites.contains(where: { $0.id == id }) {
            // Favorit: neben der Leiste
            let bar = stripFrame(for: settings, forceVisible: true)
            let anchor = NSRect(x: bar.minX + rect.minX, y: bar.maxY - rect.maxY, width: rect.width, height: rect.height)
            preview.show(item, beside: bar, anchor: anchor, edge: settings.edge, theme: settings.colorTheme)
        } else if flyoutPanel.isVisible, let rect = geometry.flyoutRowFrames[id] {
            // Link im Ordner: neben dem Ordner-Fenster
            let frame = flyoutPanel.frame
            let anchor = NSRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            preview.show(item, beside: frame, anchor: anchor, edge: settings.edge, theme: settings.colorTheme)
        }
    }

    /// Namens-Etikett neben dem Favoriten ein-/ausblenden.
    private func updateLabel(_ id: UUID?) {
        guard id != labelItemID else { return }
        labelItemID = id
        guard let id,
              let item = store.config.favorites.first(where: { $0.id == id }),
              let rect = geometry.favoriteFrames[id],
              let screen = targetScreen(for: store.config.settings) else {
            labelPanel.orderOut(nil)
            return
        }
        let theme = store.config.settings.colorTheme
        labelHost.rootView = HoverLabel(text: item.displayName, theme: theme)
        // Größe des Etiketts messen (die Anzeige selbst meldet keine Größe zurück)
        labelMeasure.rootView = HoverLabel(text: item.displayName, theme: theme)
        let measured = labelMeasure.sizeThatFits(in: CGSize(width: 600, height: 200))
        let size = NSSize(width: ceil(measured.width), height: ceil(measured.height))
        guard size.width > 0, size.height > 0 else {
            labelPanel.orderOut(nil)
            return
        }
        let bar = stripFrame(for: store.config.settings, forceVisible: true)
        let anchor = NSRect(x: bar.minX + rect.minX, y: bar.maxY - rect.maxY, width: rect.width, height: rect.height)
        let gap: CGFloat = 4
        var origin = NSPoint.zero
        switch store.config.settings.edge {
        case .left:
            origin = NSPoint(x: bar.maxX + gap, y: anchor.midY - size.height / 2)
        case .right:
            origin = NSPoint(x: bar.minX - gap - size.width, y: anchor.midY - size.height / 2)
        case .top:
            origin = NSPoint(x: anchor.midX - size.width / 2, y: bar.minY - gap - size.height)
        case .bottom:
            origin = NSPoint(x: anchor.midX - size.width / 2, y: bar.maxY + gap)
        }
        let area = screen.visibleFrame
        origin.x = min(max(origin.x, area.minX), area.maxX - size.width)
        origin.y = min(max(origin.y, area.minY), area.maxY - size.height)
        labelPanel.setFrame(NSRect(origin: origin, size: size), display: true)
        labelPanel.orderFrontRegardless()
    }

    /// Ordner-Symbol an einer Bildschirmposition.
    private func groupAt(_ point: NSPoint) -> UUID? {
        let frame = panel.frame
        let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        return geometry.groupFrames.first(where: { $0.value.contains(local) })?.key
    }

    private func screenRect(forGroup id: UUID) -> NSRect? {
        guard let rect = geometry.groupFrames[id] else { return nil }
        let frame = panel.frame
        return NSRect(x: frame.minX + rect.minX, y: frame.maxY - rect.maxY,
                      width: rect.width, height: rect.height)
    }

    // MARK: - Ordner-Fenster

    private func flyoutTargetExists(_ id: UUID) -> Bool {
        (id == LinkGroup.shelfID && store.config.settings.showShelf)
            || store.config.groups.contains(where: { $0.id == id })
    }

    private func showFlyout(_ groupID: UUID) {
        guard flyoutTargetExists(groupID) else { return }
        state.flyoutGroupID = groupID
        candidateGroup = nil
        flyoutLeftAt = nil
        positionFlyout()
        if !flyoutPanel.isVisible {
            flyoutPanel.alphaValue = 0
            flyoutPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                self.flyoutPanel.animator().alphaValue = 1
            }
        } else {
            flyoutPanel.orderFrontRegardless()
        }
    }

    private func refreshFlyout() {
        guard let id = state.flyoutGroupID else { return }
        if flyoutTargetExists(id) {
            positionFlyout()
        } else {
            hideFlyout()
        }
    }

    /// Ordner-Fenster neben das Symbol setzen – immer vom Bildschirmrand weg.
    private func positionFlyout() {
        guard let id = state.flyoutGroupID,
              flyoutTargetExists(id),
              let anchor = screenRect(forGroup: id),
              let screen = targetScreen(for: store.config.settings) else { return }
        anchorRect = anchor
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let bar = stripFrame(for: store.config.settings, forceVisible: true)
        let gap: CGFloat = 6
        let width: CGFloat
        let ideal: CGFloat
        if id == LinkGroup.shelfID {
            width = ShelfView.width
            ideal = ShelfView.idealHeight(fileCount: store.shelfFiles.count)
        } else {
            width = CGFloat(max(200, store.config.settings.expandedThickness))
            let count = store.config.groups.first(where: { $0.id == id })?.items.count ?? 0
            ideal = FlyoutView.idealHeight(itemCount: count)
        }
        let height = min(ideal, area.height)

        var frame = NSRect(x: 0, y: 0, width: width, height: height)
        switch store.config.settings.edge {
        case .left:
            frame.origin.x = bar.maxX + gap
            frame.origin.y = anchor.maxY - height + 8
        case .right:
            frame.origin.x = bar.minX - gap - width
            frame.origin.y = anchor.maxY - height + 8
        case .top:
            frame.origin.x = anchor.minX - 8
            frame.origin.y = bar.minY - gap - height
        case .bottom:
            frame.origin.x = anchor.minX - 8
            frame.origin.y = bar.maxY + gap
        }
        // Im sichtbaren Bildschirmbereich halten
        frame.origin.x = min(max(frame.origin.x, area.minX), area.maxX - width)
        frame.origin.y = min(max(frame.origin.y, area.minY), area.maxY - height)
        flyoutPanel.setFrame(frame, display: true)
    }

    // MARK: - Automatisch ausblenden

    private func setRevealed(_ revealed: Bool) {
        guard state.isRevealed != revealed else { return }
        state.isRevealed = revealed
        syncContent(store.config.settings)
        if !revealed { hideFlyout() }
        let target = windowFrame(for: store.config.settings)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.panel.animator().setFrame(target, display: true)
        }
    }

    // MARK: - Geometrie & Einstellungen

    private func targetScreen(for settings: SidebarSettings) -> NSScreen? {
        let screens = NSScreen.screens
        if let id = settings.screenID, let match = screens.first(where: { $0.displayID == id }) {
            return match
        }
        if let name = settings.screenName, let match = screens.first(where: { $0.localizedName == name }) {
            return match
        }
        return screens.first // primärer Bildschirm (mit Menüleiste)
    }

    /// Rahmen der eigentlichen Leiste (ohne den Teil der Uhr, der herausragt).
    private func stripFrame(for settings: SidebarSettings, forceVisible: Bool = false) -> NSRect {
        guard let screen = targetScreen(for: settings) else { return panel.frame }
        let area = screen.visibleFrame // ohne Menüleiste und Dock
        let hidden = settings.autoHide && !state.isRevealed && !forceVisible
        let thickness = hidden ? Self.hiddenThickness : CGFloat(settings.collapsedThickness)

        switch settings.edge {
        case .left:
            return NSRect(x: area.minX, y: area.minY, width: thickness, height: area.height)
        case .right:
            return NSRect(x: area.maxX - thickness, y: area.minY, width: thickness, height: area.height)
        case .top:
            return NSRect(x: area.minX, y: area.maxY - thickness, width: area.width, height: thickness)
        case .bottom:
            return NSRect(x: area.minX, y: area.minY, width: area.width, height: thickness)
        }
    }

    // MARK: - Uhr & Suche

    /// Bereich der Uhr auf dem Bildschirm (`nil`, wenn keine Uhr sichtbar ist).
    private func clockRect(for settings: SidebarSettings, forceVisible: Bool = false) -> NSRect? {
        let hidden = settings.autoHide && !state.isRevealed && !forceVisible
        let size = ClockLayout.panelSize(settings)
        guard settings.showClock, !hidden, size != .zero else { return nil }
        let bar = stripFrame(for: settings, forceVisible: true)
        switch settings.edge {
        case .left: return NSRect(x: bar.minX, y: bar.maxY - size.height, width: size.width, height: size.height)
        case .right: return NSRect(x: bar.maxX - size.width, y: bar.maxY - size.height, width: size.width, height: size.height)
        case .top: return NSRect(x: bar.minX, y: bar.maxY - size.height, width: size.width, height: size.height)
        case .bottom: return NSRect(x: bar.minX, y: bar.minY, width: size.width, height: size.height)
        }
    }

    /// Fensterrahmen: Leiste plus der Teil der Uhr, der in den Bildschirm hineinragt.
    /// Uhr und Leiste sind ein einziges Fenster – dadurch gibt es keine Kante dazwischen.
    private func windowFrame(for settings: SidebarSettings, forceVisible: Bool = false) -> NSRect {
        let strip = stripFrame(for: settings, forceVisible: forceVisible)
        guard let clock = clockRect(for: settings, forceVisible: forceVisible) else { return strip }
        return strip.union(clock)
    }

    /// Schnellsuche neben der Uhr öffnen.
    func openSearch() {
        let settings = store.config.settings
        let anchor = clockRect(for: settings) ?? stripFrame(for: settings, forceVisible: true)
        QuickSearchController.shared.toggle(anchor: anchor, edge: settings.edge, theme: settings.colorTheme)
    }

    /// Bereich, in dem die Maus die ausgeblendete Leiste hervorholt.
    /// Reicht bis an den echten Bildschirmrand (auch über die Menüleiste) und etwas nach innen –
    /// außer dort, wo das Dock sitzt, damit es nicht ständig auslöst.
    private func revealZone(for settings: SidebarSettings) -> NSRect {
        guard let screen = targetScreen(for: settings) else { return panel.frame }
        let strip = stripFrame(for: settings)
        let full = screen.frame
        let visible = screen.visibleFrame
        let inward: CGFloat = 10
        let dockTolerance: CGFloat = 10

        switch settings.edge {
        case .left:
            let outer = visible.minX - full.minX <= dockTolerance ? full.minX : strip.minX
            return NSRect(x: outer, y: strip.minY, width: strip.maxX + inward - outer, height: strip.height)
        case .right:
            let outer = full.maxX - visible.maxX <= dockTolerance ? full.maxX : strip.maxX
            let inner = strip.minX - inward
            return NSRect(x: inner, y: strip.minY, width: outer - inner, height: strip.height)
        case .top:
            // Oben liegt nur die Menüleiste – bis zum oberen Rand auslösen
            let inner = strip.minY - inward
            return NSRect(x: strip.minX, y: inner, width: strip.width, height: full.maxY - inner)
        case .bottom:
            let outer = visible.minY - full.minY <= dockTolerance ? full.minY : strip.minY
            return NSRect(x: strip.minX, y: outer, width: strip.width, height: strip.maxY + inward - outer)
        }
    }

    /// Inhalt und Fenstergröße immer aus derselben Bedingung ableiten (sonst bleibt ein leerer Balken stehen).
    private func syncContent(_ settings: SidebarSettings) {
        let visible = !(settings.autoHide && !state.isRevealed)
        if state.contentVisible != visible { state.contentVisible = visible }
    }

    private func applySettings(_ settings: SidebarSettings) {
        NSApp.appearance = settings.appearance.nsAppearance
        // Gerade eingeschaltet: Leiste kurz zeigen und dann sichtbar einfahren,
        // damit klar ist, was passiert.
        if settings.autoHide && lastAutoHide == false {
            state.isRevealed = true
            barLeftAt = Date().addingTimeInterval(1.2)
        }
        lastAutoHide = settings.autoHide
        panel.level = settings.alwaysOnTop ? .floating : .normal
        flyoutPanel.level = settings.alwaysOnTop
            ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            : .normal
        labelPanel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        if !settings.autoHide { state.isRevealed = false }
        syncContent(settings)
        panel.setFrame(windowFrame(for: settings), display: true)
        reloadIfLayoutChanged(settings)
        if flyoutPanel.isVisible {
            DispatchQueue.main.async { [weak self] in self?.positionFlyout() }
        }
    }

    // MARK: - Ziehen an eine andere Kante / einen anderen Bildschirm

    func handleDrag(_ phase: DragPhase, at point: NSPoint) {
        switch phase {
        case .began:
            isDragging = true
            hideFlyout()
        case .moved:
            guard let target = snapTarget(for: point) else {
                previewPanel.orderOut(nil)
                return
            }
            var preview = store.config.settings
            preview.edge = target.edge
            preview.screenID = target.screen.displayID
            preview.screenName = target.screen.localizedName
            previewPanel.setFrame(windowFrame(for: preview, forceVisible: true), display: true)
            previewPanel.orderFrontRegardless()
        case .ended:
            isDragging = false
            previewPanel.orderOut(nil)
            if let target = snapTarget(for: point) {
                var settings = store.config.settings
                settings.edge = target.edge
                settings.screenID = target.screen.displayID
                settings.screenName = target.screen.localizedName
                store.config.settings = settings
            }
            applySettings(store.config.settings)
        }
    }

    /// Bildschirm unter dem Mauszeiger und die nächstgelegene Kante.
    private func snapTarget(for point: NSPoint) -> (screen: NSScreen, edge: ScreenEdge)? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
                ?? NSScreen.screens.first else { return nil }
        let area = screen.visibleFrame
        let distances: [(ScreenEdge, CGFloat)] = [
            (.left, abs(point.x - area.minX)),
            (.right, abs(area.maxX - point.x)),
            (.top, abs(area.maxY - point.y)),
            (.bottom, abs(point.y - area.minY)),
        ]
        guard let nearest = distances.min(by: { $0.1 < $1.1 }) else { return nil }
        return (screen, nearest.0)
    }
}
