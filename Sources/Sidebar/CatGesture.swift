import AppKit
import SwiftUI

// MARK: - Rüdigers Gesten: er beugt sich aus seinem Fenster und kratzt mit seiner Pfote
//
// Während der Geste zeichnet ein eigenes, durchsichtiges Fenster über der Sidebar den ganzen Rüdiger:
// der Körper bleibt im runden Fenster, Kopf, Ohren und Vorderbein ragen über den Rand hinaus (3D).
// Alles ist im selben 100er-Maßstab wie Rüdiger gezeichnet – die Pfote passt also zur Katze.

enum CatGesture {
    /// beugt sich vor und kratzt zweimal über den Bildschirm (Spuren verblassen)
    case scratch
    /// beugt sich vor und wedelt dich abfällig weg (beim Beenden)
    case flick

    var duration: Double {
        switch self {
        case .scratch: return 2.9
        case .flick: return 2.1
        }
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

    func perform(_ gesture: CatGesture, at location: CatLocation, dark: Bool, accent: Color, pose: CatPose) {
        let diameter = location.cat.width
        let side = diameter * 4.6
        let frame = NSRect(x: location.cat.midX - side / 2, y: location.cat.midY - side / 2, width: side, height: side)
        // Richtung: vom Bildschirmrand weg, schräg ins Bild (lokal, y nach unten)
        let s = CGFloat(0.5.squareRoot())
        let direction: CGVector
        switch location.edge {
        case .top, .left: direction = CGVector(dx: s, dy: s)
        case .bottom: direction = CGVector(dx: s, dy: -s)
        case .right: direction = CGVector(dx: -s, dy: s)
        }
        let view = CatGestureView(gesture: gesture, start: Date(), diameter: diameter, direction: direction,
                                  dark: dark, accent: accent, pose: pose)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + gesture.duration + (gesture == .scratch ? 2.6 : 0.05),
                                      execute: work)
    }
}

struct CatGestureView: View {
    let gesture: CatGesture
    let start: Date
    let diameter: CGFloat
    let direction: CGVector
    let dark: Bool
    let accent: Color
    let pose: CatPose

    var body: some View {
        // ohne Mindestabstand: zeichnet mit der Bildwiederholrate des Bildschirms (flüssig)
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                CatGesturePainter.draw(in: &context, size: size, gesture: gesture, t: t, diameter: diameter,
                                       direction: direction, dark: dark, accent: accent, pose: pose,
                                       clock: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .allowsHitTesting(false)
    }
}

enum CatGesturePainter {
    /// Zustand zu einem Zeitpunkt – alles in Rüdigers 100er-Einheiten
    struct Frame {
        /// wie weit er sich vorbeugt (0 … 1)
        var lean: Double
        /// Pfote: Abstand von der Schulter entlang der Richtung
        var reach: CGFloat
        /// seitlicher Versatz der Pfote
        var across: CGFloat
        var claws: CGFloat
        /// Neigung der Pfote (Grad)
        var tilt: Double
        var pressed: Bool
    }

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    private static func smooth(_ x: Double) -> Double { let v = clamp(x); return v * v * v * (v * (v * 6 - 15) + 10) }
    private static func easeOut(_ x: Double) -> Double { let v = clamp(x); return 1 - pow(1 - v, 3) }
    private static func easeOutBack(_ x: Double) -> Double {
        let v = clamp(x), c1 = 1.5, c3 = c1 + 1
        return 1 + c3 * pow(v - 1, 3) + c1 * pow(v - 1, 2)
    }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    // Maße in Rüdiger-Einheiten (Kopf ist 60 breit)
    static let paw: CGFloat = 12.5        // Pfotengröße
    static let far: CGFloat = 40          // so weit reicht der Arm
    static let pull: CGFloat = 15         // so weit zieht er die Krallen durch
    static let shift: CGFloat = 10        // Versatz für den zweiten Kratzer
    static let drags: [(start: Double, end: Double)] = [(0.95, 1.4), (1.62, 2.07)]

