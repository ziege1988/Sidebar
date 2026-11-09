import AppKit
import SwiftUI

@MainActor
final class SidebarState: ObservableObject {
    /// Ordner, dessen Fenster gerade geöffnet ist
    @Published var flyoutGroupID: UUID?
    /// Bei „Automatisch ausblenden“: Leiste gerade sichtbar
    @Published var isRevealed = false
    /// Inhalt (Uhr, Icons) anzeigen – wird nur vom Controller gesetzt, zusammen mit der Fenstergröße
    @Published var contentVisible = true
    /// Element unter der Maus (für den Lupen-Effekt): "fav:<id>" bzw. "group:<id>"
    @Published var hoveredCell: String?
    /// Rahmen des Elements unter der Maus (für die Blase vom Bildschirmrand)
    @Published var hoverRect: CGRect?
    /// Link im Ordner-Fenster unter der Maus
    @Published var hoveredRow: UUID?
    /// Wo der Verlauf am unteren Rand der Uhr steht (0 … 1), damit Uhr und Leiste nahtlos ineinander übergehen
    @Published var clockGradientEnd: Double = 0.2
}

/// Positionen der Symbole in der Leiste (Koordinaten der Leiste, Ursprung oben links).
final class SidebarGeometry {
    var groupFrames: [UUID: CGRect] = [:]
    var favoriteFrames: [UUID: CGRect] = [:]
    var actionFrames: [String: CGRect] = [:]
    /// Links im Ordner-Fenster (Koordinaten des Ordner-Fensters)
    var flyoutRowFrames: [UUID: CGRect] = [:]
}

struct FlyoutRowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct FavoriteFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Lupen-Effekt: Nur das Element unter der Maus wird vergrößert.
struct HoverScale: ViewModifier {
    let active: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? scale : 1)
            .zIndex(active ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: active)
            .animation(.easeOut(duration: 0.15), value: scale)
    }
}

/// Name als kleines Etikett beim Darüberfahren über einen Favoriten.
struct HoverLabel: View {
    let text: String
    var theme: ColorTheme = .sage
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.text)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(palette.surface))
            .overlay(Capsule().stroke(palette.border, lineWidth: 1))
            .padding(4)
            .fixedSize()
    }
}

struct GroupFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct SidebarActions {
    var open: @MainActor (LinkItem, OpenMode?) -> Void
    var openSettings: @MainActor () -> Void
    var editItem: @MainActor (UUID) -> Void
    /// Neuen Link anlegen (Gruppe oder `LinkGroup.favoritesID`)
    var addLink: @MainActor (UUID) -> Void
    var chooseIcon: @MainActor (UUID) -> Void
    var toggleFlyout: @MainActor (UUID) -> Void
    var installUpdate: @MainActor () -> Void
    var openSearch: @MainActor () -> Void
    /// Klick auf den KI-, Google- bzw. Notiz-Knopf
    var triggerAction: @MainActor (ActionButton) -> Void
    /// Eingabe aus einem festen Feld in der Leiste (Google-Suche, Schnellnotiz)
    var submitAction: @MainActor (ActionButton, String) -> Void
    var drag: @MainActor (DragPhase, NSPoint) -> Void
}

// MARK: - Leiste

