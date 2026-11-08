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
        case .scratch: return 2.3
        case .flick: return 1.7
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
        let side = diameter * 4
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
        DispatchQueue.main.asyncAfter(deadline: .now() + gesture.duration + (gesture == .scratch ? 2.6 : 0.1),
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

/// Zeichnet eine echte Katzenpfote, die sich von innen gegen die Scheibe drückt und kratzt.
enum CatGesturePainter {
    /// Zustand der Pfote zu einem Zeitpunkt
    struct PawState {
        /// Abstand der Pfotenmitte von Rüdigers Mitte (entlang der Richtung)
        var along: CGFloat
        /// seitlicher Versatz
        var across: CGFloat
        /// Größe (näher an der Scheibe = größer)
        var scale: CGFloat
        /// Krallen 0 … 1
        var claws: CGFloat
        /// Neigung in Grad
        var tilt: Double
        /// Deckkraft
        var alpha: Double
        /// gegen die Scheibe gedrückt (für den Abdruck)
        var pressed: Bool
    }

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    private static func easeOut(_ x: Double) -> Double { let v = clamp(x); return 1 - pow(1 - v, 3) }
    private static func easeInOut(_ x: Double) -> Double { let v = clamp(x); return v * v * (3 - 2 * v) }
    private static func easeOutBack(_ x: Double) -> Double {
        let v = clamp(x), c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(v - 1, 3) + c1 * pow(v - 1, 2)
    }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    /// Zwei Kratzer: ausfahren, andrücken, Krallen raus, durchziehen, absetzen, nochmal, zurück.
    static let drags: [(start: Double, end: Double)] = [(0.6, 1.05), (1.3, 1.75)]

    static func state(_ gesture: CatGesture, t: Double, r: CGFloat) -> PawState {
        let rim = r * 0.75
        let far = r * 2.15
        let pull = r * 0.75
        let shift = r * 0.34
        switch gesture {
        case .scratch:
            switch t {
            case ..<0.45:
                let p = t / 0.45
                return PawState(along: lerp(rim, far, easeOutBack(p)), across: 0, scale: lerp(0.62, 1, easeOut(p)),
                                claws: 0, tilt: -8 * (1 - p), alpha: clamp(p * 4), pressed: false)
            case ..<0.6:
                let p = (t - 0.45) / 0.15
                return PawState(along: far, across: 0, scale: 1 + 0.06 * CGFloat(sin(.pi * p)),
                                claws: CGFloat(easeOut(p)), tilt: 0, alpha: 1, pressed: true)
            case ..<1.05:
                let p = (t - 0.6) / 0.45
                return PawState(along: far - pull * CGFloat(easeInOut(p)), across: r * 0.08 * CGFloat(sin(.pi * p)),
                                scale: 1.04, claws: 1, tilt: 5 * sin(.pi * p), alpha: 1, pressed: true)
            case ..<1.3:
                let p = (t - 1.05) / 0.25
                return PawState(along: lerp(far - pull, far, easeInOut(p)), across: shift * CGFloat(easeInOut(p)),
                                scale: 1 - 0.07 * CGFloat(sin(.pi * p)), claws: 1 - 0.5 * CGFloat(sin(.pi * p)),
                                tilt: -4 * sin(.pi * p), alpha: 1, pressed: false)
            case ..<1.75:
                let p = (t - 1.3) / 0.45
                return PawState(along: far - pull * CGFloat(easeInOut(p)), across: shift + r * 0.06 * CGFloat(sin(.pi * p)),
                                scale: 1.04, claws: 1, tilt: 6 * sin(.pi * p), alpha: 1, pressed: true)
            case ..<2.3:
                let p = (t - 1.75) / 0.55
                return PawState(along: lerp(far - pull, rim, easeInOut(p)), across: lerp(shift, 0, easeInOut(p)),
                                scale: lerp(1, 0.62, easeInOut(p)), claws: CGFloat(1 - easeOut(p * 2.5)),
                                tilt: -6 * p, alpha: 1 - clamp((p - 0.75) / 0.25), pressed: false)
            default:
                return PawState(along: rim, across: 0, scale: 0.6, claws: 0, tilt: 0, alpha: 0, pressed: false)
            }
        case .flick:
            switch t {
            case ..<0.4:
                let p = t / 0.4
                return PawState(along: lerp(rim, far * 0.9, easeOutBack(p)), across: 0, scale: lerp(0.62, 1, easeOut(p)),
                                claws: 0, tilt: 0, alpha: clamp(p * 4), pressed: false)
            case ..<1.15:
                // abfälliges Wegwedeln: zweimal hin und her, immer schwächer
                let p = (t - 0.4) / 0.75
                let wave = sin(p * .pi * 4) * (1 - p * 0.5)
                return PawState(along: far * 0.9, across: r * 0.45 * CGFloat(wave), scale: 1, claws: 0,
                                tilt: 22 * wave, alpha: 1, pressed: false)
            case ..<1.7:
                let p = (t - 1.15) / 0.55
                return PawState(along: lerp(far * 0.9, rim, easeInOut(p)), across: 0, scale: lerp(1, 0.62, easeInOut(p)),
                                claws: 0, tilt: 0, alpha: 1 - clamp((p - 0.75) / 0.25), pressed: false)
            default:
                return PawState(along: rim, across: 0, scale: 0.6, claws: 0, tilt: 0, alpha: 0, pressed: false)
            }
        }
    }

    // Lage der Zehen in Pfoten-Koordinaten (u = nach vorn, v = seitlich), in Einheiten der Pfotengröße
    static let toes: [(u: CGFloat, v: CGFloat)] = [(0.52, -0.66), (0.80, -0.24), (0.80, 0.24), (0.52, 0.66)]

    /// Kleines, festes Rauschen (für Fell und raue Kratzer)
    private static func noise(_ x: Double) -> CGFloat {
        let v = sin(x * 12.9898) * 43758.5453
        return CGFloat(v - floor(v)) * 2 - 1
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, gesture: CatGesture, t: Double,
                     radius r: CGFloat, direction d: CGVector) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let perp = CGVector(dx: -d.dy, dy: d.dx)
        let pawSize = r * 0.4

        // Weltpunkt aus Pfotenlage + lokaler Verschiebung (gedreht um die Neigung)
        func world(_ s: PawState, _ u: CGFloat, _ v: CGFloat) -> CGPoint {
            let a = CGFloat(s.tilt * .pi / 180)
            let ru = u * cos(a) - v * sin(a)
            let rv = u * sin(a) + v * cos(a)
            let along = s.along + ru, across = s.across + rv
            return CGPoint(x: center.x + d.dx * along + perp.dx * across,
                           y: center.y + d.dy * along + perp.dy * across)
        }

        // Kratzspuren: entstehen genau unter den Krallenspitzen und verblassen danach
        if gesture == .scratch {
            let fade = t < 2.3 ? 1 : max(0, 1 - (t - 2.3) / 2.4)
            if fade > 0 {
                for (index, drag) in drags.enumerated() where t > drag.start {
                    let end = min(t, drag.end)
                    var times: [Double] = []
                    var time = drag.start
                    while time <= end { times.append(time); time += 0.012 }
                    times.append(end)
                    guard times.count > 2 else { continue }
                    for (claw, toe) in toes.enumerated() {
                        // die äußeren Krallen hinterlassen kürzere, schwächere Spuren
                        let strength: CGFloat = claw == 0 || claw == 3 ? 0.65 : 1
                        var points: [CGPoint] = []
                        for (i, time) in times.enumerated() {
                            let s = state(.scratch, t: time, r: r)
                            let p = s.scale * pawSize
                            let tip = world(s, toe.u * p + 0.62 * p, toe.v * p)
                            let jitter = noise(Double(i) * 0.37 + Double(claw) * 7.1 + Double(index) * 13.3) * 0.7
                            points.append(CGPoint(x: tip.x + perp.dx * jitter, y: tip.y + perp.dy * jitter))
                        }
                        let count = points.count
                        let total = Double(times.count - 1)
                        for i in 1..<count {
                            let q = Double(i) / max(total, 1)
                            // dünn anfangen, in der Mitte am tiefsten, dünn ausfransen
                            let width = (0.8 + 2.6 * CGFloat(sin(.pi * min(q * 1.05, 1)))) * strength
                            var seg = Path()
                            seg.move(to: points[i - 1])
                            seg.addLine(to: points[i])
                            context.stroke(seg, with: .color(.black.opacity(0.42 * fade)),
                                           style: StrokeStyle(lineWidth: width + 1.2, lineCap: .round))
                            var light = Path()
                            light.move(to: CGPoint(x: points[i - 1].x + perp.dx * 0.8, y: points[i - 1].y + perp.dy * 0.8))
                            light.addLine(to: CGPoint(x: points[i].x + perp.dx * 0.8, y: points[i].y + perp.dy * 0.8))
                            context.stroke(light, with: .color(.white.opacity(0.92 * fade)),
                                           style: StrokeStyle(lineWidth: max(0.6, width * 0.5), lineCap: .round))
                        }
                        // kleine Splitter am Anfang der Spur
                        if let first = points.first {
                            for k in 0..<3 {
                                let n1 = noise(Double(claw * 5 + k) + Double(index) * 3.3)
                                let n2 = noise(Double(claw * 7 + k) * 1.7 + Double(index))
                                let dot = CGPoint(x: first.x + n1 * 4 + d.dx * 2, y: first.y + n2 * 4 + d.dy * 2)
                                context.fill(Path(ellipseIn: CGRect(x: dot.x - 0.7, y: dot.y - 0.7, width: 1.4, height: 1.4)),
                                             with: .color(.white.opacity(0.8 * fade)))
                            }
                        }
                    }
                }
            }
        }

        let s = state(gesture, t: t, r: r)
        guard s.alpha > 0.01 else { return }
        let p = s.scale * pawSize

        // Abdruck auf der Scheibe (leicht beschlagen), solange die Pfote drückt
        if s.pressed {
            var fog = context
            fog.addFilter(.blur(radius: 4))
            let pad = world(s, 0, 0)
            fog.fill(Path(ellipseIn: CGRect(x: pad.x - p * 1.05, y: pad.y - p * 1.05, width: p * 2.1, height: p * 2.1)),
                     with: .color(.white.opacity(0.22)))
        }

        context.drawLayer { layer in
            layer.opacity = s.alpha
            layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 5, x: 2, y: 4))

            // Vorderbein: vom Fensterrand zur Pfote, sich verjüngend, mit Fellkante
            let base = CGPoint(x: center.x + d.dx * r * 0.82, y: center.y + d.dy * r * 0.82)
            let wrist = world(s, -0.5 * p, 0)
            let legDir = CGVector(dx: wrist.x - base.x, dy: wrist.y - base.y)
            let legLength = max(sqrt(legDir.dx * legDir.dx + legDir.dy * legDir.dy), 1)
            let ld = CGVector(dx: legDir.dx / legLength, dy: legDir.dy / legLength)
            let lp = CGVector(dx: -ld.dy, dy: ld.dx)
            let w0 = r * 0.30, w1 = p * 0.62
            var leg = Path()
            var left: [CGPoint] = [], right: [CGPoint] = []
            let steps = 9
            for i in 0...steps {
                let q = CGFloat(i) / CGFloat(steps)
                let w = w0 + (w1 - w0) * q
                let bulge = sin(q * .pi) * w * 0.12        // leicht gewölbter Muskel
                let fur = noise(Double(i) * 3.1) * 1.1
                let fur2 = noise(Double(i) * 5.7 + 2) * 1.1
                let c = CGPoint(x: base.x + ld.dx * legLength * q, y: base.y + ld.dy * legLength * q)
                left.append(CGPoint(x: c.x + lp.dx * (w + bulge + fur), y: c.y + lp.dy * (w + bulge + fur)))
                right.append(CGPoint(x: c.x - lp.dx * (w + bulge * 0.6 + fur2), y: c.y - lp.dy * (w + bulge * 0.6 + fur2)))
            }
            leg.addLines(left + right.reversed())
            leg.closeSubpath()
            let shadeA = CGPoint(x: base.x + lp.dx * w0, y: base.y + lp.dy * w0)
            let shadeB = CGPoint(x: base.x - lp.dx * w0, y: base.y - lp.dy * w0)
            layer.fill(leg, with: .linearGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.06), Color(white: 0.03)]),
                                                  startPoint: shadeA, endPoint: shadeB))
            // Glanzlinie im Fell
            var sheen = Path()
            sheen.move(to: CGPoint(x: base.x + lp.dx * w0 * 0.55, y: base.y + lp.dy * w0 * 0.55))
            sheen.addLine(to: CGPoint(x: wrist.x + lp.dx * w1 * 0.55, y: wrist.y + lp.dy * w1 * 0.55))
            layer.stroke(sheen, with: .color(.white.opacity(0.13)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Pfote: runde „Fäustling“-Form mit Fellrand
            var palm = Path()
            let rimSteps = 30
            let palmPoints = (0..<rimSteps).map { i -> CGPoint in
                let a = Double(i) / Double(rimSteps) * 2 * .pi
                let fur = 1 + noise(Double(i) * 2.3 + 1) * 0.05
                return world(s, CGFloat(cos(a)) * p * 0.68 * fur, CGFloat(sin(a)) * p * 0.78 * fur)
            }
            palm.addLines(palmPoints)
            palm.closeSubpath()
            layer.fill(palm, with: .color(Color(white: 0.07)))
            for toe in toes {
                let c = world(s, toe.u * p, toe.v * p)
                layer.fill(Path(ellipseIn: CGRect(x: c.x - p * 0.3, y: c.y - p * 0.3, width: p * 0.6, height: p * 0.6)),
                           with: .color(Color(white: 0.07)))
            }

            // Ballen (rosa, leicht glänzend – gegen die Scheibe gedrückt etwas größer)
            let squash: CGFloat = s.pressed ? 1.08 : 1
            let padColor = Gradient(colors: [Color(red: 0.98, green: 0.72, blue: 0.78), Color(red: 0.86, green: 0.50, blue: 0.60)])
            let mainCenter = world(s, -0.12 * p, 0)
            var main = Path()
            main.addEllipse(in: CGRect(x: mainCenter.x - p * 0.36 * squash, y: mainCenter.y - p * 0.36 * squash,
                                       width: p * 0.72 * squash, height: p * 0.72 * squash))
            for side in [-1.0, 1.0] {
                let lobe = world(s, -0.28 * p, CGFloat(side) * 0.22 * p)
                main.addEllipse(in: CGRect(x: lobe.x - p * 0.2 * squash, y: lobe.y - p * 0.2 * squash,
                                           width: p * 0.4 * squash, height: p * 0.4 * squash))
            }
            layer.fill(main, with: .radialGradient(padColor, center: mainCenter, startRadius: 0, endRadius: p * 0.5))
            layer.fill(Path(ellipseIn: CGRect(x: mainCenter.x - p * 0.12, y: mainCenter.y - p * 0.16, width: p * 0.14, height: p * 0.09)),
                       with: .color(.white.opacity(0.55)))
            for toe in toes {
                let c = world(s, toe.u * p + 0.04 * p, toe.v * p)
                let bean = Path(ellipseIn: CGRect(x: c.x - p * 0.17 * squash, y: c.y - p * 0.15 * squash,
                                                  width: p * 0.34 * squash, height: p * 0.30 * squash))
                layer.fill(bean, with: .radialGradient(padColor, center: c, startRadius: 0, endRadius: p * 0.2))
                layer.fill(Path(ellipseIn: CGRect(x: c.x - p * 0.06, y: c.y - p * 0.08, width: p * 0.07, height: p * 0.05)),
                           with: .color(.white.opacity(0.6)))
            }

            // Krallen: gebogen, halb durchsichtig, fahren aus den Zehen
            if s.claws > 0.02 {
                for toe in toes {
                    let length = p * 0.55 * s.claws
                    let rootU = toe.u * p + 0.22 * p
                    let root1 = world(s, rootU, toe.v * p - p * 0.06)
                    let root2 = world(s, rootU, toe.v * p + p * 0.06)
                    let tip = world(s, rootU + length, toe.v * p + length * 0.18)
                    let ctrl = world(s, rootU + length * 0.6, toe.v * p - length * 0.12)
                    var claw = Path()
                    claw.move(to: root1)
                    claw.addQuadCurve(to: tip, control: ctrl)
                    claw.addQuadCurve(to: root2, control: world(s, rootU + length * 0.45, toe.v * p + length * 0.1))
                    claw.closeSubpath()
                    layer.fill(claw, with: .linearGradient(Gradient(colors: [Color(white: 0.97), Color(white: 0.78)]),
                                                           startPoint: root1, endPoint: tip))
                    layer.stroke(claw, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
                }
            }
        }
    }
}
