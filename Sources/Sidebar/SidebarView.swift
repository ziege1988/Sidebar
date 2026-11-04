import AppKit
import SwiftUI

@MainActor
final class SidebarState: ObservableObject {
    @Published var isExpanded = false
    @Published var isPinned = false
}

struct SidebarActions {
    var open: @MainActor (LinkItem, OpenMode?) -> Void
    var openSettings: @MainActor () -> Void
}

// MARK: - Hauptansicht

struct SidebarView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: SidebarState
    let actions: SidebarActions

    private var settings: SidebarSettings { store.config.settings }
    private var edge: ScreenEdge { settings.edge }
    private var thickness: CGFloat { CGFloat(settings.collapsedThickness) }
    private var showContent: Bool { state.isExpanded || !settings.autoHide }

    var body: some View {
        ZStack {
            if showContent {
                VisualEffectBackground()
                content
            } else {
                // Automatisch ausgeblendet: nur ein dezenter Rand als Auslöser.
                Color.primary.opacity(0.18)
            }
        }
        .clipShape(shape)
        .overlay {
            if showContent {
                shape.stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Nur die zum Bildschirm zeigenden Ecken werden abgerundet.
    private var shape: UnevenRoundedRectangle {
        let r: CGFloat = showContent ? 14 : 0
        switch edge {
        case .left:
            return UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
        case .right:
            return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, style: .continuous)
        case .top:
            return UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .continuous)
        case .bottom:
            return UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r, style: .continuous)
        }
    }

    @ViewBuilder
    private var content: some View {
        if edge.isVertical {
            verticalContent
        } else {
            horizontalContent
        }
    }

    // Links / rechts
    private var verticalContent: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.config.groups) { group in
                        VerticalGroupView(group: group, expanded: state.isExpanded, edge: edge,
                                          thickness: thickness, store: store, actions: actions)
                    }
                    if store.config.groups.isEmpty {
                        EmptyHint(thickness: thickness, actions: actions)
                    }
                }
                .padding(.vertical, 12)
            }
            Divider().opacity(0.6)
            SidebarFooter(state: state, edge: edge, thickness: thickness, actions: actions)
        }
    }

    // Oben / unten
    private var horizontalContent: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                if state.isExpanded {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(store.config.groups) { group in
                            HorizontalGroupColumn(group: group, store: store, actions: actions)
                        }
                    }
                    .padding(10)
                } else {
                    HStack(spacing: 2) {
                        ForEach(store.config.groups) { group in
                            CollapsedGroupStrip(group: group, thickness: thickness, store: store, actions: actions)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: thickness)
                }
            }
            Divider().opacity(0.6)
            SidebarFooter(state: state, edge: edge, thickness: thickness, actions: actions)
        }
    }
}

// MARK: - Bausteine

/// Zeile mit Icon-Spalte an der Bildschirmkante und Text daneben.
/// Die Icon-Spalte bleibt beim Aufklappen an derselben Stelle stehen.
struct EdgeRow<Icon: View, Title: View>: View {
    let edge: ScreenEdge
    let thickness: CGFloat
    let expanded: Bool
    @ViewBuilder var icon: Icon
    @ViewBuilder var title: Title