    static func frame(_ gesture: CatGesture, t: Double) -> Frame {
        switch gesture {
        case .scratch:
            // vorbeugen … halten … zurück
            let lean = t < 0.5 ? smooth(t / 0.5) : (t < 2.35 ? 1 : 1 - smooth((t - 2.35) / 0.5))
            switch t {
            case ..<0.3:
                return Frame(lean: lean, reach: 0, across: 0, claws: 0, tilt: 0, pressed: false)
            case ..<0.78:
                let p = (t - 0.3) / 0.48
                return Frame(lean: lean, reach: far * CGFloat(easeOutBack(p)), across: 0, claws: 0, tilt: -10 * (1 - p), pressed: false)
            case ..<0.95:
                let p = (t - 0.78) / 0.17
                return Frame(lean: lean, reach: far, across: 0, claws: CGFloat(easeOut(p)), tilt: 0, pressed: true)
            case ..<1.4:
                let p = smooth((t - 0.95) / 0.45)
                return Frame(lean: lean, reach: far - pull * CGFloat(p), across: 2 * CGFloat(sin(.pi * p)),
                             claws: 1, tilt: 6 * sin(.pi * p), pressed: true)
            case ..<1.62:
                let p = smooth((t - 1.4) / 0.22)
                return Frame(lean: lean, reach: lerp(far - pull, far, p), across: shift * CGFloat(p),
                             claws: 1 - 0.5 * CGFloat(sin(.pi * p)), tilt: -5 * sin(.pi * p), pressed: false)
            case ..<2.07:
                let p = smooth((t - 1.62) / 0.45)
                return Frame(lean: lean, reach: far - pull * CGFloat(p), across: shift + 2 * CGFloat(sin(.pi * p)),
                             claws: 1, tilt: 7 * sin(.pi * p), pressed: true)
            case ..<2.55:
                let p = smooth((t - 2.07) / 0.48)
                return Frame(lean: lean, reach: lerp(far - pull, 0, p), across: lerp(shift, 0, p),
                             claws: CGFloat(1 - easeOut(p * 3)), tilt: 0, pressed: false)
            default:
                return Frame(lean: lean, reach: 0, across: 0, claws: 0, tilt: 0, pressed: false)
            }
        case .flick:
            let lean = 0.75 * (t < 0.4 ? smooth(t / 0.4) : (t < 1.65 ? 1 : 1 - smooth((t - 1.65) / 0.45)))
            switch t {
            case ..<0.25:
                return Frame(lean: lean, reach: 0, across: 0, claws: 0, tilt: 0, pressed: false)
            case ..<0.6:
                let p = (t - 0.25) / 0.35
                return Frame(lean: lean, reach: far * 0.8 * CGFloat(easeOutBack(p)), across: 0, claws: 0, tilt: 0, pressed: false)
            case ..<1.35:
                // abfälliges Wegwedeln: zweimal hin und her, immer schwächer
                let p = (t - 0.6) / 0.75
                let wave = sin(p * .pi * 4) * (1 - p * 0.5)
                return Frame(lean: lean, reach: far * 0.8, across: 16 * CGFloat(wave), claws: 0, tilt: 28 * wave, pressed: false)
            case ..<1.75:
                let p = smooth((t - 1.35) / 0.4)
                return Frame(lean: lean, reach: lerp(far * 0.8, 0, p), across: 0, claws: 0, tilt: 0, pressed: false)
            default:
                return Frame(lean: lean, reach: 0, across: 0, claws: 0, tilt: 0, pressed: false)
            }
        }
    }

