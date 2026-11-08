import AppKit
import SwiftUI

// MARK: - Rüdigers Gesten: Pfote kommt aus dem Fenster heraus

enum CatGesture {
    /// kratzt zweimal über den Bildschirm (Kratzspuren bleiben kurz stehen)
    case scratch
    /// abfällige Handbewegung (beim Beenden)
    case flick

    /// Dauer der Bewegung (ohne Ausblenden der Kratzspuren)
    var duration: Double {
        switch self {
        case .scratch: return 1.9
        case .flick: return 1.5
        }
    }
}

/// Eigenes, durchsichtiges Fenster über der Sidebar, damit die Pfote aus Rüdigers Fenster
/// herausragen kann (3D-Effekt). Klicks gehen hindurch.
@MainActor
final class CatGestureController {
    static let shared = CatGestureController()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    func perform(_ gesture: CatGesture, at location: CatLocation) {
        let diameter = location.cat.width
        let side = diameter * 3.4
        let frame = NSRect(x: location.cat.midX - side / 2, y: location.cat.midY - side / 2, width: side, height: side)
        // Richtung: vom Bildschirmrand weg, schräg ins Bild (lokal, y nach unten)
        let s = CGFloat(0.5.squareRoot())
        let direction: CGVector
        switch location.edge {
        case .top, .left: direction = CGVector(dx: s, dy: s)
        case .bottom: direction = CGVector(dx: s, dy: -s)
        case .right: direction = CGVector(dx: -s, dy: s)
        }
        let view = CatGestureView(gesture: gesture, start: Date(), radius: diameter / 2, direction: direction)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.orderOut(nil)
                self?.panel.contentView = nil
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + gesture.duration + (gesture == .scratch ? 2.4 : 0.1),
                                      execute: work)
    }
}

struct CatGestureView: View {
    let gesture: CatGesture
    let start: Date
    let radius: CGFloat
    let direction: CGVector

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                CatGesturePainter.draw(in: &context, size: size, gesture: gesture, t: t,
                                       radius: radius, direction: direction)
            }
        }
        .allowsHitTesting(false)
    }
}

enum CatGesturePainter {
    private static func ease(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return 1 - pow(1 - v, 3)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, gesture: CatGesture, t: Double,
                     radius r: CGFloat, direction d: CGVector) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let perp = CGVector(dx: -d.dy, dy: d.dx)
        let reach = r * 0.9 + r * 0.8           // so weit kommt die Pfote heraus
        func point(along a: CGFloat, across b: CGFloat) -> CGPoint {
            CGPoint(x: center.x + d.dx * a + perp.dx * b, y: center.y + d.dy * a + perp.dy * b)
        }

        // Wie weit draußen (0…1) und Seitwärtsbewegung (in Pfotenbreiten)
        var out: Double = 0
        var across: Double = 0
        var shift: CGFloat = 0
        var clawsOut = false
        switch gesture {
        case .scratch:
            if t < 0.35 { out = ease(t / 0.35); across = -0.6 }
            else if t < 0.8 { out = 1; across = -0.6 + 1.2 * ease((t - 0.35) / 0.45); clawsOut = true }
            else if t < 0.9 { out = 0.92; across = 0.6 - 1.2 * ((t - 0.8) / 0.1) }
            else if t < 1.35 { out = 1; shift = r * 0.16; across = -0.6 + 1.2 * ease((t - 0.9) / 0.45); clawsOut = true }
            else if t < 1.85 { out = 1 - ease((t - 1.35) / 0.5); across = 0.6; shift = r * 0.16 }
            else { out = 0 }
        case .flick:
            if t < 0.35 { out = ease(t / 0.35); across = 0.5 }
            else if t < 0.6 { out = 1; across = 0.5 - 1.4 * ease((t - 0.35) / 0.25) }
            else if t < 1.0 { out = 1; across = -0.9 }
            else if t < 1.45 { out = 1 - ease((t - 1.0) / 0.45); across = -0.9 }
        }

        // Kratzspuren (bleiben stehen und verblassen)
        if gesture == .scratch {
            let fade = t < 1.9 ? 1 : max(0, 1 - (t - 1.9) / 2.2)
            for (index, (from, to, extra)) in [(0.35, 0.8, CGFloat(0)), (0.9, 1.35, r * 0.16)].enumerated() {
                guard t > from, fade > 0 else { continue }
                let progress = min(1, ease((t - from) / (to - from)))
                let along = reach + extra
                for offset in [-0.14, 0.0, 0.14] {
                    let a = along + r * CGFloat(offset)
                    let start = point(along: a, across: r * 0.42 * -0.6)
                    let end = point(along: a, across: r * 0.42 * CGFloat(-0.6 + 1.2 * progress))
                    var mark = Path()
                    mark.move(to: start)
                    let mid = point(along: a + r * 0.05, across: r * 0.42 * CGFloat(-0.6 + 0.6 * progress))
                    mark.addQuadCurve(to: end, control: mid)
                    context.stroke(mark, with: .color(.black.opacity(0.32 * fade)),
                                   style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                    context.stroke(mark, with: .color(.white.opacity(0.9 * fade)),
                                   style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
                _ = index
            }
        }

        guard out > 0.01 else { return }
        let fur = CatPainter.fur
        let base = point(along: r * 0.86, across: 0)
        let tip = point(along: r * 0.86 + (reach - r * 0.86) * CGFloat(out) + shift,
                        across: r * 0.42 * CGFloat(across) * CGFloat(out))
        // Arm mit leichtem Schatten (3D)
        var arm = Path()
        arm.move(to: base)
        arm.addLine(to: tip)
        var shadow = context
        shadow.translateBy(x: 2, y: 3)
        shadow.stroke(arm, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: r * 0.34, lineCap: .round))
        context.stroke(arm, with: .color(fur), style: StrokeStyle(lineWidth: r * 0.32, lineCap: .round))
        // Pfote
        let paw = r * 0.22
        context.fill(Path(ellipseIn: CGRect(x: tip.x - paw, y: tip.y - paw, width: 2 * paw, height: 2 * paw)),
                     with: .color(fur))
        // Ballen (zum Betrachter)
        let bean = CatPainter.innerEar
        let pad = point(along: 0, across: 0)
        _ = pad
        context.fill(Path(ellipseIn: CGRect(x: tip.x - paw * 0.38, y: tip.y - paw * 0.3, width: paw * 0.76, height: paw * 0.62)),
                     with: .color(bean))
        for k in [-1.0, -0.35, 0.35, 1.0] {
            let toe = CGPoint(x: tip.x + d.dx * paw * 0.62 + perp.dx * paw * 0.5 * CGFloat(k),
                              y: tip.y + d.dy * paw * 0.62 + perp.dy * paw * 0.5 * CGFloat(k))
            context.fill(Path(ellipseIn: CGRect(x: toe.x - paw * 0.17, y: toe.y - paw * 0.17,
                                                width: paw * 0.34, height: paw * 0.34)), with: .color(bean))
            // Krallen beim Kratzen
            if clawsOut {
                var claw = Path()
                let root = CGPoint(x: toe.x + d.dx * paw * 0.25, y: toe.y + d.dy * paw * 0.25)
                claw.move(to: root)
                claw.addLine(to: CGPoint(x: root.x + d.dx * paw * 0.45 - perp.dx * paw * 0.1,
                                         y: root.y + d.dy * paw * 0.45 - perp.dy * paw * 0.1))
                context.stroke(claw, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }
}
