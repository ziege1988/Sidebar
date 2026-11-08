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

// MARK: Sprüche

/// Ein Spruch und ab welchem Ton er vorkommt: 0 = lieb, 1 = frech, 2 = beleidigend.
struct CatLine {
    let tone: Int
    let text: String
    init(_ tone: Int, _ text: String) {
        self.tone = tone
        self.text = text
    }
}

enum CatLines {
    static let ask: [CatLine] = [
        .init(0, "Streichel mich!"),
        .init(0, "Kopf kraulen, bitte."),
        .init(1, "Hey. Streicheln. Jetzt."),
        .init(1, "Ich bin flauschig. Nutz das aus."),
        .init(2, "Streichel mich, du Tastaturquäler!"),
        .init(2, "Hände weg von der Maus. Her damit."),
    ]
    static let annoyed1: [CatLine] = [
        .init(0, "Hallooo? Ich warte!"),
        .init(1, "Haallooo, pennst du?"),
        .init(2, "Haallooo?! Pennst du, Schnarchnase?"),
        .init(2, "Bist du taub oder nur langsam?"),
    ]
    static let annoyed2: [CatLine] = [
        .init(0, "Du ignorierst mich, oder?"),
        .init(1, "Ich seh genau, dass du mich ignorierst."),
        .init(2, "Ignorier mich ruhig weiter, du Flachpfeife."),
        .init(2, "Wow. Nicht mal das kriegst du hin."),
    ]
    static let annoyed3: [CatLine] = [
        .init(0, "Na gut. Dann schlaf ich halt."),
        .init(1, "Pff. Dann eben nicht. Beleidigt."),
        .init(2, "Weißt du was? Du kannst mich mal. Ich schlaf jetzt."),
        .init(2, "Ich merk mir das, du Trantüte."),
    ]
    static let petted: [CatLine] = [
        .init(0, "Schnurrr …"),
        .init(0, "Na gut. Weitermachen."),
        .init(1, "Hmpf. War okay."),
        .init(1, "Mehr davon. Aber später."),
        .init(2, "Endlich, du Trantüte."),
        .init(2, "Na also. Geht doch, Sesselpupser."),
    ]
    static let wokenByPet: [CatLine] = [
        .init(0, "Hmpf. Ich hab geschlafen."),
        .init(1, "Wer wagt es …? Ach, du."),
        .init(2, "Ernsthaft? Ich hab geschlafen, du Knalltüte."),
    ]
    static let purr: [CatLine] = [.init(0, "Schnurrr …"), .init(0, "Schnurrrrr …"), .init(0, "Prrrrr …")]
    static let nap: [CatLine] = [
        .init(0, "Ich mach mal kurz die Augen zu."),
        .init(1, "Weck mich, wenn was Spannendes passiert. Also nie."),
        .init(2, "Weck mich, wenn du was Sinnvolles machst."),
    ]
    static let back: [CatLine] = [
        .init(0, "Ach, auch wieder da?"),
        .init(1, "Schöne Pause gehabt? Ich nicht."),
        .init(2, "Na, auch mal wieder da, du Pausenkönig?"),
    ]
    static let wake: [CatLine] = [
        .init(0, "Ich war nie weg."),
        .init(1, "Na endlich. Hab dich vermisst. Nicht."),
        .init(2, "Da bin ich wieder. Freu dich gefälligst."),
    ]
    static let message: [CatLine] = [
        .init(0, "Neue Nachricht in {name}."),
        .init(1, "{name} will was von dir. Ich auch, aber egal."),
        .init(1, "Pling. {name}. Bestimmt was Unwichtiges."),
        .init(1, "{name} hat geschrieben. Ich hab nicht reingeschaut. Vielleicht."),
        .init(2, "{name} hat geschrieben. Lies es halt, du Tastaturquäler."),
        .init(2, "Schon wieder {name}. Hast du auch Freunde, die nicht nerven?"),
    ]
    static let mail: [CatLine] = [
        .init(0, "Neue E-Mail für dich."),
        .init(1, "Post für dich. Ich würd sie ignorieren."),
        .init(1, "Neue E-Mail. Arbeit, igitt."),
        .init(2, "Neue Mail. Noch mehr Arbeit für dich, du Sesselpupser."),
    ]
    static let flood: [CatLine] = [
        .init(0, "So viele Nachrichten … und mich streichelt keiner."),
        .init(1, "Na? Sind die anderen wichtiger als ich?"),
        .init(2, "Alle wollen was von dir. Ich auch, du treulose Tomate!"),
        .init(2, "Sind die anderen wichtiger als ich?! Antworte, du Verräter!"),
    ]
    static let jokes: [CatLine] = [
        .init(0, "Ich hab heute schon 14 Stunden geschlafen. Und du so?"),
        .init(0, "Ich würde dir ja helfen. Aber ich bin eine Katze."),
        .init(1, "Ich hab deine To-do-Liste gesehen. Mein Beileid."),
        .init(1, "Ich hab neun Leben. Du hast diese Excel-Tabelle."),
        .init(1, "Kaffee ist keine Persönlichkeit. Bei dir fast."),
        .init(1, "Mitarbeiter des Monats? Von mir nicht."),
        .init(1, "Weißt du, was ich an Montagen mag? Nichts."),
        .init(1, "Ich liege hier rum und werde bewundert. Lern was."),
        .init(2, "Du tippst wie ein Waschbär auf Koffein."),
        .init(2, "Selbst mein Fellknäuel hat mehr Struktur als dein Desktop."),
        .init(2, "Ich würd dich ja kratzen, aber du bist mir zu langweilig."),
        .init(2, "Wenn Dummheit schnurren könnte, wärst du ein Traktor."),
        .init(2, "Du bist genau so produktiv wie ich. Und ich schlafe."),
        .init(2, "Hör auf zu klicken wie ein Specht, du Dumpfbacke."),
    ]
    static let late: [CatLine] = [
        .init(0, "Es ist {time}. Geh nach Hause."),
        .init(1, "{time} Uhr. Selbst ich hab Feierabend."),
        .init(2, "Es ist {time}, du Arbeitstier. Hast du kein Zuhause?"),
    ]
    static let monday: [CatLine] = [
        .init(0, "Montag. Ich bin dagegen."),
        .init(2, "Montagmorgen und du siehst aus wie ich nach dem Tierarzt."),
    ]
    static let friday: [CatLine] = [
        .init(0, "Freitag! Fast geschafft."),
        .init(1, "Freitagnachmittag. Tu wenigstens so, als würdest du arbeiten."),
        .init(2, "Freitag. Mach Schluss, du Sesselpupser."),
    ]
    static let mailPile: [CatLine] = [
        .init(0, "{n} ungelesene Mails. Nur so als Info."),
        .init(1, "{n} ungelesene Mails. Ich hätte da noch einen Platz im Katzenkorb frei."),
        .init(2, "{n} ungelesene Mails, du Chaot. Respekt."),
    ]
}