struct SidebarView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: SidebarState
    @ObservedObject var updater: Updater
    let geometry: SidebarGeometry
    let actions: SidebarActions

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    private var settings: SidebarSettings { store.config.settings }
    private var edge: ScreenEdge { settings.edge }
    private var vertical: Bool { edge.isVertical }
    private var thickness: CGFloat { CGFloat(settings.collapsedThickness) }
    private var showContent: Bool { state.contentVisible }
    private var showFavoriteSlot: Bool { store.config.favorites.count < SidebarConfig.maxFavorites }

    var body: some View {
        let palette = Palette.resolve(settings.colorTheme, scheme)
        let glass = settings.glassIntensity
        let clockOn = settings.showClock && showContent
        let clockSize = clockOn ? ClockLayout.panelSize(settings) : .zero
        let clockAlong = vertical ? clockSize.height : clockSize.width
        // Rüdiger: Viertelkreis zwischen Uhr und Leiste (schwebt er, hat die Uhr ihre normale Ecke)
        let cat = settings.catFloating ? nil : CatGeometry.make(settings, clockOn: clockOn)
        // Uhr und Leiste: ein gemeinsamer Umriss, eine Glasfläche, ein Rand – ohne Kante dazwischen
        let outline = SidebarOutline(edge: edge, barCross: thickness,
                                     clockCross: vertical ? clockSize.width : clockSize.height,
                                     clockAlong: clockAlong, catRadius: cat?.radius ?? 0)
        Group {
            if showContent {
                ZStack {
                    GeometryReader { proxy in
                        let length = vertical ? proxy.size.height : proxy.size.width
                        let clockEnd = (clockOn && vertical && length > 0) ? Double(clockAlong / length) : 0
                        GlassFill(fill: palette.backgroundFill(gradient: settings.gradient, clockEnd: clockEnd),
                                  intensity: glass, mask: AnyShape(outline))
                            .clipShape(outline)
                    }
                    // Weiße, leicht durchscheinende Blase vom Bildschirmrand um das Icon unter der Maus
                    HoverBubble(edge: edge, cell: state.hoverRect, barThickness: thickness)
                        .clipShape(outline)
                    content(palette, clockOn: clockOn, clockSize: clockSize)
                    if let cat {
                        GeometryReader { proxy in
                            CatView(palette: palette, openSettings: {
                                SettingsRouter.shared.showCategory = .cat
                                actions.openSettings()
                            }, onFeed: { payloads in
                                let before = store.config.shelf.count
                                _ = store.addToShelf(payloads)
                                return store.config.shelf.count - before
                            }, onCarry: {
                                // Aus dem Viertelkreis herausziehen → schwebt frei
                                FloatingCat.shared.beginCarry(fromDock: true)
                            })
                                .frame(width: cat.diameter, height: cat.diameter)
                                .position(cat.point(in: proxy.size, edge: edge))
                        }
                    }
                }
                // Glasrand nur auf den Seiten zum Bildschirminneren, nicht am Bildschirmrand
                .overlay(GlassRim(shape: SidebarOutline(edge: edge, barCross: thickness,
                                                        clockCross: vertical ? clockSize.width : clockSize.height,
                                                        clockAlong: clockAlong, closed: false,
                                                        catRadius: cat?.radius ?? 0),
                                  intensity: glass, clip: AnyShape(outline)))
            } else {
                // Automatisch ausgeblendet: nur ein dezenter Rand als Auslöser.
                palette.accent.opacity(0.55)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "bar")
        .onPreferenceChange(GroupFramesKey.self) { frames in
            geometry.groupFrames = frames
        }
        .onPreferenceChange(FavoriteFramesKey.self) { frames in
            geometry.favoriteFrames = frames
        }
        .onPreferenceChange(ActionFramesKey.self) { frames in
            geometry.actionFrames = frames
        }
        .environment(\.colorTheme, settings.colorTheme)
    }

    /// Uhr (falls sichtbar) und darunter bzw. daneben die Leiste – an der Bildschirmkante ausgerichtet.
    @ViewBuilder
    private func content(_ palette: Palette, clockOn: Bool, clockSize: CGSize) -> some View {
        if vertical {
            VStack(alignment: edge == .right ? .trailing : .leading, spacing: 0) {
                if clockOn {
                    ClockFace(settings: settings, palette: palette)
                        .frame(width: clockSize.width, height: clockSize.height)
                }
                barContent(palette)
                    .frame(width: thickness)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: edge == .right ? .topTrailing : .topLeading)
        } else {
            HStack(alignment: edge == .top ? .top : .bottom, spacing: 0) {
                if clockOn {
                    ClockFace(settings: settings, palette: palette)
                        .frame(width: clockSize.width, height: clockSize.height)
                }
                barContent(palette)
                    .frame(height: thickness)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: edge == .top ? .topLeading : .bottomLeading)
        }
    }

    /// Nur die zum Bildschirm zeigenden Ecken werden abgerundet.
    private var shape: UnevenRoundedRectangle {
        EdgeShape.shape(for: edge, radius: showContent ? 14 : 0)
    }

    private func barContent(_ palette: Palette) -> some View {
        let outer = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return outer {
            // Quer: Google-Suche als festes, kurzes Eingabefeld
            if !vertical && settings.showSearch {
                InlineField(kind: .google, width: 200, palette: palette) { text in
                    actions.submitAction(.google, text)
                }
                .padding(.horizontal, 8)
            }

            GeometryReader { proxy in
                let length = vertical ? proxy.size.height : proxy.size.width
                // Quer: Notizfeld nur, wenn alle Ordner in voller Größe Platz haben (Ordner haben Vorrang)
                let noteField: CGFloat = 220
                let fitsNoteField = !vertical && settings.showNotes
                    && length - BarMetrics.naturalLength(cells: cellCount, thickness: thickness) >= noteField + 24
                let noteIconOnBar = !vertical && settings.showNotes && !fitsNoteField
                let available = fitsNoteField ? length - noteField - 24 : (noteIconOnBar ? length - 64 : length)
                let metrics = BarMetrics(available: available, cells: cellCount, thickness: thickness)
                let row = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                row {
                    ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                        cells(palette, metrics: metrics)
                            .padding(vertical ? .vertical : .horizontal, BarMetrics.padding)
                            .frame(minWidth: vertical ? proxy.size.width : nil,
                                   minHeight: vertical ? nil : proxy.size.height)
                    }
                    .frame(width: vertical ? nil : available, height: vertical ? available : nil)
                    if fitsNoteField {
                        InlineField(kind: .note, width: noteField, palette: palette,
                                    onSubmit: { text in actions.submitAction(.note, text) },
                                    onOpen: { actions.triggerAction(.note) })
                            // etwas mehr Luft zum Ablagefach
                            .padding(.leading, 8)
                            .padding(.trailing, 16)
                            .frame(maxHeight: .infinity)
                    } else if noteIconOnBar {
                        noteCell
                    }
                }
            }

            // Hochformat: Schnellnotiz als hervorgehobenes Symbol über dem Ablagefach
            if vertical && settings.showNotes {
                noteCell
                    .padding(.top, 4)
            }

            // Ablagefach: fest unten über den Einstellungen, hervorgehoben
            if settings.showShelf {
                let shelfIcon: CGFloat = 32
                ShelfCell(store: store, isActive: state.flyoutGroupID == LinkGroup.shelfID,
                          iconSize: shelfIcon,
                          cellSize: CGSize(width: vertical ? thickness : 60, height: vertical ? 58 : thickness),
                          showLabel: vertical, actions: actions)
                    .modifier(HoverScale(active: settings.magnification && state.hoveredCell == "group:\(LinkGroup.shelfID)",
                                         scale: min(CGFloat(settings.magnificationStrength),
                                                    max(1, (thickness - 4) / shelfIcon))))
                    .padding(vertical ? .top : .leading, 4)
            }

            if let release = updater.availableRelease {
                BarButton(symbol: "arrow.down.circle.fill", size: 20, tint: palette.accent,
                          cell: CGSize(width: vertical ? thickness : 40, height: vertical ? 36 : thickness),
                          help: "Update auf Version \(release.version) installieren") {
                    actions.installUpdate()
                }
            }
            BarButton(symbol: "gearshape", size: 15, tint: palette.secondary,
                      cell: CGSize(width: vertical ? thickness : 40, height: vertical ? 36 : thickness),
                      help: "Einstellungen") {
                actions.openSettings()
            }
            // Griff zum Verschieben ganz unten (wirkt so nicht wie eine Trennlinie)
            DragHandle(horizontal: vertical, onDrag: actions.drag)
                .frame(width: vertical ? thickness : 16, height: vertical ? 18 : thickness)
                .help("Ziehen, um die Sidebar an eine andere Kante oder auf einen anderen Bildschirm zu verschieben")
        }
    }

    /// Notiz-Symbol (hervorgehoben wie das Ablagefach)
    private var noteCell: some View {
        let icon: CGFloat = 36
        return NoteCell(store: store, iconSize: icon,
                        cellSize: CGSize(width: vertical ? thickness : 66, height: vertical ? 66 : thickness),
                        showLabel: vertical, actions: actions)
            .modifier(HoverScale(active: settings.magnification && state.hoveredCell == "action:note",
                                 scale: min(CGFloat(settings.magnificationStrength), max(1, (thickness - 4) / icon))))
    }

    /// Anzahl der Zellen in der Leiste (für die automatische Icon-Größe).
    private var cellCount: Int {
        store.config.favorites.count + (showFavoriteSlot ? 1 : 0) + max(store.config.groups.count, 1)
            + (settings.showSearch ? ActionButton.topButtons(vertical: vertical).count : 0)
    }

    private func cells(_ palette: Palette, metrics: BarMetrics) -> some View {
        let stack = vertical ? AnyLayout(VStackLayout(spacing: metrics.spacing))
                             : AnyLayout(HStackLayout(spacing: metrics.spacing))
        let cellSize = CGSize(width: vertical ? thickness : metrics.cell, height: vertical ? metrics.cell : thickness)
        let hovered = settings.magnification ? state.hoveredCell : nil
        // Lupe: Stärke aus den Einstellungen, höchstens so groß, dass das Icon in die Leiste passt
        let maxScale = min(CGFloat(settings.magnificationStrength), max(1, (thickness - 4) / metrics.icon))
        return stack {
            // KI und Google ganz oben
            if settings.showSearch {
                ForEach(ActionButton.topButtons(vertical: vertical)) { action in
                    ActionCell(action: action, iconSize: metrics.icon, cellSize: cellSize,
                               showLabel: metrics.showLabels, actions: actions)
                        .modifier(HoverScale(active: hovered == "action:\(action.rawValue)", scale: maxScale))
                }
                BarDivider(vertical: vertical, length: thickness * 0.5, color: palette.border)
            }

            // Favoriten (max. 10)
            ForEach(store.config.favorites) { item in
                FavoriteCell(item: item, iconSize: metrics.icon, cellSize: cellSize,
                             store: store, actions: actions)
                    .modifier(HoverScale(active: hovered == "fav:\(item.id)", scale: maxScale))
            }
            if showFavoriteSlot {
                AddSlotCell(containerID: LinkGroup.favoritesID,
                            symbol: store.config.favorites.isEmpty ? "star" : "plus",
                            help: "Favorit hinzufügen: Link hierher ziehen oder klicken (\(store.config.favorites.count)/\(SidebarConfig.maxFavorites))",
                            iconSize: metrics.icon, cellSize: cellSize, store: store, actions: actions)
            }

            BarDivider(vertical: vertical, length: thickness * 0.5, color: palette.border)

            // Unterordner
            ForEach(store.config.groups) { group in
                GroupCell(group: group, isActive: state.flyoutGroupID == group.id,
                          iconSize: metrics.icon, cellSize: cellSize, showLabel: metrics.showLabels,
                          store: store, actions: actions)
                    .modifier(HoverScale(active: hovered == "group:\(group.id)", scale: maxScale))
            }
            if store.config.groups.isEmpty {
                BarButton(symbol: "folder.badge.plus", size: metrics.icon * 0.6, tint: palette.secondary,
                          cell: cellSize, help: "Ordner anlegen") {
                    actions.openSettings()
                }
            }
        }
    }
}

