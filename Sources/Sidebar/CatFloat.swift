import AppKit
import Combine
import SwiftUI

// MARK: - Schwebender Rüdiger
//
// Statt im Viertelkreis an der Uhr sitzt Rüdiger in einem eigenen kleinen Fenster, das man mit der Maus
// packen und irgendwohin ziehen kann – auch auf einen anderen Bildschirm. Klickbar ist nur sein Kreis,
// alles drumherum lässt Klicks durch. Zurück in die Sidebar: auf den gestrichelten Kreis an der Uhr ziehen.

/// Zustand, den die Ansichten brauchen (Hinweis „hier einrasten“)
@MainActor
final class FloatingCatState: ObservableObject {
    /// Rüdiger hängt gerade über dem Platz an der Uhr – Loslassen rastet ihn ein
    @Published var overDock = false
}

@MainActor
final class FloatingCat {
    static let shared = FloatingCat()

    /// Größe der Glasblase – immer gleich, nicht verstellbar
    static let diameter: CGFloat = 96
    /// Fenster etwas größer als die Blase: Ohrenspitzen, Leuchten und (beim Tragen) der Schatten ragen heraus.
    /// Klickbar bleibt trotzdem nur der Kreis – der Rest lässt Klicks durch.
    private static let windowFactor: CGFloat = 1.8
    /// So nah (Mittelpunkte) muss Rüdiger am Platz an der Uhr sein, damit er einrastet
    private static let dockDistance: CGFloat = 70

    let state = FloatingCatState()
    private let panel: SidebarPanel
    private let hintPanel: NSPanel
    private var store: ConfigStore?
    private var openSettings: (@MainActor () -> Void)?
    /// Platz an der Uhr (Bildschirmkoordinaten) – `nil`, wenn es dort keinen gibt
    private var dockRect: (@MainActor () -> NSRect?)?
    /// Knopf „Text prüfen“ (wenn sichtbar) – muss klickbar sein
    private var badgeRect: (@MainActor () -> NSRect?)?
    /// Rüdiger wird gerade getragen: Abstand vom Mauszeiger zu seinem Mittelpunkt
    private var grab: CGPoint?
    private var installed = false

