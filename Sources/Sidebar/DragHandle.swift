import AppKit
import SwiftUI

enum DragPhase {
    case began, moved, ended
}

/// Griff zum Verschieben der Sidebar. Liefert die Mausposition in Bildschirmkoordinaten.
struct DragHandle: NSViewRepresentable {
    let horizontal: Bool
    let onDrag: @MainActor (DragPhase, NSPoint) -> Void

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.horizontal = horizontal
        view.onDrag = onDrag
        return view
    }

    func updateNSView(_ view: DragHandleView, context: Context) {
        view.onDrag = onDrag
        if view.horizontal != horizontal {
            view.horizontal = horizontal
            view.needsDisplay = true
        }
    }
}

final class DragHandleView: NSView {
    var horizontal = true
    var onDrag: (@MainActor (DragPhase, NSPoint) -> Void)?

    private var startPoint: NSPoint?
    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = horizontal ? NSSize(width: 28, height: 5) : NSSize(width: 5, height: 28)
        let rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).fill()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        let location = NSEvent.mouseLocation
        if !isDragging {
            // Kleine Bewegungen ignorieren (versehentliches Ziehen)
            guard hypot(location.x - startPoint.x, location.y - startPoint.y) >= 4 else { return }
            isDragging = true
            NSCursor.closedHand.push()
            onDrag?(.began, location)
        }
        onDrag?(.moved, location)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            NSCursor.pop()
            onDrag?(.ended, NSEvent.mouseLocation)
        }
        isDragging = false
        startPoint = nil
    }
}