/// KI- bzw. Google-Knopf oben in der Leiste.
struct ActionCell: View {
    let action: ActionButton
    let iconSize: CGFloat
    let cellSize: CGSize
    let showLabel: Bool
    let actions: SidebarActions
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(palette.accent)
                Image(systemName: action.symbol)
                    .font(.system(size: iconSize * 0.46, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
            }
            .frame(width: iconSize, height: iconSize)
            if showLabel {
                Text(action.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }
        }
        .frame(width: cellSize.width, height: cellSize.height)
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ActionFramesKey.self,
                                       value: [action.rawValue: proxy.frame(in: .named("bar"))])
            }
        )
        .onTapGesture { actions.triggerAction(action) }
        .help(action == .ai ? "KI: darüberfahren und lostippen · Klick öffnet die KI"
                            : "Google: darüberfahren und lostippen · Klick öffnet Google")
    }
}

/// Ablagefach in der Leiste.
struct ShelfCell: View {
    @ObservedObject var store: ConfigStore
    let isActive: Bool
    let iconSize: CGFloat
    let cellSize: CGSize
    let showLabel: Bool
    let actions: SidebarActions
    @State private var targeted = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        let highlighted = isActive || targeted
        let count = store.config.shelf.count
        VStack(spacing: 3) {
            ZStack {
                // Immer gefüllt in der Akzentfarbe mit feinem Goldrand – hebt sich von den Ordnern ab
                RoundedRectangle(cornerRadius: iconSize * 0.32, style: .continuous)
                    .fill(LinearGradient(colors: [palette.accent.opacity(highlighted ? 1 : 0.92), palette.accent],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: iconSize * 0.32, style: .continuous)
                    .strokeBorder(Palette.gold.opacity(highlighted ? 0.95 : 0.6), lineWidth: 1.2)
                Image(systemName: count > 0 ? "tray.full.fill" : "tray.fill")
                    .font(.system(size: iconSize * 0.46, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
            }
            .frame(width: iconSize, height: iconSize)
            .shadow(color: palette.accent.opacity(highlighted ? 0.55 : 0.3), radius: highlighted ? 6 : 3, y: 1)
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
                Text("Ablage")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
        }
        .frame(width: cellSize.width, height: cellSize.height)
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: GroupFramesKey.self,
                                       value: [LinkGroup.shelfID: proxy.frame(in: .named("bar"))])
            }
        )
        .onTapGesture { actions.toggleFlyout(LinkGroup.shelfID) }
        .help("Ablagefach: Dateien hierher ziehen und später gesammelt weitergeben")
        .linkDropTarget(isTargeted: $targeted) { payloads in
            store.addToShelf(payloads)
        }
    }
}

