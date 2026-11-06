import AppKit
import SwiftUI

/// Tastatur für Eingabefelder in der Leiste: kurz die Sidebar aktivieren und danach
/// zum vorherigen Programm zurückkehren.
@MainActor
enum KeyboardFocus {
    private static var previousApp: NSRunningApplication?

    static func begin() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        NSApp.activate()
    }

    static func end() {
        previousApp?.activate()
        previousApp = nil
    }
}

/// Festes, kurzes Eingabefeld in der quer liegenden Leiste (Google-Suche bzw. Schnellnotiz).
struct InlineField: View {
    let kind: ActionButton
    let width: CGFloat
    let palette: Palette
    let onSubmit: @MainActor (String) -> Void
    var onOpen: (@MainActor () -> Void)? = nil

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.accent)
            TextField(kind.placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.text)
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand {
                    text = ""
                    focused = false
                    KeyboardFocus.end()
                }
            if let onOpen {
                // Großer Knopf „alle Notizen“ (Klick wird zusätzlich direkt vom Fenster erkannt)
                Button {
                    onOpen()
                } label: {
                    // dezent wie die übrigen Feld-Symbole – nur die Klickfläche ist groß
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ActionFramesKey.self,
                                               value: ["noteOpen": proxy.frame(in: .named("bar")).insetBy(dx: -4, dy: -4)])
                    }
                )
                .help("Alle Notizen anzeigen")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, onOpen == nil ? 10 : 3)
        .frame(width: width, height: onOpen == nil ? 30 : 36)
        .background(
            GeometryReader { proxy in
                // Position merken, damit das Notiz-Fenster direkt am Feld aufgeht
                Color.clear.preference(key: ActionFramesKey.self,
                                       value: [(kind == .note ? "noteField" : "googleField"): proxy.frame(in: .named("bar"))])
            }
        )
        .background(Capsule().fill(palette.gradientBottom.opacity(0.85)))
        .overlay(Capsule().stroke(palette.accent.opacity(focused ? 0.9 : 0.3), lineWidth: 1))
        .onChange(of: focused) { _, isFocused in
            if isFocused { KeyboardFocus.begin() }
        }
        .help(kind == .note ? "Schnellnotiz: tippen und ↩" : "Google Suche: tippen und ↩")
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSubmit(value)
        text = ""
        focused = false
        KeyboardFocus.end()
    }
}

/// Notiz-Symbol in der Leiste – hervorgehoben wie das Ablagefach.
struct NoteCell: View {
    @ObservedObject var store: ConfigStore
    let iconSize: CGFloat
    let cellSize: CGSize
    let showLabel: Bool
    let actions: SidebarActions
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        let count = store.config.notes.count
        Button {
            actions.triggerAction(.note)
        } label: {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: iconSize * 0.32, style: .continuous)
                    .fill(LinearGradient(colors: [palette.accent.opacity(0.92), palette.accent],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: iconSize * 0.32, style: .continuous)
                    .strokeBorder(Palette.gold.opacity(0.6), lineWidth: 1.2)
                Image(systemName: "note.text")
                    .font(.system(size: iconSize * 0.46, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
            }
            .frame(width: iconSize, height: iconSize)
            .shadow(color: palette.accent.opacity(0.3), radius: 3, y: 1)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().stroke(Palette.gold.opacity(0.8), lineWidth: 1))
                        .offset(x: 6, y: -5)
                }
            }
            if showLabel {
                Text("Notiz")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
        }
        .frame(width: cellSize.width, height: cellSize.height)
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ActionFramesKey.self,
                                       value: [ActionButton.note.rawValue: proxy.frame(in: .named("bar"))])
            }
        )
        .help("Schnellnotiz: darüberfahren und lostippen · Klick zeigt alle Notizen")
    }
}

/// Fenster zum Verwalten der Schnellnotizen.
@MainActor
final class NotesController {
    static let shared = NotesController()
    private var panel: KeyPanel?
    var isVisible: Bool { panel?.isVisible == true }

    private var deactivateObserver: NSObjectProtocol?

