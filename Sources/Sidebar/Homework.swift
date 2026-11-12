import AppKit
import Combine
import NaturalLanguage
import SwiftUI

// MARK: - Rüdiger als Lehrer
//
// Ein Blatt mit Linien, Rüdiger sitzt an der oberen Ecke. Nach „Abgeben“ setzt er den Rotstift an:
// Wellenlinien unter Fehlern, fehlende Zeichen am Rand, R/Z/Gr am Rand und eine Note. Verbessern musst du
// selbst – jeder behobene Fehler verliert sofort sein Rot. Kopieren geht erst, wenn alles stimmt.
// ✕ verwirft alles; „Zur Schnellnotiz“ legt den Text in die Schnellnotizen.
// Geprüft wird lokal: Rechtschreibung/Grammatik von macOS plus eigene Regeln für typische deutsche Fehler.

// MARK: Farben (dezent, entsättigt)

enum HomeworkStyle {
    static let red = Color(red: 0.66, green: 0.38, blue: 0.35)
    static let green = Color(red: 0.44, green: 0.54, blue: 0.41)
    static let ink = Color(red: 0.23, green: 0.24, blue: 0.25)
    static let nsRed = NSColor(srgbRed: 0.66, green: 0.38, blue: 0.35, alpha: 0.85)
    static let nsInk = NSColor(srgbRed: 0.23, green: 0.24, blue: 0.25, alpha: 1)
    static let nsLine = NSColor(srgbRed: 0.84, green: 0.87, blue: 0.89, alpha: 1)
    static let nsMargin = NSColor(srgbRed: 0.78, green: 0.55, blue: 0.53, alpha: 0.45)

    static func hand(_ size: CGFloat) -> NSFont {
        NSFont(name: "Noteworthy-Bold", size: size) ?? NSFont(name: "ChalkboardSE-Bold", size: size)
            ?? NSFont.boldSystemFont(ofSize: size)
    }
}

// MARK: - Fehler

struct HomeworkMark: Identifiable {
    enum Kind: Equatable {
        /// Wellenlinie unter dem Bereich
        case wavy
        /// fehlendes Zeichen hinter dem Bereich (z. B. Komma)
        case insert(String)
    }

    let id = UUID()
    let range: NSRange
    let kind: Kind
    /// Randzeichen: R (Rechtschreibung), Z (Zeichensetzung), Gr (Grammatik)
    let symbol: String
    /// Tipp beim Klick – nie die Lösung
    let tip: String
    /// zum Ignorieren („Stimmt so“)
    let key: String

    var weight: Double { symbol == "Z" ? 0.5 : 1 }
}

enum HomeworkChecker {
    static let spellTag = NSSpellChecker.uniqueSpellDocumentTag()

    static func language(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .english ? "en" : "de"
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.filter { $0.contains(where: \.isLetter) }.count
    }

    static func check(_ text: String, language: String, ignored: Set<String>) -> [HomeworkMark] {
        let ns = text as NSString
        var marks: [HomeworkMark] = []

        func add(_ range: NSRange, _ kind: HomeworkMark.Kind, _ symbol: String, _ tip: String, rule: String) {
            guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= ns.length else { return }
            let key = rule + "|" + ns.substring(with: range).lowercased()
            guard !ignored.contains(key) else { return }
            // Überschneidungen: der erste Fund gewinnt
            if marks.contains(where: { NSIntersectionRange($0.range, range).length > 0 && $0.kind == kind }) { return }
            marks.append(HomeworkMark(range: range, kind: kind, symbol: symbol, tip: tip, key: key))
        }

        // Eigene Regeln (zuerst – ihre Tipps sind genauer)
        for rule in rules(for: language) {
            rule.apply(text, add)
        }

        // Rechtschreibung von macOS
        let checker = NSSpellChecker.shared
        var start = 0
        while start < ns.length {
            let r = checker.checkSpelling(of: text, startingAt: start, language: language, wrap: false,
                                          inSpellDocumentWithTag: spellTag, wordCount: nil)
            guard r.location != NSNotFound, r.length > 0, r.location >= start else { break }
            add(r, .wavy, "R", "Schau dir dieses Wort noch mal genau an – Buchstabe für Buchstabe.", rule: "spell")
            start = NSMaxRange(r)
        }

        // Grammatik von macOS (Englisch ordentlich, Deutsch eher dünn)
        start = 0
        while start < ns.length {
            var details: NSArray?
            let sentence = checker.checkGrammar(of: text, startingAt: start, language: language, wrap: false,
                                                inSpellDocumentWithTag: spellTag, details: &details)
            guard sentence.location != NSNotFound, sentence.length > 0, sentence.location >= start else { break }
            for case let detail as [String: Any] in (details as? [Any]) ?? [] {
                guard let value = detail["NSGrammarRange"] as? NSValue else { continue }
                var r = value.rangeValue
                // Bereich zählt ab Satzanfang
                if NSMaxRange(r) <= sentence.length { r.location += sentence.location }
                let description = (detail["NSGrammarUserDescription"] as? String).map { "Hinweis: \($0)" }
                add(r, .wavy, "Gr", description ?? "Stimmt der Satzbau hier?", rule: "grammar")
            }
            start = NSMaxRange(sentence)
        }

        return marks.sorted { $0.range.location < $1.range.location }
    }

