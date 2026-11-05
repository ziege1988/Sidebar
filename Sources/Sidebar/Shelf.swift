import AppKit
import Combine
import QuickLookThumbnailing
import SwiftUI

/// Vorschaubilder für Dateien im Ablagefach (Quick Look), mit Programm-Icon als Ersatz.
final class ThumbnailStore: ObservableObject {
    static let shared = ThumbnailStore()
    @Published private(set) var images: [URL: NSImage] = [:]
    private var requested: Set<URL> = []

    func image(for url: URL) -> NSImage? { images[url] }

    func load(_ url: URL) {
        guard !requested.contains(url) else { return }
        requested.insert(url)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 144, height: 144),
                                                   scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async { self.images[url] = image }
        }
    }
}

/// Inhalt des Ablagefach-Fensters.
struct ShelfView: View {
    @ObservedObject var store: ConfigStore
    let palette: Palette

    static let tile: CGFloat = 72
    static let spacing: CGFloat = 8
    static let headerHeight: CGFloat = 44
    static let footerHeight: CGFloat = 48
    static let width: CGFloat = 3 * tile + 2 * spacing + 24

    static func idealHeight(fileCount: Int) -> CGFloat {
        let rows = CGFloat((fileCount + 1 + 2) / 3) // +1 für das Ablagefeld
        return headerHeight + 1 + 20 + rows * tile + max(0, rows - 1) * spacing + footerHeight
    }

    @State private var targeted = false

    var body: some View {
        let files = store.shelfFiles
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.accent)
                    Image(systemName: "tray.full")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.onAccent)
                }
                .frame(width: 24, height: 24)
                Text("Ablagefach")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text(files.count == 1 ? "1 Datei" : "\(files.count) Dateien")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: Self.headerHeight)

            Rectangle().fill(palette.border).frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.tile), spacing: Self.spacing), count: 3),
                          spacing: Self.spacing) {
                    ForEach(files, id: \.self) { url in
                        ShelfTile(url: url, store: store, palette: palette)
                    }
                    ShelfDropTile(palette: palette, targeted: targeted)
                }
                .padding(10)
            }

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.surface)
                    Label("Alle ziehen", systemImage: "hand.draw")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.text)
                    FileDragSource(urls: files,
                                   toolTip: "Alle Dateien zusammen herausziehen – sie verschwinden danach aus dem Fach",
                                   onDragged: { [store] in store.removeFromShelf(files) })
                }
                .frame(height: 28)
                .help("Hier anfassen und alle Dateien zusammen z. B. in eine Mail oder einen Ordner ziehen")
                .opacity(files.isEmpty ? 0.4 : 1)

                Button {
                    store.clearShelf()
                } label: {
                    Text("Leeren")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.surface))
                }
                .buttonStyle(.plain)
                .disabled(files.isEmpty)
                .help("Ablagefach leeren – die Dateien selbst bleiben erhalten")
            }
            .padding(.horizontal, 10)
            .frame(height: Self.footerHeight)
        }
        .linkDropTarget(isTargeted: $targeted) { payloads in
            store.addToShelf(payloads)
        }
    }
}

struct ShelfTile: View {
    let url: URL
    let store: ConfigStore
    let palette: Palette
    @ObservedObject private var thumbnails = ThumbnailStore.shared

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = thumbnails.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                palette.surface
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(14)
            }
            Text(url.lastPathComponent)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: ShelfView.tile, height: ShelfView.tile)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            FileDragSource(
                urls: [url],
                image: thumbnails.image(for: url),
                toolTip: url.lastPathComponent + " – herausziehen zum Weitergeben, Doppelklick öffnet",
                onDoubleClick: { NSWorkspace.shared.open(url) },
                menu: { [store] in
                    let menu = NSMenu()
                    menu.addItem(Self.item("Öffnen") { NSWorkspace.shared.open(url) })
                    menu.addItem(Self.item("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
                    menu.addItem(.separator())
                    menu.addItem(Self.item("Aus dem Ablagefach entfernen") { store.removeFromShelf(url) })
                    return menu
                },
                onDragged: { [store] in
                    // Erfolgreich woanders abgelegt → raus aus dem Fach
                    store.removeFromShelf(url)
                }
            )
        )
        .onAppear { thumbnails.load(url) }
    }

    @MainActor
    private static func item(_ title: String, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let target = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        return item
    }
}

struct ShelfDropTile: View {
    let palette: Palette
    let targeted: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
            Text("hierher\nziehen")
                .font(.system(size: 9))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(palette.secondary)
        .frame(width: ShelfView.tile, height: ShelfView.tile)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(targeted ? palette.accentSoft : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(palette.dashed, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        )
    }
}

/// Unsichtbare Fläche, von der aus Dateien weggezogen werden.
/// Meldet über `onDragged`, wenn die Dateien tatsächlich woanders abgelegt wurden.
struct FileDragSource: NSViewRepresentable {
    let urls: [URL]
    var image: NSImage? = nil
    var toolTip: String? = nil
    var onDoubleClick: (@MainActor () -> Void)? = nil
    var menu: (@MainActor () -> NSMenu)? = nil
    let onDragged: @MainActor () -> Void

    func makeNSView(context: Context) -> FileDragView {
        let view = FileDragView()
        update(view)
        return view
    }

    func updateNSView(_ view: FileDragView, context: Context) {
        update(view)
    }

    private func update(_ view: FileDragView) {
        view.urls = urls
        view.image = image
        view.toolTip = toolTip
        view.onDoubleClick = onDoubleClick
        view.makeMenu = menu
        view.onDragged = onDragged
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var image: NSImage?
    var onDoubleClick: (@MainActor () -> Void)?
    var makeMenu: (@MainActor () -> NSMenu)?
    var onDragged: (@MainActor () -> Void)?
    private var downLocation: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        downLocation = event.locationInWindow
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func mouseUp(with event: NSEvent) {
        downLocation = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeMenu?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !urls.isEmpty, let start = downLocation else { return }
        // Erst ab ein paar Punkten Bewegung ziehen (Doppelklick bleibt möglich)
        let moved = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
        guard moved >= 3 else { return }
        downLocation = nil

        let location = convert(event.locationInWindow, from: nil)
        let items: [NSDraggingItem] = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let picture = (urls.count == 1 ? image : nil) ?? NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(min(index, 4)) * 5
            item.setDraggingFrame(NSRect(x: location.x - 28 + offset, y: location.y - 28 - offset,
                                         width: 56, height: 56),
                                  contents: picture)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        // Abgebrochen → bleibt im Fach
        guard operation != [] else { return }
        // Wieder auf der Sidebar abgelegt → bleibt im Fach
        let droppedOnSidebar = NSApp.windows.contains { $0.isVisible && $0.frame.contains(screenPoint) }
        guard !droppedOnSidebar else { return }
        onDragged?()
    }
}