/// Berechnet, wie groß Icons sein dürfen, damit alles in die Leiste passt.
struct BarMetrics {
    static let padding: CGFloat = 8

    /// Platz, den alle Zellen in voller Größe brauchen
    static func naturalLength(cells: Int, thickness: CGFloat) -> CGFloat {
        2 * padding + 12 + CGFloat(max(cells, 1)) * (thickness * 0.95 + 4)
    }
    let cell: CGFloat
    let icon: CGFloat
    let spacing: CGFloat
    let showLabels: Bool

    init(available: CGFloat, cells: Int, thickness: CGFloat) {
        spacing = 4
        let count = CGFloat(max(cells, 1))
        let usable = available - 2 * Self.padding - 12 /* Trennlinie */ - spacing * count
        let maxCell = thickness * 0.95
        let minCell: CGFloat = 30
        cell = min(maxCell, max(minCell, usable / count))
        icon = min(30, max(18, cell * 0.58))
        showLabels = cell >= 50
    }
}

struct BarDivider: View {
    let vertical: Bool
    let length: CGFloat
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: vertical ? length : 1, height: vertical ? 1 : length)
            .padding(vertical ? .vertical : .horizontal, 5)
    }
}

struct BarButton: View {
    let symbol: String
    let size: CGFloat
    let tint: Color
    let cell: CGSize
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(tint)
                .frame(width: cell.width, height: cell.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct FavoriteCell: View {
    let item: LinkItem
    let iconSize: CGFloat
    let cellSize: CGSize
    let store: ConfigStore
    let actions: SidebarActions
    @State private var targeted = false
    @ObservedObject private var badges = BadgeStore.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        Button {
            actions.open(item, nil)
        } label: {
            FaviconView(item: item, size: iconSize)
                .overlay(alignment: .topTrailing) {
                    BadgeView(count: badges.count(for: item))
                        .offset(x: 6, y: -5)
                }
                .badgePulse(badges.count(for: item))
                .frame(width: cellSize.width, height: cellSize.height)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(targeted ? palette.accentSoft : Color.clear)
                        .padding(4)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: FavoriteFramesKey.self,
                                       value: [item.id: proxy.frame(in: .named("bar"))])
            }
        )
        .contextMenu {
            ItemContextMenu(item: item, isFavorite: true, store: store, actions: actions)
        }
        .onDrag { DropSupport.provider(for: item) }
        .linkDropTarget(isTargeted: $targeted) { payloads in
            store.handleDrop(payloads, into: LinkGroup.favoritesID, targetItem: item.id)
        }
    }
}

