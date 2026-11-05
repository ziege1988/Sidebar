import AppKit
import SwiftUI

/// Glas-Effekt: Unschärfe des Hintergrunds, darüber die Farbe der Sidebar.
/// Auch bei voller Stärke bleibt die Farbe erkennbar (mindestens 25 % deckend).
enum Glass {
    /// Deckkraft der Farbschicht für eine Glas-Stärke (0 … 1)
    static func tintOpacity(_ intensity: Double) -> Double {
        1 - 0.75 * min(max(intensity, 0), 1)
    }

    /// Helligkeit des Glasrands
    static func rimStrength(_ intensity: Double) -> Double {
        0.3 + 0.7 * min(max(intensity, 0), 1)
    }

    /// Anteil der Unschärfe: macOS erlaubt keine einstellbare Unschärfe-Stärke. Deshalb wird
    /// die unscharfe Schicht nur teilweise eingeblendet – der Hintergrund bleibt so leicht
    /// unscharf und mit steigender Intensität immer besser erkennbar.
    static func blurOpacity(_ intensity: Double) -> Double {
        0.62 - 0.27 * min(max(intensity, 0), 1)
    }
}

/// Unscharfer macOS-Hintergrund, auf eine Form zugeschnitten (sonst würden die Ecken als Rechteck durchscheinen).
struct VisualEffectBackground: NSViewRepresentable {
    var mask: AnyShape? = nil
    var opacity: Double = 1

    func makeNSView(context: Context) -> MaskedEffectView {
        let view = MaskedEffectView()
        view.material = .popover // passt sich hell/dunkel an und ist gut durchscheinend
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskShape = mask
        view.alphaValue = CGFloat(opacity)
        return view
    }

    func updateNSView(_ view: MaskedEffectView, context: Context) {
        view.maskShape = mask
        view.alphaValue = CGFloat(opacity)
        view.needsLayout = true
    }
}

final class MaskedEffectView: NSVisualEffectView {
    var maskShape: AnyShape?
    private var lastMaskSize: CGSize = .zero

    override func layout() {
        super.layout()
        guard let maskShape, bounds.width > 0, bounds.height > 0 else {
            maskImage = nil
            return
        }
        guard bounds.size != lastMaskSize || maskImage == nil else { return }
        lastMaskSize = bounds.size
        let path = maskShape.path(in: CGRect(origin: .zero, size: bounds.size)).cgPath
        maskImage = NSImage(size: bounds.size, flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(cgPath: path).fill()
            return true
        }
    }
}

/// Hintergrund mit Glas: unscharfer Schreibtisch + Farbe der Sidebar.
struct GlassFill: View {
    let fill: LinearGradient
    let intensity: Double
    var mask: AnyShape? = nil

    var body: some View {
        ZStack {
            if intensity > 0 {
                VisualEffectBackground(mask: mask, opacity: Glass.blurOpacity(intensity))
            }
            Rectangle()
                .fill(fill)
                .opacity(Glass.tintOpacity(intensity))
            if intensity > 0 {
                // leichter Schimmer von oben, wie eine Glasscheibe
                LinearGradient(colors: [Color.white.opacity(0.16 * intensity), .clear],
                               startPoint: .top, endPoint: .center)
            }
        }
    }
}

/// Glaskante: feine dunkle Kontur, helle Lichtkante und ein weiches Leuchten nach innen.
struct GlassRim<S: Shape>: View {
    let shape: S
    let intensity: Double
    /// Fläche, auf die das innere Leuchten begrenzt wird (bei offenem Umriss die ganze Sidebar)
    var clip: AnyShape? = nil

    var body: some View {
        let k = Glass.rimStrength(intensity)
        ZStack {
            shape.stroke(Color.black.opacity(0.14 * k), lineWidth: 1)
            shape.stroke(Color.white.opacity(0.32 * k), lineWidth: 7)
                .blur(radius: 4)
                .clipShape(clip ?? AnyShape(shape))
            shape.stroke(LinearGradient(colors: [Color.white.opacity(0.9 * k), Color.white.opacity(0.3 * k)],
                                        startPoint: .top, endPoint: .bottom),
                         lineWidth: 1)
                .padding(0.5)
        }
        .allowsHitTesting(false)
    }
}

/// Gemeinsamer Umriss von Uhr und Leiste: ein Stück, mit weich gerundetem Übergang („Schulter“).
/// Gerechnet wird für die linke Kante und dann für die anderen Kanten gespiegelt/gedreht.
struct SidebarOutline: Shape {
    let edge: ScreenEdge
    /// Breite der Leiste (quer zur Kante)
    let barCross: CGFloat
    /// Ausdehnung der Uhr quer zur Kante (0 = keine Uhr)
    let clockCross: CGFloat
    /// Ausdehnung der Uhr entlang der Kante
    let clockAlong: CGFloat
    var barRadius: CGFloat = 14
    var clockRadius: CGFloat = 16
    /// `false`: Umriss ohne die Seite am Bildschirmrand (für den Glasrand)
    var closed = true

    func path(in rect: CGRect) -> Path {
        let length = edge.isVertical ? rect.height : rect.width

        func map(_ c: CGFloat, _ a: CGFloat) -> CGPoint {
            switch edge {
            case .left: return CGPoint(x: c, y: a)
            case .right: return CGPoint(x: rect.width - c, y: a)
            case .top: return CGPoint(x: a, y: c)
            case .bottom: return CGPoint(x: a, y: rect.height - c)
            }
        }

        var path = Path()
        let t = barCross
        let r = min(barRadius, t / 2)
        // Offener Umriss (Glasrand): nur die Seiten zum Bildschirminneren –
        // ohne Bildschirmkante und ohne die Enden oben/unten am Bildschirmrand.
        func start(at point: CGPoint) {
            if closed {
                path.move(to: map(0, 0))
                path.addLine(to: point)
            } else {
                path.move(to: point)
            }
        }
        if clockCross > t + 1 && clockAlong > 0 {
            let cw = clockCross
            let cl = min(clockAlong, length)
            let rc = min(clockRadius, cw / 2, cl / 2)
            let fillet = min(10, (cw - t) / 2)
            start(at: map(cw - rc, 0))
            path.addArc(tangent1End: map(cw, 0), tangent2End: map(cw, rc), radius: rc)
            path.addLine(to: map(cw, cl - rc))
            path.addArc(tangent1End: map(cw, cl), tangent2End: map(cw - rc, cl), radius: rc)
            path.addLine(to: map(t + fillet, cl))
            // weicher, nach innen gewölbter Übergang von der Uhr in die Leiste
            path.addArc(tangent1End: map(t, cl), tangent2End: map(t, cl + fillet), radius: fillet)
        } else {
            start(at: map(t - r, 0))
            path.addArc(tangent1End: map(t, 0), tangent2End: map(t, r), radius: r)
        }
        path.addLine(to: map(t, length - r))
        path.addArc(tangent1End: map(t, length), tangent2End: map(t - r, length), radius: r)
        if closed {
            path.addLine(to: map(0, length))
            path.closeSubpath()
        }
        return path
    }
}
