import AppKit
import SwiftUI

@MainActor
final class SidebarState: ObservableObject {
    /// Ordner, dessen Fenster gerade geöffnet ist
    @Published var flyoutGroupID: UUID?
    /// Bei „Automatisch ausblenden“: Leiste gerade sichtbar
    @Published var isRevealed = false
    /// Element unter der Maus (für den Lupen-Effekt): "fav:<id>" bzw. "group:<id>"
    @Published var hoveredCell: String?
    /// Wo der Verlauf am unteren Rand der Uhr steht (0 … 1), damit Uhr und Leiste nahtlos ineinander übergehen
    @Published var clockGradientEnd: Double = 0.2
}

/// Positionen der Symbole in der Leiste (Koordinaten der Leiste, Ursprung oben links).
final class SidebarGeometry {
    var groupFrames: [UUID: CGRect] = [:]
    var favoriteFrames: [UUID: CGRect] = [:]
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
    private var showContent: Bool { state.isRevealed || !settings.autoHide }
    private var showFavoriteSlot: Bool { store.config.favorites.count < SidebarConfig.maxFavorites }

    var body: some View {
        let palette = Palette.resolve(settings.colorTheme, scheme)
        ZStack {
            if showContent {
                Rectangle().fill(palette.backgroundFill(gradient: settings.gradient))
                barContent(palette)
            } else {
                // Automatisch ausgeblendet: nur ein dezenter Rand als Auslöser.
                palette.accent.opacity(0.55)
            }
        }
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "bar")
        .onPreferenceChange(GroupFramesKey.self) { frames in
            geometry.groupFrames = frames
        }
        .onPreferenceChange(FavoriteFramesKey.self) { frames in
            geometry.favoriteFrames = frames
        }
        .environment(\.colorTheme, settings.colorTheme)
    }

    /// Nur die zum Bildschirm zeigenden Ecken werden abgerundet.
    private var shape: UnevenRoundedRectangle {
        EdgeShape.shape(for: edge, radius: showContent ? 14 : 0)
    }

    private func barContent(_ palette: Palette) -> some View {
        let outer = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        let clockInset = ClockLayout.inset(settings)
        return outer {
            // Platz für die Uhr, die oben aus der Leiste heraussteht
            if clockInset > 0 {
                Color.clear
                    .frame(width: vertical ? thickness : clockInset, height: vertical ? clockInset : thickness)
            }
            DragHandle(horizontal: vertical, onDrag: actions.drag)
                .frame(width: vertical ? thickness : 16, height: vertical ? 16 : thickness)
                .help("Ziehen, um die Sidebar an eine andere Kante oder auf einen anderen Bildschirm zu verschieben")

            GeometryReader { proxy in
                let length = vertical ? proxy.size.height : proxy.size.width
                let metrics = BarMetrics(available: length, cells: cellCount, thickness: thickness)
                ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                    cells(palette, metrics: metrics)
                        .padding(vertical ? .vertical : .horizontal, BarMetrics.padding)
                        .frame(minWidth: vertical ? proxy.size.width : nil,
                               minHeight: vertical ? nil : proxy.size.height)
                }
            }

            if let release = updater.availableRelease {
                BarButton(symbol: "arrow.down.circle.fill", size: 20, tint: palette.accent,
                          cell: CGSize(width: vertical ? thickness : 40, height: vertical ? 36 : thickness),
                          help: "Update auf Version \(release.version) installieren") {
                    actions.installUpdate()
                }
            }
            BarButton(symbol: "gearshape", size: 15, tint: palette.secondary,
                      cell: CGSize(width: vertical ? thickness : 40, height: vertical ? 40 : thickness),
                      help: "Einstellungen") {
                actions.openSettings()
            }
        }
    }

    /// Anzahl der Zellen in der Leiste (für die automatische Icon-Größe).
    private var cellCount: Int {
        store.config.favorites.count + (showFavoriteSlot ? 1 : 0) + max(store.config.groups.count, 1)
    }

    private func cells(_ palette: Palette, metrics: BarMetrics) -> some View {
        let stack = vertical ? AnyLayout(VStackLayout(spacing: metrics.spacing))
                             : AnyLayout(HStackLayout(spacing: metrics.spacing))
        let cellSize = CGSize(width: vertical ? thickness : metrics.cell, height: vertical ? metrics.cell : thickness)
        let hovered = settings.magnification ? state.hoveredCell : nil
        // Lupe: Stärke aus den Einstellungen, höchstens so groß, dass das Icon in die Leiste passt
        let maxScale = min(CGFloat(settings.magnificationStrength), max(1, (thickness - 4) / metrics.icon))
        return stack {
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

/// Berechnet, wie groß Icons sein dürfen, damit alles in die Leiste passt.
struct BarMetrics {
    static let padding: CGFloat = 8
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
            VisualEffectBackground()
            Rectangle().fill(palette.backgroundFill(gradient: store.config.settings.gradient)).opacity(0.95)
            if let id = state.flyoutGroupID, let group = store.config.groups.first(where: { $0.id == id }) {
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
                    .padding(.horizontal, 14)
                    .frame(height: Self.headerHeight)

                    Rectangle().fill(palette.border).frame(height: 1)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: Self.rowSpacing) {
                            ForEach(group.items) { item in
                                FlyoutRow(item: item, groupID: group.id, store: store, actions: actions)
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
        .environment(\.colorTheme, store.config.settings.colorTheme)
    }
}

struct FlyoutRow: View {
    let item: LinkItem
    let groupID: UUID
    let store: ConfigStore
    let actions: SidebarActions
    @ObservedObject private var badges = BadgeStore.shared
    @State private var hovering = false
    @State private var targeted = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorTheme) private var theme

    var body: some View {
        let palette = Palette.resolve(theme, scheme)
        Button {
            actions.open(item, nil)
        } label: {
            HStack(spacing: 10) {
                FaviconView(item: item, size: 24)
                Text(item.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                BadgeView(count: badges.count(for: item))
            }
            .padding(.horizontal, 8)
            .frame(height: FlyoutView.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering || targeted ? palette.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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

/// Unscharfer, halbtransparenter macOS-Hintergrund.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
