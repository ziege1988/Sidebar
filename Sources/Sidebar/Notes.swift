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
    @State private var editingID: UUID?
    @State private var query = ""

    static let size = CGSize(width: 580, height: 560)

    private var filtered: [QuickNote] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.config.notes }
        return store.config.notes.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

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
            searchField(palette)
            NotesBoard(notes: filtered, searching: !query.trimmingCharacters(in: .whitespaces).isEmpty,
                       editingID: $editingID, palette: palette,
                       actions: NotesBoardActions(
                        add: { addNote() },
                        update: { id, text, rtf in store.updateNote(id: id, text: text, rtf: rtf) },
                        cycleTint: { store.cycleNoteTint(id: $0) },
                        copy: { note in
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(note.text, forType: .string)
                            if let rtf = note.rtf { NSPasteboard.general.setData(rtf, forType: .rtf) }
                        },
                        delete: { id in
                            if editingID == id { editingID = nil }
                            store.deleteNote(id: id)
                        }))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(GlassFill(fill: palette.panelFill(gradient: true),
                              intensity: max(store.config.settings.glassIntensity, 0.05),
                              mask: AnyShape(shape)))
        .clipShape(shape)
        .overlay(shape.stroke(palette.border, lineWidth: 1))
        .overlay(GlassRim(shape: shape, intensity: store.config.settings.glassIntensity))
    }

    private func addNote() {
        query = ""
        let note = store.addNote("")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { editingID = note.id }
    }

    private func searchField(_ palette: Palette) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondary)
            TextField("In Notizen suchen …", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.text)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(palette.border, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.top, 10)
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
            Button(action: addNote) {
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

// MARK: - Kachelsystem

/// Was eine Kachel tun darf (vom Fenster übergeben – so lässt sich das Raster auch ohne Konfiguration zeichnen).
struct NotesBoardActions {
    var add: () -> Void = {}
    var update: (UUID, String, Data?) -> Void = { _, _, _ in }
    var cycleTint: (UUID) -> Void = { _ in }
    var copy: (QuickNote) -> Void = { _ in }
    var delete: (UUID) -> Void = { _ in }
}

/// Notizen als Zettel-Kacheln im Raster: zwei Spalten, vorne „+ Neue Notiz".
/// Ein Klick öffnet eine Kachel zum Bearbeiten – sie wird zwei Spalten breit, die übrigen rücken nach.
struct NotesBoard: View {
    let notes: [QuickNote]
    var searching = false
    @Binding var editingID: UUID?
    let palette: Palette
    let actions: NotesBoardActions

    private enum Entry {
        case add
        case note(QuickNote)
        var key: String {
            switch self {
            case .add: return "add"
            case .note(let note): return note.id.uuidString
            }
        }
    }

    /// Zeilen: Normalerweise zwei Kacheln nebeneinander; die gerade bearbeitete Kachel bekommt eine ganze Zeile.
    private var rows: [[Entry]] {
        var rows: [[Entry]] = []
        var current: [Entry] = []
        let entries: [Entry] = (searching ? [] : [.add]) + notes.map(Entry.note)
        for entry in entries {
            if case .note(let note) = entry, note.id == editingID {
                if !current.isEmpty { rows.append(current); current = [] }
                rows.append([entry])
            } else {
                current.append(entry)
                if current.count == 2 { rows.append(current); current = [] }
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(rows, id: \.first!.key) { row in
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(row, id: \.key) { entry in
                            cell(entry)
                        }
                        if row.count == 1, !isEditingRow(row) { Color.clear.frame(maxWidth: .infinity) }
                    }
                }
                if searching && notes.isEmpty {
                    Text("Keine Treffer.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: editingID)
        }
    }

    private func isEditingRow(_ row: [Entry]) -> Bool {
        if case .note(let note)? = row.first { return note.id == editingID }
        return false
    }

    @ViewBuilder
    private func cell(_ entry: Entry) -> some View {
        switch entry {
        case .add:
            Button(action: actions.add) {
                VStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 20, weight: .light))
                    Text("Neue Notiz").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(palette.secondary)
                .frame(maxWidth: .infinity, minHeight: NoteCard.height)
                .background(RoundedRectangle(cornerRadius: 4).fill(palette.surface.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(palette.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .note(let note):
            NoteCard(note: note, editing: note.id == editingID, palette: palette, actions: actions,
                     onOpen: { editingID = note.id },
                     onDone: { editingID = nil })
                .frame(maxWidth: .infinity)
        }
    }
}

/// Eine Notiz als Zettel: Papierton mit Klebeband, leicht schräg. Zeigt die Notiz mit ihrer Formatierung.
struct NoteCard: View {
    static let height: CGFloat = 150
    let note: QuickNote
    let editing: Bool
    let palette: Palette
    let actions: NotesBoardActions
    let onOpen: () -> Void
    let onDone: () -> Void

    private static let tape: [Color] = [
        Color(red: 0.62, green: 0.60, blue: 0.56), Color(red: 0.36, green: 0.58, blue: 0.40),
        Color(red: 0.30, green: 0.52, blue: 0.80), Color(red: 0.82, green: 0.40, blue: 0.40),
        Color(red: 0.55, green: 0.46, blue: 0.78), Color(red: 0.77, green: 0.62, blue: 0.29),
    ]

    private var tint: Int { ((note.tint ?? 0) % NoteTint.count + NoteTint.count) % NoteTint.count }
    /// Leichte, für jede Notiz feste Schräglage (−1,1° … +1,1°)
    private var tilt: Double { (Double(note.id.uuid.0 % 21) - 10) / 10 * 1.1 }
    private let ink = Color(red: 0.18, green: 0.16, blue: 0.10)

    var body: some View {
        let paper = NoteTint.color(tint, scheme: .light)
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                RichTextEditor(initialText: note.text, initialRTF: note.rtf, focusOnAppear: editing) { plain, rtf in
                    actions.update(note.id, plain, rtf)
                }
                .id(editing)
                .allowsHitTesting(editing)
                if !editing {
                    // Klick auf den Zettel öffnet ihn zum Bearbeiten
                    Color.clear.contentShape(Rectangle()).onTapGesture(perform: onOpen)
                }
            }
            .frame(height: editing ? 230 : Self.height - 56)
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: editing ? 1 : 0.86),
                                       .init(color: .black.opacity(editing ? 1 : 0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
            HStack(spacing: 10) {
                Text(note.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(ink.opacity(0.55))
                Spacer()
                icon("paintpalette", "Farbe wechseln") { actions.cycleTint(note.id) }
                icon("doc.on.doc", "Kopieren (mit Formatierung)") { actions.copy(note) }
                icon("trash", "Löschen") { actions.delete(note.id) }
                if editing {
                    Button(action: onDone) {
                        Label("Fertig", systemImage: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.onAccent)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Capsule().fill(palette.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(minHeight: editing ? 0 : Self.height, alignment: .top)
        .background(
            ZStack {
                Rectangle().fill(paper)
                Rectangle().fill(LinearGradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0)],
                                                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .shadow(color: .black.opacity(editing ? 0.42 : 0.3), radius: editing ? 12 : 6, y: editing ? 7 : 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(palette.accent, lineWidth: editing ? 2 : 0))
        .overlay(alignment: .top) {
            // Klebeband
            Rectangle()
                .fill(Self.tape[tint].opacity(0.55))
                .overlay(HStack { Rectangle().stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 1); Spacer(); Rectangle().stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 1) })
                .frame(width: 46, height: 14)
                .rotationEffect(.degrees(-3))
                .offset(y: -7)
                .allowsHitTesting(false)
        }
        .rotationEffect(.degrees(editing ? 0 : tilt))
    }

    private func icon(_ name: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 10))
                .foregroundStyle(ink.opacity(0.6))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
