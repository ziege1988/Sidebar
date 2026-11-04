import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        TabView {
            GroupsEditor(store: store)
                .tabItem { Label("Gruppen & Links", systemImage: "square.grid.2x2") }
            GeneralSettingsView(store: store)
                .tabItem { Label("Darstellung", systemImage: "sidebar.left") }
        }
        .padding()
        .frame(minWidth: 740, minHeight: 500)
    }
}

// MARK: - Darstellung & Verhalten

struct GeneralSettingsView: View {
    @ObservedObject var store: ConfigStore
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
            }

            Section("Größe & Verhalten") {
                LabeledContent("Breite eingeklappt: \(Int(store.config.settings.collapsedThickness)) pt") {
                    Slider(value: $store.config.settings.collapsedThickness, in: 44...88, step: 2)
                }
                LabeledContent("Breite ausgeklappt: \(Int(store.config.settings.expandedThickness)) pt") {
                    Slider(value: $store.config.settings.expandedThickness, in: 160...480, step: 10)
                }
                LabeledContent("Verzögerung beim Aufklappen: \(String(format: "%.2f", store.config.settings.hoverDelay)) s") {
                    Slider(value: $store.config.settings.hoverDelay, in: 0...0.8, step: 0.05)
                }
                Toggle("Automatisch ausblenden (eingeklappt nur schmaler Rand sichtbar)",
                       isOn: $store.config.settings.autoHide)
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
            ItemEditorSheet(draft: draft, groups: store.config.groups) { item, groupID in
                store.upsert(item, into: groupID)
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
                ForEach(store.config.groups) { group in
                    Label(group.name.isEmpty ? "Ohne Namen" : group.name, systemImage: group.symbol)
                        .tag(group.id)
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
                .disabled(selection == nil)
                .help("Gruppe löschen")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection, store.config.groups.contains(where: { $0.id == id }) {
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
                }
                .onMove { from, to in
                    store.updateGroup(groupID) { $0.items.move(fromOffsets: from, toOffset: to) }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Button {
                    onEdit(nil)
                } label: {
                    Label("Link hinzufügen", systemImage: "plus")
                }
                Spacer()
                Text("Tipp: Adresse aus dem Browser direkt auf eine Gruppe in der Sidebar ziehen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text(item.urlString)
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
    private let groups: [LinkGroup]
    private let isNew: Bool
    private let onSave: (LinkItem, UUID) -> Void

    init(draft: ItemDraft, groups: [LinkGroup], onSave: @escaping (LinkItem, UUID) -> Void) {
        _item = State(initialValue: draft.item)
        _groupID = State(initialValue: draft.groupID)
        self.groups = groups
        self.isNew = draft.isNew
        self.onSave = onSave
    }

    private var isValid: Bool { item.url != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Neuer Link" : "Link bearbeiten").font(.headline)
            Form {
                TextField("Adresse (URL)", text: $item.urlString, prompt: Text("z. B. ads.google.com"))
                TextField("Name", text: $item.name, prompt: Text("leer = Domain verwenden"))
                Picker("Gruppe", selection: $groupID) {
                    ForEach(groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                Picker("Öffnen als", selection: $item.openMode) {
                    Text("Standard (aus Einstellungen)").tag(OpenMode?.none)
                    ForEach(OpenMode.allCases) { mode in
                        Text(mode.title).tag(OpenMode?.some(mode))
                    }
                }
            }
            .formStyle(.grouped)

            if !item.urlString.isEmpty && !isValid {
                Text("Bitte eine gültige Adresse eingeben.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 480)
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
