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

/// Container, der Maus-Eintritt/-Austritt über die gesamte Sidebar erkennt.
final class HoverContainerView: NSView {
    var onHoverChange: (@MainActor (Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}

/// Steuert Position, Größe und Auf-/Zuklappen der Sidebar.
@MainActor
final class SidebarController {
    let state = SidebarState()
    private let store: ConfigStore
    private let panel: SidebarPanel
    private var cancellables = Set<AnyCancellable>()
    private var pendingTask: Task<Void, Never>?
    private var watchdog: Timer?
    private var mouseInside = false
    private var expandedTarget = false
    private(set) var isVisible = true

    init(store: ConfigStore, actions: SidebarActions) {
        self.store = store
        panel = SidebarPanel(
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

        let container = HoverContainerView(frame: panel.contentRect(forFrameRect: panel.frame))
        let host = FirstMouseHostingView(rootView: SidebarView(store: store, state: state, actions: actions))
        host.sizingOptions = []
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.onHoverChange = { [weak self] inside in self?.hoverChanged(inside) }
        panel.contentView = container

        // Einstellungen geändert (Seite, Bildschirm, Breite …) → neu positionieren.
        store.$config
            .map(\.settings)
            .removeDuplicates()
            .sink { [weak self] settings in self?.applyFrame(settings: settings) }
            .store(in: &cancellables)

        // Monitor angeschlossen/entfernt, Auflösung oder Dock geändert.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyFrame(settings: self.store.config.settings)
            }
            .store(in: &cancellables)

        state.$isPinned
            .dropFirst()
            .sink { [weak self] pinned in
                guard let self else { return }
                if pinned {
                    self.setExpanded(true)
                } else if !self.mouseInside {
                    self.schedule(expanded: false, after: 0.3)
                }
            }
            .store(in: &cancellables)

        panel.orderFrontRegardless()
    }

    // MARK: - Sichtbarkeit

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            applyFrame(settings: store.config.settings)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    var currentScreen: NSScreen? { targetScreen(for: store.config.settings) }

    // MARK: - Hover

    private func hoverChanged(_ inside: Bool) {
        mouseInside = inside
        if inside {
            schedule(expanded: true, after: store.config.settings.hoverDelay)
        } else if !state.isPinned {
            schedule(expanded: false, after: 0.35)
        } else {
            pendingTask?.cancel()
        }
    }

    private func schedule(expanded: Bool, after delay: Double) {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            self.setExpanded(expanded)
        }
    }

    func setExpanded(_ expanded: Bool) {
        if !expanded {
            if state.isPinned { return }
            // Kontextmenü offen → nicht einklappen, später erneut prüfen.
            if RunLoop.current.currentMode == .eventTracking {
                schedule(expanded: false, after: 0.5)
                return
            }
        }
        guard expanded != expandedTarget else { return }
        expandedTarget = expanded

        if expanded {
            state.isExpanded = true
            startWatchdog()
        } else {
            stopWatchdog()
        }

        let target = frame(for: store.config.settings, expanded: expanded)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.expandedTarget else { return }
                self.state.isExpanded = false
            }
        })
    }

    /// Sicherheitsnetz, falls ein „Maus verlässt“-Ereignis verloren geht.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkMousePosition() }
        }
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    private func checkMousePosition() {
        guard expandedTarget, !state.isPinned else { return }
        let inside = panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        if !inside {
            mouseInside = false
            setExpanded(false)
        }
    }

    // MARK: - Geometrie

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

    private func frame(for settings: SidebarSettings, expanded: Bool) -> NSRect {
        guard let screen = targetScreen(for: settings) else { return panel.frame }
        let area = screen.visibleFrame // ohne Menüleiste und Dock
        let collapsed = settings.autoHide ? 4 : settings.collapsedThickness
        let thickness = CGFloat(expanded ? max(settings.expandedThickness, settings.collapsedThickness) : collapsed)

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

    private func applyFrame(settings: SidebarSettings) {
        panel.setFrame(frame(for: settings, expanded: expandedTarget), display: true)
    }
}
