import AppKit
import SwiftUI

/// Gedeckte, leicht unterschiedliche Farbtöne für die Notiz-Kacheln (keine knalligen Farben).
enum NoteTint {
    static let light: [UInt32] = [0xF6F0DC, 0xE3EBDD, 0xDFE8F1, 0xF3E3E3, 0xE7E3F2, 0xEFE7DA]
    static let dark: [UInt32] = [0x3B382F, 0x323A31, 0x2F3640, 0x3D3233, 0x36334A, 0x3A352D]
    static var count: Int { light.count }

    static func color(_ index: Int?, scheme: ColorScheme) -> Color {
        let list = scheme == .dark ? dark : light
        return Color(hex: list[((index ?? 0) % count + count) % count])
    }
}

/// Textfarben für Notizen (gedeckt, gut lesbar).
enum NoteTextColor: CaseIterable, Identifiable {
    case standard, red, blue, green, gold
    var id: Self { self }

    var title: String {
        switch self {
        case .standard: return "Standardfarbe"
        case .red: return "Rot"
        case .blue: return "Blau"
        case .green: return "Grün"
        case .gold: return "Gold"
        }
    }

    var nsColor: NSColor? {
        switch self {
        case .standard: return nil
        case .red: return NSColor(srgbRed: 0.75, green: 0.27, blue: 0.25, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.22, green: 0.43, blue: 0.70, alpha: 1)
        case .green: return NSColor(srgbRed: 0.27, green: 0.52, blue: 0.29, alpha: 1)
        case .gold: return NSColor(srgbRed: 0.69, green: 0.54, blue: 0.18, alpha: 1)
        }
    }

    var swatch: Color {
        if let nsColor { return Color(nsColor: nsColor) }
        return Color.primary
    }
}

/// Formatierung für die gerade bearbeitete Notiz (Knöpfe in der Werkzeugleiste und ⌘B/⌘I/⌘U).
@MainActor
enum NoteFormatting {
    /// Neongelber Textmarker
    static let highlighter = NSColor(srgbRed: 0.93, green: 1.0, blue: 0.24, alpha: 0.95)
    /// Textfarbe auf dem Textmarker (gut lesbar, auch im Dunkelmodus)
    static let highlighterText = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.08, alpha: 1)

    weak static var activeTextView: NSTextView?

    static func toggleBold() { if let tv = activeTextView { toggleTrait(.boldFontMask, in: tv) } }
    static func toggleItalic() { if let tv = activeTextView { toggleTrait(.italicFontMask, in: tv) } }
    static func toggleUnderline() { if let tv = activeTextView { toggleUnderline(in: tv) } }
    static func toggleHighlight() { if let tv = activeTextView { toggleHighlight(in: tv) } }

    static func setColor(_ color: NoteTextColor) {
        guard let tv = activeTextView else { return }
        apply(tv, change: { storage, range in
            if let ns = color.nsColor {
                storage.addAttribute(.foregroundColor, value: ns, range: range)
            } else {
                storage.removeAttribute(.foregroundColor, range: range)
            }
        }, typing: { attrs in
            attrs[.foregroundColor] = color.nsColor ?? NSColor.labelColor
        })
    }

    static func toggleTrait(_ trait: NSFontTraitMask, in tv: NSTextView) {
        let manager = NSFontManager.shared
        let range = tv.selectedRange()
        let fallback = NSFont.systemFont(ofSize: 13)
        var allHave = true
        if range.length > 0, let storage = tv.textStorage {
            storage.enumerateAttribute(.font, in: range) { value, _, _ in
                let font = (value as? NSFont) ?? fallback
                if !manager.traits(of: font).contains(trait) { allHave = false }
            }
        } else {
            let font = (tv.typingAttributes[.font] as? NSFont) ?? fallback
            allHave = manager.traits(of: font).contains(trait)
        }
        func convert(_ font: NSFont) -> NSFont {
            allHave ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
        }
        apply(tv, change: { storage, range in
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                storage.addAttribute(.font, value: convert((value as? NSFont) ?? fallback), range: subrange)
            }
        }, typing: { attrs in
            attrs[.font] = convert((attrs[.font] as? NSFont) ?? fallback)
        })
    }

    static func toggleUnderline(in tv: NSTextView) {
        let range = tv.selectedRange()
        var allHave = true
        if range.length > 0, let storage = tv.textStorage {
            storage.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
                if ((value as? Int) ?? 0) == 0 { allHave = false }
            }
        } else {
            allHave = ((tv.typingAttributes[.underlineStyle] as? Int) ?? 0) != 0
        }
        apply(tv, change: { storage, range in
            if allHave {
                storage.removeAttribute(.underlineStyle, range: range)
            } else {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }, typing: { attrs in
            attrs[.underlineStyle] = allHave ? 0 : NSUnderlineStyle.single.rawValue
        })
    }

    static func toggleHighlight(in tv: NSTextView) {
        let range = tv.selectedRange()
        var allHave = true
        if range.length > 0, let storage = tv.textStorage {
            storage.enumerateAttribute(.backgroundColor, in: range) { value, _, _ in
                if value == nil { allHave = false }
            }
        } else {
            allHave = tv.typingAttributes[.backgroundColor] != nil
        }
        apply(tv, change: { storage, range in
            if allHave {
                storage.removeAttribute(.backgroundColor, range: range)
                storage.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
                    if let color = value as? NSColor, color == highlighterText {
                        storage.removeAttribute(.foregroundColor, range: subrange)
                    }
                }
            } else {
                storage.addAttribute(.backgroundColor, value: highlighter, range: range)
                storage.addAttribute(.foregroundColor, value: highlighterText, range: range)
            }
        }, typing: { attrs in
            if allHave {
                attrs[.backgroundColor] = nil
                attrs[.foregroundColor] = NSColor.labelColor
            } else {
                attrs[.backgroundColor] = highlighter
                attrs[.foregroundColor] = highlighterText
            }
        })
    }

    /// Auf die Auswahl anwenden – oder ohne Auswahl auf das, was als Nächstes getippt wird.
    private static func apply(_ tv: NSTextView,
                              change: (NSTextStorage, NSRange) -> Void,
                              typing: (inout [NSAttributedString.Key: Any]) -> Void) {
        let range = tv.selectedRange()
        guard range.length > 0 else {
            var attrs = tv.typingAttributes
            typing(&attrs)
            tv.typingAttributes = attrs
            return
        }
        guard let storage = tv.textStorage, tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        change(storage, range)
        storage.endEditing()
        tv.didChangeText()
    }
}