// MARK: Verhalten

@MainActor
final class CatBrain: ObservableObject {
    static let shared = CatBrain()

    enum Mood: Equatable {
        case sleeping, awake, asking, purring
        case annoyed(Int)
    }

    @Published private(set) var mood: Mood = .awake
    /// Schlummermodus: bewusst an- und ausgeschaltet, gilt bis zum nächsten Start der App
    @Published private(set) var snoozed = false
    /// Kurz wütend (z. B. viele Nachrichten in kurzer Zeit)
    @Published private(set) var furious = false

    /// Maus/Eingabe gerade in der Sidebar → nicht dazwischenquatschen
    var sidebarBusy = false
    weak var store: ConfigStore?
    var locate: (@MainActor () -> CatLocation?)?

    private var settings = SidebarSettings()
    private var timer: Timer?
    private var moodSince = Date()
    private var nextEventAt = Date().addingTimeInterval(180)
    private var napUntil: Date?
    private var away = false
    private var lastSpoke = Date.distantPast
    private var lastAnnounce = Date.distantPast
    private var lastFlood = Date.distantPast
    private var furiousUntil = Date.distantPast
    private var messageTimes: [Date] = []
    private var previousCounts: [String: Int] = [:]
    private var previousExtra: [UUID: Int] = [:]
    private let launched = Date()
    private var recent: [String] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        BadgeStore.shared.$counts
            .combineLatest(BadgeStore.shared.$extra)
            .receive(on: RunLoop.main)
            .sink { [weak self] counts, extra in
                MainActor.assumeIsolated { self?.badgesChanged(counts, extra) }
            }
            .store(in: &cancellables)
    }

    func apply(_ settings: SidebarSettings) {
        self.settings = settings
        if !settings.catEnabled { CatBubbleController.shared.hide() }
    }

    /// Wie Rüdiger gerade aussieht
    var pose: CatPose {
        if snoozed || mood == .sleeping { return .sleep }
        if furious { return .angry }
        switch mood {
        case .asking: return .ask
        case .purring: return .purr
        case .annoyed(let level): return level >= 2 ? .angry : .grumpy
        default: return .grumpy
        }
    }

    // MARK: Aktionen

    func pet() {
        guard settings.catEnabled, !snoozed else { return }
        let wasSleeping = mood == .sleeping
        napUntil = nil
        furious = false
        set(.purring)
        say(wasSleeping ? CatLines.wokenByPet : CatLines.petted, style: .purr, force: true)
        scheduleNext()
    }

    func toggleSnooze() {
        snoozed.toggle()
        if snoozed {
            CatBubbleController.shared.hide()
            set(.sleeping)
        } else {
            napUntil = nil
            set(.awake)
            say(CatLines.wake, force: true)
            scheduleNext()
        }
    }

    // MARK: Ablauf

    private func set(_ new: Mood) {
        mood = new
        moodSince = Date()
    }

    private func scheduleNext() {
        let range: ClosedRange<Double>
        switch settings.catFrequency {
        case 0: range = 1500...3000
        case 2: range = 240...600
        default: range = 600...1500
        }
        nextEventAt = Date().addingTimeInterval(.random(in: range))
    }

    private var canSpeak: Bool {
        settings.catEnabled && !snoozed && !away && !sidebarBusy && !AlertState.shared.quiet
            && Date().timeIntervalSince(lastSpoke) > 8 && locate?() != nil
    }

    private func tick() {
        guard settings.catEnabled else { return }
        let now = Date()
        if furious && now > furiousUntil { furious = false }
        if snoozed {
            if mood != .sleeping { set(.sleeping) }
            return
        }

        // Niemand am Mac → schlafen, beim Zurückkommen kurz kommentieren
        let idle = Self.idleSeconds()
        if idle > 600 {
            if !away {
                away = true
                set(.sleeping)
                CatBubbleController.shared.hide()
            }
            return
        }
        if away && idle < 5 {
            away = false
            napUntil = nil
            set(.awake)
            say(CatLines.back)
            scheduleNext()
            return
        }

        let age = now.timeIntervalSince(moodSince)
        switch mood {
        case .asking:
            if age > 150, canSpeak { set(.annoyed(1)); say(CatLines.annoyed1, style: .angry) }
        case .annoyed(let level):
            if level >= 3 {
                if age > 60 {
                    set(.sleeping)
                    napUntil = now.addingTimeInterval(1200)
                    scheduleNext()
                }
            } else if age > 150, canSpeak {
                set(.annoyed(level + 1))
                say(level + 1 == 2 ? CatLines.annoyed2 : CatLines.annoyed3, style: .angry)
            }
        case .purring:
            if age > 25 { set(.awake) }
        case .sleeping:
            if let napUntil {
                if now > napUntil {
                    self.napUntil = nil
                    set(.awake)
                }
            } else {
                set(.awake)
            }
        case .awake:
            if now >= nextEventAt {
                if canSpeak {
                    randomEvent()
                } else {
                    nextEventAt = now.addingTimeInterval(45)
                }
            }
        }
    }

    private func randomEvent() {
        let roll = Double.random(in: 0..<1)
        if roll < 0.32 {
            set(.asking)
            say(CatLines.ask)
        } else if roll < 0.62 {
            if let context = contextLines(), Bool.random() {
                say(context.lines, values: context.values)
            } else {
                say(CatLines.jokes)
            }
        } else if roll < 0.74 {
            set(.purring)
            say(CatLines.purr, style: .purr)
        } else if roll < 0.9 {
            set(.sleeping)
            napUntil = Date().addingTimeInterval(.random(in: 600...1800))
            if Bool.random() { say(CatLines.nap) }
        } else {
            say(CatLines.jokes)
        }
        scheduleNext()
    }

    /// Sprüche passend zu Uhrzeit, Wochentag und Postfach
    private func contextLines() -> (lines: [CatLine], values: [String: String])? {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now) // 1 = Sonntag
        let time = now.formatted(date: .omitted, time: .shortened)
        if hour >= 20 || hour < 5 { return (CatLines.late, ["time": time]) }
        let unread = MailWatcher.shared.unread
        if unread >= 10 { return (CatLines.mailPile, ["n": "\(unread)"]) }
        if weekday == 2 && hour < 11 { return (CatLines.monday, [:]) }
        if weekday == 6 && hour >= 14 { return (CatLines.friday, [:]) }
        return nil
    }

    // MARK: Nachrichten

    private func badgesChanged(_ counts: [String: Int], _ extra: [UUID: Int]) {
        defer {
            previousCounts = counts
            previousExtra = extra
        }
        // Beim Start kommen alle Zahlen auf einmal – das sind keine neuen Nachrichten
        guard Date().timeIntervalSince(launched) > 20 else { return }
        var names: [String] = []
        var mail = false
        for (key, value) in counts where value > (previousCounts[key] ?? 0) {
            names.append(name(forKey: key))
        }
        for (id, value) in extra where value > (previousExtra[id] ?? 0) {
            if id == settings.mailItemID { mail = true } else { names.append(name(forID: id)) }
        }
        guard !names.isEmpty || mail else { return }

        let now = Date()
        messageTimes = messageTimes.filter { now.timeIntervalSince($0) < 600 } + [now]
        guard settings.catEnabled, settings.catMessages, canSpeak else { return }

        // Erst die Einblendung am Icon zeigen lassen, dann meldet sich Rüdiger
        let delay = settings.messageToast ? settings.messageToastDuration + 0.6 : 0.3
        if messageTimes.count >= 5 && now.timeIntervalSince(lastFlood) > 600 {
            lastFlood = now
            furious = true
            furiousUntil = now.addingTimeInterval(40 + delay)
            later(delay) { $0.say(CatLines.flood, style: .angry, force: true) }
            return
        }
        guard now.timeIntervalSince(lastAnnounce) > 45 else { return }
        lastAnnounce = now
        if mood == .sleeping {
            napUntil = nil
            set(.awake)
        }
        if names.isEmpty {
            later(delay) { $0.say(CatLines.mail, force: true) }
        } else {
            let name = names[0]
            later(delay) { $0.say(CatLines.message, values: ["name": name], force: true) }
        }
    }

    private func later(_ delay: Double, _ action: @escaping @MainActor (CatBrain) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.settings.catEnabled, !self.snoozed, !AlertState.shared.quiet else { return }
                action(self)
            }
        }
    }

    private func name(forKey key: String) -> String {
        guard let store else { return "einer App" }
        let items = store.config.favorites + store.config.groups.flatMap(\.items)
        if let item = items.first(where: { BadgeStore.key(for: $0) == key }) {
            return DockBadgeWatcher.cleanDisplayName(item.displayName)
        }
        return "einer App"
    }

    private func name(forID id: UUID) -> String {
        guard let item = store?.item(id: id) else { return "einer App" }
        return DockBadgeWatcher.cleanDisplayName(item.displayName)
    }

    // MARK: Sprechen

    private func say(_ lines: [CatLine], values: [String: String] = [:], style: CatBubbleStyle = .normal,
                     force: Bool = false) {
        guard settings.catEnabled, !snoozed, !AlertState.shared.quiet else { return }
        guard force || canSpeak, let location = locate?() else { return }
        var text = pick(lines)
        for (key, value) in values { text = text.replacingOccurrences(of: "{\(key)}", with: value) }
        lastSpoke = Date()
        CatBubbleController.shared.show(text, style: style, at: location)
    }

    /// Spruch passend zum eingestellten Ton – meist aus der „schärfsten“ erlaubten Stufe
    private func pick(_ lines: [CatLine]) -> String {
        let tone = settings.catTone
        let allowed = lines.filter { $0.tone <= tone }
        let top = allowed.filter { $0.tone == tone }
        var pool = (!top.isEmpty && Double.random(in: 0..<1) < 0.7) ? top : allowed
        if pool.isEmpty { pool = lines }
        let fresh = pool.filter { !recent.contains($0.text) }
        let line = (fresh.isEmpty ? pool : fresh).randomElement()?.text ?? "Hmpf."
        recent.append(line)
        if recent.count > 12 { recent.removeFirst() }
        return line
    }

    /// Sekunden seit der letzten Eingabe (Maus, Tastatur, Trackpad)
    private static func idleSeconds() -> Double {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}