struct GroupCell: View {
    let group: LinkGroup
    let isActive: Bool
    let iconSize: CGFloat
    let cellSize: CGSize
    let showLabel: Bool
    let store: ConfigStore
    let actions: SidebarActions
    @State private var targeted = false
    @ObservedObject private var badges = BadgeStore.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        let highlighted = isActive || targeted
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: iconSize * 0.3, style: .continuous)
                    .fill(highlighted ? palette.accent : palette.accentSoft)
                Image(systemName: group.symbol)
                    .font(.system(size: iconSize * 0.48, weight: .semibold))
                    .foregroundStyle(highlighted ? palette.onAccent : palette.accent)
            }
            .frame(width: iconSize, height: iconSize)
            .overlay(alignment: .topTrailing) {
                BadgeView(count: badges.count(for: group))
                    .offset(x: 6, y: -5)
            }
            .badgePulse(badges.count(for: group))
            if showLabel {
                Text(group.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: cellSize.width - 6)
            }
        }
        .frame(width: cellSize.width, height: cellSize.height)
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: GroupFramesKey.self,
                                       value: [group.id: proxy.frame(in: .named("bar"))])
            }
        )
        .onTapGesture { actions.toggleFlyout(group.id) }
        .help("\(group.name) – \(group.items.count) Links · ziehen zum Umsortieren")
        .contextMenu {
            Button("Link hinzufügen …") { actions.addLink(group.id) }
            Button("Ordner bearbeiten …") { actions.openSettings() }
        }
        .onDrag { DropSupport.provider(forGroup: group) }
        .linkDropTarget(isTargeted: $targeted) { payloads in
            for case .internalGroup(let id) in payloads {
                store.moveGroup(id, onto: group.id)
            }
            store.handleDrop(payloads, into: group.id)
        }
    }
}