    /// Rüdiger-Einheiten → Fenster-Koordinaten, inkl. Vorbeugen (größer, leicht geneigt, Richtung Bildschirm)
    static func transform(size: CGSize, diameter: CGFloat, direction d: CGVector, lean: Double) -> CGAffineTransform {
        let unit = diameter / 100
        let l = CGFloat(lean)
        var m = CGAffineTransform(translationX: size.width / 2 - diameter / 2, y: size.height / 2 - diameter / 2)
        m = m.scaledBy(x: unit, y: unit)
        m = m.translatedBy(x: d.dx * 15 * l, y: d.dy * 15 * l)
        m = m.translatedBy(x: 50, y: 100)
        m = m.rotated(by: (d.dx >= 0 ? -1 : 1) * 0.1 * l)
        m = m.scaledBy(x: 1 + 0.42 * l, y: 1 + 0.42 * l)
        m = m.translatedBy(x: -50, y: -100)
        return m
    }

    // Zehen in Pfoten-Koordinaten (u = nach vorn, v = seitlich), in Pfotengrößen
    static let toes: [(u: CGFloat, v: CGFloat)] = [(0.52, -0.66), (0.80, -0.24), (0.80, 0.24), (0.52, 0.66)]

    /// Schulter, an der das Vorderbein ansetzt (auf der Seite zur Richtung)
    static func shoulder(_ d: CGVector) -> CGPoint { CGPoint(x: 50 + (d.dx >= 0 ? 16 : -16), y: 82) }

    /// Punkt an der Pfote (Rüdiger-Einheiten)
    static func pawPoint(_ f: Frame, _ d: CGVector, u: CGFloat, v: CGFloat, scale: CGFloat) -> CGPoint {
        let perp = CGVector(dx: -d.dy, dy: d.dx)
        let a = CGFloat(f.tilt * .pi / 180)
        let ru = (u * cos(a) - v * sin(a)) * scale
        let rv = (u * sin(a) + v * cos(a)) * scale
        let s = shoulder(d)
        let along = f.reach + ru, across = f.across + rv
        return CGPoint(x: s.x + d.dx * along + perp.dx * across, y: s.y + d.dy * along + perp.dy * across)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, gesture: CatGesture, t: Double,
                     diameter: CGFloat, direction d: CGVector, dark: Bool, accent: Color, pose: CatPose, clock: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let f = frame(gesture, t: t)
        let m = transform(size: size, diameter: diameter, direction: d, lean: f.lean)
        let unit = diameter / 100
        let perpScreen = CGVector(dx: -d.dy, dy: d.dx)

        // 1. Kratzspuren auf der „Scheibe“ – entstehen unter den Krallenspitzen
        if gesture == .scratch {
            let fade = t < 2.6 ? 1 : max(0, 1 - (t - 2.6) / 2.4)
            if fade > 0 {
                for (index, drag) in drags.enumerated() where t > drag.start {
                    let end = min(t, drag.end)
                    var times: [Double] = []
                    var time = drag.start
                    while time < end { times.append(time); time += 0.01 }
                    times.append(end)
                    guard times.count > 2 else { continue }
                    for (claw, toe) in toes.enumerated() {
                        let strength: CGFloat = claw == 0 || claw == 3 ? 0.7 : 1
                        let points: [CGPoint] = times.enumerated().map { i, time in
                            let fr = frame(.scratch, t: time)
                            let tip = pawPoint(fr, d, u: toe.u + 0.77, v: toe.v + 0.08, scale: paw * 1.06)
                                .applying(transform(size: size, diameter: diameter, direction: d, lean: fr.lean))
                            let jitter = noise(Double(i) * 0.41 + Double(claw) * 7.1 + Double(index) * 13.3) * 0.5
                            return CGPoint(x: tip.x + perpScreen.dx * jitter, y: tip.y + perpScreen.dy * jitter)
                        }
                        let total = Double(points.count - 1)
                        for i in 1..<points.count {
                            let q = Double(i) / max(total, 1)
                            let width = (0.7 + 2.4 * CGFloat(sin(.pi * min(q * 1.05, 1)))) * strength * max(unit, 0.8)
                            var groove = Path()
                            groove.move(to: points[i - 1])
                            groove.addLine(to: points[i])
                            context.stroke(groove, with: .color(.black.opacity(0.4 * fade)),
                                           style: StrokeStyle(lineWidth: width + 1, lineCap: .round))
                            var edge = Path()
                            edge.move(to: CGPoint(x: points[i - 1].x + perpScreen.dx * 0.7, y: points[i - 1].y + perpScreen.dy * 0.7))
                            edge.addLine(to: CGPoint(x: points[i].x + perpScreen.dx * 0.7, y: points[i].y + perpScreen.dy * 0.7))
                            context.stroke(edge, with: .color(.white.opacity(0.9 * fade)),
                                           style: StrokeStyle(lineWidth: max(0.5, width * 0.45), lineCap: .round))
                        }
                    }
                }
            }
        }

        // 2. Rüdiger im Fenster: Hintergrund fest, Körper beugt sich vor (im runden Fenster beschnitten)
        let window = Path(ellipseIn: CGRect(x: center.x - diameter / 2 + 1.5, y: center.y - diameter / 2 + 1.5,
                                            width: diameter - 3, height: diameter - 3))
        var inside = context
        inside.clip(to: window)
        var bg = inside
        bg.translateBy(x: center.x - diameter / 2, y: center.y - diameter / 2)
        bg.scaleBy(x: unit, y: unit)
        CatPainter.drawBackground(&bg, dark: dark, accent: accent)
        var body = inside
        body.concatenate(m)
        CatPainter.drawBust(&body, pose: pose, dark: dark, t: clock)

        // 3. Kopf und Ohren ragen über den Fensterrand hinaus (3D)
        var head = context
        head.concatenate(m)
        head.clip(to: Path(CGRect(x: -100, y: -100, width: 300, height: 171)))
        head.addFilter(.shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1.5))
        CatPainter.drawBust(&head, pose: pose, dark: dark, t: clock)

