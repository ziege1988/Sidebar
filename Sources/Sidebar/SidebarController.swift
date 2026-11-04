import AppKit
import Combine
import SwiftUI

/// Rahmenloses, schwebendes Panel, das die App nicht aktiviert
/// (der Fokus bleibt in der App, mit der du gerade arbeitest).
final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
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

    init(store: ConfigStore, updater: Updater, actions: SidebarActions) {
        self.store = store
        panel = SidebarController.makePanel()
        flyoutPanel = SidebarController.makePanel()

        let bar = FirstMouseHostingView(rootView: SidebarView(store: store, state: state, updater: updater,
                                                              geometry: geometry, actions: actions))
        bar.sizingOptions = []
        panel.contentView = bar

        let flyout = FirstMouseHostingView(rootView: FlyoutView(store: store, state: state, actions: actions))
        flyout.sizingOptions = []
        flyoutPanel.contentView = flyout

        // Einstellungen geändert (Seite, Bildschirm, Breite, Farben …)
        store.$config
            .map(\.settings)
            .removeDuplicates()
            .sink { [weak self] settings in self?.applySettings(settings) }
            .store(in: &cancellables)

        // Inhalt geändert → Ordner-Fenster an neue Höhe anpassen (nach dem Speichern)
        store.$config
            .map(\.groups)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshFlyout() }
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
            applySettings(store.config.settings)
            panel.orderFrontRegardless()
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
        state.flyoutGroupID = nil
        flyoutPanel.orderOut(nil)
        flyoutLeftAt = nil
    }

    // MARK: - Maus-Abfrage

    private func startPolling() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common: läuft auch während Drag & Drop und Scrollen
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func tick() {
        guard isVisible, !isDragging else { return }
        let settings = store.config.settings
        let mouse = NSEvent.mouseLocation
        let now = Date()
        // Kontextmenü offen oder Drag aus der Sidebar heraus → nichts schließen
        let tracking = RunLoop.current.currentMode == .eventTracking

        let inBar = panel.frame.contains(mouse)
        let flyoutVisible = flyoutPanel.isVisible
        let flyoutZone = flyoutPanel.frame.insetBy(dx: -8, dy: -8)
        // Korridor zwischen Ordner-Symbol und Ordner-Fenster (diagonale Mausbewegung)
        let corridor = anchorRect.union(flyoutPanel.frame).insetBy(dx: -4, dy: -4)
        let inFlyout = flyoutVisible && (flyoutZone.contains(mouse) || corridor.contains(mouse))

        // 1. Automatisch ausblenden: Leiste ein-/ausfahren
        if settings.autoHide {
            if inBar || inFlyout || tracking {
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

    private func showFlyout(_ groupID: UUID) {
        guard store.config.groups.contains(where: { $0.id == groupID }) else { return }
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
        if store.config.groups.contains(where: { $0.id == id }) {
            positionFlyout()
        } else {
            hideFlyout()
        }
    }

    /// Ordner-Fenster neben das Symbol setzen – immer vom Bildschirmrand weg.
    private func positionFlyout() {
        guard let id = state.flyoutGroupID,
              let group = store.config.groups.first(where: { $0.id == id }),
              let anchor = screenRect(forGroup: id),
              let screen = targetScreen(for: store.config.settings) else { return }
        anchorRect = anchor
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let bar = panel.frame
        let gap: CGFloat = 6
        let width = CGFloat(max(200, store.config.settings.expandedThickness))
        let height = min(FlyoutView.idealHeight(itemCount: group.items.count), area.height)

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
        if !revealed { hideFlyout() }
        let target = frame(for: store.config.settings)
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

    private func frame(for settings: SidebarSettings, forceVisible: Bool = false) -> NSRect {
        guard let screen = targetScreen(for: settings) else { return panel.frame }
        let area = screen.visibleFrame // ohne Menüleiste und Dock
        let hidden = settings.autoHide && !state.isRevealed && !forceVisible
        let thickness = CGFloat(hidden ? 4 : settings.collapsedThickness)

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

    private func applySettings(_ settings: SidebarSettings) {
        NSApp.appearance = settings.appearance.nsAppearance
        panel.level = settings.alwaysOnTop ? .floating : .normal
        flyoutPanel.level = settings.alwaysOnTop
            ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            : .normal
        if !settings.autoHide { state.isRevealed = false }
        panel.setFrame(frame(for: settings), display: true)
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
            previewPanel.setFrame(frame(for: preview, forceVisible: true), display: true)
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
