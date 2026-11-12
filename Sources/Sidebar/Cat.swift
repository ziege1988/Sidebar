import AppKit
import Combine
import CoreGraphics
import SwiftUI

// MARK: - Rüdiger, die Bürokatze
//
// Sitzt in einem runden Fenster in der Mulde des Bogens zwischen Uhr und Leiste. Schläft, wenn nichts los ist,
// will ab und zu gestreichelt werden, wird ungemütlich, wenn man sie ignoriert, und kommentiert
// neue Nachrichten. Alles lokal – keine Internetverbindung, keine KI.

// MARK: Lage

/// Wo das Katzenfenster sitzt. Gerechnet wie der Umriss: c = quer zur Kante, a = entlang der Kante.
struct CatGeometry {
    let centerCross: CGFloat
    let centerAlong: CGFloat
    let diameter: CGFloat

    /// Rüdiger sitzt frei in der Mulde des Bogens zwischen Uhr und Leiste.
    static func make(_ s: SidebarSettings, clockOn: Bool) -> CatGeometry? {
        guard s.catEnabled, clockOn else { return nil }
        let size = ClockLayout.panelSize(s)
        guard abs(size.width - size.height) < 1,
              let sweep = ClockSweep.make(clock: size.width, bar: CGFloat(s.collapsedThickness)) else { return nil }
        // Größe folgt dem Bogen; ist die Mulde zu klein, ist dort kein Platz für ihn
        let diameter = min(96, 0.8 * sweep.radius)
        guard diameter >= 56 else { return nil }
        // Mitte: vom Mittelpunkt des Bogens zur Mitte der Mulde hin (zwischen Leiste und Uhr)
        var bx = -1 - sweep.direction.x, by = -sweep.direction.y
        let length = max((bx * bx + by * by).squareRoot(), 0.001)
        bx /= length
        by /= length
        let distance = sweep.radius - diameter / 2 - 7
        return CatGeometry(centerCross: sweep.center.x + bx * distance,
                           centerAlong: sweep.center.y + by * distance,
                           diameter: diameter)
    }

    /// Mittelpunkt im Fenster der Leiste (Ursprung oben links)
    func point(in size: CGSize, edge: ScreenEdge) -> CGPoint {
        switch edge {
        case .left: return CGPoint(x: centerCross, y: centerAlong)
        case .right: return CGPoint(x: size.width - centerCross, y: centerAlong)
        case .top: return CGPoint(x: centerAlong, y: centerCross)
        case .bottom: return CGPoint(x: centerAlong, y: size.height - centerCross)
        }
    }
}

/// Lage auf dem Bildschirm (für die Sprechblase)
struct CatLocation {
    let cat: NSRect
    let strip: NSRect
    let edge: ScreenEdge
    let visible: NSRect
    /// Rüdiger schwebt frei (Sprechblase dorthin, wo am meisten Platz ist)
    var floating = false
}