    // MARK: Eigene Regeln

    private struct Rule {
        let pattern: NSRegularExpression?
        let handle: (NSTextCheckingResult, NSString, (NSRange, HomeworkMark.Kind, String, String, String) -> Void) -> Void

        init(_ pattern: String, options: NSRegularExpression.Options = [],
             _ handle: @escaping (NSTextCheckingResult, NSString, (NSRange, HomeworkMark.Kind, String, String, String) -> Void) -> Void) {
            self.pattern = try? NSRegularExpression(pattern: pattern, options: options)
            self.handle = handle
        }

        func apply(_ text: String, _ add: (NSRange, HomeworkMark.Kind, String, String, String) -> Void) {
            guard let pattern else { return }
            let ns = text as NSString
            for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                handle(match, ns, add)
            }
        }
    }

    private static let abbreviations: Set<String> = [
        "z", "b", "ca", "bzw", "usw", "etc", "vgl", "ggf", "evtl", "nr", "str", "tel", "inkl", "zzgl", "u", "a", "d",
        "h", "s", "dr", "prof", "mr", "mrs", "ms", "e", "g", "i", "vs", "bspw", "max", "min", "jan", "feb", "mrz",
        "apr", "jun", "jul", "aug", "sep", "sept", "okt", "nov", "dez",
    ]

    /// Wort vor der Stelle (ohne Satzzeichen)
    private static func word(before location: Int, in ns: NSString) -> (String, NSRange)? {
        var end = location
        while end > 0, let scalar = UnicodeScalar(ns.character(at: end - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.punctuationCharacters.contains(scalar) {
            end -= 1
        }
        var begin = end
        while begin > 0, let scalar = UnicodeScalar(ns.character(at: begin - 1)),
              CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
            begin -= 1
        }
        guard end > begin else { return nil }
        let range = NSRange(location: begin, length: end - begin)
        return (ns.substring(with: range), range)
    }

    private static func rules(for language: String) -> [Rule] {
        var list: [Rule] = []

        // Satzanfang klein
        list.append(Rule(#"(?:\A\s*|[.!?]\s+)(\p{Ll}[\p{L}]*)"#) { m, ns, add in
            let r = m.range(at: 1)
            if r.location > 0, m.range.location > 0 {
                // Abkürzung oder Ordnungszahl davor („z. B. ein“, „am 3. november“) → kein Satzanfang
                if case let (prev, _)? = HomeworkChecker.word(before: m.range.location + 1, in: ns) {
                    if HomeworkChecker.abbreviations.contains(prev.lowercased()) || prev.allSatisfy(\.isNumber) { return }
                }
            }
            add(r, .wavy, "R", "Satzanfang – groß oder klein?", "start")
        })

        // Leerzeichen vor Satzzeichen, fehlendes nach dem Komma, doppelte Leerzeichen
        list.append(Rule(#"[ \t]+([,.!?;:])"#) { m, _, add in
            add(m.range, .wavy, "Z", "Schau mal zwischen Wort und Satzzeichen.", "spacebefore")
        })
        list.append(Rule(#",(\p{L})"#) { m, _, add in
            add(NSRange(location: m.range.location, length: 1), .wavy, "Z", "Nach dem Komma fehlt etwas.", "spaceafter")
        })
        list.append(Rule(#"(?<=\S) {2,}(?=\S)"#) { m, _, add in
            add(m.range, .wavy, "Z", "Hier ist es etwas zu luftig.", "doublespace")
        })

        // Wort doppelt
        list.append(Rule(#"\b(\p{L}+)\s+\1\b"#, options: [.caseInsensitive]) { m, _, add in
            add(m.range, .wavy, "Gr", "Doppelt gemoppelt?", "double")
        })

        if language == "en" {
            list.append(Rule(#"\bi\b"#) { m, _, add in
                add(m.range, .wavy, "R", "Wie schreibt man „ich“ auf Englisch?", "en-i")
            })
            return list
        }

        // Nomen nach Grußformeln klein („vielen dank“, „liebe grüße“)
        list.append(Rule(#"\b(?:vielen|herzlichen|besten|lieben|schönen|schöne|liebe|beste|freundliche|freundlichen|herzliche|einen schönen|ein schönes)\s+(dank|gruß|grüße|grüßen|abend|tag|wochenende|start|feierabend|urlaub)\b"#,
                         options: [.caseInsensitive]) { m, ns, add in
            let r = m.range(at: 1)
            guard let first = ns.substring(with: r).first, first.isLowercase else { return }
            add(r, .wavy, "R", "Was für ein Wort ist das? Nomen haben eine Besonderheit …", "noun")
        })

        // Zeitangaben groß („bis Morgen“)
        list.append(Rule(#"\b(?:bis|ab|für|seit)\s+(Morgen|Übermorgen|Gestern|Vorgestern|Heute)\b(?!\s+(?:früh|Früh))"#) { m, _, add in
            add(m.range(at: 1), .wavy, "R", "Zeitangabe – groß oder klein?", "time")
        })

        // das / dass nach Verben des Sagens/Denkens
        let dassVerbs = "denke|denken|glaube|glauben|hoffe|hoffen|weiß|wissen|finde|finden|meine|meinen|sage|sagen|bitte|sicher|froh|schade|klar|wichtig|möglich|sehe|sehen|zeigt|bedeutet|heißt|erwarte|vermute|befürchte|merke|freue mich|freuen uns|ist gut|bestätige|bestätigen"
        let dassNext = "ich|du|er|sie|es|wir|ihr|Sie|man|die|der|das|den|dem|mein|meine|dein|deine|sein|seine|unser|unsere|euer|eure|Ihr|Ihre|ihre|alles|nichts|jemand|niemand|dies|diese|dieser|morgen|heute|noch|bald"
        list.append(Rule(#"\b(?:\#(dassVerbs))(,?)\s+(das)\s+(?=(?:\#(dassNext))\b)"#) { m, ns, add in
            add(m.range(at: 2), .wavy, "Gr", "das oder dass? Probier mal „dieses“ oder „welches“ einzusetzen.", "dass")
            if m.range(at: 1).length == 0, case let (_, prev)? = HomeworkChecker.word(before: m.range(at: 2).location, in: ns) {
                add(prev, .insert(","), "Z", "Vor einem Nebensatz fehlt etwas.", "comma")
            }
        })

        // Komma vor Nebensätzen
        let skipBefore: Set<String> = ["und", "oder", "als", "so", "auch", "nur", "erst", "sogar", "gerade", "aber",
                                       "doch", "selbst", "wie", "außer", "kurz", "noch", "bzw", "sowie", "je"]
        list.append(Rule(#"(\p{L})[ \t]+(dass|weil|obwohl|sodass|nachdem|sobald|falls|ob|wenn|bevor|sondern)\b"#) { m, ns, add in
            guard case let (prev, prevRange)? = HomeworkChecker.word(before: m.range(at: 2).location, in: ns),
                  !skipBefore.contains(prev.lowercased()) else { return }
            add(prevRange, .insert(","), "Z", "Vor einem Nebensatz fehlt etwas.", "comma")
        })

        // Anrede im Brief (Sie-Form) klein
        let formal = text(matches: #"\b(?:Herr|Frau|Sehr geehrte|Sehr geehrter|Ihnen|Ihre|Ihren|Ihrem)\b"#)
        list.append(Rule(#"\b(ihnen|ihre|ihren|ihrem|ihrer|ihres)\b"#) { m, ns, add in
            guard formal(ns as String) else { return }
            add(m.range, .wavy, "R", "Sprichst du hier jemanden in der Sie-Form an? Dann gilt eine Sonderregel.", "formal")
        })

        return list
    }

    private static func text(matches pattern: String) -> (String) -> Bool {
        let regex = try? NSRegularExpression(pattern: pattern)
        return { text in
            regex?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
        }
    }

    /// Note nach Fehlern pro 100 Wörter (kurze Texte werden nicht übermäßig hart bewertet)
    static func grade(errors: Double, words: Int) -> String {
        let rate = errors * 100 / Double(max(words, 60))
        switch rate {
        case 0: return "1"
        case ..<1: return "1–"
        case ..<2: return "2"
        case ..<3: return "2–"
        case ..<4.5: return "3"
        case ..<6: return "3–"
        case ..<8: return "4"
        case ..<10: return "4–"
        case ..<13: return "5"
        default: return "6"
        }
    }
}

// MARK: - Sprüche des Lehrers

enum HomeworkLines {
    /// 0 lieb, 1 frech, 2 schwarz
    private static func level(_ tone: Int) -> Int { tone == 0 ? 0 : (tone == 3 ? 2 : 1) }

    static func waiting(_ tone: Int) -> String {
        ["Schreib deinen Text oder füg ihn ein (⌘V). Dann auf „Abgeben“.",
         "Text rein (⌘V), dann „Abgeben“. Ich hab den Rotstift schon gespitzt.",
         "Her mit dem Text. Mein Rotstift hat Hunger."][level(tone)]
    }

    static func corrected(_ tone: Int, grade: String, errors: Int) -> String {
        let n = errors == 1 ? "Ein Fehler" : "\(errors) Fehler"
        let g = grade
        if errors == 0 {
            return ["Eine glatte Eins! Ich bin stolz auf dich.",
                    "Eins. Hast du abgeschrieben?",
                    "Eins. Fehlerfrei. Ich bin enttäuscht – ich wollte rot malen."][level(tone)]
        }
        let band = g.hasPrefix("1") || g.hasPrefix("2") || g.hasPrefix("3") ? 0 : (g.hasPrefix("4") ? 1 : 2)
        let lines = [
            ["\(n) – das kriegst du hin. Note \(g).", "Note \(g). \(n). Geht so.", "\(g). \(n). Mittelmaß ist auch eine Kunst."],
            ["Note \(g). \(n) – schau sie dir in Ruhe an.", "\(g). \(n). Bei einigen hab ich kurz geweint.", "\(g). \(n). Mein Rotstift ist jetzt leer. Danke."],
            ["Note \(g). Nicht schlimm – Fehler sind zum Lernen da.", "\(g). \(n). War das Absicht?", "\(g). \(n). Ich ruf deine Eltern an."],
        ]
        return lines[band][level(tone)]
    }

    static func done(_ tone: Int, grade: String) -> String {
        ["Super, alles verbessert! Jetzt kannst du kopieren.",
         "Na also. Geht doch. Eine \(grade) – die Eins gibt's nur beim ersten Versuch.",
         "Verbessert. Hat ja nur ewig gedauert. \(grade)."][level(tone)]
    }

    static func copied(_ tone: Int) -> String {
        ["Kopiert. Viel Erfolg damit!", "Kopiert. Ab damit.", "Kopiert. Jetzt blamier dich woanders."][level(tone)]
    }
}

// MARK: - Zustand

@MainActor
final class HomeworkModel: ObservableObject {
    enum Phase { case writing, corrected, done }

    @Published var phase: Phase = .writing
    @Published var marks: [HomeworkMark] = []
    @Published var firstGrade = ""
    @Published var finalGrade = ""
    @Published var speech: String
    @Published var style: CatBubbleStyle = .normal
    @Published var language = "de"
    /// Blatt ist aufgeklappt (steuert Auf- und Zuklappen)
    @Published var shown = false
    var ignored: Set<String> = []
    weak var textView: TeacherTextView?
    private var recheckWork: DispatchWorkItem?
    let tone: Int

    init(tone: Int) {
        self.tone = tone
        speech = HomeworkLines.waiting(tone)
    }

    var text: String { textView?.string ?? "" }
    var openErrors: Int { marks.count }
    var canCopy: Bool { phase == .done }

    func handIn() {
        let text = self.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            speech = ["Ein leeres Blatt? Mutig.", "Ein leeres Blatt abgeben? Mutig.", "Leeres Blatt. Sechs. Nächster."][tone == 0 ? 0 : (tone == 3 ? 2 : 1)]
            style = .normal
            return
        }
        language = HomeworkChecker.language(of: text)
        let found = HomeworkChecker.check(text, language: language, ignored: ignored)
        let weighted = found.reduce(0) { $0 + $1.weight }
        firstGrade = HomeworkChecker.grade(errors: weighted, words: HomeworkChecker.wordCount(text))
        marks = found
        if found.isEmpty {
            phase = .done
            finalGrade = firstGrade
            style = .purr
        } else {
            phase = .corrected
            style = found.count > 4 ? .angry : .normal
        }
        speech = HomeworkLines.corrected(tone, grade: firstGrade, errors: found.count)
        textView?.showMarks = true
        textView?.marks = marks
    }

    /// Text geändert: nach kurzer Pause neu prüfen (das Rote verschwindet, sobald es stimmt)
    func textChanged() {
        guard phase != .writing else { return }
        recheckWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.recheck() }
        }
        recheckWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func recheck() {
        let found = HomeworkChecker.check(text, language: language, ignored: ignored)
        marks = found
        textView?.marks = found
        if found.isEmpty, phase != .done {
            phase = .done
            finalGrade = firstGrade == "1" ? "1" : (firstGrade.hasPrefix("1") ? "1–" : "2")
            style = .purr
            speech = HomeworkLines.done(tone, grade: finalGrade)
        } else if !found.isEmpty, phase == .done {
            // wieder etwas falsch gemacht
            phase = .corrected
            style = .normal
            speech = found.count == 1 ? "Da ist wieder ein Fehler reingerutscht." : "Da sind wieder Fehler reingerutscht."
        }
    }

    func ignore(_ mark: HomeworkMark) {
        ignored.insert(mark.key)
        if mark.key.hasPrefix("spell|") {
            NSSpellChecker.shared.ignoreWord((text as NSString).substring(with: mark.range),
                                             inSpellDocumentWithTag: HomeworkChecker.spellTag)
        }
        recheck()
    }

    func copy() {
        guard canCopy else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        speech = HomeworkLines.copied(tone)
        style = .purr
    }
}