/// Gestricheltes Feld „Link hierher ziehen oder klicken“ – in der Leiste (Favoriten).
struct AddSlotCell: View {
    let containerID: UUID
    let symbol: String
    let help: String
    let iconSize: CGFloat
    let cellSize: CGSize
    let store: ConfigStore
    let actions: SidebarActions
    @State private var targeted = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        Button {
            actions.addLink(containerID)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: iconSize * 0.3, style: .continuous)
                    .fill(targeted ? palette.accentSoft : Color.clear)
                RoundedRectangle(cornerRadius: iconSize * 0.3, style: .continuous)
                    .strokeBorder(palette.dashed, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                Image(systemName: symbol)
                    .font(.system(size: iconSize * 0.42, weight: .semibold))
                    .foregroundStyle(palette.dashed)
            }
            .frame(width: iconSize, height: iconSize)
            .frame(width: cellSize.width, height: cellSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .linkDropTarget(isTargeted: $targeted) { payloads in
            store.handleDrop(payloads, into: containerID)
        }
    }
}

// MARK: - Ordner-Fenster (öffnet sich beim Hover)

struct FlyoutView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: SidebarState
    let geometry: SidebarGeometry
    let actions: SidebarActions
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    static let headerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 34
    static let rowSpacing: CGFloat = 2
    static let addRowHeight: CGFloat = 38
    static let listPadding: CGFloat = 8

    static func idealHeight(itemCount: Int) -> CGFloat {
        headerHeight + 1 + listPadding * 2
            + CGFloat(itemCount) * (rowHeight + rowSpacing) + addRowHeight
    }

    var body: some View {
        let palette = Palette.resolve(store.config.settings.colorTheme, scheme)
        ZStack {
            GlassFill(fill: palette.panelFill(gradient: store.config.settings.gradient),
                      intensity: max(store.config.settings.glassIntensity, 0.05),
                      mask: AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
            if state.flyoutGroupID == LinkGroup.shelfID {
                ShelfView(store: store, palette: palette)
            } else if let id = state.flyoutGroupID, let group = store.config.groups.first(where: { $0.id == id }) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.accent)
                            Image(systemName: group.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.onAccent)
                        }
                        .frame(width: 24, height: 24)
                        Text(group.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                        Spacer()
                        Text("\(group.items.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                    .background(
                        // Ordnername dauerhaft im Weiß der Blasen hervorgehoben
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(scheme == .dark ? 0.16 : 0.42))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(scheme == .dark ? 0.22 : 0.6), lineWidth: 0.8))
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(height: Self.headerHeight)

                    Rectangle().fill(palette.border).frame(height: 1)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: Self.rowSpacing) {
                            ForEach(group.items) { item in
                                FlyoutRow(item: item, groupID: group.id, store: store, actions: actions,
                                          isHovered: state.hoveredRow == item.id)
                            }
                            AddLinkRow(containerID: group.id, store: store, actions: actions)
                        }
                        .padding(Self.listPadding)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.border, lineWidth: 1))
        .overlay(GlassRim(shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                          intensity: store.config.settings.glassIntensity))
        .environment(\.colorTheme, store.config.settings.colorTheme)
        .coordinateSpace(name: "flyout")
        .onPreferenceChange(FlyoutRowFramesKey.self) { frames in
            geometry.flyoutRowFrames = frames
        }
    }
}

