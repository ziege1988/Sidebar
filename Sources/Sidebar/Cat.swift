import AppKit
import Combine
import CoreGraphics
import SwiftUI

// MARK: - Rüdiger, die Bürokatze
//
// Sitzt in einem runden Fenster im Viertelkreis zwischen Uhr und Leiste. Schläft, wenn nichts los ist,
// will ab und zu gestreichelt werden, wird ungemütlich, wenn man sie ignoriert, und kommentiert
// neue Nachrichten. Alles lokal – keine Internetverbindung, keine KI.

// MARK: Lage

/// Wo das Katzenfenster sitzt. Gerechnet wie der Umriss: c = quer zur Kante, a = entlang der Kante.
struct CatGeometry {
    /// Radius des Viertelkreises zwischen Uhr und Leiste
    let radius: CGFloat
    let centerCross: CGFloat
    let centerAlong: CGFloat
    let diameter: CGFloat

    static let fillet: CGFloat = 10

    static func make(_ s: SidebarSettings, clockOn: Bool) -> CatGeometry? {
        guard s.catEnabled, clockOn else { return nil }
        let size = ClockLayout.panelSize(s)
        let vertical = s.edge.isVertical
        let clockCross = vertical ? size.width : size.height
        let clockAlong = vertical ? size.height : size.width
        let bar = CGFloat(s.collapsedThickness)
        let radius = clockCross - bar
        // Die Uhr muss deutlich über die Leiste hinausragen, sonst ist kein Platz für die Katze
        guard radius >= 80 else { return nil }
        let q = radius - fillet
        let inner = q / (1 + 2.squareRoot())
        return CatGeometry(radius: radius,
                           centerCross: bar + fillet + inner,
                           centerAlong: clockAlong + inner,
                           diameter: 2 * inner - 6)
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

    static func draw(in context: inout GraphicsContext, size: CGSize, pose: CatPose, dark: Bool,
                     accent: Color, time t: Double) {
        let scale = min(size.width, size.height) / 100
        context.scaleBy(x: scale, y: scale)

        // Hintergrund: weiches, helles Rund (dunkel: Graphit)
        let bg = Path(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 100))
        context.fill(bg, with: .radialGradient(
            Gradient(colors: dark
                     ? [Color(red: 0.31, green: 0.33, blue: 0.31), Color(red: 0.17, green: 0.18, blue: 0.19)]
                     : [Color(red: 0.97, green: 0.96, blue: 0.92), accent.opacity(0.45)]),
            center: CGPoint(x: 50, y: 38), startRadius: 4, endRadius: 70))

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
    private static func drawBust(_ context: inout GraphicsContext, pose: CatPose, dark: Bool, t: Double) {
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

// MARK: - Sprechblase

enum CatBubbleStyle {
    /// leicht gezackt
    case normal
    /// stark gezackt (genervt, wütend)
    case angry
    /// weich (Schnurren, Streicheln)
    case purr

    var spikes: Int {
        switch self {
        case .normal: return 20
        case .angry: return 15
        case .purr: return 26
        }
    }

    var amplitude: CGFloat {
        switch self {
        case .normal: return 0.09
        case .angry: return 0.22
        case .purr: return 0.035
        }
    }
}

/// Comic-Sprechblase: gezackte Ellipse mit Spitze zur Katze.
struct SpikyBubble: Shape {
    let ellipse: CGRect
    let tail: CGPoint
    let spikes: Int
    let amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: ellipse.midX, y: ellipse.midY)
        let rx = ellipse.width / 2, ry = ellipse.height / 2
        let tailAngle = atan2(Double(tail.y - center.y), Double(tail.x - center.x))
        let count = spikes * 2
        var points: [CGPoint] = []
        var tailAdded = false
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi
            let diff = atan2(sin(angle - tailAngle), cos(angle - tailAngle))
            if abs(diff) < 0.26 {
                if !tailAdded {
                    points.append(tail)
                    tailAdded = true
                }
                continue
            }
            let k = i % 2 == 0 ? 1 : 1 - amplitude
            points.append(CGPoint(x: center.x + CGFloat(cos(angle)) * rx * k,
                                  y: center.y + CGFloat(sin(angle)) * ry * k))
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

struct CatBubbleView: View {
    let text: String
    let style: CatBubbleStyle
    let ellipse: CGRect
    let tail: CGPoint
    let size: CGSize
    @State private var shown = false

    static let font = NSFont(name: "ChalkboardSE-Bold", size: 15) ?? NSFont.boldSystemFont(ofSize: 15)

    var body: some View {
        let shape = SpikyBubble(ellipse: ellipse, tail: tail, spikes: style.spikes, amplitude: style.amplitude)
        ZStack(alignment: .topLeading) {
            shape.fill(Color.white)
            shape.stroke(Color.black.opacity(0.88),
                         style: StrokeStyle(lineWidth: style == .angry ? 2.6 : 2.2, lineJoin: .round))
            Text(text)
                .font(.custom("ChalkboardSE-Bold", size: 15))
                .foregroundColor(Color(white: 0.08))
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .frame(width: ellipse.width * 0.76, height: ellipse.height * 0.8)
                .position(x: ellipse.midX, y: ellipse.midY)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .scaleEffect(shown ? 1 : 0.55, anchor: UnitPoint(x: tail.x / max(size.width, 1), y: tail.y / max(size.height, 1)))
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: style == .angry ? 0.45 : 0.6)) { shown = true }
        }
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
        // Größe der Blase aus dem Text
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: 230, height: 400), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: CatBubbleView.font])
        let ew = max(120, ceil(measured.width) * 1.3 + 40)
        let eh = max(58, ceil(measured.height) * 1.45 + 30)
        let margin: CGFloat = 46

        // Mitte der Blase: über der Leiste, neben der Katze
        let cat = location.cat
        let strip = location.strip
        var center: CGPoint
        switch location.edge {
        case .top, .bottom:
            center = CGPoint(x: cat.midX + cat.width * 0.25 + ew / 2, y: strip.midY)
        case .left:
            center = CGPoint(x: strip.midX + ew / 2 - 12, y: cat.minY - eh / 2 - 8)
        case .right:
            center = CGPoint(x: strip.midX - ew / 2 + 12, y: cat.minY - eh / 2 - 8)
        }
        let area = location.visible.insetBy(dx: 4, dy: 4)
        center.x = min(max(center.x, area.minX + ew / 2), area.maxX - ew / 2)
        center.y = min(max(center.y, area.minY + eh / 2), area.maxY - eh / 2)

        let size = CGSize(width: ew + 2 * margin, height: eh + 2 * margin)
        let frame = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                           width: size.width, height: size.height)

        // Spitze zur Katze (lokale Koordinaten, Ursprung oben links)
        let local = { (p: CGPoint) in CGPoint(x: p.x - frame.minX, y: frame.maxY - p.y) }
        let ellipse = CGRect(x: margin, y: margin, width: ew, height: eh)
        let c = CGPoint(x: ellipse.midX, y: ellipse.midY)
        let target = local(CGPoint(x: cat.midX, y: cat.midY))
        let dx = target.x - c.x, dy = target.y - c.y
        let distance = max(sqrt(dx * dx + dy * dy), 1)
        let angle = atan2(dy, dx)
        let rx = ew / 2, ry = eh / 2
        let edgeRadius = rx * ry / sqrt(pow(ry * cos(angle), 2) + pow(rx * sin(angle), 2))
        let reach = min(distance - cat.width * 0.42, edgeRadius + 34)
        var tail = CGPoint(x: c.x + dx / distance * max(reach, edgeRadius + 8),
                           y: c.y + dy / distance * max(reach, edgeRadius + 8))
        tail.x = min(max(tail.x, 2), size.width - 2)
        tail.y = min(max(tail.y, 2), size.height - 2)

        let host = NSHostingView(rootView: CatBubbleView(text: text, style: style, ellipse: ellipse, tail: tail, size: size))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let duration = max(2.8, min(6.5, Double(text.count) * 0.075))
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
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

