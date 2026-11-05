import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Leitet Klicks aus der Sidebar („Bearbeiten …“, „+“) an den Editor weiter.
@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()

    enum Request: Equatable {
        case edit(UUID)
        /// Neuer Link in Gruppe bzw. `LinkGroup.favoritesID`
        case add(UUID)
    }

    @Published var request: Request?
}

struct SettingsView: View {
    enum Tab: Hashable { case links, appearance }

    @ObservedObject var store: ConfigStore
    @ObservedObject var updater: Updater
    @ObservedObject var router: SettingsRouter
    @State private var tab: Tab = .links

    var body: some View {
        TabView(selection: $tab) {
            GroupsEditor(store: store, router: router)
                .tabItem { Label("Ordner & Links", systemImage: "square.grid.2x2") }
                .tag(Tab.links)
            GeneralSettingsView(store: store, updater: updater)
                .tabItem { Label("Darstellung", systemImage: "sidebar.left") }
                .tag(Tab.appearance)
        }
        .padding()
        .frame(minWidth: 740, minHeight: 500)
        .onReceive(router.$request) { request in
            if request != nil { tab = .links }
        }
        .environment(\.colorTheme, store.config.settings.colorTheme)
    }
}

// MARK: - Darstellung & Verhalten

struct GeneralSettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var updater: Updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Position") {
                Picker("Bildschirm", selection: screenBinding) {
                    Text("Primärer Bildschirm (mit Menüleiste)").tag(UInt32?.none)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(screen.displayID)
                    }
                    if let missing = missingScreenName {
                        Text("\(missing) (nicht verbunden)").tag(store.config.settings.screenID)
                    }
                }
                Picker("Seite", selection: $store.config.settings.edge) {
                    ForEach(ScreenEdge.allCases) { edge in
                        Text(edge.title).tag(edge)
                    }
                }
                .pickerStyle(.segmented)
                Text("Tipp: Du kannst die Sidebar auch am Griff (kleiner Balken oben bzw. links) an eine beliebige Kante oder auf einen anderen Bildschirm ziehen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Farben") {
                LabeledContent("Farbwelt") {
                    HStack(spacing: 8) {
                        ForEach(ColorTheme.allCases) { theme in
                            ThemeSwatch(theme: theme, selected: store.config.settings.colorTheme == theme) {
                                store.config.settings.colorTheme = theme
                            }
                        }
                    }
                }
                Picker("Erscheinungsbild", selection: $store.config.settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Farbverlauf (oben dunkler, unten heller)", isOn: $store.config.settings.gradient)
                LabeledContent("Glas-Effekt: \(Int((store.config.settings.glassIntensity * 100).rounded())) %") {
                    Slider(value: $store.config.settings.glassIntensity, in: 0...1, step: 0.05)
                }
                Text("0 % = deckend. Je höher, desto mehr scheint der Hintergrund unscharf durch – die Farbe der Sidebar bleibt immer erkennbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Hell: Pastellton der Farbwelt · Dunkel: Graphit mit Pastell-Akzent. „Automatisch“ wechselt mit dem macOS-Modus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Uhr, KI & Google") {
                Toggle("Analoge Uhr oben an der Sidebar", isOn: $store.config.settings.showClock)
                if store.config.settings.showClock {
                    LabeledContent("Größe der Uhr: \(Int(store.config.settings.clockSize)) pt") {
                        Slider(value: $store.config.settings.clockSize, in: 64...220, step: 4)
                    }
                    Toggle("Sekundenzeiger", isOn: $store.config.settings.clockShowSeconds)
                }
                Toggle("KI- und Google-Knopf oben in der Leiste", isOn: $store.config.settings.showSearch)
                if store.config.settings.showSearch {
                    Picker("KI-Anbieter", selection: $store.config.settings.aiProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    Picker("KI öffnen in", selection: $store.config.settings.aiTarget) {
                        ForEach(AITarget.allCases) { target in
                            Text(target.title).tag(target)
                        }
                    }
                }
                Text("Klick auf die Uhr öffnet den Kalender. Über KI bzw. Google fahren und direkt lostippen – ↩ öffnet das Ergebnis, esc schließt. Im Seitenfenster steht die Frage bereits im Eingabefeld (bei ChatGPT noch einmal ↩ drücken). Die Frage liegt außerdem in der Zwischenablage – in der Desktop-App mit ⌘V einfügen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Ablagefach in der Leiste", isOn: $store.config.settings.showShelf)
                Toggle("Schnellnotiz in der Leiste", isOn: $store.config.settings.showNotes)
            }

            Section("Größe & Verhalten") {
                LabeledContent("Breite der Leiste: \(Int(store.config.settings.collapsedThickness)) pt") {
                    Slider(value: $store.config.settings.collapsedThickness, in: 44...88, step: 2)
                }
                LabeledContent("Breite der Ordner-Fenster: \(Int(store.config.settings.expandedThickness)) pt") {
                    Slider(value: $store.config.settings.expandedThickness, in: 160...480, step: 10)
                }
                LabeledContent("Verzögerung beim Öffnen: \(String(format: "%.2f", store.config.settings.hoverDelay)) s") {
                    Slider(value: $store.config.settings.hoverDelay, in: 0...0.8, step: 0.05)
                }
                Toggle("Lupen-Effekt beim Darüberfahren", isOn: $store.config.settings.magnification)
                if store.config.settings.magnification {
                    LabeledContent("Stärke der Lupe: \(Int((store.config.settings.magnificationStrength - 1) * 100 + 0.5)) %") {
                        Slider(value: $store.config.settings.magnificationStrength, in: 1.1...1.8, step: 0.05)
                    }
                    Text("Vergrößert nur das Element unter der Maus. Die maximale Größe ist durch die Breite der Leiste begrenzt – für mehr Wirkung die Leiste etwas breiter stellen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Automatisch ausblenden", isOn: $store.config.settings.autoHide)
                if store.config.settings.autoHide {
                    Text("Die Sidebar wird zu einem schmalen farbigen Streifen. Zum Einblenden die Maus an den Bildschirmrand schieben und kurz stehen lassen. Abschalten geht auch über das Menüleisten-Symbol.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Immer im Vordergrund", isOn: $store.config.settings.alwaysOnTop)
                Text(store.config.settings.alwaysOnTop
                     ? "Die Sidebar liegt immer über allen Fenstern."
                     : "Fenster anderer Programme können die Sidebar verdecken. Fährst du mit der Maus auf einen sichtbaren Teil der Sidebar, kommt sie nach vorne.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Links öffnen") {
                Picker("Standard-Öffnungsart", selection: $store.config.settings.defaultOpenMode) {
                    ForEach(OpenMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Browser für Chrome-App-Fenster", selection: $store.config.settings.chromiumBundleID) {
                    ForEach(ChromiumBrowser.all) { browser in
                        Text(isInstalled(browser) ? browser.name : "\(browser.name) (nicht installiert)")
                            .tag(browser.bundleID)
                    }
                }
                Text("""
                • Standard-Browser: öffnet einen neuen Tab in Safari/Chrome/…
                • Integriertes App-Fenster: eigenes Fenster in dieser App, Logins bleiben gespeichert (getrennt von deinem Browser).
                • Chrome-App-Fenster: eigenes Fenster ohne Tabs und Adressleiste, nutzt die Logins deines Chrome/Edge/Brave-Profils.
                Die Öffnungsart lässt sich pro Link überschreiben.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Updates") {
                LabeledContent("Installierte Version") {
                    Text(updater.currentVersion).monospacedDigit()
                }
                Toggle("Automatisch nach Updates suchen", isOn: $store.config.settings.autoCheckUpdates)
                HStack {
                    Text(updateStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let release = updater.availableRelease {
                        Button("Auf \(release.version) aktualisieren") {
                            Task { await updater.install(release) }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Jetzt prüfen") {
                            Task { await updater.check(userInitiated: true) }
                        }
                        .disabled(updater.isBusy)
                    }
                }
            }

            Section("System") {
                Toggle("Bei Anmeldung automatisch starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Konfigurationsdatei") {
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var updateStatusText: String {
        switch updater.status {
        case .idle: return "Noch nicht geprüft."
        case .checking: return "Suche nach Updates …"
        case .upToDate: return "Du verwendest die neueste Version."
        case .available(let release): return "Version \(release.version) ist verfügbar."
        case .downloading: return "Lade Update herunter …"
        case .installing: return "Installiere Update …"
        case .failed(let message): return "Fehler: \(message)"
        }
    }

    private var screenBinding: Binding<UInt32?> {
        Binding(
            get: { store.config.settings.screenID },
            set: { id in
                let screen = NSScreen.screens.first { $0.displayID == id }
                store.setScreen(id == nil ? nil : screen)
            }
        )
    }

    private var missingScreenName: String? {
        guard let id = store.config.settings.screenID,
              !NSScreen.screens.contains(where: { $0.displayID == id }) else { return nil }
        return store.config.settings.screenName ?? "Bildschirm \(id)"
    }

    private func isInstalled(_ browser: ChromiumBrowser) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Konnte nicht geändert werden: \(error.localizedDescription). Tipp: App zuerst nach /Programme verschieben."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Gruppen & Links

struct ItemDraft: Identifiable {
    let id = UUID()
    var item: LinkItem
    var groupID: UUID
    var isNew: Bool
}

struct GroupsEditor: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var router: SettingsRouter
    @State private var selection: UUID?
    @State private var draft: ItemDraft?
    @State private var confirmDelete = false

    var body: some View {
        HSplitView {
            groupList
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selection == nil { selection = store.config.groups.first?.id }
        }
        .sheet(item: $draft) { draft in
            ItemEditorSheet(draft: draft, groups: store.config.groups,
                            favoritesFull: store.favoritesFull) { item, groupID in
                store.upsert(item, into: groupID)
            }
        }
        .onReceive(router.$request) { request in
            guard let request else { return }
            DispatchQueue.main.async {
                router.request = nil
                handle(request)
            }
        }
        .confirmationDialog("Gruppe mit allen Links löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) { deleteSelectedGroup() }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var groupList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Label("Favoriten (\(store.config.favorites.count)/\(SidebarConfig.maxFavorites))", systemImage: "star.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .tag(LinkGroup.favoritesID)
                    .linkDropTarget { payloads in
                        store.handleDrop(payloads, into: LinkGroup.favoritesID)
                    }
                ForEach(store.config.groups) { group in
                    Label(group.name.isEmpty ? "Ohne Namen" : group.name, systemImage: group.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .tag(group.id)
                        .linkDropTarget { payloads in
                            store.handleDrop(payloads, into: group.id)
                        }
                }
                .onMove { from, to in
                    store.config.groups.move(fromOffsets: from, toOffset: to)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button {
                    let group = store.addGroup()
                    selection = group.id
                } label: {
                    Image(systemName: "plus")
                }
                .help("Gruppe hinzufügen")
                Button {
                    let hasItems = store.config.groups.first { $0.id == selection }?.items.isEmpty == false
                    if hasItems { confirmDelete = true } else { deleteSelectedGroup() }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil || selection == LinkGroup.favoritesID)
                .help("Gruppe löschen")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if selection == LinkGroup.favoritesID {
            FavoritesDetail(store: store) { item in
                if let item {
                    draft = ItemDraft(item: item, groupID: LinkGroup.favoritesID, isNew: false)
                } else {
                    draft = ItemDraft(item: LinkItem(name: "", urlString: ""), groupID: LinkGroup.favoritesID, isNew: true)
                }
            }
        } else if let id = selection, store.config.groups.contains(where: { $0.id == id }) {
            GroupDetail(store: store, groupID: id) { item in
                if let item {
                    draft = ItemDraft(item: item, groupID: id, isNew: false)
                } else {
                    draft = ItemDraft(item: LinkItem(name: "", urlString: ""), groupID: id, isNew: true)
                }
            }
            .id(id)
        } else {
            ContentUnavailableView("Keine Gruppe ausgewählt",
                                   systemImage: "square.grid.2x2",
                                   description: Text("Lege links mit „+“ eine Gruppe an, z. B. „Fotografie“ oder „ADS“."))
        }
    }

    private func handle(_ request: SettingsRouter.Request) {
        switch request {
        case .edit(let id):
            guard let item = store.item(id: id), let container = store.container(of: id) else { return }
            selection = container
            draft = ItemDraft(item: item, groupID: container, isNew: false)
        case .add(let container):
            selection = container
            draft = ItemDraft(item: LinkItem(name: "", urlString: ""), groupID: container, isNew: true)
        }
    }

    private func deleteSelectedGroup() {
        guard let id = selection else { return }
        let oldIndex = store.config.groups.firstIndex { $0.id == id } ?? 0
        selection = nil
        store.deleteGroup(id: id)
        let remaining = store.config.groups
        selection = remaining.isEmpty ? nil : remaining[min(oldIndex, remaining.count - 1)].id
    }
}

struct GroupDetail: View {
    @ObservedObject var store: ConfigStore
    let groupID: UUID
    /// `nil` = neuen Link anlegen
    let onEdit: (LinkItem?) -> Void

    private var group: LinkGroup? { store.config.groups.first { $0.id == groupID } }

    private func binding<T>(_ keyPath: WritableKeyPath<LinkGroup, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { group?[keyPath: keyPath] ?? fallback },
            set: { value in store.updateGroup(groupID) { $0[keyPath: keyPath] = value } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SymbolPicker(symbol: binding(\.symbol, fallback: "folder"))
                TextField("Gruppenname", text: binding(\.name, fallback: ""))
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }
            HStack {
                Text("SF-Symbol:").font(.caption).foregroundStyle(.secondary)
                TextField("z. B. camera", text: binding(\.symbol, fallback: "folder"))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 200)
            }

            Text("Links").font(.headline)
            List {
                ForEach(group?.items ?? []) { item in
                    ItemRow(item: item,
                            onEdit: { onEdit(item) },
                            onDelete: { store.deleteItem(id: item.id) })
                        .onDrag { DropSupport.provider(for: item) }
                }
                .onInsert(of: DropSupport.types) { index, providers in
                    DropSupport.load(providers) { payloads in
                        store.handleDrop(payloads, into: groupID, at: index)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            LinkDropZone(text: "Hierher ziehen: Webadressen aus dem Browser, Programme aus Finder/Dock oder Links aus einem anderen Ordner") { payloads in
                store.handleDrop(payloads, into: groupID)
            }

            HStack {
                Button {
                    onEdit(nil)
                } label: {
                    Label("Link hinzufügen", systemImage: "plus")
                }
                Spacer()
                Text("Reihenfolge ändern: Links in der Liste ziehen. Auf „Favoriten“ links ziehen = Favorit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

/// Farbfeld zur Auswahl der Farbwelt.
struct ThemeSwatch: View {
    let theme: ColorTheme
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        Button(action: action) {
            Circle()
                .fill(LinearGradient(colors: [palette.gradientTop, palette.gradientBottom],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(selected ? Color.primary : Color.primary.opacity(0.15),
                                         lineWidth: selected ? 2 : 1))
                .padding(2)
        }
        .buttonStyle(.plain)
        .help(theme.title)
    }
}

/// Gestrichelte Fläche zum Hineinziehen von Links.
struct LinkDropZone: View {
    let text: String
    let perform: @MainActor ([DropPayload]) -> Void
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
            Text(targeted ? "Loslassen zum Hinzufügen" : text)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .linkDropTarget(isTargeted: $targeted, perform: perform)
    }
}

struct FavoritesDetail: View {
    @ObservedObject var store: ConfigStore
    /// `nil` = neuen Favoriten anlegen
    let onEdit: (LinkItem?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "star.fill").font(.title2).foregroundStyle(Color.accentColor)
                Text("Favoriten").font(.title3.weight(.semibold))
                Spacer()
                Text("\(store.config.favorites.count) von \(SidebarConfig.maxFavorites)")
                    .foregroundStyle(.secondary)
            }
            Text("Die Favoriten stehen oben in der Sidebar für den Schnellzugriff – maximal \(SidebarConfig.maxFavorites). Reihenfolge per Ziehen ändern. Links aus einem Ordner (hier in den Einstellungen oder direkt in der Sidebar) auf die Favoriten ziehen.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(store.config.favorites) { item in
                    ItemRow(item: item,
                            onEdit: { onEdit(item) },
                            onDelete: { store.removeFromFavorites(id: item.id) })
                        .onDrag { DropSupport.provider(for: item) }
                }
                .onInsert(of: DropSupport.types) { index, providers in
                    DropSupport.load(providers) { payloads in
                        store.handleDrop(payloads, into: LinkGroup.favoritesID, at: index)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            if !store.favoritesFull {
                LinkDropZone(text: "Links hierher ziehen, um sie zu Favoriten zu machen") { payloads in
                    store.handleDrop(payloads, into: LinkGroup.favoritesID)
                }
            }

            HStack {
                Button {
                    onEdit(nil)
                } label: {
                    Label("Favorit hinzufügen", systemImage: "plus")
                }
                .disabled(store.favoritesFull)
                Spacer()
            }
        }
        .padding()
    }
}

struct ItemRow: View {
    let item: LinkItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(item: item, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                Text(item.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let mode = item.openMode {
                Text(mode.shortTitle)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("Bearbeiten")
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Entfernen")
        }
        .padding(.vertical, 2)
    }
}

struct ItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: LinkItem
    @State private var groupID: UUID
    @State private var iconTargeted = false
    private let groups: [LinkGroup]
    private let isNew: Bool
    private let originalIcon: String?
    private let originalContainer: UUID
    private let favoritesFull: Bool
    private let onSave: (LinkItem, UUID) -> Void

    init(draft: ItemDraft, groups: [LinkGroup], favoritesFull: Bool,
         onSave: @escaping (LinkItem, UUID) -> Void) {
        _item = State(initialValue: draft.item)
        _groupID = State(initialValue: draft.groupID)
        self.groups = groups
        self.isNew = draft.isNew
        self.originalIcon = draft.item.customIcon
        self.originalContainer = draft.groupID
        self.favoritesFull = favoritesFull
        self.onSave = onSave
    }

    private var favoritesBlocked: Bool {
        groupID == LinkGroup.favoritesID && originalContainer != LinkGroup.favoritesID && favoritesFull
    }

    private var isValid: Bool { item.url != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Neuer Link" : "Link bearbeiten").font(.headline)
            HStack(spacing: 14) {
                FaviconView(item: item, size: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(iconTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .onDrop(of: [.fileURL], isTargeted: $iconTargeted) { providers in
                        DropSupport.load(providers) { payloads in
                            for case .image(let url) in payloads {
                                if let image = NSImage(contentsOf: url) { setIcon(image) }
                            }
                        }
                        return true
                    }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button("Eigenes Bild wählen …") { chooseImage() }
                        if item.customIcon != nil {
                            Button("Standard-Icon") { item.customIcon = nil }
                        }
                    }
                    Text("Oder ein Bild auf das Icon ziehen. Ohne eigenes Bild wird das Icon der Webseite bzw. des Programms verwendet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Form {
                LabeledContent("Adresse oder Programm") {
                    HStack {
                        TextField("", text: $item.urlString, prompt: Text("z. B. ads.google.com"))
                            .labelsHidden()
                        Button("Programm/Datei …") { chooseLocalTarget() }
                    }
                }
                TextField("Name", text: $item.name, prompt: Text("leer = Domain verwenden"))
                Picker("Ablegen in", selection: $groupID) {
                    Label("Favoriten", systemImage: "star.fill").tag(LinkGroup.favoritesID)
                    ForEach(groups) { group in
                        Label(group.name, systemImage: group.symbol).tag(group.id)
                    }
                }
                if !item.isLocal {
                    Picker("Öffnen als", selection: $item.openMode) {
                        Text("Standard (aus Einstellungen)").tag(OpenMode?.none)
                        ForEach(OpenMode.allCases) { mode in
                            Text(mode.title).tag(OpenMode?.some(mode))
                        }
                    }
                    Toggle("Benachrichtigungen (im Hintergrund aktiv halten)", isOn: Binding(
                        get: { item.keepAlive == true },
                        set: { enabled in
                            item.keepAlive = enabled ? true : nil
                            if enabled { item.openMode = .appWindow }
                        }
                    ))
                    if item.keepAlive == true {
                        Text("Die Seite läuft unsichtbar im integrierten App-Fenster weiter. Neue Nachrichten erscheinen als Zähler am Icon und als macOS-Mitteilung. Einmal öffnen und anmelden ist nötig.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            if favoritesBlocked {
                Text("Die Favoritenleiste ist voll (max. \(SidebarConfig.maxFavorites)). Entferne zuerst einen Favoriten.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !item.urlString.isEmpty && !isValid {
                Text("Bitte eine gültige Adresse eingeben.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || favoritesBlocked)
            }
        }
        .padding()
        .frame(width: 480)
    }

    /// Programm, Datei oder Ordner auf dem Mac auswählen.
    private func chooseLocalTarget() {
        let panel = NSOpenPanel()
        panel.title = "Programm, Datei oder Ordner wählen"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        item.urlString = url.absoluteString
        if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.name = LinkItem.suggestedName(for: url)
        }
        item.openMode = nil
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Bild für das Icon wählen"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        setIcon(image)
    }

    private func setIcon(_ image: NSImage) {
        guard let file = IconStore.shared.save(image) else {
            NSSound.beep()
            return
        }
        // Zwischenstände, die nie gespeichert wurden, wieder löschen
        if let current = item.customIcon, current != originalIcon {
            IconStore.shared.delete(current)
        }
        item.customIcon = file
    }

    private func cancel() {
        if let current = item.customIcon, current != originalIcon {
            IconStore.shared.delete(current)
        }
        dismiss()
    }

    private func save() {
        guard let url = item.url else { return }
        var result = item
        result.urlString = url.absoluteString
        if result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.name = LinkItem.suggestedName(for: url)
        }
        onSave(result, groupID)
        dismiss()
    }
}

struct SymbolPicker: View {
    @Binding var symbol: String

    static let presets = [
        "folder", "camera", "camera.aperture", "photo.on.rectangle", "megaphone",
        "chart.bar", "chart.line.uptrend.xyaxis", "briefcase", "envelope", "cart",
        "globe", "star", "heart", "paintpalette", "doc.text", "person.2", "calendar",
        "bolt", "house", "video", "music.note", "bubble.left.and.bubble.right",
        "dollarsign.circle", "wrench.and.screwdriver",
    ]

    var body: some View {
        Menu {
            ForEach(Self.presets, id: \.self) { name in
                Button {
                    symbol = name
                } label: {
                    Label(name, systemImage: name)
                }
            }
        } label: {
            Image(systemName: symbol)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Symbol wählen")
    }
}
