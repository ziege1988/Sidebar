import AppKit
import SwiftUI

// MARK: - Rüdigers Gesten als Sprite-Animation
//
// Die Einzelbilder liegen in Resources/Sprites/<name>/NNNN.png (erzeugt mit tools/sprites/render.js):
// Rüdiger beugt sich vor, hebt die Pfote gerade nach vorn an die „Scheibe“ (den Bildschirm) und kratzt.
// Die Bilder sind durchsichtig – das runde Fenster zeichnet die App selbst darunter.
// Die Kratzspuren zeichnet die App unter den Krallenspitzen (Positionen in <name>.json).

enum CatGesture: String {
    /// beugt sich vor und zerkratzt die Scheibe (Spuren verblassen)
    case scratch
    /// beugt sich vor und wedelt dich abfällig weg (beim Beenden)
    case flick

    var duration: Double { CatSprites.shared.sequence(self)?.duration ?? 2.5 }
}

/// Geladene Einzelbilder einer Geste
struct CatSpriteSequence {
    let frames: [NSImage]
    let fps: Double
    /// Bildbreite in Fensterdurchmessern
    let span: Double
    /// Krallenspitzen je Bild (0 … 1 im Bild), `nil` = Pfote kratzt gerade nicht
    let claws: [[CGPoint]?]
    /// Ende des letzten Kratzers (Sekunden) – die Spuren bleiben danach 2 s stehen
    let scratchEnd: Double

    var duration: Double { Double(frames.count) / fps }
    /// Spuren bleiben 2 s nach dem letzten Kratzer, dann verblassen sie in 0,6 s
    var marksGone: Double { scratchEnd > 0 ? scratchEnd + 2.6 : 0 }
}

final class CatSprites {
    static let shared = CatSprites()
    private var cache: [CatGesture: CatSpriteSequence] = [:]

    private struct Meta: Decodable {
        let fps: Double
        let span: Double
        let frames: Int
        let scratchEnd: Double?
        let claws: [[[Double]]?]
    }

    func sequence(_ gesture: CatGesture) -> CatSpriteSequence? {
        if let cached = cache[gesture] { return cached }
        guard let base = Bundle.main.resourceURL?.appendingPathComponent("Sprites"),
              let data = try? Data(contentsOf: base.appendingPathComponent(gesture.rawValue + ".json")),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return nil }
        let folder = base.appendingPathComponent(gesture.rawValue)
        var frames: [NSImage] = []
        for i in 0..<meta.frames {
            guard let image = NSImage(contentsOf: folder.appendingPathComponent(String(format: "%04d.png", i))) else { return nil }
            frames.append(image)
        }
        let claws = meta.claws.map { frame in frame?.map { CGPoint(x: $0[0], y: $0[1]) } }
        let sequence = CatSpriteSequence(frames: frames, fps: meta.fps, span: meta.span, claws: claws,
                                         scratchEnd: meta.scratchEnd ?? 0)
        cache[gesture] = sequence
        return sequence
    }
}

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

    /// `false`, wenn die Bilder fehlen
    @discardableResult
    func perform(_ gesture: CatGesture, at location: CatLocation) -> Bool {
        guard let sequence = CatSprites.shared.sequence(gesture) else { return false }
        let side = location.cat.width * CGFloat(sequence.span)
        let frame = NSRect(x: location.cat.midX - side / 2, y: location.cat.midY - side / 2, width: side, height: side)
        // An der rechten Bildschirmkante gespiegelt – die Pfote kratzt immer zur Bildschirmmitte hin
        let host = NSHostingView(rootView: CatGestureView(sequence: sequence, start: Date(), scratches: gesture == .scratch,
                                                          mirrored: location.edge == .right))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + max(sequence.duration, sequence.marksGone) + 0.05,
                                      execute: work)
        return true
    }
}

struct CatGestureView: View {
    let sequence: CatSpriteSequence
    let start: Date
    let scratches: Bool
    var mirrored = false

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                if mirrored {
                    context.translateBy(x: size.width, y: 0)
                    context.scaleBy(x: -1, y: 1)
                }
                let index = min(Int(t * sequence.fps), sequence.frames.count - 1)
                if t < sequence.duration {
                    context.draw(Image(nsImage: sequence.frames[index]), in: CGRect(origin: .zero, size: size))
                }
                if scratches { drawScratches(&context, size: size, upTo: index, t: t) }
            }
        }
        .allowsHitTesting(false)
    }

    /// Kratzspuren auf der „Scheibe“: folgen den Krallenspitzen, dünn → tief → ausgefranst, verblassen
    private func drawScratches(_ context: inout GraphicsContext, size: CGSize, upTo index: Int, t: Double) {
        // bleiben 2 s nach dem letzten Kratzer voll stehen, dann sanft weg
        let hold = sequence.scratchEnd + 2
        let fade = t < hold ? 1 : max(0, 1 - (t - hold) / 0.6)
        guard fade > 0 else { return }
        // zusammenhängende Kratzer (Bilder, in denen die Pfote zieht)
        var runs: [[[CGPoint]]] = []
        var current: [[CGPoint]] = []
        for i in 0...index {
            if let claws = sequence.claws[i] {
                current.append(claws)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }

        let scale = size.width / 220      // Breite der Spur passend zur Größe
        for (r, run) in runs.enumerated() where run.count > 1 {
            for claw in 0..<4 {
                let strength: CGFloat = claw == 0 || claw == 3 ? 0.7 : 1
                for i in 1..<run.count {
                    let a = CGPoint(x: run[i - 1][claw].x * size.width, y: run[i - 1][claw].y * size.height)
                    let b = CGPoint(x: run[i][claw].x * size.width, y: run[i][claw].y * size.height)
                    let q = Double(i) / Double(run.count - 1)
                    let jitter = CGFloat(sin(Double(i * 7 + claw * 13 + r * 29) * 1.7)) * 0.4
                    let width = (1 + 2.6 * CGFloat(sin(.pi * min(q * 1.05, 1)))) * strength * max(scale, 0.8)
                    var groove = Path()
                    groove.move(to: CGPoint(x: a.x + jitter, y: a.y))
                    groove.addLine(to: CGPoint(x: b.x + jitter, y: b.y))
                    context.stroke(groove, with: .color(.black.opacity(0.4 * fade)),
                                   style: StrokeStyle(lineWidth: width + 1, lineCap: .round))
                    var edge = Path()
                    edge.move(to: CGPoint(x: a.x + jitter + 0.8, y: a.y))
                    edge.addLine(to: CGPoint(x: b.x + jitter + 0.8, y: b.y))
                    context.stroke(edge, with: .color(.white.opacity(0.9 * fade)),
                                   style: StrokeStyle(lineWidth: max(0.5, width * 0.45), lineCap: .round))
                }
            }
        }
    }
}
