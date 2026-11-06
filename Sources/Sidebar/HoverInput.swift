import AppKit
import Combine
import SwiftUI

/// Die beiden Knöpfe oben in der Leiste.
enum ActionButton: String, CaseIterable, Identifiable {
    case ai, google, note
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: return "KI"
        case .google: return "Google"
        case .note: return "Notiz"
        }
    }

    var symbol: String {
        switch self {
        case .ai: return "sparkles"
        case .google: return "magnifyingglass"
        case .note: return "note.text"
        }
    }

    var placeholder: String {
        switch self {
        case .ai: return "KI fragen …"
        case .google: return "Google Suche"
        case .note: return "Schnellnotiz …"
        }
    }

    /// Knöpfe oben in der Leiste. Quer ist Google als festes Eingabefeld eingebaut.
    static func topButtons(vertical: Bool) -> [ActionButton] {
        vertical ? [.ai, .google] : [.ai]
    }
}

/// Positionen der Knöpfe in der Leiste (wie bei den Ordnern).
struct ActionFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

final class HoverInputModel: ObservableObject {
    @Published var text = ""
    @Published var kind: ActionButton = .google
    @Published var focusToken = UUID()
}

/// Eingabefeld, das beim Darüberfahren neben dem KI- bzw. Google-Knopf erscheint.
/// Man kann sofort lostippen; ↩ führt aus, esc schließt.
@MainActor
final class HoverInputController {
    static let shared = HoverInputController()

    let model = HoverInputModel()
    private let panel: KeyPanel
    private var previousApp: NSRunningApplication?
    private var resignObserver: NSObjectProtocol?
    private var shownAt = Date.distantPast
    /// Wird mit Eingabe und Art aufgerufen (↩)
    var onSubmit: ((String, ActionButton) -> Void)?

    private(set) var kind: ActionButton?
    private(set) var anchor: NSRect = .zero

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }
    var hasText: Bool { !model.text.trimmingCharacters(in: .whitespaces).isEmpty }

    private init() {
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            // Woanders hingeklickt → schließen, ohne den Fokus umzulenken.
            // Direkt nach dem Öffnen gibt macOS den Fokus beim Aktivieren der App manchmal kurz
            // an ein anderes Fenster – dann das Feld wieder nach vorne holen statt es zu schließen.
            MainActor.assumeIsolated {
                guard let self else { return }
                if Date().timeIntervalSince(self.shownAt) < 0.8 {
                    DispatchQueue.main.async {
                        guard self.isVisible else { return }
                        self.panel.makeKeyAndOrderFront(nil)
                        self.model.focusToken = UUID()
                    }
                } else {
                    self.close(restoreFocus: false)
                }
            }
        }
    }

    func show(_ kind: ActionButton, anchor: NSRect, edge: ScreenEdge, theme: ColorTheme) {
        if isVisible && self.kind == kind { return }
        let switching = isVisible
        self.kind = kind
        self.anchor = anchor
        model.kind = kind
        model.text = ""

        let view = HoverInputView(model: model, theme: theme,
                                  onSubmit: { [weak self] in self?.submit() },
                                  onCancel: { [weak self] in self?.close(restoreFocus: true) })
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
        let size = NSSize(width: 420, height: 60)

        let gap: CGFloat = 4
        var origin = NSPoint.zero
        switch edge {
        case .left: origin = NSPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case .right: origin = NSPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        case .top: origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
        case .bottom: origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            let area = screen.visibleFrame
            origin.x = min(max(origin.x, area.minX + 4), area.maxX - size.width - 4)
            origin.y = min(max(origin.y, area.minY + 4), area.maxY - size.height - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        // Vorheriges Programm merken, um nach dem Schließen dorthin zurückzukehren
        if !switching, let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        shownAt = Date()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.focusToken = UUID()
        // nach der Aktivierung der App noch einmal Fokus setzen
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.panel.makeKeyAndOrderFront(nil)
            self.model.focusToken = UUID()
        }
    }

    func close(restoreFocus: Bool) {
        guard isVisible else { return }
        panel.orderOut(nil)
        kind = nil
        if restoreFocus, let previousApp {
            previousApp.activate()
        }
        previousApp = nil
    }

    private func submit() {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind, !text.isEmpty else { return }
        close(restoreFocus: false)
        onSubmit?(text, kind)
    }
}

struct HoverInputView: View {
    @ObservedObject var model: HoverInputModel
    let theme: ColorTheme
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(palette.accent)
                Image(systemName: model.kind.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.onAccent)
            }
            .frame(width: 32, height: 32)
            TextField(model.kind.placeholder, text: $model.text)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(palette.text)
                .focused($focused)
                .onSubmit(onSubmit)
            Text("↩")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).stroke(palette.border, lineWidth: 1))
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(width: 410, height: 50)
        .background(
            Capsule().fill(palette.gradientBottom)
        )
        .overlay(Capsule().stroke(palette.accent.opacity(0.35), lineWidth: 1))
        .padding(5)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: model.focusToken) { _, _ in
            DispatchQueue.main.async { focused = true }
        }
        .onExitCommand(perform: onCancel)
    }
}
