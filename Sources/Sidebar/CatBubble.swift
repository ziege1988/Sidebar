import AppKit
import SwiftUI

// MARK: - Sprechblase (Skizzen-Stil)
//
// Handgezeichnet wirkender Rahmen: doppelte, leicht verrutschte Tuschelinie, schraffierte Ecke neben dem spitzen
// Haken, Handschrift. Die Ränder sind für jeden Text etwas anders (aus dem Text abgeleitet, also stabil – kein Flackern).
// Beim Erscheinen wird der Rahmen kurz „gezeichnet".

/// Die Blase sieht immer gleich aus (leichtes Creme, schwarze Tusche) – auch wenn Rüdiger genervt ist oder schnurrt.
/// Die Stimmung steckt allein im Text. (Die Fälle bleiben, weil die Aufrufer sie weiterhin mitgeben.)
enum CatBubbleStyle {
    case normal
    case angry
    case purr

    var fill: Color { Color(red: 0.988, green: 0.973, blue: 0.933) }
    var ink: Color { Color(red: 0.10, green: 0.094, blue: 0.082) }
    var textColor: Color { Color(red: 0.10, green: 0.094, blue: 0.082) }
    var passes: Int { 2 }
    var lineScale: CGFloat { 1 }
    var hearts: Bool { false }
}

/// Kleiner fester Zufallsgenerator – gleicher Text, gleiche Ränder.
struct SketchRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    /// 0 … 1
    mutating func next() -> CGFloat {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return CGFloat(Double(z >> 11) / Double(1 << 53))
    }
    /// Beständiger Startwert aus einem Text (nicht `hashValue`, das sich bei jedem Start ändert)
    static func seed(for text: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
        return h
    }
}

/// Wo und wie der Haken sitzt: an der Kante, die zur Katze zeigt.
struct SketchTail {
    let baseA: CGPoint
    let baseB: CGPoint
    let tip: CGPoint
    /// Richtung ins Innere der Blase (Einheitsvektor) – deckt die Rahmenlinie am Ansatz zu
    let inward: CGVector

    init(body: CGRect, tail: CGPoint) {
        let dx = tail.x - body.midX, dy = tail.y - body.midY
        let corner: CGFloat = 14
        let span: CGFloat = 34
        if abs(dx) / max(body.width, 1) > abs(dy) / max(body.height, 1) {
            // links oder rechts heraus
            let x = dx > 0 ? body.maxX : body.minX
            let a = min(max(tail.y, body.minY + corner), body.maxY - corner)
            let dir: CGFloat = tail.y <= body.midY ? 1 : -1
            let b = min(max(a + dir * span, body.minY + corner), body.maxY - corner)
            baseA = CGPoint(x: x, y: a); baseB = CGPoint(x: x, y: b)
            inward = CGVector(dx: dx > 0 ? -1 : 1, dy: 0)
        } else {
            let y = dy > 0 ? body.maxY : body.minY
            let a = min(max(tail.x, body.minX + corner), body.maxX - corner)
            let dir: CGFloat = tail.x <= body.midX ? 1 : -1
            let b = min(max(a + dir * span, body.minX + corner), body.maxX - corner)
            baseA = CGPoint(x: a, y: y); baseB = CGPoint(x: b, y: y)
            inward = CGVector(dx: 0, dy: dy > 0 ? -1 : 1)
        }
        tip = tail
    }

    private func pushed(_ p: CGPoint, by d: CGFloat) -> CGPoint {
        CGPoint(x: p.x + inward.dx * d, y: p.y + inward.dy * d)
    }

    /// Gefülltes Dreieck (ragt 3 pt in die Blase und deckt dort den Rahmen)
    var cover: Path {
        var p = Path()
        p.move(to: baseA)
        p.addLine(to: tip)
        p.addLine(to: baseB)
        p.addLine(to: pushed(baseB, by: 3))
        p.addLine(to: pushed(baseA, by: 3))
        p.closeSubpath()
        return p
    }
    var outline: Path {
        var p = Path()
        p.move(to: baseA)
        p.addLine(to: tip)
        p.addLine(to: baseB)
        return p
    }
    /// Kräftigere Innenkante (wie in der Vorlage)
    var heavy: Path {
        var p = Path()
        p.move(to: tip)
        p.addLine(to: baseB)
        return p
    }
}

/// Wackeliges, leicht verrutschtes Rechteck – jeder Durchgang etwas anders.
struct SketchBodyShape: Shape {
    let body: CGRect
    let pass: Int
    let seed: UInt64
    let jitter: CGFloat

