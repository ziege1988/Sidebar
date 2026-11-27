import AppKit
import SwiftUI

// MARK: - Wetter-Ebene über Rüdiger
//
// Gezeichnet wird alles direkt in EINEN Zeichenkontext (keine verschachtelten Ebenen-Kontexte – die lassen
// SwiftUI abstürzen). Koordinaten wie bei den Sprite-Bildern: 320 × 320, Mitte der Blase bei 160/160, Radius 121.

/// Ein Bild der Wetter-Ebene
struct WeatherFrame {
    var mood: WeatherMood
    /// laufende Zeit in Sekunden (für Bewegung)
    var t: Double
    /// Sekunden seit dem Blitzeinschlag (0 … 4), sonst nil
    var strikeT: Double?
    /// Sekunden seit dem Schütteln (0 … 2,6), sonst nil
    var shakeT: Double?
    /// Schneehaube auf dem Kopf (0 … 1)
    var snowCap: Double = 1

    var isEmpty: Bool { mood == .normal && strikeT == nil && shakeT == nil }
}

struct WeatherCanvas: View {
    let frame: WeatherFrame

    var body: some View {
        Canvas { context, size in
            WeatherArt.draw(context, size: size, frame: frame)
        }
        .allowsHitTesting(false)
    }
}

enum WeatherArt {
    // MARK: Hilfen

    private static func h(_ n: Double) -> Double {
        let x = sin(n * 12.9898) * 43758.5453
        return x - floor(x)
    }

    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    private static func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static func path(_ build: (inout Path) -> Void) -> Path {
        var p = Path()
        build(&p)
        return p
    }