// MARK: - Textfeld auf liniertem Papier

final class TeacherTextView: NSTextView {
    static let lineHeight: CGFloat = 26
    static let indent: CGFloat = 58
    static let font = NSFont.systemFont(ofSize: 14)

    var marks: [HomeworkMark] = [] { didSet { needsDisplay = true } }
    var showMarks = false { didSet { needsDisplay = true } }
    var onMarkClicked: ((HomeworkMark, NSRect) -> Void)?

    static func make() -> (NSScrollView, TeacherTextView) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = TeacherTextView(frame: .zero, textContainer: container)
        view.isRichText = false
        view.allowsUndo = true
        view.importsGraphics = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.drawsBackground = true
        view.backgroundColor = .clear
        view.textContainerInset = NSSize(width: 0, height: 4)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.insertionPointColor = HomeworkStyle.nsInk
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        paragraph.tailIndent = -14
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: font, .foregroundColor: HomeworkStyle.nsInk, .paragraphStyle: paragraph]

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        // Platz für die Note unten rechts
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 64, right: 0)
        scroll.documentView = view
        return (scroll, view)
    }

    /// Abstand vom Zeilenanfang bis zur Grundlinie (aus der ersten Zeile, sonst geschätzt)
    private var baseline: CGFloat {
        guard let lm = layoutManager, lm.numberOfGlyphs > 0 else { return Self.lineHeight - 7 }
        return lm.location(forGlyphAt: 0).y
    }

    override func drawBackground(in rect: NSRect) {
        let origin = textContainerOrigin
        // Linien unter den Zeilen
        HomeworkStyle.nsLine.setFill()
        var y = origin.y + baseline + 6
        while y < bounds.maxY {
            if y >= rect.minY - 2 && y <= rect.maxY + 2 {
                NSRect(x: 0, y: y.rounded(), width: bounds.width, height: 1).fill()
            }
            y += Self.lineHeight
        }
        // roter Rand
        HomeworkStyle.nsMargin.setFill()
        NSRect(x: Self.indent - 10, y: rect.minY, width: 1, height: rect.height).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showMarks, let lm = layoutManager, let tc = textContainer, !marks.isEmpty else { return }
        let origin = textContainerOrigin
        let base = baseline
        let red = HomeworkStyle.nsRed
        var margin: [CGFloat: [String]] = [:]
        let length = (string as NSString).length

        for mark in marks where NSMaxRange(mark.range) <= length {
            let glyphs = lm.glyphRange(forCharacterRange: mark.range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            let line = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            margin[line.minY, default: []].append(mark.symbol)
            switch mark.kind {
            case .wavy:
                lm.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                           in: tc) { r, _ in
                    let lineTop = lm.lineFragmentRect(forGlyphAt: lm.glyphIndex(for: NSPoint(x: r.midX, y: r.midY), in: tc),
                                                      effectiveRange: nil).minY
                    Self.wave(from: r.minX + origin.x, to: max(r.maxX + origin.x, r.minX + origin.x + 6),
                              y: lineTop + origin.y + base + 3.5, color: red)
                }
            case .insert(let sign):
                let last = NSRange(location: NSMaxRange(glyphs) - 1, length: 1)
                let r = lm.boundingRect(forGlyphRange: last, in: tc)
                (sign as NSString).draw(at: NSPoint(x: r.maxX + origin.x + 0.5, y: line.minY + origin.y + base - 16),
                                        withAttributes: [.font: HomeworkStyle.hand(17), .foregroundColor: red])
            }
        }
        // Randzeichen
        for (top, symbols) in margin {
            (symbols.joined() as NSString).draw(at: NSPoint(x: 6, y: top + origin.y + base - 17),
                                                withAttributes: [.font: HomeworkStyle.hand(15), .foregroundColor: red,
                                                                 .kern: 0.6])
        }
    }

    private static func wave(from x0: CGFloat, to x1: CGFloat, y: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        var x = x0
        path.move(to: NSPoint(x: x, y: y))
        var up = true
        while x < x1 {
            let next = min(x + 2.2, x1)
            path.line(to: NSPoint(x: next, y: y + (up ? -1.4 : 1.4)))
            up.toggle()
            x = next
        }
        color.setStroke()
        path.stroke()
    }

    /// Bereiche eines Fehlers in Ansichtskoordinaten (zum Anklicken)
    func rects(for mark: HomeworkMark) -> [NSRect] {
        guard let lm = layoutManager, let tc = textContainer,
              NSMaxRange(mark.range) <= (string as NSString).length else { return [] }
        let glyphs = lm.glyphRange(forCharacterRange: mark.range, actualCharacterRange: nil)
        var result: [NSRect] = []
        lm.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                   in: tc) { r, _ in
            var rect = r.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
            if case .insert = mark.kind { rect.size.width += 8 }
            result.append(rect.insetBy(dx: -2, dy: -2))
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard showMarks else { return }
        let point = convert(event.locationInWindow, from: nil)
        for mark in marks {
            if let hit = rects(for: mark).first(where: { $0.contains(point) }) {
                onMarkClicked?(mark, hit)
                return
            }
        }
    }
}