    func path(in rect: CGRect) -> Path {
        var rng = SketchRandom(seed: seed &+ UInt64(pass + 1) &* 7919)
        let ox = pass == 0 ? 0 : (rng.next() - 0.5) * 3
        let oy = pass == 0 ? 0 : (rng.next() - 0.5) * 3
        let r: CGFloat = 10
        var points: [CGPoint] = []
        func edge(_ a: CGPoint, _ b: CGPoint, _ n: Int) {
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n)
                points.append(CGPoint(x: a.x + (b.x - a.x) * t + (rng.next() - 0.5) * jitter + ox,
                                      y: a.y + (b.y - a.y) * t + (rng.next() - 0.5) * jitter + oy))
            }
        }
        let b = body
        edge(CGPoint(x: b.minX + r, y: b.minY), CGPoint(x: b.maxX - r, y: b.minY), 9)
        edge(CGPoint(x: b.maxX, y: b.minY + r), CGPoint(x: b.maxX, y: b.maxY - r), 6)
        edge(CGPoint(x: b.maxX - r, y: b.maxY), CGPoint(x: b.minX + r, y: b.maxY), 9)
        edge(CGPoint(x: b.minX, y: b.maxY - r), CGPoint(x: b.minX, y: b.minY + r), 6)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 1...points.count {
            let current = points[i % points.count], previous = points[i - 1]
            path.addQuadCurve(to: CGPoint(x: (current.x + previous.x) / 2, y: (current.y + previous.y) / 2),
                              control: previous)
        }
        path.closeSubpath()
        return path
    }
}

/// Schraffur in der Ecke neben dem Haken
struct SketchHatchShape: Shape {
    let body: CGRect
    let tip: CGPoint
    let seed: UInt64

    var corner: (point: CGPoint, sx: CGFloat, vy: CGFloat) {
        let left = tip.x <= body.midX, top = tip.y <= body.midY
        return (CGPoint(x: left ? body.minX : body.maxX, y: top ? body.minY : body.maxY), left ? 1 : -1, top ? 1 : -1)
    }

    func path(in rect: CGRect) -> Path {
        var rng = SketchRandom(seed: seed &+ 4242)
        let c = corner
        var path = Path()
        let n = 11
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            let x = c.point.x + c.sx * (8 + t * 58)
            let y = c.point.y + c.vy * 6
            let base: CGFloat = i < 3 ? CGFloat(6 + i * 4) : (i > n - 4 ? 7 : 18)
            let length = base * (0.7 + rng.next() * 0.5)
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + c.sx * length * 0.62, y: y + c.vy * length * 0.9))
        }
        return path
    }
}

/// Die ganze Blase: Rahmen, Haken, Schraffur und Text. `body` und `tail` in den Koordinaten der Ansicht.
struct SketchBubbleView: View {
    let text: String
    let style: CatBubbleStyle
    let body_: CGRect
    let tail: CGPoint
    let size: CGSize
    let fontSize: CGFloat
    let textSize: CGSize
    /// Rahmen beim Erscheinen „zeichnen"
    var drawIn = true

    @State private var drawn: CGFloat
    @State private var tailDrawn: CGFloat
    @State private var inked: Double

    init(text: String, style: CatBubbleStyle, body: CGRect, tail: CGPoint, size: CGSize,
         fontSize: CGFloat, textSize: CGSize, drawIn: Bool = true) {
        self.text = text; self.style = style; self.body_ = body; self.tail = tail; self.size = size
        self.fontSize = fontSize; self.textSize = textSize; self.drawIn = drawIn
        _drawn = State(initialValue: drawIn ? 0 : 1)
        _tailDrawn = State(initialValue: drawIn ? 0 : 1)
        _inked = State(initialValue: drawIn ? 0 : 1)
    }