    private init() {
        panel = SidebarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = .floating
        // wie die Sidebar: auf jedem Schreibtisch (Space), auf dem auch die Sidebar läuft
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        hintPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        hintPanel.isOpaque = false
        hintPanel.backgroundColor = .clear
        hintPanel.hasShadow = false
        hintPanel.ignoresMouseEvents = true
        hintPanel.isReleasedWhenClosed = false
        hintPanel.animationBehavior = .none
        hintPanel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        hintPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    func configure(store: ConfigStore, openSettings: @escaping @MainActor () -> Void,
                   dockRect: @escaping @MainActor () -> NSRect?,
                   badgeRect: @escaping @MainActor () -> NSRect?) {
        self.store = store
        self.openSettings = openSettings
        self.dockRect = dockRect
        self.badgeRect = badgeRect
    }

    private func installContent() {
        guard !installed, let store else { return }
        installed = true
        let host = FirstMouseHostingView(rootView: FloatingCatView(store: store, openSettings: { [weak self] in
            self?.openSettings?()
        }))
        host.sizingOptions = []
        panel.contentView = host
        let hint = NSHostingView(rootView: DockHintView(state: state))
        hint.sizingOptions = []
        hintPanel.contentView = hint
    }

    var isCarrying: Bool { grab != nil }

    /// Rüdigers Kreis auf dem Bildschirm – `nil`, wenn er gerade nicht schwebt
    var catRect: NSRect? {
        guard panel.isVisible else { return nil }
        let d = Self.diameter
        let f = panel.frame
        return NSRect(x: f.midX - d / 2, y: f.midY - d / 2, width: d, height: d)
    }

    // MARK: Laufend (60× pro Sekunde aus der Sidebar)

    func update(sidebarVisible: Bool) {
        guard let store else { return }
        let s = store.config.settings
        guard sidebarVisible, s.catEnabled, s.catFloating else {
            if panel.isVisible { panel.orderOut(nil) }
            endCarry()
            return
        }
        installContent()
        let level: NSWindow.Level = s.catFloatOnTop ? .floating : .normal
        if panel.level != level { panel.level = level }
        if !panel.isVisible {
            place(at: savedCenter(s))
            panel.orderFrontRegardless()
        }

        let mouse = NSEvent.mouseLocation
        if let grab {
            // Getragen: folgt der Maus über alle Bildschirme, bis die Taste losgelassen wird
            let center = CGPoint(x: mouse.x + grab.x, y: mouse.y + grab.y)
            place(at: center)
            let dock = dockRect?()
            let over = dock.map { hypot($0.midX - center.x, $0.midY - center.y) < Self.dockDistance } ?? false
            if state.overDock != over { state.overDock = over }
            showHint(dock)
            if NSEvent.pressedMouseButtons & 1 == 0 { drop(at: center, docked: over) }
        } else if let rect = catRect, !NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
            // Bildschirm abgesteckt → zurück auf einen vorhandenen
            place(at: savedCenter(s))
        }

        // Nur der Kreis ist klickbar, alles drumherum geht durch
        let inCat = (catRect?.insetBy(dx: -2, dy: -2).contains(mouse) ?? false)
            || (badgeRect?()?.contains(mouse) ?? false)
        let ignore = !(inCat || grab != nil)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    // MARK: Tragen

    /// Rüdiger wird gepackt – `fromDock`: aus dem Viertelkreis an der Uhr herausgezogen
    func beginCarry(fromDock: Bool = false) {
        guard let store, grab == nil else { return }
        let mouse = NSEvent.mouseLocation
        let center = fromDock ? dockRect?().map { CGPoint(x: $0.midX, y: $0.midY) } : nil
        if fromDock && center == nil { return }
        if let center {
            // Aus dem Viertelkreis herausgezogen: ab jetzt schwebt er
            installContent()
            place(at: center)
            store.config.settings.catFloating = true
            panel.orderFrontRegardless()
        }
        guard let rect = catRect ?? center.map({ NSRect(x: $0.x - 1, y: $0.y - 1, width: 2, height: 2) }) else { return }
        grab = CGPoint(x: rect.midX - mouse.x, y: rect.midY - mouse.y)
        panel.ignoresMouseEvents = false
        CatBubbleController.shared.hide()
        CatBrain.shared.carried = true
    }

    private func drop(at center: CGPoint, docked: Bool) {
        guard let store else { return }
        endCarry()
        var s = store.config.settings
        if docked {
            s.catFloating = false
        } else {
            // Ganz auf den Bildschirm unter der Maus holen
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.screens.first
            var c = center
            if let area = screen?.visibleFrame.insetBy(dx: Self.diameter / 2 + 4, dy: Self.diameter / 2 + 4),
               area.width > 0, area.height > 0 {
                c.x = min(max(c.x, area.minX), area.maxX)
                c.y = min(max(c.y, area.minY), area.maxY)
            }
            place(at: c)
            s.catFloatX = Double(c.x)
            s.catFloatY = Double(c.y)
            s.catFloatScreenID = screen?.displayID
            CatBrain.shared.landed()
        }
        store.config.settings = s
    }

    private func endCarry() {
        guard grab != nil else { return }
        grab = nil
        state.overDock = false
        hintPanel.orderOut(nil)
        CatBrain.shared.carried = false
    }

    private func showHint(_ dock: NSRect?) {
        guard let dock else {
            hintPanel.orderOut(nil)
            return
        }
        let side = dock.width + 16
        let frame = NSRect(x: dock.midX - side / 2, y: dock.midY - side / 2, width: side, height: side)
        if hintPanel.frame != frame { hintPanel.setFrame(frame, display: true) }
        if !hintPanel.isVisible { hintPanel.orderFrontRegardless() }
    }

    // MARK: Lage

    private func place(at center: CGPoint) {
        let side = Self.diameter * Self.windowFactor
        let frame = NSRect(x: (center.x - side / 2).rounded(), y: (center.y - side / 2).rounded(),
                           width: side, height: side)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// Gemerkter Platz – oder, wenn es den nicht (mehr) gibt, neben der Uhr ins Bildschirminnere versetzt
    private func savedCenter(_ s: SidebarSettings) -> CGPoint {
        let half = Self.diameter / 2 + 4
        if let x = s.catFloatX, let y = s.catFloatY {
            let p = CGPoint(x: x, y: y)
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: half - 2, dy: half - 2).contains(p) }) {
                return p
            }
        }
        let screen = NSScreen.screens.first(where: { $0.displayID == s.screenID }) ?? NSScreen.screens.first
        guard let area = screen?.visibleFrame else { return .zero }
        let middle = CGPoint(x: area.midX, y: area.midY)
        guard let dock = dockRect?() else { return middle }
        let dx = middle.x - dock.midX, dy = middle.y - dock.midY
        let length = max(hypot(dx, dy), 1)
        let step = Self.diameter * 2
        return CGPoint(x: dock.midX + dx / length * step, y: dock.midY + dy / length * step)
    }
}

