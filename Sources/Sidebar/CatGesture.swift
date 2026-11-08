import AppKit
import ImageIO
import SwiftUI

// MARK: - Rüdigers Sprite-Animationen
//
// Alle Bewegungen liegen als Einzelbilder in Resources/Sprites/<name>/NNNN.png (erzeugt mit
// tools/sprites/render.js, verkleinert mit tools/sprites/optimize.py). Die Bilder sind durchsichtig:
// die Glasblase (Farbe, Leuchten) zeichnet die App darunter, Rand und Lichtreflexe stecken im Bild.

/// Daten einer Animation
struct CatSpriteSequence {
    /// PNG-Daten je Bild (werden erst beim Zeichnen entpackt – spart Arbeitsspeicher)
    let frames: [Data]
    let fps: Double
    let loop: Bool
    /// Bildbreite in Blasendurchmessern (1 = nur die Blase, 2.2 = Gesten, die herausragen)
    let span: Double
    /// so lange ist Rüdiger in den Gestenbildern zu sehen (danach z. B. nur noch Kratzspuren)
    let catUntil: Double

    var duration: Double { Double(frames.count) / fps }

    func index(at t: Double) -> Int {
        let i = Int(t * fps)
        return loop ? ((i % frames.count) + frames.count) % frames.count : min(max(i, 0), frames.count - 1)
    }
}

final class CatSprites {
    static let shared = CatSprites()
    private var cache: [String: CatSpriteSequence] = [:]
    private var missing: Set<String> = []

    private struct Meta: Decodable {
        let fps: Double
        let frames: Int
        let loop: Bool?
        let span: Double?
        let catUntil: Double?
    }

    func has(_ name: String) -> Bool { sequence(name) != nil }

    func sequence(_ name: String) -> CatSpriteSequence? {
        if let cached = cache[name] { return cached }
        if missing.contains(name) { return nil }
        guard let base = Bundle.main.resourceURL?.appendingPathComponent("Sprites"),
              let data = try? Data(contentsOf: base.appendingPathComponent(name + ".json")),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else {
            missing.insert(name)
            return nil
        }
        let folder = base.appendingPathComponent(name)
        var frames: [Data] = []
        for i in 0..<meta.frames {
            guard let frame = try? Data(contentsOf: folder.appendingPathComponent(String(format: "%04d.png", i))) else {
                missing.insert(name)
                return nil
            }
            frames.append(frame)
        }
        let sequence = CatSpriteSequence(frames: frames, fps: meta.fps, loop: meta.loop ?? true, span: meta.span ?? 1,
                                         catUntil: meta.catUntil ?? Double(meta.frames) / meta.fps)
        cache[name] = sequence
        return sequence
    }

    /// Bild einer Animation zur Zeit t (Sekunden seit Beginn)
    func image(_ name: String, at t: Double) -> NSImage? {
        guard let sequence = sequence(name) else { return nil }
        return NSImage(data: sequence.frames[sequence.index(at: t)])
    }

    /// Bild für Rüdigers Fenster: Schleifen laufen mit der Uhr, der Auftritt ab seinem Beginn
    func frame(_ name: String, pose: CatPose, at date: Date) -> NSImage? {
        if case .intro(let since) = pose { return image(name, at: since) }
        return image(name, at: date.timeIntervalSinceReferenceDate)
    }
}

// MARK: - Gesten (ragen aus der Blase heraus)

enum CatGesture: String {
    /// beugt sich heraus, holt seitlich aus und zerkratzt den Bildschirm (Spuren bleiben 2 s)
    case scratch
    /// beugt sich heraus und wedelt dich abfällig weg (beim Beenden)
    case flick

    /// so lange zeigt das Gesten-Fenster Rüdiger (sein eigenes Fenster zeigt so lange nur die Blase)
    var catTime: Double { CatSprites.shared.sequence(rawValue)?.catUntil ?? 0 }
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
        guard let sequence = CatSprites.shared.sequence(gesture.rawValue) else { return false }
        let side = location.cat.width * CGFloat(sequence.span)
        let frame = NSRect(x: location.cat.midX - side / 2, y: location.cat.midY - side / 2, width: side, height: side)
        // An der rechten Bildschirmkante gespiegelt – Rüdiger holt immer zur Bildschirmmitte hin aus
        let host = NSHostingView(rootView: CatGestureView(name: gesture.rawValue, start: Date(),
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
        DispatchQueue.main.asyncAfter(deadline: .now() + sequence.duration + 0.05, execute: work)
        return true
    }
}

struct CatGestureView: View {
    let name: String
    let start: Date
    var mirrored = false

    var body: some View {
        TimelineView(.animation) { timeline in
            if let image = CatSprites.shared.image(name, at: timeline.date.timeIntervalSince(start)) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