    var body: some View {
        let seed = SketchRandom.seed(for: text)
        let geometry = SketchTail(body: body_, tail: tail)
        let line = 1.5 * style.lineScale
        ZStack(alignment: .topLeading) {
            // Fläche
            SketchBodyShape(body: body_, pass: 0, seed: seed, jitter: 1.2).fill(style.fill).opacity(Double(min(1, drawn * 3)))
            ForEach(0..<style.passes, id: \.self) { pass in
                SketchBodyShape(body: body_, pass: pass, seed: seed, jitter: 2.6)
                    .trim(from: 0, to: drawn)
                    .stroke(style.ink.opacity(pass == 0 ? 1 : 0.85),
                            style: StrokeStyle(lineWidth: [2.6, 1.6, 1.3][pass] * style.lineScale,
                                               lineCap: .round, lineJoin: .round))
            }
            // Haken
            geometry.cover.fill(style.fill).opacity(Double(min(1, drawn * 3)))
            geometry.outline.trim(from: 0, to: tailDrawn)
                .stroke(style.ink, style: StrokeStyle(lineWidth: 2.4 * style.lineScale, lineCap: .round, lineJoin: .round))
            geometry.heavy.trim(from: 0, to: tailDrawn)
                .stroke(style.ink, style: StrokeStyle(lineWidth: 3.2 * style.lineScale, lineCap: .round))
            // Schraffur oder Herzchen
            if style.hearts {
                let hatch = SketchHatchShape(body: body_, tip: tail, seed: seed).corner
                ForEach(0..<4, id: \.self) { i in
                    Text("♥")
                        .font(.system(size: CGFloat(12 - i)))
                        .foregroundColor(style.ink.opacity(0.9 - Double(i) * 0.18))
                        .position(x: hatch.point.x + hatch.sx * CGFloat(14 + i * 13),
                                  y: hatch.point.y + hatch.vy * CGFloat(14 + i * 8))
                        .opacity(inked)
                }
            } else {
                SketchHatchShape(body: body_, tip: tail, seed: seed)
                    .stroke(style.ink.opacity(0.92), style: StrokeStyle(lineWidth: line * 1.1, lineCap: .round))
                    .opacity(inked)
            }
            Text(text)
                .font(Font(CatBubbleView.font(fontSize) as CTFont))
                .foregroundColor(style.textColor)
                .multilineTextAlignment(.center)
                .lineSpacing(CatBubbleLayout.lineSpacing)
                // Falls SwiftUI doch etwas anders umbricht: lieber kleiner als abgeschnitten
                .minimumScaleFactor(0.6)
                .frame(width: textSize.width, height: textSize.height)
                .position(x: body_.midX, y: body_.midY)
                .opacity(inked)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
        .onAppear {
            guard drawIn else { return }
            withAnimation(.easeOut(duration: 0.34)) { drawn = 1 }
            withAnimation(.easeOut(duration: 0.14).delay(0.26)) { tailDrawn = 1 }
            withAnimation(.easeOut(duration: 0.18).delay(0.24)) { inked = 1 }
        }
    }
}

/// Ansicht der Sprechblase über der Leiste (Fenster von `CatBubbleController`)
struct CatBubbleView: View {
    let text: String
    let style: CatBubbleStyle
    let body_: CGRect
    let tail: CGPoint
    let size: CGSize
    let fontSize: CGFloat
    let textSize: CGSize

    /// Handschrift, die auf jedem Mac vorhanden ist (Bradley Hand → Noteworthy → Marker Felt → Systemschrift)
    static func font(_ size: CGFloat) -> NSFont {
        for name in ["BradleyHandITCTT-Bold", "Noteworthy-Bold", "MarkerFelt-Thin"] {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.systemFont(ofSize: size, weight: .medium)
    }

    var body: some View {
        SketchBubbleView(text: text, style: style, body: body_, tail: tail, size: size,
                         fontSize: fontSize, textSize: textSize)
    }
}

/// Größe der Blase so, dass der Text immer ganz drin steht (mit Luft für Rahmen und Schraffur).
/// Ist die Blase zu groß für den Bildschirm, wird die Schrift kleiner (bis 12 pt) bzw. der Text breiter umbrochen.
struct CatBubbleLayout {
    static let lineSpacing: CGFloat = 1
    static let padX: CGFloat = 26
    static let padY: CGFloat = 24
    let fontSize: CGFloat
    let textSize: CGSize
    let bubbleSize: CGSize

    static func make(_ text: String, style: CatBubbleStyle, maxSize: CGSize) -> CatBubbleLayout {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = .center
        var best: CatBubbleLayout?
        for fontSize in stride(from: CGFloat(17), through: 12, by: -1) {
            for wrap in [CGFloat(220), 280, 340] {
                let measured = (text as NSString).boundingRect(
                    with: CGSize(width: wrap, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: CatBubbleView.font(fontSize), .paragraphStyle: paragraph])
                // etwas Reserve, weil SwiftUI minimal anders setzt als AppKit
                let tw = ceil(measured.width) + 8
                let th = ceil(measured.height) + 6
                let bw = max(130, tw + 2 * padX)
                let bh = max(58, th + 2 * padY)
                let layout = CatBubbleLayout(fontSize: fontSize, textSize: CGSize(width: tw, height: th),
                                             bubbleSize: CGSize(width: bw, height: bh))
                if bw <= maxSize.width && bh <= maxSize.height { return layout }
                if best == nil || bw * bh < best!.bubbleSize.width * best!.bubbleSize.height { best = layout }
            }
        }
        // Sehr langer Text: kleinste Variante (minimumScaleFactor in der Ansicht hilft notfalls weiter)
        return best!
    }
}