    private init() {
        // Schließen, wenn ein anderes Programm in den Vordergrund kommt (Klick daneben).
        // Früher wurde beim Fokuswechsel geschlossen – das passierte beim Öffnen manchmal
        // sofort wieder, weil macOS den Fokus kurz an ein anderes Sidebar-Fenster gab.
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.orderOut(nil) }
        }
    }

    func show(store: ConfigStore, anchor: NSRect, edge: ScreenEdge, theme: ColorTheme) {
        if let panel, panel.isVisible {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: NotesView(store: store, theme: theme,
                                                     onClose: { [weak self] in self?.close() }))
        host.sizingOptions = []
        panel.contentView = host
        let size = NSSize(width: NotesView.size.width, height: NotesView.size.height)
        let gap: CGFloat = 8
        var origin = NSPoint.zero
        switch edge {
        case .left: origin = NSPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case .right: origin = NSPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        case .top: origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
        case .bottom: origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            let area = screen.visibleFrame
            origin.x = min(max(origin.x, area.minX + 8), area.maxX - size.width - 8)
            origin.y = min(max(origin.y, area.minY + 8), area.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        KeyboardFocus.begin()
        panel.makeKeyAndOrderFront(nil)
        // nach der Aktivierung der App noch einmal nach vorne holen
        DispatchQueue.main.async { panel.makeKeyAndOrderFront(nil) }
    }

    func close() {
        guard isVisible else { return }
        panel?.orderOut(nil)
        KeyboardFocus.end()
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

struct NotesView: View {
    @ObservedObject var store: ConfigStore
    let theme: ColorTheme
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var newNoteID: UUID?

    static let size = CGSize(width: 580, height: 560)
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 0) {
            header(palette)
            Rectangle().fill(palette.border).frame(height: 1)
            FormatBar(palette: palette)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            Rectangle().fill(palette.border).frame(height: 1)

            if store.config.notes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.system(size: 26))
                        .foregroundStyle(palette.accent.opacity(0.6))
                    Text("Noch keine Notizen.\nMit „+“ eine neue Kachel anlegen.")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.config.notes) { note in
                            NoteTile(note: note, store: store, palette: palette,
                                     focusOnAppear: note.id == newNoteID)
                                .id(note.id)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(GlassFill(fill: palette.panelFill(gradient: true),
                              intensity: max(store.config.settings.glassIntensity, 0.05),
                              mask: AnyShape(shape)))
        .clipShape(shape)
        .overlay(shape.stroke(palette.border, lineWidth: 1))
        .overlay(GlassRim(shape: shape, intensity: store.config.settings.glassIntensity))
    }

    private func header(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.accent)
                Image(systemName: "note.text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
            }
            .frame(width: 24, height: 24)
            Text("Schnellnotizen")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.text)
            Text("\(store.config.notes.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
            Spacer()
            Button {
                let note = store.addNote("")
                newNoteID = note.id
            } label: {
                Label("Neue Notiz", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(palette.accent))
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Schließen (esc)")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }
}

/// Werkzeugleiste: Fett, Kursiv, Unterstrichen, Textfarben, Textmarker.
struct FormatBar: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 6) {
            formatButton("bold", "Fett (⌘B)") { NoteFormatting.toggleBold() }
            formatButton("italic", "Kursiv (⌘I)") { NoteFormatting.toggleItalic() }
            formatButton("underline", "Unterstrichen (⌘U)") { NoteFormatting.toggleUnderline() }
            Rectangle().fill(palette.border).frame(width: 1, height: 18).padding(.horizontal, 4)
            ForEach(NoteTextColor.allCases) { color in
                Button {
                    NoteFormatting.setColor(color)
                } label: {
                    Circle()
                        .fill(color.swatch)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(palette.border, lineWidth: 1))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Textfarbe: \(color.title)")
            }
            Rectangle().fill(palette.border).frame(width: 1, height: 18).padding(.horizontal, 4)
            Button {
                NoteFormatting.toggleHighlight()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Marker").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color(nsColor: NoteFormatting.highlighterText))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: NoteFormatting.highlighter)))
            }
            .buttonStyle(.plain)
            .help("Neongelber Textmarker")
            Spacer()
            Text("Text markieren, dann formatieren")
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
        }
    }

    private func formatButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.surface))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Eine Notiz als Kachel in einem gedeckten Farbton.
struct NoteTile: View {
    let note: QuickNote
    let store: ConfigStore
    let palette: Palette
    var focusOnAppear = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RichTextEditor(initialText: note.text, initialRTF: note.rtf, focusOnAppear: focusOnAppear) { plain, rtf in
                store.updateNote(id: note.id, text: plain, rtf: rtf)
            }
            .frame(height: 118)
            HStack(spacing: 10) {
                Text(note.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
                Spacer()
                Button {
                    store.cycleNoteTint(id: note.id)
                } label: {
                    Image(systemName: "paintpalette").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondary)
                .help("Kachelfarbe wechseln")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(note.text, forType: .string)
                    if let rtf = note.rtf { NSPasteboard.general.setData(rtf, forType: .rtf) }
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondary)
                .help("Kopieren (mit Formatierung)")
                Button {
                    store.deleteNote(id: note.id)
                } label: {
                    Image(systemName: "trash").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondary)
                .help("Löschen")
            }
        }
        .padding(10)
        .frame(height: 160)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NoteTint.color(note.tint, scheme: scheme))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
    }
}
