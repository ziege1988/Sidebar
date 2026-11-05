import AppKit
import SwiftUI

/// Panel, das Tastatureingaben annimmt (für das Suchfeld).
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Schnellsuche: Google-Suche im Browser oder Frage an Claude.
@MainActor
final class QuickSearchController {
    static let shared = QuickSearchController()

    enum Target { case google, claude }

    private var panel: KeyPanel?
    private var resignObserver: NSObjectProtocol?

    var isVisible: Bool { panel?.isVisible == true }

    /// - Parameter anchor: Bereich der Uhr bzw. Leiste (Bildschirmkoordinaten), daneben erscheint die Suche
    func toggle(anchor: NSRect, edge: ScreenEdge, theme: ColorTheme) {
        if isVisible {
            close()
        } else {
            show(anchor: anchor, edge: edge, theme: theme)
        }
    }

    func show(anchor: NSRect, edge: ScreenEdge, theme: ColorTheme) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let view = QuickSearchView(theme: theme,
                                   onSubmit: { [weak self] text, target in
                                       self?.close()
                                       QuickSearchController.run(text, target: target)
                                   },
                                   onCancel: { [weak self] in self?.close() })
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
        let size = NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: 600, height: 400))

        let gap: CGFloat = 8
        var origin = NSPoint.zero
        switch edge {
        case .left: origin = NSPoint(x: anchor.maxX + gap, y: anchor.maxY - size.height)
        case .right: origin = NSPoint(x: anchor.minX - gap - size.width, y: anchor.maxY - size.height)
        case .top: origin = NSPoint(x: anchor.minX, y: anchor.minY - gap - size.height)
        case .bottom: origin = NSPoint(x: anchor.minX, y: anchor.maxY + gap)
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            origin.x = min(max(origin.x, area.minX + 8), area.maxX - size.width - 8)
            origin.y = min(max(origin.y, area.minY + 8), area.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Klick daneben → Suche schließen
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        return panel
    }

    /// Führt die Suche aus.
    static func run(_ text: String, target: Target) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query

        switch target {
        case .google:
            // Sieht die Eingabe wie eine Adresse aus, direkt öffnen
            if !query.contains(" "), query.contains("."),
               let url = LinkItem.normalizedURL(from: query), !url.isFileURL {
                NSWorkspace.shared.open(url)
            } else if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                NSWorkspace.shared.open(url)
            }
        case .claude:
            // Sicherheitsnetz: Frage liegt in der Zwischenablage (⌘V), falls Claude sie nicht übernimmt
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(query, forType: .string)
            let hasDesktopApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
            let address = hasDesktopApp
                ? "claude://claude.ai/new?q=\(encoded)"
                : "https://claude.ai/new?q=\(encoded)"
            if let url = URL(string: address) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

struct QuickSearchView: View {
    let theme: ColorTheme
    let onSubmit: (String, QuickSearchController.Target) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.accent)
                TextField("Google Suche", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(palette.text)
                    .focused($focused)
                    .onSubmit { onSubmit(text, .google) }
            }
            HStack(spacing: 8) {
                Button {
                    onSubmit(text, .google)
                } label: {
                    Label("Google", systemImage: "globe")
                }
                Button {
                    onSubmit(text, .claude)
                } label: {
                    Label("Claude fragen", systemImage: "sparkles")
                }
                .keyboardShortcut(.return, modifiers: .command)
                Spacer()
                Text("↩ Google · ⌘↩ Claude · esc")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .frame(width: 440)
        .background(
            ZStack {
                VisualEffectBackground()
                palette.background.opacity(0.94)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.border, lineWidth: 1))
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
        .onExitCommand { onCancel() }
    }
}