// MARK: - Ansichten

private struct FloatingCatView: View {
    @ObservedObject var store: ConfigStore
    let openSettings: @MainActor () -> Void
    @ObservedObject private var brain = CatBrain.shared
    @Environment(\.colorScheme) private var scheme
    /// Schatten nur als kurze Animation beim Tragen und Absetzen – sonst keiner
    @State private var shadow: ShadowPhase = .hidden

    private enum ShadowPhase { case hidden, lifted, impact }

    var body: some View {
        let d = FloatingCat.diameter
        ZStack {
            // Schatten am „Boden“ unter der Blase (nur gezeichnet – fängt keine Klicks ab)
            Ellipse()
                .fill(RadialGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: d * 0.6))
                .frame(width: d * shadowWidth, height: shadowHeight)
                .blur(radius: shadow == .lifted ? 6 : 2.5)
                .opacity(shadowOpacity)
                .offset(y: d / 2 + 8)
                .allowsHitTesting(false)
            CatView(palette: Palette.resolve(store.config.settings.colorTheme, scheme),
                    openSettings: {
                        SettingsRouter.shared.showCategory = .cat
                        openSettings()
                    }, onFeed: { payloads in
                        let before = store.config.shelf.count
                        _ = store.addToShelf(payloads)
                        return store.config.shelf.count - before
                    }, onCarry: { FloatingCat.shared.beginCarry() },
                    onReturnToDock: { store.config.settings.catFloating = false })
                .frame(width: d, height: d)
                // Getragen: hebt leicht ab
                .offset(y: brain.carried ? -12 : 0)
                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: brain.carried)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: brain.carried) { _, carried in
            if carried {
                withAnimation(.easeOut(duration: 0.18)) { shadow = .lifted }
            } else {
                // Plumps: Schatten kurz breit und dunkel, dann ausblenden
                withAnimation(.easeIn(duration: 0.1)) { shadow = .impact }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.easeOut(duration: 0.4)) { shadow = .hidden }
                }
            }
        }
    }

    private var shadowWidth: CGFloat {
        switch shadow {
        case .hidden: return 0.8
        case .lifted: return 1.15
        case .impact: return 1.05
        }
    }

    private var shadowHeight: CGFloat {
        switch shadow {
        case .hidden: return 10
        case .lifted: return 22
        case .impact: return 13
        }
    }

    private var shadowOpacity: Double {
        switch shadow {
        case .hidden: return 0
        case .lifted: return 0.45
        case .impact: return 0.75
        }
    }
}

/// Gestrichelter Kreis am Platz an der Uhr, solange Rüdiger getragen wird
private struct DockHintView: View {
    @ObservedObject var state: FloatingCatState

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(state.overDock ? 0.35 : 0.12))
            Circle()
                .strokeBorder(Color.white.opacity(0.95),
                              style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
            Circle()
                .strokeBorder(Color.black.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1, dash: [7, 5]))
                .padding(2.5)
            Text("hier\neinrasten")
                .font(.system(size: 11, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2)
        }
        .padding(8)
        .scaleEffect(state.overDock ? 1.08 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: state.overDock)
    }
}