        // 4. Vorderbein mit Pfote – über allem
        guard f.reach > 1 else { return }
        var arm = context
        arm.concatenate(m)
        arm.addFilter(.shadow(color: .black.opacity(0.3), radius: 4, x: 1.5, y: 3))
        drawLeg(&arm, f, d)
    }

    /// Vorderbein, Pfote, Ballen und Krallen – in Rüdiger-Einheiten
    private static func drawLeg(_ c: inout GraphicsContext, _ f: Frame, _ d: CGVector) {
        let fur = CatPainter.fur
        let scale = paw * (f.pressed ? 1.06 : 1)
        let base = shoulder(d)
        let wrist = pawPoint(f, d, u: -0.45, v: 0, scale: scale)
        let vec = CGVector(dx: wrist.x - base.x, dy: wrist.y - base.y)
        let length = max(sqrt(vec.dx * vec.dx + vec.dy * vec.dy), 0.1)
        let ld = CGVector(dx: vec.dx / length, dy: vec.dy / length)
        let lp = CGVector(dx: -ld.dy, dy: ld.dx)

        // Bein: an der Schulter kräftig, zum Handgelenk schmaler, weiche Fellkante
        let w0: CGFloat = 10, w1: CGFloat = scale * 0.7
        var left: [CGPoint] = [], right: [CGPoint] = []
        let steps = 24
        for i in 0...steps {
            let q = CGFloat(i) / CGFloat(steps)
            let w = w0 + (w1 - w0) * q
            let bulge = sin(q * .pi) * 1.4
            let fluffL = CGFloat(sin(Double(q) * .pi * 5 + 1.2)) * 0.45
            let fluffR = CGFloat(sin(Double(q) * .pi * 4 + 0.3)) * 0.45
            let p = CGPoint(x: base.x + ld.dx * length * q, y: base.y + ld.dy * length * q)
            left.append(CGPoint(x: p.x + lp.dx * (w + bulge + fluffL), y: p.y + lp.dy * (w + bulge + fluffL)))
            right.append(CGPoint(x: p.x - lp.dx * (w + bulge * 0.5 + fluffR), y: p.y - lp.dy * (w + bulge * 0.5 + fluffR)))
        }
        var leg = Path()
        leg.addLines(left + right.reversed())
        leg.closeSubpath()
        c.fill(leg, with: .linearGradient(Gradient(colors: [CatPainter.furLight, fur, Color(white: 0.04)]),
                                          startPoint: CGPoint(x: base.x + lp.dx * w0, y: base.y + lp.dy * w0),
                                          endPoint: CGPoint(x: base.x - lp.dx * w0, y: base.y - lp.dy * w0)))

        // Pfote (Fäustling) mit vier Zehen
        var palm = Path()
        palm.addLines((0..<36).map { i -> CGPoint in
            let a = Double(i) / 36 * 2 * .pi
            return pawPoint(f, d, u: CGFloat(cos(a)) * 0.7, v: CGFloat(sin(a)) * 0.8, scale: scale)
        })
        palm.closeSubpath()
        c.fill(palm, with: .color(fur))
        for toe in toes {
            let p = pawPoint(f, d, u: toe.u, v: toe.v, scale: scale)
            c.fill(Path(ellipseIn: CGRect(x: p.x - scale * 0.31, y: p.y - scale * 0.31, width: scale * 0.62, height: scale * 0.62)),
                   with: .color(fur))
        }

        // rosa Ballen – zur Scheibe gedrückt
        let pad = Gradient(colors: [Color(red: 0.99, green: 0.74, blue: 0.80), Color(red: 0.86, green: 0.5, blue: 0.6)])
        let main = pawPoint(f, d, u: -0.1, v: 0, scale: scale)
        var mainPad = Path(ellipseIn: CGRect(x: main.x - scale * 0.36, y: main.y - scale * 0.33, width: scale * 0.72, height: scale * 0.66))
        for side in [-1.0, 1.0] {
            let lobe = pawPoint(f, d, u: -0.3, v: CGFloat(side) * 0.2, scale: scale)
            mainPad.addEllipse(in: CGRect(x: lobe.x - scale * 0.19, y: lobe.y - scale * 0.19, width: scale * 0.38, height: scale * 0.38))
        }
        c.fill(mainPad, with: .radialGradient(pad, center: main, startRadius: 0, endRadius: scale * 0.5))
        for toe in toes {
            let p = pawPoint(f, d, u: toe.u + 0.04, v: toe.v, scale: scale)
            c.fill(Path(ellipseIn: CGRect(x: p.x - scale * 0.16, y: p.y - scale * 0.14, width: scale * 0.32, height: scale * 0.28)),
                   with: .radialGradient(pad, center: p, startRadius: 0, endRadius: scale * 0.2))
            c.fill(Path(ellipseIn: CGRect(x: p.x - scale * 0.07, y: p.y - scale * 0.08, width: scale * 0.07, height: scale * 0.05)),
                   with: .color(.white.opacity(0.6)))
        }

        // Krallen: gebogen, fahren aus den Zehen
        guard f.claws > 0.02 else { return }
        for toe in toes {
            let length = 0.55 * f.claws
            let root1 = pawPoint(f, d, u: toe.u + 0.22, v: toe.v - 0.07, scale: scale)
            let root2 = pawPoint(f, d, u: toe.u + 0.22, v: toe.v + 0.07, scale: scale)
            let tip = pawPoint(f, d, u: toe.u + 0.22 + length, v: toe.v + length * 0.15, scale: scale)
            let c1 = pawPoint(f, d, u: toe.u + 0.22 + length * 0.6, v: toe.v - length * 0.1, scale: scale)
            let c2 = pawPoint(f, d, u: toe.u + 0.22 + length * 0.45, v: toe.v + length * 0.12, scale: scale)
            var claw = Path()
            claw.move(to: root1)
            claw.addQuadCurve(to: tip, control: c1)
            claw.addQuadCurve(to: root2, control: c2)
            claw.closeSubpath()
            c.fill(claw, with: .linearGradient(Gradient(colors: [Color(white: 0.98), Color(white: 0.8)]),
                                               startPoint: root1, endPoint: tip))
        }
    }

    private static func noise(_ x: Double) -> CGFloat {
        let v = sin(x * 12.9898) * 43758.5453
        return CGFloat(v - floor(v)) * 2 - 1
    }
}