// MARK: - Zeichnung

enum CatPose {
    case sleep, grumpy, ask, purr, angry
}

/// Rüdiger im runden Fenster – gezeichnet in einem 100 × 100-Feld, animiert.
struct CatView: View {
    let palette: Palette
    var openSettings: (() -> Void)?
    @ObservedObject private var brain = CatBrain.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pose = brain.pose
        let dark = scheme == .dark
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                CatPainter.draw(in: &context, size: size, pose: pose, dark: dark,
                                accent: palette.accent,
                                time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(dark ? 0.35 : 0.8), lineWidth: 2))
        .overlay(Circle().inset(by: 1.5).stroke(Color.black.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
        .contentShape(Circle())
        .onTapGesture { brain.pet() }
        .contextMenu {
            Button("Streicheln") { brain.pet() }
            Button(brain.snoozed ? "Rüdiger wecken" : "Rüdiger schlafen schicken") { brain.toggleSnooze() }
            if let openSettings {
                Divider()
                Button("Rüdiger-Einstellungen …") { openSettings() }
            }
        }
        .help(brain.snoozed ? "Rüdiger schläft (Rechtsklick → wecken)" : "Rüdiger – klicken zum Streicheln")
    }
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

        if pose == .sleep {
            drawSleeping(&context, dark: dark, t: t)
        } else {
            drawBust(&context, pose: pose, dark: dark, t: t)
        }
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

// MARK: - Einstellungen

struct CatSettingsSection: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject private var brain = CatBrain.shared

    var body: some View {
        Section("Rüdiger") {
            Toggle("Rüdiger anzeigen", isOn: $store.config.settings.catEnabled)
            if store.config.settings.catEnabled {
                Picker("Wie oft meldet er sich?", selection: $store.config.settings.catFrequency) {
                    Text("Selten").tag(0)
                    Text("Normal").tag(1)
                    Text("Oft").tag(2)
                }
                .pickerStyle(.segmented)
                Picker("Ton", selection: $store.config.settings.catTone) {
                    Text("Lieb").tag(0)
                    Text("Frech").tag(1)
                    Text("Beleidigend").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("Kommentiert neue Nachrichten und E-Mails", isOn: $store.config.settings.catMessages)
                LabeledContent("Schlummermodus") {
                    Button(brain.snoozed ? "Rüdiger wecken" : "Rüdiger schlafen schicken") { brain.toggleSnooze() }
                }
                Text("Schlummermodus z. B. für Bildschirmfreigaben: Rüdiger schläft und sagt nichts, bis du ihn wieder weckst – auch über das Menüleisten-Symbol oder per Rechtsklick auf ihn. Nach einem Neustart der Sidebar ist er wieder wach.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if CatGeometry.make(store.config.settings, clockOn: store.config.settings.showClock) == nil {
                    Text("Rüdiger sitzt im Viertelkreis zwischen Uhr und Leiste. Dafür muss die Uhr eingeschaltet sein und deutlich über die Leiste hinausragen (Uhr größer oder Leiste schmaler stellen).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Klick auf Rüdiger = streicheln. Ignorierst du ihn, wird er ungemütlich. Ist niemand am Mac, schläft er. Im Ruhemodus ist er still.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