    var body: some View {
        HStack(spacing: 0) {
            if edge == .right {
                if expanded {
                    title
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.leading, 12)
                }
                icon.frame(width: thickness)
            } else {
                icon.frame(width: thickness)
                if expanded {
                    title
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .right ? .trailing : .leading)
    }
}

struct VerticalGroupView: View {
    let group: LinkGroup
    let expanded: Bool
    let edge: ScreenEdge
    let thickness: CGFloat
    let store: ConfigStore
    let actions: SidebarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EdgeRow(edge: edge, thickness: thickness, expanded: expanded) {
                Image(systemName: group.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            } title: {
                Text(group.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(height: 18)
            .help(group.name)

            ForEach(group.items) { item in
                SidebarItemButton(item: item, expanded: expanded, edge: edge,
                                  thickness: thickness, store: store, actions: actions)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.addDroppedURLs(urls, to: group.id)
        }
    }
}

struct SidebarItemButton: View {
    let item: LinkItem
    let expanded: Bool
    let edge: ScreenEdge
    let thickness: CGFloat
    let store: ConfigStore
    let actions: SidebarActions

    @State private var hovering = false

    var body: some View {
        Button {
            actions.open(item, nil)
        } label: {
            EdgeRow(edge: edge, thickness: thickness, expanded: expanded) {
                FaviconView(item: item, size: 24)
            } title: {
                Text(item.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.1) : Color.clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.displayName)
        .contextMenu {
            ItemContextMenu(item: item, store: store, actions: actions)
        }
    }
}

struct ItemContextMenu: View {
    let item: LinkItem
    let store: ConfigStore
    let actions: SidebarActions

    var body: some View {
        Button("Öffnen") { actions.open(item, nil) }
        Menu("Öffnen als") {
            ForEach(OpenMode.allCases) { mode in
                Button(mode.title) { actions.open(item, mode) }
            }
        }
        Button("Adresse kopieren") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url?.absoluteString ?? item.urlString, forType: .string)
        }
        Divider()
        Button("Bearbeiten …") { actions.openSettings() }
        Button("Entfernen", role: .destructive) { store.deleteItem(id: item.id) }
    }
}

/// Eingeklappte Darstellung oben/unten: Gruppen-Symbol + Icons in einer Reihe.
struct CollapsedGroupStrip: View {
    let group: LinkGroup
    let thickness: CGFloat
    let store: ConfigStore
    let actions: SidebarActions

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: group.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .help(group.name)
            ForEach(group.items) { item in
                Button {
                    actions.open(item, nil)
                } label: {
                    FaviconView(item: item, size: 24)
                        .frame(width: 40, height: thickness)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.displayName)
                .contextMenu { ItemContextMenu(item: item, store: store, actions: actions) }
            }
            Divider()
                .frame(height: thickness * 0.5)
                .padding(.horizontal, 6)
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.addDroppedURLs(urls, to: group.id)
        }
    }
}

/// Ausgeklappte Darstellung oben/unten: eine Spalte pro Gruppe.
struct HorizontalGroupColumn: View {
    let group: LinkGroup
    let store: ConfigStore
    let actions: SidebarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EdgeRow(edge: .left, thickness: 36, expanded: true) {
                Image(systemName: group.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            } title: {
                Text(group.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(height: 20)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        SidebarItemButton(item: item, expanded: true, edge: .left,
                                          thickness: 40, store: store, actions: actions)
                    }
                }
            }
        }
        .frame(width: 210)
        .dropDestination(for: URL.self) { urls, _ in
            store.addDroppedURLs(urls, to: group.id)
        }
    }
}

struct SidebarFooter: View {
    @ObservedObject var state: SidebarState
    let edge: ScreenEdge
    let thickness: CGFloat
    let actions: SidebarActions

    var body: some View {
        if edge.isVertical {
            HStack(spacing: 0) {
                if edge == .right {
                    if state.isExpanded {
                        pinButton.padding(.leading, 12)
                        Spacer()
                    }
                    settingsButton.frame(width: thickness)
                } else {
                    settingsButton.frame(width: thickness)
                    if state.isExpanded {
                        Spacer()
                        pinButton.padding(.trailing, 12)
                    }
                }
            }
            .frame(height: 44)
        } else {
            VStack(spacing: 4) {
                settingsButton
                if state.isExpanded { pinButton }
            }
            .frame(width: 48)
        }
    }

    private var settingsButton: some View {
        Button {
            actions.openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Einstellungen")
    }

    private var pinButton: some View {
        Button {
            state.isPinned.toggle()
        } label: {
            Image(systemName: state.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13))
                .foregroundStyle(state.isPinned ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(state.isPinned ? "Nicht mehr offen halten" : "Offen halten")
    }
}

struct EmptyHint: View {
    let thickness: CGFloat
    let actions: SidebarActions

    var body: some View {
        Button {
            actions.openSettings()
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: thickness, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Gruppe hinzufügen")
    }
}

/// Unscharfer, halbtransparenter macOS-Hintergrund.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