private struct TeacherTextField: NSViewRepresentable {
    let model: HomeworkModel

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, text) = TeacherTextView.make()
        text.delegate = context.coordinator
        model.textView = text
        text.onMarkClicked = { [weak text] mark, rect in
            guard let text else { return }
            context.coordinator.showTip(mark, at: rect, in: text)
        }
        DispatchQueue.main.async { text.window?.makeFirstResponder(text) }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: HomeworkModel
        private var popover: NSPopover?

        init(model: HomeworkModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            model.textChanged()
        }

        func showTip(_ mark: HomeworkMark, at rect: NSRect, in view: NSView) {
            popover?.close()
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: HomeworkTipView(mark: mark) { [weak self] in
                self?.popover?.close()
                self?.model.ignore(mark)
            })
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
            self.popover = popover
        }
    }
}

private struct HomeworkTipView: View {
    let mark: HomeworkMark
    let ignore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mark.symbol)
                    .font(Font(HomeworkStyle.hand(16) as CTFont))
                    .foregroundColor(HomeworkStyle.red)
                Text(mark.tip)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Stimmt so – ignorieren", action: ignore)
                .controlSize(.small)
        }
        .padding(12)
        .frame(width: 250, alignment: .leading)
    }
}

// MARK: - Blatt mit Rüdiger