    private static func segment(_ g: GraphicsContext, _ a: CGPoint, _ b: CGPoint, color: Color, width: Double) {
        g.stroke(path { p in
            p.move(to: a)
            p.addLine(to: b)
        }, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static let circleRect = CGRect(x: 39, y: 39, width: 242, height: 242)

    private static func drop(_ x: Double, _ y: Double, _ s: Double) -> Path {
        path { p in
            p.move(to: pt(x, y - 10 * s))
            p.addQuadCurve(to: pt(x + 7 * s, y + 4 * s), control: pt(x + 2 * s, y - 2 * s))
            p.addQuadCurve(to: pt(x - 7 * s, y + 4 * s), control: pt(x, y + 14 * s))
            p.addQuadCurve(to: pt(x, y - 10 * s), control: pt(x - 2 * s, y - 2 * s))
        }
    }

    // MARK: Zeichnen

    static func draw(_ context: GraphicsContext, size: CGSize, frame f: WeatherFrame) {
        guard !f.isEmpty, size.width > 1 else { return }
        let k = size.width / 320
        var outer = context
        outer.scaleBy(x: k, y: k)
        var inner = outer
        inner.clip(to: Path(ellipseIn: circleRect))

        let t = f.t
        // Blitzeinschlag und Schütteln gehen vor dem Zustand
        if let s = f.strikeT {
            strike(inner, outer, t: t, s: s)
            return
        }
        switch f.mood {
        case .rain: rain(inner, t: t)
        case .hot:
            inner.fill(Path(ellipseIn: circleRect), with: .color(rgba(255, 190, 80, 0.22)))
            glasses(inner)
        case .sweat: sweat(inner, t: t)
        case .wind: wind(inner, t: t)
        case .thunder: thunder(inner, outer, t: t)
        case .frost: frost(inner, outer, t: t)
        case .snow: snow(inner, t: t, cap: f.snowCap, shakeT: f.shakeT)
        case .normal:
            if f.shakeT != nil { snow(inner, t: t, cap: f.snowCap, shakeT: f.shakeT) }
        }
    }

    // MARK: Regen

    private static func streaks(_ g: GraphicsContext, t: Double, count: Int, color: Color) {
        for i in 0..<count {
            let fi = Double(i)
            let speed = 260 * (0.8 + h(fi * 1.7) * 0.4)
            let y = (h(fi * 3.1) * 340 + t * speed).truncatingRemainder(dividingBy: 340) - 10
            let x = h(fi * 7.7) * 270 + 25 - y * 0.3
            segment(g, pt(x, y), pt(x - 7, y + 22), color: color, width: 2.2)
        }
    }

    private static func rain(_ g: GraphicsContext, t: Double) {
        g.fill(Path(ellipseIn: circleRect), with: .color(rgba(60, 85, 120, 0.30)))
        streaks(g, t: t, count: 30, color: rgba(214, 235, 255, 0.8))
        // Spritzer auf dem Kopf
        for (i, x) in [128.0, 196.0].enumerated() {
            let phase = (t * 1.3 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            let r = 4 + 8 * phase
            g.stroke(Path(ellipseIn: CGRect(x: x - r, y: 117 - r * 0.35, width: r * 2, height: r * 0.7)),
                     with: .color(rgba(214, 235, 255, 1 - phase)), lineWidth: 2)
        }
        // Tropfen von den Ohrspitzen
        for (i, x) in [80.0, 240.0].enumerated() {
            let phase = (t * 0.7 + Double(i) * 0.4).truncatingRemainder(dividingBy: 1)
            g.fill(drop(x, 100 + phase * 60, 0.8), with: .color(rgba(143, 211, 255, 1 - phase * 0.8)))
        }
    }

    // MARK: Hitze: Sonnenbrille (weißer Rahmen, Gläser durchscheinend)

    private static func glasses(_ g: GraphicsContext) {
        let left = path { p in
            p.move(to: pt(96, 185))
            p.addQuadCurve(to: pt(118, 160), control: pt(96, 160))
            p.addLine(to: pt(146, 160))
            p.addQuadCurve(to: pt(162, 178), control: pt(162, 160))
            p.addQuadCurve(to: pt(140, 208), control: pt(162, 208))
            p.addLine(to: pt(118, 208))
            p.addQuadCurve(to: pt(96, 185), control: pt(96, 208))
            p.closeSubpath()
        }
        let right = path { p in
            p.move(to: pt(158, 178))
            p.addQuadCurve(to: pt(174, 160), control: pt(158, 160))
            p.addLine(to: pt(202, 160))
            p.addQuadCurve(to: pt(224, 185), control: pt(224, 160))
            p.addQuadCurve(to: pt(202, 208), control: pt(224, 208))
            p.addLine(to: pt(180, 208))
            p.addQuadCurve(to: pt(158, 178), control: pt(158, 208))
            p.closeSubpath()
        }
        let outline = rgba(0, 0, 0, 0.55)
        for lens in [left, right] {
            g.fill(lens, with: .color(rgba(20, 20, 22, 0.5)))
            g.stroke(lens, with: .color(outline), style: StrokeStyle(lineWidth: 6.4, lineCap: .round, lineJoin: .round))
            g.stroke(lens, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        for (a, b) in [(pt(96, 176), pt(74, 170)), (pt(224, 176), pt(246, 170)), (pt(157, 176), pt(163, 176))] {
            segment(g, a, b, color: outline, width: 6)
            segment(g, a, b, color: .white, width: 3.6)
        }
        segment(g, pt(104, 168), pt(124, 168), color: rgba(255, 255, 255, 0.6), width: 4)
        segment(g, pt(168, 168), pt(188, 168), color: rgba(255, 255, 255, 0.6), width: 4)
    }

    // MARK: Schwitzen (hoher UV-Index)

    private static func sweat(_ g: GraphicsContext, t: Double) {
        g.fill(Path(ellipseIn: circleRect), with: .color(rgba(255, 170, 90, 0.22)))
        g.fill(Path(ellipseIn: CGRect(x: 94, y: 206, width: 28, height: 16)), with: .color(rgba(255, 122, 122, 0.38)))
        g.fill(Path(ellipseIn: CGRect(x: 198, y: 206, width: 28, height: 16)), with: .color(rgba(255, 122, 122, 0.38)))
        for (i, spot) in [(228.0, 146.0, 1.3), (92.0, 156.0, 1.1), (172.0, 126.0, 0.9)].enumerated() {
            let phase = (t * 0.45 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
            let d = drop(spot.0, spot.1 + phase * 34, spot.2)
            g.fill(d, with: .color(rgba(143, 211, 255, 0.95 - phase * 0.5)))
            g.stroke(d, with: .color(rgba(30, 90, 140, 0.6)), lineWidth: 1.2)
        }
    }

    // MARK: Wind

    private static func leaf(_ g: GraphicsContext, x: Double, y: Double, rot: Double, s: Double, color: Color) {
        var c = g
        c.translateBy(x: x, y: y)
        c.rotate(by: .degrees(rot))
        c.scaleBy(x: s, y: s)
        let shape = path { p in
            p.move(to: pt(0, 0))
            p.addCurve(to: pt(28, 0), control1: pt(6, -11), control2: pt(20, -11))
            p.addCurve(to: pt(0, 0), control1: pt(20, 11), control2: pt(6, 11))
            p.closeSubpath()
        }
        c.fill(shape, with: .color(color))
        c.stroke(shape, with: .color(rgba(0, 0, 0, 0.35)), lineWidth: 1)
        segment(c, pt(2, 0), pt(26, 0), color: rgba(0, 0, 0, 0.35), width: 1)
    }

    private static func wind(_ g: GraphicsContext, t: Double) {
        g.fill(Path(ellipseIn: circleRect), with: .color(rgba(150, 190, 200, 0.16)))
        let dash = StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [14, 9], dashPhase: -t * 60)
        let lines: [Path] = [
            path { p in
                p.move(to: pt(30, 110))
                p.addCurve(to: pt(215, 98), control1: pt(90, 90), control2: pt(150, 130))
            },
            path { p in
                p.move(to: pt(40, 240))
                p.addCurve(to: pt(270, 226), control1: pt(110, 220), control2: pt(160, 260))
            },
            path { p in
                p.move(to: pt(60, 60))
                p.addCurve(to: pt(260, 50), control1: pt(120, 44), control2: pt(190, 70))
            },
        ]
        for line in lines { g.stroke(line, with: .color(rgba(255, 255, 255, 0.8)), style: dash) }
        let colors = [rgba(200, 134, 46, 1), rgba(138, 160, 74, 1), rgba(181, 83, 42, 1)]
        for i in 0..<7 {
            let fi = Double(i)
            let p = (t * 0.09 * (0.8 + h(fi) * 0.5) + h(fi * 5)).truncatingRemainder(dividingBy: 1)
            let x = -30 + p * 380
            let y = 60 + h(fi * 2.3) * 200 + 25 * sin(p * Double.pi * 3 + h(fi) * 6)
            leaf(g, x: x, y: y, rot: p * 540 + h(fi * 3) * 360, s: 0.8 + h(fi * 4) * 0.4, color: colors[i % 3])
        }
    }

    // MARK: Gewitter

    private static func flash(_ t: Double) -> Double {
        let ph = t.truncatingRemainder(dividingBy: 4.3)
        if ph < 0.08 { return 1 }
        if ph < 0.14 { return 0.15 }
        if ph < 0.22 { return 0.8 }
        if ph < 0.5 { return 0.8 * (1 - (ph - 0.22) / 0.28) }
        return 0
    }

    private static func boltPath() -> Path {
        path { p in
            p.move(to: pt(292, 6))
            p.addLine(to: pt(262, 64))
            p.addLine(to: pt(282, 64))
            p.addLine(to: pt(246, 126))
        }
    }

    private static func thunder(_ g: GraphicsContext, _ outer: GraphicsContext, t: Double) {
        g.fill(Path(ellipseIn: circleRect), with: .color(rgba(20, 28, 55, 0.5)))
        streaks(g, t: t, count: 14, color: rgba(170, 196, 234, 0.8))
        let f = flash(t)
        if f > 0.01 {
            g.fill(Path(ellipseIn: circleRect), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.85 * f), Color.white.opacity(0)]),
                center: pt(240, 80), startRadius: 0, endRadius: 190))
            if f > 0.3 {
                outer.stroke(boltPath(), with: .color(rgba(255, 240, 150, 0.55)),
                             style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                outer.stroke(boltPath(), with: .color(rgba(255, 247, 194, 1)),
                             style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Blitzeinschlag: s = Sekunden seit dem Treffer
    private static func strike(_ g: GraphicsContext, _ outer: GraphicsContext, t: Double, s: Double) {
        let on = s < 0.1 ? 0.0 : (s < 2.6 ? 1.0 : max(0, 1 - (s - 2.6) / 1.0))
        let flashAmount = s < 0.45 ? 1 - s / 0.45 : 0
        g.fill(Path(ellipseIn: circleRect), with: .color(rgba(255, 240, 120, 0.34 * on)))
        if flashAmount > 0 {
            g.fill(Path(ellipseIn: circleRect), with: .color(Color.white.opacity(0.85 * flashAmount)))
        }
        // Funken, die durchs Fell laufen (bei jedem Bild anders)
        if on > 0.01 {
            let seed = floor(t * 18)
            let anchors: [(Double, Double, Double, Double)] = [
                (60, 120, -30, -36), (262, 120, 30, -36), (54, 236, -28, 34), (268, 236, 28, 34),
                (112, 92, -24, -34), (210, 92, 24, -34), (160, 250, 0, 38),
            ]
            for (i, a) in anchors.enumerated() {
                var pts: [CGPoint] = [pt(a.0, a.1)]
                for j in 1...5 {
                    let q = Double(j) / 5
                    let jx = (h(seed * 3.1 + Double(i * 7 + j)) - 0.5) * 12
                    let jy = (h(seed * 5.3 + Double(i * 11 + j)) - 0.5) * 12
                    pts.append(pt(a.0 + a.2 * q + jx, a.1 + a.3 * q + jy))
                }
                let zig = path { p in
                    p.move(to: pts[0])
                    for q in pts.dropFirst() { p.addLine(to: q) }
                }
                g.stroke(zig, with: .color(rgba(255, 242, 122, 0.6 * on)),
                         style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                g.stroke(zig, with: .color(rgba(255, 251, 224, 0.95 * on)),
                         style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
        // Leuchtring und Blitz außerhalb der Blase
        outer.stroke(Path(ellipseIn: CGRect(x: 36, y: 36, width: 248, height: 248)),
                     with: .color(rgba(255, 242, 122, 0.6 * on)), lineWidth: 3)
        if s < 0.4 {
            let bolt = path { p in
                p.move(to: pt(160, 4))
                p.addLine(to: pt(184, 40))
                p.addLine(to: pt(150, 42))
                p.addLine(to: pt(168, 112))
            }
            outer.stroke(bolt, with: .color(rgba(255, 240, 150, 0.6)),
                         style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
            outer.stroke(bolt, with: .color(rgba(255, 247, 194, 1)),
                         style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Frost

    private static func frost(_ g: GraphicsContext, _ outer: GraphicsContext, t: Double) {
        g.fill(Path(ellipseIn: circleRect), with: .color(rgba(140, 195, 255, 0.30)))
        // Zapfen am oberen Rand
        for (i, x) in [92.0, 118.0, 206.0, 232.0].enumerated() {
            let y = 160 - (121 * 121 - (x - 160) * (x - 160)).squareRoot() + 2
            let len = 20 + h(Double(i) * 2.9) * 10
            let icicle = path { p in
                p.move(to: pt(x - 7, y))
                p.addLine(to: pt(x, y + len))
                p.addLine(to: pt(x + 7, y))
                p.closeSubpath()
            }
            g.fill(icicle, with: .color(rgba(225, 244, 255, 0.95)))
            g.stroke(icicle, with: .color(rgba(120, 170, 215, 0.8)), lineWidth: 1.2)
        }
        // Atemwolke
        for i in 0..<3 {
            let phase = (t / 2.2 + Double(i) * 0.15).truncatingRemainder(dividingBy: 1)
            let r = 8 + phase * 10 + Double(i) * 2
            g.fill(Path(ellipseIn: CGRect(x: 176 + phase * 40 + Double(i) * 8 - r, y: 236 - phase * 18 - r, width: r * 2, height: r * 2)),
                   with: .color(Color.white.opacity(0.7 * (1 - phase))))
        }
        // Zittern
        let a = 0.5 + 0.5 * sin(t * 20)
        let shiver = rgba(90, 134, 184, 0.4 + 0.6 * a)
        for side in [0.0, 1.0] {
            for offset in [0.0, 10.0] {
                let x = side == 0 ? 62 - offset : 258 + offset
                let dir = side == 0 ? -1.0 : 1.0
                let wave = path { p in
                    p.move(to: pt(x, 150))
                    p.addQuadCurve(to: pt(x, 170), control: pt(x + dir * 8, 160))
                    p.addQuadCurve(to: pt(x, 190), control: pt(x - dir * 8, 180))
                }
                g.stroke(wave, with: .color(shiver), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        // Eis am Blasenrand
        outer.stroke(Path(ellipseIn: CGRect(x: 41, y: 41, width: 238, height: 238)),
                     with: .color(rgba(235, 248, 255, 0.9)), lineWidth: 4)
        for i in 0..<22 {
            let ang = Double(i) / 22 * 2 * Double.pi
            let cx = 160 + cos(ang) * 118, cy = 160 + sin(ang) * 118
            let r = 3 + h(Double(i)) * 3
            segment(outer, pt(cx - r, cy), pt(cx + r, cy), color: .white, width: 1.8)
            segment(outer, pt(cx, cy - r), pt(cx, cy + r), color: .white, width: 1.8)
        }
    }

    // MARK: Schnee

    private static func snow(_ g: GraphicsContext, t: Double, cap: Double, shakeT: Double?) {
        g.fill(Path(ellipseIn: circleRect), with: .color(rgba(200, 220, 245, 0.20)))
        for i in 0..<34 {
            let fi = Double(i)
            let y = (h(fi * 3.7) * 340 + t * 40 * (0.6 + h(fi * 1.3))).truncatingRemainder(dividingBy: 340) - 10
            let x = h(fi * 5.1) * 250 + 35 + 8 * sin(t * 1.3 + h(fi) * 9)
            let r = 2 + h(fi * 2.1) * 2.6
            let flake = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            g.fill(flake, with: .color(Color.white.opacity(0.95)))
            g.stroke(flake, with: .color(rgba(120, 150, 190, 0.45)), lineWidth: 0.8)
        }
        let line = rgba(110, 140, 185, 0.7)
        if cap > 0.02 {
            var c = g
            c.translateBy(x: 0, y: 138)
            c.scaleBy(x: 1, y: max(cap, 0.05))
            c.translateBy(x: 0, y: -138)
            let hood = path { p in
                p.move(to: pt(104, 138))
                p.addCurve(to: pt(160, 104), control1: pt(108, 118), control2: pt(128, 106))
                p.addCurve(to: pt(216, 138), control1: pt(192, 106), control2: pt(212, 118))
                p.addCurve(to: pt(182, 130), control1: pt(204, 130), control2: pt(192, 134))
                p.addCurve(to: pt(148, 134), control1: pt(170, 138), control2: pt(158, 130))
                p.addCurve(to: pt(104, 138), control1: pt(136, 130), control2: pt(118, 138))
                p.closeSubpath()
            }
            c.fill(hood, with: .color(.white))
            c.stroke(hood, with: .color(line), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
        }
        if cap > 0.6 {
            for x in [76.0, 244.0] {
                let spot = Path(ellipseIn: CGRect(x: x - 9, y: 75, width: 18, height: 18))
                g.fill(spot, with: .color(.white))
                g.stroke(spot, with: .color(line), lineWidth: 2)
            }
        }
        // Schnee fällt beim Schütteln herunter
        if let s = shakeT, s > 0.2 {
            for i in 0..<6 {
                let fi = Double(i)
                let drift = (h(fi * 2.7) - 0.5) * 140
                let x = 160 + drift * min(1, (s - 0.2) / 0.8)
                let y = 118 + (s - 0.2) * 130 * (0.7 + h(fi) * 0.6)
                let r = 5 + h(fi * 4.1) * 5
                let clump = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                g.fill(clump, with: .color(Color.white.opacity(max(0, 1 - (s - 0.2) / 2.2))))
                g.stroke(clump, with: .color(rgba(110, 140, 185, max(0, 0.7 - (s - 0.2) / 3))), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Rüdiger mit Blase und Wetter (Vorschau und Selbsttest)

struct WeatherCatArt: View {
    let spriteName: String
    let spriteTime: Double
    let frame: WeatherFrame
    var accent: Color = Color(red: 0.44, green: 0.56, blue: 0.40)
    var diameter: CGFloat = 96

    var body: some View {
        let span = CGFloat(CatSprites.shared.span(spriteName))
        ZStack {
            Circle().fill(accent.opacity(0.45)).blur(radius: 6).padding(-3)
            Circle().fill(Color.white.opacity(0.88))
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.5), accent.opacity(0.55)],
                                         center: UnitPoint(x: 0.45, y: 0.36), startRadius: 2, endRadius: 60))
            if let image = CatSprites.shared.image(spriteName, at: spriteTime) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: diameter * span, height: diameter * span)
            }
            WeatherCanvas(frame: frame)
                .frame(width: diameter * 1.3, height: diameter * 1.3)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Vorschau-Fenster

/// Reihenfolge der Vorschau: jeder Zustand 10 Sekunden
private struct PreviewStep {
    enum Kind { case plain, strike, shake }
    let mood: WeatherMood
    let kind: Kind

    static let all: [PreviewStep] = [
        .init(mood: .rain, kind: .plain), .init(mood: .hot, kind: .plain), .init(mood: .sweat, kind: .plain),
        .init(mood: .wind, kind: .plain), .init(mood: .thunder, kind: .plain), .init(mood: .thunder, kind: .strike),
        .init(mood: .frost, kind: .plain), .init(mood: .snow, kind: .plain), .init(mood: .snow, kind: .shake),
    ]
}

/// Bild für einen Zeitpunkt der Vorschau
enum WeatherPreviewScript {
    static let secondsPerStep = 10.0
    static var duration: Double { Double(PreviewStep.all.count) * secondsPerStep }

    static func art(at elapsed: Double, now: Double, accent: Color) -> WeatherCatArt {
        let index = min(max(Int(elapsed / secondsPerStep), 0), PreviewStep.all.count - 1)
        let step = PreviewStep.all[index]
        let local = elapsed - Double(index) * secondsPerStep
        return art(mood: step.mood, kindIndex: step.kind == .strike ? 1 : (step.kind == .shake ? 2 : 0),
                   local: local, now: now, accent: accent)
    }

    /// kindIndex: 0 normal, 1 Blitzeinschlag, 2 Schütteln
    static func art(mood: WeatherMood, kindIndex: Int, local: Double, now: Double, accent: Color) -> WeatherCatArt {
        var frame = WeatherFrame(mood: mood, t: now, strikeT: nil, shakeT: nil, snowCap: 1)
        var sprite = mood.clip ?? "idle"
        var spriteTime = now
        switch kindIndex {
        case 1:
            let cycle = local.truncatingRemainder(dividingBy: 5)
            if cycle >= 0.4, cycle < 4.4 {
                frame.strikeT = cycle - 0.4
                sprite = "struck"
                spriteTime = cycle - 0.4
            }
        case 2:
            let cycle = local.truncatingRemainder(dividingBy: 5)
            if cycle >= 0.5, cycle < 3.1 {
                frame.shakeT = cycle - 0.5
                sprite = "shake"
                spriteTime = cycle - 0.5
            }
            frame.snowCap = cycle < 0.9 ? 1 : (cycle < 3.1 ? 0 : min(1, (cycle - 3.1) / 1.9))
        default: break
        }
        return WeatherCatArt(spriteName: sprite, spriteTime: spriteTime, frame: frame, accent: accent)
    }
}

private struct WeatherPreviewView: View {
    let accent: Color
    let onFinish: () -> Void
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            WeatherPreviewScript.art(at: elapsed, now: timeline.date.timeIntervalSinceReferenceDate, accent: accent)
        }
        .frame(width: 220, height: 220)
        .task {
            try? await Task.sleep(nanoseconds: UInt64(WeatherPreviewScript.duration * 1_000_000_000))
            onFinish()
        }
    }
}

@MainActor
final class WeatherPreviewController {
    static let shared = WeatherPreviewController()
    private var window: NSWindow?

    func show(accent: Color) {
        window?.close()
        let size = NSSize(width: 220, height: 220)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        let content = WeatherPreviewView(accent: accent) { [weak self] in self?.close() }
            .background(.ultraThinMaterial)
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        panel.contentView = host
        panel.setContentSize(size)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Selbsttest (beim Bau automatisch: `Sidebar --selftest`)

@MainActor
enum WeatherSelfTest {
    /// Gibt die Fehler zurück (leer = alles in Ordnung)
    static func run() -> [String] {
        var failures: [String] = []
        func expect(_ name: String, _ value: WeatherMood, _ expected: WeatherMood) {
            if value != expected { failures.append("Logik „\(name)“: \(value.rawValue) statt \(expected.rawValue)") }
        }
        let th = WeatherThresholds()
        func decide(_ i: WeatherInput, _ previous: WeatherMood = .normal) -> WeatherMood {
            WeatherLogic.decide(i, th: th, previous: previous)
        }
        expect("normal", decide(.init(temp: 5, uv: 0)), .normal)
        expect("hot", decide(.init(temp: 27, uv: 2)), .hot)
        expect("sweat", decide(.init(temp: 27, uv: 5)), .sweat)
        expect("rain geht vor sweat", decide(.init(temp: 27, raining: true, uv: 5)), .rain)
        expect("thunder", decide(.init(raining: true, code: 95)), .thunder)
        expect("snow", decide(.init(code: 73)), .snow)
        expect("snow vor frost", decide(.init(temp: -5, code: 71)), .snow)
        expect("frost", decide(.init(temp: -5)), .frost)
        expect("wind", decide(.init(temp: 10, wind: 40)), .wind)
        expect("hot vor wind", decide(.init(temp: 27, wind: 40)), .hot)
        expect("uv 4 schwitzt nicht", decide(.init(temp: 20, uv: 4)), .normal)
        expect("hysterese hot bleibt", decide(.init(temp: 24.5), .hot), .hot)
        expect("hysterese hot startet nicht", decide(.init(temp: 24.5), .normal), .normal)

        // Sprites vorhanden?
        for name in ["wet", "cold", "shake", "struck", "windy", "idle"] where !CatSprites.shared.has(name) {
            failures.append("Bilder fehlen: \(name)")
        }

        // Alle Zustände zeichnen (das hätte den Absturz bei der Uhr abgefangen)
        func render<V: View>(_ name: String, _ view: V) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            if renderer.cgImage == nil { failures.append("Zeichnen fehlgeschlagen: \(name)") }
        }
        let accent = Color(red: 0.44, green: 0.56, blue: 0.40)
        for mood in WeatherMood.allCases where mood != .normal {
            for t in [0.3, 1.9, 4.5] {
                render("\(mood.rawValue) \(t)", WeatherPreviewScript.art(mood: mood, kindIndex: 0, local: 0, now: t, accent: accent))
            }
        }
        for local in [0.5, 1.0, 2.5, 4.0, 4.6] {
            render("Blitzeinschlag \(local)", WeatherPreviewScript.art(mood: .thunder, kindIndex: 1, local: local, now: local, accent: accent))
            render("Schütteln \(local)", WeatherPreviewScript.art(mood: .snow, kindIndex: 2, local: local, now: local, accent: accent))
        }
        for step in 0..<9 {
            render("Vorschau \(step)", WeatherPreviewScript.art(at: Double(step) * 10 + 3, now: 3, accent: accent))
        }
        // Uhr mit Datum, hell und dunkel
        for scheme in [ColorScheme.light, ColorScheme.dark] {
            let palette = Palette.resolve(.sage, scheme)
            render("Uhr \(scheme)", AnalogClock(date: Date(), showSeconds: true, showDate: true, palette: palette)
                .frame(width: 158, height: 158))
            render("Uhr klein \(scheme)", AnalogClock(date: Date(), showSeconds: false, showDate: true, palette: palette)
                .frame(width: 64, height: 64))
        }
        // Sprechblasen (alle Stimmungen, Haken in alle Richtungen)
        let samples = ["Na toll. Regen. Und ich hab keinen Schirm.", "Hallo!", "Das ist jetzt schon die dritte Mail von Frau Meier heute und es ist erst Mittag, wirklich."]
        for style in [CatBubbleStyle.normal, .angry, .purr] {
            for text in samples {
                let layout = CatBubbleLayout.make(text, style: style, maxSize: CGSize(width: 400, height: 200))
                if layout.bubbleSize.width > 400 || layout.bubbleSize.height > 200 {
                    failures.append("Blase zu groß: \(text.prefix(12))")
                }
                let margin: CGFloat = 46
                let size = CGSize(width: layout.bubbleSize.width + 2 * margin, height: layout.bubbleSize.height + 2 * margin)
                let body = CGRect(x: margin, y: margin, width: layout.bubbleSize.width, height: layout.bubbleSize.height)
                let tails = [CGPoint(x: 20, y: size.height - 6), CGPoint(x: size.width - 20, y: size.height - 6),
                             CGPoint(x: 8, y: size.height / 2), CGPoint(x: size.width - 8, y: size.height / 2),
                             CGPoint(x: size.width / 2, y: 6)]
                for (i, tail) in tails.enumerated() {
                    render("Blase \(style) \(text.prefix(6)) \(i)",
                           SketchBubbleView(text: text, style: style, body: body, tail: tail, size: size,
                                            fontSize: layout.fontSize, textSize: layout.textSize, drawIn: false))
                }
            }
        }
        // Wartezeit vor dem Auftritt (Kugel im Halbdunkel)
        if CatPose.waiting(CatTiming.introDelay).waitProgress != 0 { failures.append("Wartezeit: Start nicht dunkel") }
        if CatPose.waiting(0).waitProgress != 1 { failures.append("Wartezeit: Ende nicht hell") }
        if CatPose.waiting(CatTiming.introDelay / 2).waitProgress != 0.5 { failures.append("Wartezeit: Mitte") }
        if CatPose.waiting(3).sprite != "sleep" || CatPose.absent.sprite != nil { failures.append("Wartezeit: Bilder") }
        // Blase darf nicht in Rüdigers Kugel ragen
        let area = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for (c, b) in [(CGPoint(x: 330, y: 820), CGPoint(x: 300, y: 800)), (CGPoint(x: 300, y: 800), CGPoint(x: 300, y: 800)),
                       (CGPoint(x: 700, y: 400), CGPoint(x: 640, y: 400))] {
            let size = CGSize(width: 260, height: 90)
            let moved = CatBubbleController.pushOut(center: c, size: size, ball: b, radius: 40, area: area)
            let rect = CGRect(x: moved.x - 130, y: moved.y - 45, width: 260, height: 90)
            let nearest = CGPoint(x: min(max(b.x, rect.minX), rect.maxX), y: min(max(b.y, rect.minY), rect.maxY))
            if hypot(nearest.x - b.x, nearest.y - b.y) < 39.5 { failures.append("Blase ragt in die Kugel (\(c))") }
        }
        // Server-Verknüpfungen und Fenster außerhalb der Sidebar
        for (text, expected) in [("smb://nas.local/Daten", true), ("afp://nas/Freigabe", true), ("https://example.com", false),
                                 ("/Applications/Safari.app", false)] {
            if let url = LinkItem.normalizedURL(from: text), LinkOpener.isServerAddress(url) != expected {
                failures.append("Server-Adresse falsch erkannt: \(text)")
            }
        }
        let screenArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for edge in [ScreenEdge.top, .bottom, .left, .right] {
            let thickness: CGFloat = 56
            let strip: CGRect, clock: CGRect
            switch edge {
            case .top: strip = CGRect(x: 0, y: screenArea.maxY - thickness, width: screenArea.width, height: thickness); clock = CGRect(x: 0, y: screenArea.maxY - 150, width: 150, height: 150)
            case .bottom: strip = CGRect(x: 0, y: 0, width: screenArea.width, height: thickness); clock = CGRect(x: 0, y: 0, width: 150, height: 150)
            case .left: strip = CGRect(x: 0, y: 0, width: thickness, height: screenArea.height); clock = CGRect(x: 0, y: screenArea.maxY - 150, width: 150, height: 150)
            case .right: strip = CGRect(x: screenArea.maxX - thickness, y: 0, width: thickness, height: screenArea.height); clock = CGRect(x: screenArea.maxX - 150, y: screenArea.maxY - 150, width: 150, height: 150)
            }
            for frame in [CGRect(x: 80, y: 60, width: 1280, height: 820), CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 300, y: 200, width: 600, height: 400),
                          CGRect(x: 1000, y: 800, width: 400, height: 300)] {
                let moved = SidebarKeepOut.adjust(frame, strip: strip, clock: clock, edge: edge, area: screenArea)
                if moved.intersects(strip) { failures.append("Fenster berührt die Leiste (\(edge.rawValue), \(frame))") }
                if moved.intersects(clock) { failures.append("Fenster berührt die Uhr (\(edge.rawValue), \(frame))") }
                if moved.width < 100 || moved.height < 100 { failures.append("Fenster zu klein gemacht (\(edge.rawValue), \(frame))") }
            }
            let free = CGRect(x: 400, y: 200, width: 500, height: 300)
            if SidebarKeepOut.adjust(free, strip: strip, clock: clock, edge: edge, area: screenArea) != free {
                failures.append("Freies Fenster wurde verschoben (\(edge.rawValue))")
            }
        }
        // Schließen-Knopf erreichbar; Fenster auf anderem Bildschirm bleiben unberührt
        for edge in [ScreenEdge.top, .bottom, .left, .right] {
            let thickness: CGFloat = 56
            let strip: CGRect
            switch edge {
            case .top: strip = CGRect(x: 0, y: screenArea.maxY - thickness, width: screenArea.width, height: thickness)
            case .bottom: strip = CGRect(x: 0, y: 0, width: screenArea.width, height: thickness)
            case .left: strip = CGRect(x: 0, y: 0, width: thickness, height: screenArea.height)
            case .right: strip = CGRect(x: screenArea.maxX - thickness, y: 0, width: thickness, height: screenArea.height)
            }
            let under = CGRect(x: strip.minX + 10, y: strip.maxY - 200, width: 700, height: 500)
            let moved = SidebarKeepOut.reachable(under, strip: strip, clock: nil, edge: edge, area: screenArea)
            let corner = CGRect(x: moved.minX, y: moved.maxY - 36, width: 90, height: 36)
            if corner.intersects(strip) { failures.append("Schließen-Knopf liegt unter der Leiste (\(edge.rawValue))") }
            let away = CGRect(x: -1600, y: 100, width: 1200, height: 800)
            if SidebarKeepOut.reachable(away, strip: strip, clock: nil, edge: edge, area: screenArea) != away {
                failures.append("Fenster auf anderem Bildschirm wurde verschoben (\(edge.rawValue))")
            }
        }
        // Rüdigers Größe: schwebend wie eingestellt, angedockt immer Standard
        var sizeSettings = SidebarSettings()
        sizeSettings.catFloatScale = 1.8
        sizeSettings.catFloating = true
        if let decoded = try? JSONDecoder().decode(SidebarSettings.self, from: JSONEncoder().encode(sizeSettings)),
           decoded.catFloatScale != 1.8 { failures.append("Größe wird nicht gespeichert") }
        if let old = try? JSONDecoder().decode(SidebarSettings.self, from: Data("{}".utf8)), old.catFloatScale != 1 {
            failures.append("Größe: Standard ist nicht 100 %")
        }
        if let huge = try? JSONDecoder().decode(SidebarSettings.self, from: Data("{\"catFloatScale\": 9}".utf8)),
           huge.catFloatScale > CatTiming.maxFloatScale { failures.append("Größe: Obergrenze fehlt") }
        // Chrome-Fenster: Koordinaten, Abfrage-Text, gemerkte Lage prüfen
        let raws = ChromeBounds.parse("12|100|50|1380|870|https://www.example.com/a|b\n7|0|0|10|10|x\nkaputt\n")
        if raws.count != 2 || raws.first?.id != 12 || raws.first?.url != "https://www.example.com/a|b" {
            failures.append("Chrome-Fensterliste falsch gelesen")
        }
        if let raw = raws.first {
            let cocoa = ChromeBounds.cocoa(raw, primaryHeight: 900)
            let back = ChromeBounds.script(cocoa, primaryHeight: 900)
            if back.l != 100 || back.t != 50 || back.r != 1380 || back.b != 870 { failures.append("Chrome-Koordinaten stimmen nicht") }
            if cocoa.minY != 30 || cocoa.height != 820 { failures.append("Chrome-Koordinaten (Cocoa) falsch") }
        }
        if ChromeBounds.host(of: "https://www.Pinterest.com/x") != "pinterest.com" { failures.append("Adresse → Host falsch") }
        let displays = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        let visibles = [CGRect(x: 0, y: 0, width: 1440, height: 876), CGRect(x: 1440, y: 0, width: 1920, height: 1056)]
        let there = CGRect(x: 1600, y: 100, width: 1200, height: 800)
        if ChromeBounds.sanitized(there, screens: displays, visible: visibles, preferred: visibles[0]) != there { failures.append("Gemerkte Lage auf 2. Bildschirm geändert") }
        let filled = visibles[1]
        if ChromeBounds.sanitized(filled, screens: displays, visible: visibles, preferred: visibles[0]) != filled { failures.append("Bildschirmfüllendes Fenster auf 2. Bildschirm verschoben") }
        let overMenu = CGRect(x: 1500, y: 300, width: 1000, height: 800)   // Titelleiste ragt über den sichtbaren Bereich
        let fixedMenu = ChromeBounds.sanitized(overMenu, screens: displays, visible: visibles, preferred: visibles[0])
        if fixedMenu.minX < 1440 || fixedMenu.maxY > 1056 { failures.append("Fenster mit Titelleiste über der Menüleiste nicht korrigiert") }
        let gone = CGRect(x: 5000, y: 100, width: 1200, height: 800)
        let rescued = ChromeBounds.sanitized(gone, screens: displays, visible: visibles, preferred: visibles[0])
        if !displays[0].contains(rescued) { failures.append("Gemerkte Lage auf fehlendem Bildschirm nicht gerettet") }
        // Bildschirmfüllendes Fenster unter einer Leiste oben: kürzer machen, nicht aus dem Bildschirm schieben
        let fullStrip = CGRect(x: 0, y: 876 - 56, width: 1440, height: 56)
        let maxed = SidebarKeepOut.reachable(visibles[0], strip: fullStrip, clock: nil, edge: .top, area: visibles[0])
        if maxed.minY != 0 || maxed.maxY > fullStrip.minY { failures.append("Bildschirmfüllendes Fenster unter der Leiste: falsch angepasst") }
        // Update: App austauschen (an Wegwerf-Ordnern) und Version prüfen
        do {
            let fm = FileManager.default
            let base = fm.temporaryDirectory.appendingPathComponent("SidebarUpdateTest-\(UUID().uuidString)")
            func makeApp(_ name: String, version: String) throws -> URL {
                let app = base.appendingPathComponent(name)
                let contents = app.appendingPathComponent("Contents")
                try fm.createDirectory(at: contents, withIntermediateDirectories: true)
                let plist: [String: Any] = ["CFBundleShortVersionString": version, "CFBundleIdentifier": "test.sidebar", "CFBundleName": "T"]
                try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
                try Data(version.utf8).write(to: contents.appendingPathComponent("marker.txt"))
                return app
            }
            let installed = try makeApp("Sidebar.app", version: "1.0.1")
            // wie bei der laufenden App: Bundle ist vorher schon geladen (zwischengespeichert)
            _ = Bundle(url: installed)?.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            let staged = try makeApp("Sidebar.app.update", version: "1.0.2")
            try Updater.swapBundle(replacing: installed, with: staged, expectedVersion: "1.0.2")
            let marker = try? String(contentsOf: installed.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
            if marker != "1.0.2" { failures.append("Update-Austausch: neue Dateien fehlen") }
            if fm.fileExists(atPath: staged.path) { failures.append("Update-Austausch: Zwischenordner bleibt liegen") }
            // falsche Version muss gemeldet werden
            let again = try makeApp("Other.app.update", version: "1.0.9")
            var reported = false
            do { try Updater.swapBundle(replacing: installed, with: again, expectedVersion: "1.0.3") } catch { reported = true }
            if !reported { failures.append("Update-Austausch: falsche Version nicht gemeldet") }
            try? fm.removeItem(at: base)
        } catch {
            failures.append("Update-Austausch-Test: \(error.localizedDescription)")
        }
        // Dauer der Sprechblase: kurz ≥ 8 s, lang höchstens 24 s
        if CatBubbleController.visibleSeconds(for: "Hallo!") < 8 { failures.append("Blase zu kurz sichtbar") }
        if CatBubbleController.visibleSeconds(for: String(repeating: "x", count: 400)) > 24 { failures.append("Blase zu lange sichtbar") }
        // Update-Merkzettel und Protokoll
        let pending = UpdateLog.Pending(expected: "1.0.9", fromVersion: "1.0.8", fromPath: "/Applications/Sidebar.app")
        UpdateLog.writePending(pending)
        if UpdateLog.takePending() != pending { failures.append("Update-Merkzettel nicht lesbar") }
        if UpdateLog.takePending() != nil { failures.append("Update-Merkzettel bleibt liegen") }
        if Updater.permissionSummary(for: URL(fileURLWithPath: "/Applications")).isEmpty { failures.append("Update: Rechte-Zusammenfassung leer") }
        // Chrome-Lage: zwischen zwei Bildschirmen ist nicht brauchbar, ganz auf einem schon
        let twoScreens = [CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
        if ChromeBounds.bestShare(CGRect(x: -1898, y: 22, width: 1200, height: 1006), screens: twoScreens) < 0.98 { failures.append("Fenster auf linkem Bildschirm nicht brauchbar") }
        if ChromeBounds.bestShare(CGRect(x: -546, y: 53, width: 1513, height: 979), screens: twoScreens) >= 0.98 { failures.append("Fenster zwischen zwei Bildschirmen gilt als brauchbar") }
        // Beim Start: Modus je Eintrag speichern und auswählen
        var startItem = LinkItem(name: "NAS", urlString: "smb://nas.local/Daten")
        startItem.startMode = .open
        if startItem.startMode != .open || startItem.connectAtStart != nil { failures.append("Start-Modus „Öffnen“ falsch gesetzt") }
        startItem.startMode = .connect
        if startItem.startMode != .connect || startItem.openAtStart != nil { failures.append("Start-Modus „Verbinden“ falsch gesetzt") }
        startItem.startMode = .none
        if startItem.connectAtStart != nil || startItem.openAtStart != nil { failures.append("Start-Modus „Nichts“ falsch gesetzt") }
        var startConfig = SidebarConfig()
        var openItem = LinkItem(name: "Ordner", urlString: "/Applications")
        openItem.startMode = .open
        startConfig.favorites = [openItem, LinkItem(name: "Web", urlString: "https://example.com")]
        if StartupRunner.startItems(in: startConfig).count != 1 { failures.append("Start-Einträge falsch ausgewählt") }
        if !StartupRunner.openQuietly(LinkItem(name: "x", urlString: ""), settings: SidebarSettings()) { failures.append("Leerer Eintrag blockiert den Start") }
        if StartupRunner.openQuietly(LinkItem(name: "Weg", urlString: "/Volumes/gibt-es-nicht-\(UUID().uuidString)"), settings: SidebarSettings()) {
            failures.append("Fehlendes Laufwerk gilt als geöffnet")
        }
        // Fenster zwischen Bildschirmen: das 1920 breite, in den Hauptbildschirm gepresste Fenster geht auf den linken Bildschirm
        let mainScreen = CGRect(x: 0, y: 0, width: 1728, height: 1117), leftScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let mainVisible = CGRect(x: 0, y: 61, width: 1728, height: 1023), leftVisible = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        let pressed = ChromeBounds.snapped(CGRect(x: -192, y: 61, width: 1920, height: 1023), screens: [mainScreen, leftScreen], visible: [mainVisible, leftVisible])
        if pressed.minX != -1920 || pressed.width != 1920 { failures.append("Gepresstes Fenster ging nicht auf den linken Bildschirm: \(pressed)") }
        let halfway = ChromeBounds.snapped(CGRect(x: -546, y: 53, width: 1513, height: 979), screens: [mainScreen, leftScreen], visible: [mainVisible, leftVisible])
        if halfway.minX < 0 && halfway.maxX > 0 { failures.append("Fenster zwischen Bildschirmen bleibt dazwischen") }
        let fine = CGRect(x: -1900, y: 20, width: 1200, height: 1000)
        if ChromeBounds.snapped(fine, screens: [mainScreen, leftScreen], visible: [mainVisible, leftVisible]) != fine { failures.append("Ganz auf einem Bildschirm liegendes Fenster verschoben") }
        // Fenster-Lage der integrierten Link-Fenster merken
        let webID = UUID()
        WebFrameMemory.save(CGRect(x: -1900, y: 20, width: 1200, height: 900), for: webID)
        if WebFrameMemory.frame(for: webID) != CGRect(x: -1900, y: 20, width: 1200, height: 900) { failures.append("Fensterlage wird nicht gemerkt") }
        if WebFrameMemory.frame(for: UUID()) != nil { failures.append("Unbekanntes Fenster hat eine Lage") }
        // Notiz-Kacheln (Raster, mit und ohne bearbeiteter Kachel)
        let sample = (0..<5).map { i in QuickNote(text: "Notiz \(i): Rückruf Frau Meier, Do 14 Uhr", tint: i) }
        for scheme in [ColorScheme.light, ColorScheme.dark] {
            let palette = Palette.resolve(.sage, scheme)
            for editing in [nil, sample[1].id] as [UUID?] {
                render("Notizen \(scheme) \(editing == nil ? "Raster" : "bearbeitet")",
                       NotesBoard(notes: sample, editingID: .constant(editing), palette: palette, actions: NotesBoardActions())
                    .frame(width: 580, height: 480))
            }
            render("Notizen leer \(scheme)", NotesBoard(notes: [], editingID: .constant(nil), palette: palette,
                                                        actions: NotesBoardActions()).frame(width: 580, height: 300))
        }
        let stored = NSMutableAttributedString(string: "weiß", attributes: [.foregroundColor: NSColor.white])
        stored.append(NSAttributedString(string: "rot", attributes: [.foregroundColor: NSColor(srgbRed: 0.75, green: 0.27, blue: 0.25, alpha: 1)]))
        RichTextEditor.dropPaleInk(stored)
        if stored.attribute(.foregroundColor, at: 0, effectiveRange: nil) != nil { failures.append("Weiße Schrift bleibt in Notizen stehen") }
        if stored.attribute(.foregroundColor, at: 4, effectiveRange: nil) == nil { failures.append("Farbige Schrift ging verloren") }
        return failures
    }
}