struct FlyoutRow: View {
    let item: LinkItem
    let groupID: UUID
    let store: ConfigStore
    let actions: SidebarActions
    var isHovered = false
    @ObservedObject private var badges = BadgeStore.shared
    @State private var targeted = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        Button {
            actions.open(item, nil)
        } label: {
            let active = isHovered || targeted
            HStack(spacing: 10) {
                FaviconView(item: item, size: 24)
                    // leichter Lupen-Effekt auf dem Icon
                    .scaleEffect(active ? 1.18 : 1)
                    .badgePulse(badges.count(for: item))
                Text(item.displayName)
                    .font(.system(size: 13, weight: active ? .medium : .regular))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                BadgeView(count: badges.count(for: item))
            }
            .padding(.horizontal, 8)
            .frame(height: FlyoutView.rowHeight)
            .background(
                // gleiche weiße, leicht durchscheinende Hervorhebung wie die Blase in der Leiste
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(active ? (scheme == .dark ? 0.16 : 0.42) : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(active ? (scheme == .dark ? 0.22 : 0.6) : 0), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(active ? 0.06 : 0), radius: 3, y: 1)
            )
            .scaleEffect(active ? 1.03 : 1, anchor: .leading)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
            .contentShape(Rectangle())
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: FlyoutRowFramesKey.self,
                                           value: [item.id: proxy.frame(in: .named("flyout"))])
                }
            )
        }
        .buttonStyle(.plain)
        .help(item.location)
        .contextMenu {
            ItemContextMenu(item: item, isFavorite: false, store: store, actions: actions)
        }
        .onDrag { DropSupport.provider(for: item) }
        .linkDropTarget(isTargeted: $targeted) { payloads in
            store.handleDrop(payloads, into: groupID, targetItem: item.id)
        }
    }
}

/// Das eine Feld am Ende der Liste: Link hineinziehen oder klicken.
struct AddLinkRow: View {
    let containerID: UUID
    let store: ConfigStore
    let actions: SidebarActions
    @State private var targeted = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        Button {
            actions.addLink(containerID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text(targeted ? "Loslassen zum Hinzufügen" : "Link hierher ziehen oder klicken")
                    .font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 10)
            .frame(height: FlyoutView.addRowHeight - 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(targeted ? palette.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.dashed, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .linkDropTarget(isTargeted: $targeted) { payloads in
            store.handleDrop(payloads, into: containerID)
        }
    }
}

struct ItemContextMenu: View {
    let item: LinkItem
    let isFavorite: Bool
    let store: ConfigStore
    let actions: SidebarActions

    var body: some View {
        Button("Öffnen") { actions.open(item, nil) }
        if item.isLocal {
            Button("Im Finder zeigen") {
                if let url = item.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        } else {
            Menu("Öffnen als") {
                ForEach(OpenMode.allCases) { mode in
                    Button(mode.title) { actions.open(item, mode) }
                }
            }
        }
        Divider()
        if isFavorite {
            Button("Aus Favoriten entfernen") { store.removeFromFavorites(id: item.id) }
        } else {
            Button("Zu Favoriten hinzufügen") { store.addToFavorites(itemID: item.id) }
                .disabled(store.favoritesFull)
        }
        Button("Eigenes Bild wählen …") { actions.chooseIcon(item.id) }
        if item.customIcon != nil {
            Button("Eigenes Bild entfernen") { store.removeCustomIcon(itemID: item.id) }
        }
        Button(item.isLocal ? "Pfad kopieren" : "Adresse kopieren") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.isLocal ? item.location : (item.url?.absoluteString ?? item.urlString),
                                           forType: .string)
        }
        Divider()
        Button("Bearbeiten …") { actions.editItem(item.id) }
        if !isFavorite {
            Button("Entfernen", role: .destructive) { store.deleteItem(id: item.id) }
        }
    }
}