/// Maße des Fensters. Rüdiger sitzt an der oberen Ecke, das Blatt hängt schräg darunter.
struct HomeworkLayout {
    static let diameter: CGFloat = 96
    static let paper = CGSize(width: 470, height: 420)
    static let pad: CGFloat = 26
    /// Rüdiger rechts oben (sonst links oben)
    let right: Bool

    var catCenter: CGPoint {
        CGPoint(x: right ? Self.pad + Self.paper.width - 8 : Self.pad + Self.diameter / 2,
                y: Self.pad + 74)
    }

    var paperOrigin: CGPoint {
        CGPoint(x: right ? Self.pad : catCenter.x + 8, y: catCenter.y + 8)
    }

    var size: CGSize {
        CGSize(width: Self.pad * 2 + Self.paper.width + Self.diameter / 2 + 8,
               height: paperOrigin.y + Self.paper.height + Self.pad)
    }
}

private struct HomeworkView: View {
    @ObservedObject var model: HomeworkModel
    let layout: HomeworkLayout
    let palette: Palette
    let onClose: () -> Void
    let onNote: () -> Void
    let onMove: (CGSize, Bool) -> Void
    @ObservedObject private var power = PowerState.shared

    private static let dateText: String = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMMM"
        return f.string(from: Date())
    }()

    var body: some View {
        let paper = HomeworkLayout.paper
        let origin = layout.paperOrigin
        ZStack(alignment: .topLeading) {
            // Das Blatt entfaltet sich langsam aus der Ecke bei Rüdiger: erst wächst es leicht gedreht heraus,
            // dann blendet der Inhalt ein, zuletzt poppt die Sprechblase auf.
            let corner: UnitPoint = layout.right ? .topTrailing : .topLeading
            sheet
                .frame(width: paper.width, height: paper.height)
                .scaleEffect(model.shown ? 1 : 0.4, anchor: corner)
                .rotationEffect(.degrees(model.shown ? 0 : (layout.right ? 5 : -5)), anchor: corner)
                .opacity(model.shown ? 1 : 0)
                .animation(model.shown ? .spring(response: 0.62, dampingFraction: 0.8) : .easeIn(duration: 0.2),
                           value: model.shown)
                .offset(x: origin.x, y: origin.y)
            bubble
                .scaleEffect(model.shown ? 1 : 0.5,
                             anchor: UnitPoint(x: layout.catCenter.x / layout.size.width,
                                               y: layout.catCenter.y / layout.size.height))
                .opacity(model.shown ? 1 : 0)
                .animation(model.shown ? .spring(response: 0.4, dampingFraction: 0.65).delay(0.42)
                                       : .easeIn(duration: 0.12), value: model.shown)
            cat
                .frame(width: HomeworkLayout.diameter, height: HomeworkLayout.diameter)
                .position(layout.catCenter)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    // Blatt
    private var sheet: some View {
        VStack(spacing: 0) {
            // Kopf: Fach und Datum – hier lässt sich das Blatt verschieben
            ZStack(alignment: .topLeading) {
                Color.clear
                Text("\(model.language == "en" ? "Englisch" : "Deutsch") · \(Self.dateText)")
                    .font(Font(HomeworkStyle.hand(17) as CTFont))
                    .foregroundColor(Color(white: 0.55))
                    .padding(.leading, TeacherTextView.indent)
                    .padding(.top, 42)
                Button(action: onClose) {
                    Label("verwerfen", systemImage: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
                }
                .buttonStyle(.plain)
                .help("Blatt schließen – der Text wird verworfen")
                .frame(maxWidth: .infinity, alignment: layout.right ? .leading : .trailing)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
            .frame(height: 70)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in onMove(value.translation, false) }
                .onEnded { value in onMove(value.translation, true) })
            Rectangle().fill(Color(nsColor: HomeworkStyle.nsLine)).frame(height: 1)
            ZStack(alignment: .bottomTrailing) {
                TeacherTextField(model: model)
                if model.phase != .writing { grade }
            }
            footer
        }
        .opacity(model.shown ? 1 : 0)
        .animation(model.shown ? .easeOut(duration: 0.35).delay(0.28) : .easeIn(duration: 0.1), value: model.shown)
        .background(
            ZStack {
                VisualEffectBlur()
                Color(red: 0.99, green: 0.985, blue: 0.97).opacity(0.82)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
    }

    private var grade: some View {
        let done = model.phase == .done
        let color = done ? HomeworkStyle.green : HomeworkStyle.red
        return VStack(spacing: 2) {
            Text(done ? model.finalGrade : model.firstGrade)
                .font(Font(HomeworkStyle.hand(30) as CTFont))
                .frame(width: 56, height: 50)
                .overlay(Ellipse().stroke(color, lineWidth: 2))
            Text(done ? "verbessert ✓" : "Bitte verbessern! – R.")
                .font(Font(HomeworkStyle.hand(14) as CTFont))
        }
        .foregroundColor(color)
        .opacity(0.85)
        .rotationEffect(.degrees(-6))
        .padding(.trailing, 18)
        .padding(.bottom, 6)
        .allowsHitTesting(false)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.phase == .writing {
                Button("Abgeben") { model.handIn() }
                    .buttonStyle(HomeworkButtonStyle(prominent: true, enabled: true))
            } else {
                Button { model.copy() } label: { Label("Kopieren", systemImage: "doc.on.doc") }
                    .buttonStyle(HomeworkButtonStyle(prominent: model.canCopy, enabled: model.canCopy))
                    .disabled(!model.canCopy)
                    .help(model.canCopy ? "Text kopieren" : "Erst alles verbessern")
            }
            Button { onNote() } label: { Label("Zur Schnellnotiz", systemImage: "note.text") }
                .buttonStyle(HomeworkButtonStyle(prominent: false, enabled: true))
                .help("Text in die Schnellnotizen legen – dort bleibt er, bis du ihn löschst")
            Spacer()
            switch model.phase {
            case .writing:
                Text("tippen oder mit ⌘V einfügen").foregroundColor(Color(white: 0.6))
            case .corrected:
                Text(model.openErrors == 1 ? "noch 1 Fehler · klick aufs Rote" : "noch \(model.openErrors) Fehler · klick aufs Rote")
                    .foregroundColor(Color(white: 0.6))
            case .done:
                Label("alles verbessert", systemImage: "checkmark").foregroundColor(HomeworkStyle.green)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Color(white: 0.96).opacity(0.7))
        .overlay(alignment: .top) { Rectangle().fill(Color(nsColor: HomeworkStyle.nsLine)).frame(height: 1) }
    }

    // Sprechblase (Skizzen-Stil) – ragt über den Kopf des Blatts
    private var bubble: some View {
        let layoutText = CatBubbleLayout.make(model.speech, style: model.style, maxSize: CGSize(width: 300, height: 140))
        let ew = layoutText.bubbleSize.width, eh = layoutText.bubbleSize.height
        let cat = layout.catCenter
        let gap = HomeworkLayout.diameter / 2 + 14
        let cx = layout.right ? cat.x - gap - ew / 2 : cat.x + gap + ew / 2
        let cy = cat.y - 6
        let body = CGRect(x: cx - ew / 2, y: cy - eh / 2, width: ew, height: eh)
        let tail = CGPoint(x: layout.right ? cat.x - HomeworkLayout.diameter / 2 + 2 : cat.x + HomeworkLayout.diameter / 2 - 2,
                           y: cat.y + 4)
        let textSize = CGSize(width: min(layoutText.textSize.width, ew - 2 * CatBubbleLayout.padX + 8),
                              height: min(layoutText.textSize.height, eh - 2 * CatBubbleLayout.padY + 6))
        return SketchBubbleView(text: model.speech, style: model.style, body: body, tail: tail,
                                size: layout.size, fontSize: layoutText.fontSize, textSize: textSize, drawIn: false)
            .id(model.speech)
            .allowsHitTesting(false)
    }

    // Rüdiger in seiner Glasblase
    private var cat: some View {
        let name: String
        switch model.phase {
        case .writing: name = "idle"
        case .corrected: name = "annoyed"
        case .done: name = "purr"
        }
        return ZStack {
            Circle().fill(palette.accent.opacity(0.45)).blur(radius: 6).padding(-3)
            Circle().fill(Color.white.opacity(0.88))
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.5), palette.accent.opacity(0.55)],
                                         center: UnitPoint(x: 0.45, y: 0.36), startRadius: 2, endRadius: 60))
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: power.paused)) { timeline in
                if let image = CatSprites.shared.image(name, at: timeline.date.timeIntervalSinceReferenceDate) {
                    GeometryReader { proxy in
                        let side = proxy.size.width * CGFloat(CatSprites.shared.span(name))
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: side, height: side)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 5)
        .allowsHitTesting(false)
    }
}