enum CatPainter {
    static let fur = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let furLight = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let innerEar = Color(red: 0.86, green: 0.55, blue: 0.62)
    static let nose = Color(red: 0.95, green: 0.62, blue: 0.70)
    static let blush = Color(red: 0.98, green: 0.62, blue: 0.70)
    static let iris = Color(red: 0.93, green: 0.84, blue: 0.36)
    static let irisAngry = Color(red: 0.93, green: 0.66, blue: 0.22)

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
    }

    /// Hintergrund: weiches, helles Rund (dunkel: Graphit) – im 100er-Feld
    static func drawBackground(_ context: inout GraphicsContext, dark: Bool, accent: Color) {
        let bg = Path(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 100))
        context.fill(bg, with: .radialGradient(
            Gradient(colors: dark
                     ? [Color(red: 0.31, green: 0.33, blue: 0.31), Color(red: 0.17, green: 0.18, blue: 0.19)]
                     : [Color(red: 0.97, green: 0.96, blue: 0.92), accent.opacity(0.45)]),
            center: CGPoint(x: 50, y: 38), startRadius: 4, endRadius: 70))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, pose: CatPose, dark: Bool,
                     accent: Color, time t: Double) {
        let scale = min(size.width, size.height) / 100
        context.scaleBy(x: scale, y: scale)

        drawBackground(&context, dark: dark, accent: accent)

        switch pose {
        case .absent:
            break
        case .sleep:
            drawSleeping(&context, dark: dark, t: t)
        case .walk(let x, let right):
            drawWalking(&context, x: x, facingRight: right, dark: dark, t: t)
        default:
            drawBust(&context, pose: pose, dark: dark, t: t)
        }
    }

    // Ganzer Körper von der Seite, läuft (Auftritt beim Start)
    private static func drawWalking(_ context: inout GraphicsContext, x: CGFloat, facingRight: Bool,
                                    dark: Bool, t: Double) {
        var c = context
        if !facingRight {
            c.translateBy(x: x, y: 0)
            c.scaleBy(x: -1, y: 1)
            c.translateBy(x: -x, y: 0)
        }
        let bob = CGFloat(abs(sin(t * 12))) * 1.4
        // Schatten
        context.fill(ellipse(x, 84, 24, 3.5), with: .color(.black.opacity(dark ? 0.3 : 0.12)))
        c.translateBy(x: 0, y: -bob)
        // Schwanz
        var tail = Path()
        tail.move(to: CGPoint(x: x - 18, y: 64))
        tail.addCurve(to: CGPoint(x: x - 30, y: 40), control1: CGPoint(x: x - 32, y: 62),
                      control2: CGPoint(x: x - 36, y: 48 + CGFloat(sin(t * 6)) * 3))
        c.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        // Beine (schwingen abwechselnd)
        for (i, lx) in [x - 13, x - 7, x + 8, x + 14].enumerated() {
            let swing = CGFloat(sin(t * 12 + (i % 2 == 0 ? 0 : .pi))) * 3.2
            var leg = Path()
            leg.move(to: CGPoint(x: lx, y: 68))
            leg.addLine(to: CGPoint(x: lx + swing, y: 82 + bob))
            c.stroke(leg, with: .color(i < 2 ? furLight : fur), style: StrokeStyle(lineWidth: 4.6, lineCap: .round))
        }
        // Körper
        c.fill(ellipse(x, 65, 21, 11), with: .color(fur))
        c.fill(ellipse(x + 2, 60, 13, 4), with: .color(furLight))
        // Kopf
        var earBack = Path()
        earBack.move(to: CGPoint(x: x + 13, y: 50))
        earBack.addQuadCurve(to: CGPoint(x: x + 14, y: 37), control: CGPoint(x: x + 11, y: 41))
        earBack.addQuadCurve(to: CGPoint(x: x + 21, y: 46), control: CGPoint(x: x + 19, y: 40))
        var earFront = Path()
        earFront.move(to: CGPoint(x: x + 22, y: 46))
        earFront.addQuadCurve(to: CGPoint(x: x + 28, y: 36), control: CGPoint(x: x + 24, y: 38))
        earFront.addQuadCurve(to: CGPoint(x: x + 30, y: 50), control: CGPoint(x: x + 31, y: 42))
        c.fill(earBack, with: .color(fur))
        c.fill(earFront, with: .color(fur))
        c.fill(ellipse(x + 27, 43, 1.6, 3), with: .color(innerEar.opacity(0.75)))
        c.fill(ellipse(x + 22, 55, 12, 11), with: .color(fur))
        // Auge, Wange, Nase
        c.fill(ellipse(x + 26, 54, 3.2, 3.6), with: .color(iris))
        c.fill(ellipse(x + 26.8, 54.3, 1.3, 2.8), with: .color(.black))
        c.fill(ellipse(x + 27.4, 52.6, 0.9, 0.9), with: .color(.white.opacity(0.9)))
        c.fill(ellipse(x + 27, 59.5, 2.6, 1.5), with: .color(blush.opacity(0.4)))
        c.fill(ellipse(x + 33.2, 57.6, 1.3, 1), with: .color(nose))
        var whisker = Path()
        whisker.move(to: CGPoint(x: x + 31, y: 59)); whisker.addLine(to: CGPoint(x: x + 40, y: 57.5))
        whisker.move(to: CGPoint(x: x + 31, y: 60.5)); whisker.addLine(to: CGPoint(x: x + 40, y: 61.5))
        c.stroke(whisker, with: .color(Color(white: 0.6).opacity(0.75)), lineWidth: 0.6)
    }

    // Ganzer Körper, eingerollt
    private static func drawSleeping(_ context: inout GraphicsContext, dark: Bool, t: Double) {
        let breath = 1 + 0.025 * sin(t * 1.6)
        // Schatten
        context.fill(ellipse(52, 82, 34, 5), with: .color(.black.opacity(dark ? 0.35 : 0.12)))
        var body = context
        body.translateBy(x: 54, y: 70)
        body.scaleBy(x: 1, y: breath)
        body.translateBy(x: -54, y: -70)
        // Körper
        body.fill(ellipse(56, 66, 30, 16), with: .color(fur))
        body.fill(ellipse(60, 60, 18, 6), with: .color(furLight))
        // Schwanz um die Pfoten
        var tail = Path()
        tail.move(to: CGPoint(x: 84, y: 70))
        tail.addCurve(to: CGPoint(x: 40, y: 80), control1: CGPoint(x: 92, y: 84), control2: CGPoint(x: 62, y: 86))
        body.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        // Pfoten
        body.fill(ellipse(30, 75, 7, 4), with: .color(fur))
        // Kopf
        var earL = Path()
        earL.move(to: CGPoint(x: 20, y: 52))
        earL.addQuadCurve(to: CGPoint(x: 21, y: 35), control: CGPoint(x: 15, y: 40))
        earL.addQuadCurve(to: CGPoint(x: 32, y: 45), control: CGPoint(x: 28, y: 38))
        var earR = Path()
        earR.move(to: CGPoint(x: 38, y: 44))
        earR.addQuadCurve(to: CGPoint(x: 48, y: 36), control: CGPoint(x: 42, y: 36))
        earR.addQuadCurve(to: CGPoint(x: 47, y: 52), control: CGPoint(x: 51, y: 44))
        body.fill(earL, with: .color(fur))
        body.fill(earR, with: .color(fur))
        body.fill(ellipse(24, 43, 2.5, 3.5), with: .color(innerEar.opacity(0.7)))
        body.fill(ellipse(45, 42, 2.5, 3.5), with: .color(innerEar.opacity(0.7)))
        body.fill(ellipse(34, 59, 16, 14), with: .color(fur))
        // geschlossene Augen
        let lid = Color(red: 0.55, green: 0.58, blue: 0.52)
        for x in [26.0, 37.0] {
            var eye = Path()
            eye.move(to: CGPoint(x: x, y: 59))
            eye.addQuadCurve(to: CGPoint(x: x + 6, y: 59), control: CGPoint(x: x + 3, y: 61.8))
            body.stroke(eye, with: .color(lid), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        body.fill(ellipse(34.5, 64, 1.6, 1.1), with: .color(nose))
        body.fill(ellipse(25, 64, 3, 1.6), with: .color(blush.opacity(0.35)))
        body.fill(ellipse(44, 64, 3, 1.6), with: .color(blush.opacity(0.35)))

        // Zzz steigen auf und verblassen
        for i in 0..<3 {
            let phase = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let x = 62 + phase * 18
            let y = 40 - phase * 24
            let size = 7 + phase * 7
            let text = Text("Z").font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.36, green: 0.48, blue: 0.34).opacity(dark ? 0.9 * (1 - phase) + 0.1 : 1 - phase))
            context.draw(text, at: CGPoint(x: x, y: y))
        }
    }

    // Oberkörper mit Gesicht
    static func drawBust(_ context: inout GraphicsContext, pose: CatPose, dark: Bool, t: Double) {
        let breath = 1 + 0.018 * sin(t * 2.2)
        let angry = pose == .angry
        var c = context
        c.translateBy(x: 50, y: 100)
        c.scaleBy(x: 1, y: breath)
        c.translateBy(x: -50, y: -100)

        // Körper
        var body = Path()
        body.move(to: CGPoint(x: 12, y: 104))
        body.addCurve(to: CGPoint(x: 50, y: 70), control1: CGPoint(x: 14, y: 80), control2: CGPoint(x: 30, y: 70))
        body.addCurve(to: CGPoint(x: 88, y: 104), control1: CGPoint(x: 70, y: 70), control2: CGPoint(x: 86, y: 80))
        body.closeSubpath()
        c.fill(body, with: .color(fur))

        // Ohren (zucken ab und zu, angelegt wenn wütend)
        let twitch = (t.truncatingRemainder(dividingBy: 6.3) < 0.25) ? sin(t * 40) * 6 : 0
        drawEar(&c, left: true, angle: angry ? -28 : twitch)
        drawEar(&c, left: false, angle: angry ? 28 : 0)

        // Kopf
        c.fill(ellipse(50, 52, 30, 26), with: .color(fur))
        c.fill(ellipse(50, 41, 17, 7), with: .color(furLight))

        // Augen
        let blink = (t + 1.3).truncatingRemainder(dividingBy: 4.7) < 0.14
        if pose == .purr || blink {
            let color = pose == .purr ? iris : Color(red: 0.55, green: 0.58, blue: 0.52)
            for x in [32.0, 54.0] {
                var eye = Path()
                if pose == .purr {
                    eye.move(to: CGPoint(x: x, y: 55))
                    eye.addQuadCurve(to: CGPoint(x: x + 14, y: 55), control: CGPoint(x: x + 7, y: 48))
                } else {
                    eye.move(to: CGPoint(x: x, y: 53))
                    eye.addQuadCurve(to: CGPoint(x: x + 14, y: 53), control: CGPoint(x: x + 7, y: 57))
                }
                c.stroke(eye, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        } else {
            let look = pose == .ask ? 0.0 : sin(t * 0.4) * 1.2
            for (x, inner) in [(39.0, 1.0), (61.0, -1.0)] {
                c.fill(ellipse(x, 53, 8.5, 9), with: .color(angry ? irisAngry : iris))
                let pupilW: CGFloat = angry ? 1.8 : (pose == .ask ? 5.5 : 4.2)
                c.fill(ellipse(x + look, 53.5, pupilW, angry ? 6.5 : 7), with: .color(.black))
                c.fill(ellipse(x + 2.6, 49.5, 2.3, 2.3), with: .color(.white.opacity(0.95)))
                c.fill(ellipse(x - 2.6, 57, 1.1, 1.1), with: .color(.white.opacity(0.8)))
                // Lider: leicht grummelig, wütend tief und schräg
                if pose != .ask {
                    let drop: CGFloat = angry ? 7.5 : 3.2
                    let slant: CGFloat = angry ? 5 : 2
                    var lidPath = Path()
                    lidPath.move(to: CGPoint(x: x - 10, y: 43))
                    lidPath.addLine(to: CGPoint(x: x + 10, y: 43))
                    lidPath.addLine(to: CGPoint(x: x + 10, y: 44 + drop + (inner < 0 ? slant : 0)))
                    lidPath.addLine(to: CGPoint(x: x - 10, y: 44 + drop + (inner > 0 ? slant : 0)))
                    lidPath.closeSubpath()
                    c.fill(lidPath, with: .color(fur))
                }
            }
        }

        // Wangen, Nase, Mund, Schnurrhaare
        c.fill(ellipse(30, 63, 4.5, 2.6), with: .color(blush.opacity(angry ? 0.15 : 0.38)))
        c.fill(ellipse(70, 63, 4.5, 2.6), with: .color(blush.opacity(angry ? 0.15 : 0.38)))
        var nosePath = Path()
        nosePath.move(to: CGPoint(x: 47.6, y: 60.5))
        nosePath.addQuadCurve(to: CGPoint(x: 52.4, y: 60.5), control: CGPoint(x: 50, y: 59.3))
        nosePath.addQuadCurve(to: CGPoint(x: 50, y: 63), control: CGPoint(x: 51.5, y: 62.2))
        nosePath.addQuadCurve(to: CGPoint(x: 47.6, y: 60.5), control: CGPoint(x: 48.5, y: 62.2))
        c.fill(nosePath, with: .color(nose))
        var mouth = Path()
        if angry {
            mouth.move(to: CGPoint(x: 44.5, y: 68))
            mouth.addQuadCurve(to: CGPoint(x: 55.5, y: 68), control: CGPoint(x: 50, y: 63.5))
            c.stroke(mouth, with: .color(Color(white: 0.5)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            var fang = Path()
            fang.move(to: CGPoint(x: 47.5, y: 66.1))
            fang.addLine(to: CGPoint(x: 48.4, y: 68.6))
            fang.addLine(to: CGPoint(x: 49.3, y: 65.6))
            c.fill(fang, with: .color(.white.opacity(0.9)))
        } else {
            mouth.move(to: CGPoint(x: 45.5, y: 64))
            mouth.addQuadCurve(to: CGPoint(x: 50, y: 64), control: CGPoint(x: 47.75, y: 66.8))
            mouth.addQuadCurve(to: CGPoint(x: 54.5, y: 64), control: CGPoint(x: 52.25, y: 66.8))
            c.stroke(mouth, with: .color(Color(white: 0.48)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        var whiskers = Path()
        for (y1, y2) in [(61.0, 58.0), (63.5, 64.5)] {
            whiskers.move(to: CGPoint(x: 28, y: y1)); whiskers.addLine(to: CGPoint(x: 12, y: y2))
            whiskers.move(to: CGPoint(x: 72, y: y1)); whiskers.addLine(to: CGPoint(x: 88, y: y2))
        }
        c.stroke(whiskers, with: .color(Color(white: 0.6).opacity(0.75)), lineWidth: 0.7)

        // Pfote winkt
        if pose == .ask {
            var paw = c
            let wave = sin(t * 7) * 14
            paw.translateBy(x: 74, y: 96)
            paw.rotate(by: .degrees(wave - 10))
            paw.translateBy(x: -74, y: -96)
            paw.fill(ellipse(74, 88, 7, 12), with: .color(fur))
            paw.fill(ellipse(74, 79, 8.5, 7), with: .color(fur))
            paw.fill(ellipse(74, 80.5, 2.6, 2.2), with: .color(innerEar))
            for (x, y) in [(69.8, 76.8), (72.8, 74.6), (76.2, 74.6), (79, 76.8)] {
                paw.fill(ellipse(x, y, 1.3, 1.3), with: .color(innerEar))
            }
        }

        // Herzchen beim Schnurren
        if pose == .purr {
            for i in 0..<2 {
                let phase = (t * 0.45 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let x = i == 0 ? 80.0 : 18.0
                let y = 34 - phase * 22
                context.fill(heart(x: x, y: y, size: 6 + phase * 3),
                             with: .color(Color(red: 0.9, green: 0.33, blue: 0.3).opacity(1 - phase)))
            }
        }

        // Dampf, wenn wütend
        if angry {
            let flick = sin(t * 9) > 0 ? 1.0 : 0.6
            var steam = Path()
            steam.move(to: CGPoint(x: 14, y: 20)); steam.addLine(to: CGPoint(x: 20, y: 25))
            steam.move(to: CGPoint(x: 21, y: 14)); steam.addLine(to: CGPoint(x: 23, y: 21))
            steam.move(to: CGPoint(x: 10, y: 28)); steam.addLine(to: CGPoint(x: 17, y: 30))
            context.stroke(steam, with: .color(Color(red: 0.9, green: 0.33, blue: 0.3).opacity(flick)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private static func drawEar(_ context: inout GraphicsContext, left: Bool, angle: Double) {
        var ear = context
        let base = CGPoint(x: left ? 32 : 68, y: 38)
        ear.translateBy(x: base.x, y: base.y)
        ear.rotate(by: .degrees(angle))
        ear.translateBy(x: -base.x, y: -base.y)
        let s: CGFloat = left ? 1 : -1
        var outer = Path()
        outer.move(to: CGPoint(x: 50 - s * 27, y: 46))
        outer.addQuadCurve(to: CGPoint(x: 50 - s * 23, y: 14), control: CGPoint(x: 50 - s * 30, y: 20))
        outer.addQuadCurve(to: CGPoint(x: 50 - s * 6, y: 32), control: CGPoint(x: 50 - s * 15, y: 18))
        outer.closeSubpath()
        ear.fill(outer, with: .color(fur))
        var inner = Path()
        inner.move(to: CGPoint(x: 50 - s * 24, y: 40))
        inner.addQuadCurve(to: CGPoint(x: 50 - s * 22, y: 21), control: CGPoint(x: 50 - s * 26, y: 25))
        inner.addQuadCurve(to: CGPoint(x: 50 - s * 11, y: 33), control: CGPoint(x: 50 - s * 16, y: 24))
        inner.closeSubpath()
        ear.fill(inner, with: .color(innerEar.opacity(0.75)))
    }

    private static func heart(x: Double, y: Double, size s: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y + s * 0.35))
        p.addCurve(to: CGPoint(x: x - s * 0.5, y: y - s * 0.15),
                   control1: CGPoint(x: x - s * 0.15, y: y + s * 0.1), control2: CGPoint(x: x - s * 0.5, y: y + s * 0.15))
        p.addArc(center: CGPoint(x: x - s * 0.25, y: y - s * 0.15), radius: s * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: x + s * 0.25, y: y - s * 0.15), radius: s * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: x, y: y + s * 0.35),
                   control1: CGPoint(x: x + s * 0.5, y: y + s * 0.15), control2: CGPoint(x: x + s * 0.15, y: y + s * 0.1))
        p.closeSubpath()
        return p
    }
}

/// Zeigt Rüdigers Sprechblase für ein paar Sekunden – über der Leiste, Klicks gehen hindurch.
@MainActor
final class CatBubbleController {
    static let shared = CatBubbleController()
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
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    func show(_ text: String, style: CatBubbleStyle, at location: CatLocation) {
        let area = location.visible.insetBy(dx: 4, dy: 4)
        // Größe der Blase aus dem Text – nie größer als ein guter Teil des Bildschirms
        let layout = CatBubbleLayout.make(text, style: style,
                                          maxSize: CGSize(width: min(560, area.width * 0.5),
                                                          height: min(320, area.height * 0.45)))
        let ew = min(layout.bubbleSize.width, area.width)
        let eh = min(layout.bubbleSize.height, area.height)
        let margin: CGFloat = 46

        let cat = location.cat
        let strip = location.strip
        var center: CGPoint
        if location.floating {
            // Schwebend: dorthin, wo am meisten Platz ist
            let gap: CGFloat = 14
            let room = [
                (CGPoint(x: cat.maxX + gap + ew / 2, y: cat.midY + cat.height * 0.3), (area.maxX - cat.maxX) / ew),
                (CGPoint(x: cat.minX - gap - ew / 2, y: cat.midY + cat.height * 0.3), (cat.minX - area.minX) / ew),
                (CGPoint(x: cat.midX, y: cat.maxY + gap + eh / 2), (area.maxY - cat.maxY) / eh),
                (CGPoint(x: cat.midX, y: cat.minY - gap - eh / 2), (cat.minY - area.minY) / eh),
            ]
            // Seitlich bevorzugt (liest sich besser), wenn dort genug Platz ist
            if let side = room.prefix(2).filter({ $0.1 >= 1.05 }).max(by: { $0.1 < $1.1 }) {
                center = side.0
            } else {
                center = room.max(by: { $0.1 < $1.1 })?.0 ?? CGPoint(x: cat.midX, y: cat.maxY + eh / 2)
            }
        } else {
            // In der Sidebar: seitlich neben der Kugel und etwas höher – nie direkt darüber
            let side: CGFloat = 22
            let up = eh * 0.32
            switch location.edge {
            case .right:
                center = CGPoint(x: cat.minX - side - ew / 2, y: cat.midY + up)
            default:
                center = CGPoint(x: cat.maxX + side + ew / 2, y: cat.midY + up)
            }
        }
        center.x = min(max(center.x, area.minX + ew / 2), area.maxX - ew / 2)
        center.y = min(max(center.y, area.minY + eh / 2), area.maxY - eh / 2)
        // Die Blase ragt nie in Rüdigers Kugel: bei Überschneidung wegschieben (mit Luft für den Haken)
        center = Self.pushOut(center: center, size: CGSize(width: ew, height: eh),
                              ball: CGPoint(x: cat.midX, y: cat.midY), radius: cat.width / 2 + 16, area: area)

        let size = CGSize(width: ew + 2 * margin, height: eh + 2 * margin)
        let frame = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                           width: size.width, height: size.height)

        // Spitze zur Katze (lokale Koordinaten, Ursprung oben links)
        let local = { (p: CGPoint) in CGPoint(x: p.x - frame.minX, y: frame.maxY - p.y) }
        let body = CGRect(x: margin, y: margin, width: ew, height: eh)
        let c = CGPoint(x: body.midX, y: body.midY)
        let target = local(CGPoint(x: cat.midX, y: cat.midY))
        let dx = target.x - c.x, dy = target.y - c.y
        let distance = max(sqrt(dx * dx + dy * dy), 1)
        // Abstand vom Mittelpunkt bis zum Rand des Rechtecks in Richtung Katze
        let rx = ew / 2, ry = eh / 2
        let edgeRadius = min(rx / max(abs(dx / distance), 0.001), ry / max(abs(dy / distance), 0.001))
        // Die Spitze endet am Rand der Kugel, nicht in ihr
        let reach = min(distance - cat.width / 2 - 3, edgeRadius + 40)
        var tail = CGPoint(x: c.x + dx / distance * max(reach, edgeRadius + 12),
                           y: c.y + dy / distance * max(reach, edgeRadius + 12))
        tail.x = min(max(tail.x, 2), size.width - 2)
        tail.y = min(max(tail.y, 2), size.height - 2)

        // Textfeld nie größer als das, was in die (evtl. begrenzte) Blase passt
        let textSize = CGSize(width: min(layout.textSize.width, ew - 2 * CatBubbleLayout.padX + 8),
                              height: min(layout.textSize.height, eh - 2 * CatBubbleLayout.padY + 6))
        let host = NSHostingView(rootView: CatBubbleView(text: text, style: style, body_: body, tail: tail,
                                                         size: size, fontSize: layout.fontSize, textSize: textSize))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let duration = max(2.8, min(8, Double(text.count) * 0.075))
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Schiebt eine Blase (Mittelpunkt `center`, Größe `size`) aus dem Kreis um `ball` heraus.
    /// Alles in Bildschirmkoordinaten. Bleibt innerhalb von `area`.
    static func pushOut(center: CGPoint, size: CGSize, ball: CGPoint, radius: CGFloat, area: CGRect) -> CGPoint {
        var c = center
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, area.minX + size.width / 2), area.maxX - size.width / 2),
                    y: min(max(p.y, area.minY + size.height / 2), area.maxY - size.height / 2))
        }
        for _ in 0..<4 {
            let rect = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
            let nearest = CGPoint(x: min(max(ball.x, rect.minX), rect.maxX), y: min(max(ball.y, rect.minY), rect.maxY))
            let dx = nearest.x - ball.x, dy = nearest.y - ball.y
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist >= radius { break }
            if dist < 0.5 {
                // Mittelpunkt der Kugel liegt in der Blase: seitlich hinausschieben
                c.x = ball.x + (c.x >= ball.x ? 1 : -1) * (size.width / 2 + radius)
            } else {
                let push = radius - dist
                c.x += dx / dist * push
                c.y += dy / dist * push
            }
            c = clamp(c)
        }
        return c
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideWork == nil else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        })
    }
}