/// Textfeld einer Notiz-Kachel mit ⌘B, ⌘I, ⌘U.
final class NoteTextView: NSTextView {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { NoteFormatting.activeTextView = self }
        return accepted
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "b": NoteFormatting.toggleTrait(.boldFontMask, in: self); return true
        case "i": NoteFormatting.toggleTrait(.italicFontMask, in: self); return true
        case "u": NoteFormatting.toggleUnderline(in: self); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

/// Formatierbarer Text einer Notiz (speichert RTF und reinen Text).
struct RichTextEditor: NSViewRepresentable {
    let initialText: String
    let initialRTF: Data?
    var focusOnAppear = false
    let onChange: @MainActor (_ plain: String, _ rtf: Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        // Notizen liegen auf hellem Papier: Text immer dunkel, auch im Dunkelmodus
        scroll.appearance = NSAppearance(named: .aqua)

        let textView = NoteTextView(frame: .zero)
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]

        if let initialRTF, let attributed = NSAttributedString(rtf: initialRTF, documentAttributes: nil) {
            let fixed = NSMutableAttributedString(attributedString: attributed)
            Self.dropPaleInk(fixed)
            textView.textStorage?.setAttributedString(fixed)
        } else {
            textView.string = initialText
        }
        textView.delegate = context.coordinator
        scroll.documentView = textView

        if focusOnAppear {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
    }

    /// Ältere Notizen, die im Dunkelmodus gespeichert wurden, haben weiße Schrift – auf Papier unlesbar. Die
    /// „Standardfarbe" (fast weiß, kaum Farbe, ohne Textmarker) wird entfernt, dann gilt wieder dunkle Tinte.
    static func dropPaleInk(_ text: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            guard let color = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            let pale = color.brightnessComponent > 0.78 && color.saturationComponent < 0.25
            if pale, text.attribute(.backgroundColor, at: range.location, effectiveRange: nil) == nil {
                text.removeAttribute(.foregroundColor, range: range)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: @MainActor (String, Data?) -> Void

        init(onChange: @escaping @MainActor (String, Data?) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = NSRange(location: 0, length: (textView.string as NSString).length)
            // Mit hellem Erscheinungsbild speichern, damit „Standardfarbe" nicht als Weiß im RTF landet
            var rtf: Data?
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { rtf = textView.rtf(from: range) }
            let plain = textView.string
            MainActor.assumeIsolated { onChange(plain, rtf) }
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            MainActor.assumeIsolated { NoteFormatting.activeTextView = textView }
        }
    }
}