private struct HomeworkButtonStyle: ButtonStyle {
    let prominent: Bool
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(prominent ? HomeworkStyle.green : Color.black.opacity(enabled ? 0.06 : 0.04)))
            .foregroundColor(prominent ? .white : Color(white: enabled ? 0.33 : 0.65))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Milchglas hinter dem Blatt
private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Knopf an Rüdiger (Heft mit Note)

struct HomeworkIcon: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerRadius: r * s)
            }
            let cover = Color(red: 0.54, green: 0.61, blue: 0.69)
            let page = Color(red: 0.98, green: 0.98, blue: 0.965)
            let red = HomeworkStyle.red
            context.fill(rect(4, 3, 14.5, 18, 2), with: .color(cover))
            context.fill(rect(6.3, 3, 12.2, 18, 1.5), with: .color(page))
            context.stroke(rect(6.3, 3, 12.2, 18, 1.5), with: .color(cover), lineWidth: 1.1 * s)
            var lines = Path()
            for (y, w) in [(7.5, 6.6), (10.3, 6.6), (13.1, 4.0)] as [(CGFloat, CGFloat)] {
                lines.move(to: CGPoint(x: 8.6 * s, y: y * s))
                lines.addLine(to: CGPoint(x: (8.6 + w) * s, y: y * s))
            }
            context.stroke(lines, with: .color(Color(red: 0.84, green: 0.87, blue: 0.89)), lineWidth: 1.1 * s)
            let circle = Path(ellipseIn: CGRect(x: (16.6 - 4.6) * s, y: (16.6 - 4.6) * s, width: 9.2 * s, height: 9.2 * s))
            context.fill(circle, with: .color(page))
            context.stroke(circle, with: .color(red), lineWidth: 1.4 * s)
            context.draw(Text("1").font(Font(HomeworkStyle.hand(7.6 * s) as CTFont)).foregroundColor(red),
                         at: CGPoint(x: 16.6 * s, y: 16.9 * s))
        }
    }
}

/// Erscheint, sobald die Maus in die Nähe von Rüdiger kommt
struct HomeworkBadge: View {
    let hovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(hovered ? 1 : 0.8))
                    .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                HomeworkIcon().frame(width: 20, height: 20)
            }
            .frame(width: HomeworkBadge.size, height: HomeworkBadge.size)
            .scaleEffect(hovered ? 1.12 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Text prüfen lassen")
        .animation(.easeOut(duration: 0.1), value: hovered)
    }

    static let size: CGFloat = 30
    /// Abstand des Knopfs vom Mittelpunkt (Anteil am Durchmesser, je Achse)
    static let offset: CGFloat = 0.42
    /// So nah (ab Blasenrand) muss die Maus kommen
    static let radius: CGFloat = 40
}

// MARK: - Fenster

@MainActor
final class HomeworkController {
    static let shared = HomeworkController()
    weak var store: ConfigStore?
    private var panel: SidebarPanel?
    private var model: HomeworkModel?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    var isOpen: Bool { panel != nil }

    func open() {
        if let panel {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            return
        }
        guard let store else { return }
        let settings = store.config.settings
        let location = CatBrain.shared.locate?()
        let cat = location?.cat
        let screen = cat.flatMap { rect in NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) } }
            ?? NSScreen.main ?? NSScreen.screens.first
        let area = location?.visible ?? screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Rüdiger setzt sich auf seinen Platz – das Blatt liegt dort, wo mehr Platz ist
        let center = cat.map { NSPoint(x: $0.midX, y: $0.midY) } ?? NSPoint(x: area.midX - 200, y: area.maxY - 140)
        let right = center.x + HomeworkLayout.paper.width + 40 > area.maxX && center.x - HomeworkLayout.paper.width > area.minX
        let layout = HomeworkLayout(right: right)
        let size = layout.size
        var frame = NSRect(x: center.x - layout.catCenter.x, y: center.y + layout.catCenter.y - size.height,
                           width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, area.minX), area.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, area.minY), area.maxY - frame.height)

        let model = HomeworkModel(tone: settings.catTone)
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let view = HomeworkView(model: model, layout: layout,
                                palette: Palette.resolve(settings.colorTheme, dark ? .dark : .light),
                                onClose: { [weak self] in self?.close() },
                                onNote: { [weak self] in self?.saveToNote() },
                                onMove: { [weak self] translation, ended in self?.move(translation, ended: ended) })
            .environment(\.colorScheme, .light)

        let panel = SidebarPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.allowsKey = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let host = FirstMouseHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: true)

        self.panel = panel
        self.model = model
        CatBubbleController.shared.hide()
        CatBrain.shared.teaching = true
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // Aufklappen starten, sobald das Fenster steht (sonst fehlt der Anfang der Animation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak model] in
            model?.shown = true
        }
    }

    func close() {
        guard let closing = panel else { return }
        let closingModel = model
        panel = nil
        model = nil
        dragStart = nil
        // Blatt klappt wieder in Rüdigers Ecke zusammen, dann Fenster weg und Rüdiger zurück an seinen Platz
        closingModel?.shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                closing.orderOut(nil)
                closing.contentView = nil
                if self?.panel == nil { CatBrain.shared.teaching = false }
            }
        }
    }

    private func saveToNote() {
        guard let model, let store else { return }
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            model.speech = "Ein leeres Blatt speichere ich nicht."
            return
        }
        store.addNote(text)
        close()
        CatBrain.shared.remark("Liegt in deinen Schnellnotizen.")
    }

    /// Blatt am Kopf verschieben
    private func move(_ translation: CGSize, ended: Bool) {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                     y: start.origin.y + mouse.y - start.mouse.y))
        if ended { dragStart = nil }
    }
}
