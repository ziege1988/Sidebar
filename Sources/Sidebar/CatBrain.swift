import AppKit
import Combine
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Rüdigers Verhalten

enum CatPose: Equatable {
    /// noch nicht da (vor dem Auftritt)
    case absent
    case sleep, grumpy, ask, purr, angry
    /// läuft durchs Fenster (x = Mitte im 100er-Feld)
    case walk(x: CGFloat, facingRight: Bool)
}

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
    /// Versteckter Schalter: erscheint nach 4 s mit der Maus auf Rüdiger
    @Published var showSnoozeControl = false

    /// Auftritt beim Start: 3 Minuten nach dem Start läuft er durchs Fenster, kommt zurück und winkt
    let introStart = Date().addingTimeInterval(180)
    static let introLength: Double = 9.6
    private(set) var introDone = false

    /// Maus/Eingabe gerade in der Sidebar → nicht dazwischenquatschen
    var sidebarBusy = false
    weak var store: ConfigStore?
    var locate: (@MainActor () -> CatLocation?)?

    private var settings = SidebarSettings()
    private var timer: Timer?
    private var moodSince = Date()
    private var nextEventAt = Date().addingTimeInterval(180 + 600)
    private var napUntil: Date?
    private var away = false
    private var lastSpoke = Date.distantPast
    private var lastFlood = Date.distantPast
    private var furiousUntil = Date.distantPast
    private var messageTimes: [Date] = []
    private var activeSince = Date()
    private var lastPause = Date()
    private var treats: [Date] = []
    private var ignoredToday = 0
    private var recent: [String] = []

    private init() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func apply(_ settings: SidebarSettings) {
        self.settings = settings
        if !settings.catEnabled { CatBubbleController.shared.hide() }
    }

    /// Rüdiger ist zu sehen und übernimmt das Vorlesen neuer Nachrichten (statt der Einblendung am Icon)
    var takesOverMessages: Bool {
        settings.catEnabled && settings.catMessages && introDone && locate?() != nil
    }

    // MARK: Aussehen

    func pose(at date: Date) -> CatPose {
        let since = date.timeIntervalSince(introStart)
        if since < 0 { return .absent }
        if since < Self.introLength {
            // läuft von links nach rechts hinaus, kurz weg, kommt von rechts zurück und winkt
            switch since {
            case ..<3.2: return .walk(x: CGFloat(-30 + since / 3.2 * 160), facingRight: true)
            case ..<4.2: return .absent
            case ..<6.4: return .walk(x: CGFloat(130 - (since - 4.2) / 2.2 * 80), facingRight: false)
            default: return .ask
            }
        }
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
        guard settings.catEnabled, introDone, !snoozed else { return }
        let wasSleeping = mood == .sleeping
        napUntil = nil
        furious = false
        set(.purring)
        say(wasSleeping ? CatLines.wokenByPet : CatLines.petted, style: .purr, force: true)
        scheduleNext()
    }

    func giveTreat() {
        guard settings.catEnabled, introDone, !snoozed else { return }
        let now = Date()
        treats = treats.filter { now.timeIntervalSince($0) < 1800 } + [now]
        napUntil = nil
        set(.purring)
        say(treats.count > 3 ? CatLines.treatTooMuch : CatLines.treat, style: .purr, force: true)
        scheduleNext()
    }

    func fileDropped() {
        guard settings.catEnabled, introDone, !snoozed else { return }
        napUntil = nil
        set(.annoyed(1))
        say(CatLines.fileDrop, style: .angry, force: true)
    }

    func toggleSnooze() {
        showSnoozeControl = false
        snoozed.toggle()
        if snoozed {
            say(CatLines.snooze, force: true)
            set(.sleeping)
        } else {
            napUntil = nil
            set(.awake)
            say(CatLines.wake, force: true)
            scheduleNext()
        }
    }

    // MARK: Abschied

    /// Beim Beenden: abfälliger Spruch mit bösem Blick. `false`, wenn Rüdiger gerade nicht da ist.
    func sayGoodbye() -> Bool {
        guard settings.catEnabled, introDone, !snoozed, !AlertState.shared.quiet, locate?() != nil else { return false }
        napUntil = nil
        set(.awake)
        furious = true
        furiousUntil = Date().addingTimeInterval(10)
        say(CatLines.quit, style: .angry, force: true)
        return true
    }

    // MARK: Nachrichten vorlesen

    /// Neue Nachricht oder Mail vorlesen und kommentieren.
    func announce(app: String, from: String, text: String, isMail: Bool) {
        guard settings.catEnabled, !snoozed else { return }
        let now = Date()
        messageTimes = messageTimes.filter { now.timeIntervalSince($0) < 600 } + [now]
        if mood == .sleeping {
            napUntil = nil
            set(.awake)
        }

        // Viele Nachrichten in kurzer Zeit → Rüdiger wird wütend
        if messageTimes.count >= 5 && now.timeIntervalSince(lastFlood) > 600 {
            lastFlood = now
            furious = true
            furiousUntil = now.addingTimeInterval(40)
            queue { $0.say(CatLines.flood, style: .angry, force: true) }
            return
        }

        let sender = from.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        if body.count > 80 { body = String(body.prefix(78)) + " …" }
        let header: String
        if isMail {
            header = body.isEmpty ? "Neue Mail von \(sender)." : "Mail von \(sender): „\(body)“"
        } else if sender.isEmpty || sender.caseInsensitiveCompare(app) == .orderedSame {
            header = body.isEmpty ? "\(app) hat geschrieben." : "\(app): „\(body)“"
        } else {
            header = body.isEmpty ? "\(app): Nachricht von \(sender)." : "\(app), \(sender): „\(body)“"
        }
        let comments = isMail ? CatLines.mailComment : CatLines.messageComment
        queue { brain in
            brain.say([CatLine(0, header + "\n" + brain.pick(comments))], force: true, raw: true)
        }
    }

    /// Wartet, bis die vorige Blase gelesen werden konnte
    private func queue(_ action: @escaping @MainActor (CatBrain) -> Void) {
        let wait = max(0, 4.5 - Date().timeIntervalSince(lastSpoke))
        lastSpoke = Date().addingTimeInterval(wait)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.settings.catEnabled, !self.snoozed, !AlertState.shared.quiet else { return }
                action(self)
            }
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
        settings.catEnabled && introDone && !snoozed && !away && !sidebarBusy && !AlertState.shared.quiet
            && Date().timeIntervalSince(lastSpoke) > 8 && locate?() != nil
    }

    private func tick() {
        guard settings.catEnabled else { return }
        let now = Date()

        // Auftritt: beim Winken begrüßt er dich
        if !introDone {
            if now.timeIntervalSince(introStart) >= 6.6 {
                introDone = true
                set(.awake)
                activeSince = now
                if !snoozed { say(CatLines.intro, force: true) }
                scheduleNext()
            }
            return
        }
        if furious && now > furiousUntil { furious = false }
        if snoozed {
            if mood != .sleeping { set(.sleeping) }
            return
        }

        // Niemand am Mac → schlafen, beim Zurückkommen kurz kommentieren
        let idle = Self.idleSeconds()
        if idle > 300 { activeSince = now }
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
            say(context(returning: true) ?? (CatLines.back, [:]))
            scheduleNext()
            return
        }

        // Pausen-Erinnerung nach 90 Minuten am Stück
        if now.timeIntervalSince(activeSince) > 90 * 60, now.timeIntervalSince(lastPause) > 80 * 60, canSpeak {
            lastPause = now
            activeSince = now
            say(CatLines.pause)
            return
        }

        let age = now.timeIntervalSince(moodSince)
        switch mood {
        case .asking:
            if age > 150, canSpeak {
                ignoredToday += 1
                set(.annoyed(1))
                say(CatLines.annoyed1, style: .angry)
            }
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
        if roll < 0.3 {
            set(.asking)
            say(CatLines.ask)
        } else if roll < 0.62 {
            if let context = context(returning: false), Bool.random() {
                say(context)
            } else {
                say(jokes)
            }
        } else if roll < 0.74 {
            set(.purring)
            say(CatLines.purr, style: .purr)
        } else if roll < 0.9 {
            set(.sleeping)
            napUntil = Date().addingTimeInterval(.random(in: 600...1800))
            if Bool.random() { say(CatLines.nap) }
        } else {
            say(jokes)
        }
        scheduleNext()
    }

    /// Witze plus eigene Sprüche aus den Einstellungen
    private var jokes: [CatLine] {
        let own = settings.catCustomLines
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { CatLine(1, $0) }
        return CatLines.jokes + own + own // eigene Sprüche etwas häufiger
    }

    /// Sprüche passend zu Uhrzeit, Wochentag, Postfach und Ablagefach
    private func context(returning: Bool) -> ([CatLine], [String: String])? {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now) // 1 = Sonntag
        let time = now.formatted(date: .omitted, time: .shortened)
        if hour >= 20 || hour < 5 { return (CatLines.late, ["time": time]) }
        if returning && hour < 10 { return (CatLines.morning, [:]) }
        if returning && (12...13).contains(hour) { return (CatLines.lunch, [:]) }
        if returning { return nil }
        var options: [([CatLine], [String: String])] = []
        let unread = MailWatcher.shared.unread
        if unread >= 10 { options.append((CatLines.mailPile, ["n": "\(unread)"])) }
        if (store?.config.shelf.count ?? 0) >= 8 { options.append((CatLines.shelfFull, [:])) }
        if weekday == 1 || weekday == 7 { options.append((CatLines.weekend, [:])) }
        if weekday == 2 && hour < 11 { options.append((CatLines.monday, [:])) }
        if weekday == 6 && hour >= 14 { options.append((CatLines.friday, [:])) }
        if (12...13).contains(hour) { options.append((CatLines.lunch, [:])) }
        if hour < 10 { options.append((CatLines.morning, [:])) }
        return options.randomElement()
    }

    // MARK: Sprechen

    private func say(_ context: ([CatLine], [String: String]), style: CatBubbleStyle = .normal) {
        say(context.0, values: context.1, style: style)
    }

    private func say(_ lines: [CatLine], values: [String: String] = [:], style: CatBubbleStyle = .normal,
                     force: Bool = false, raw: Bool = false) {
        guard settings.catEnabled, !AlertState.shared.quiet else { return }
        guard force || canSpeak, let location = locate?() else { return }
        var text = raw ? (lines.first?.text ?? "") : pick(lines)
        for (key, value) in values { text = text.replacingOccurrences(of: "{\(key)}", with: value) }
        lastSpoke = Date()
        CatBubbleController.shared.show(text, style: style, at: location)
    }

    /// Ton „frech, wird schwarz“: frech – wird er ignoriert, genervt oder ist er wütend, wird's schwarz.
    private var tone: Int {
        switch settings.catTone {
        case 0: return 0
        case 1: return 1
        case 3: return 2
        default:
            if furious { return 2 }
            if case .annoyed = mood { return 2 }
            let chance = min(0.25 + Double(ignoredToday) * 0.15, 0.7)
            return Double.random(in: 0..<1) < chance ? 2 : 1
        }
    }

    /// Spruch passend zum Ton – meist aus der „schärfsten“ erlaubten Stufe, ohne Wiederholungen
    fileprivate func pick(_ lines: [CatLine]) -> String {
        let tone = self.tone
        let allowed = lines.filter { $0.tone <= tone }
        let top = allowed.filter { $0.tone == tone }
        var pool = (!top.isEmpty && Double.random(in: 0..<1) < 0.7) ? top : allowed
        if pool.isEmpty { pool = lines }
        let fresh = pool.filter { !recent.contains($0.text) }
        let line = (fresh.isEmpty ? pool : fresh).randomElement()?.text ?? "Hmpf."
        recent.append(line)
        if recent.count > 20 { recent.removeFirst() }
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

// MARK: - Anzeige

/// Rüdiger im runden Fenster – animiert.
struct CatView: View {
    let palette: Palette
    var openSettings: (() -> Void)?
    @ObservedObject private var brain = CatBrain.shared
    @State private var dropTargeted = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let pose = brain.pose(at: timeline.date)
            Canvas { context, size in
                CatPainter.draw(in: &context, size: size, pose: pose, dark: dark,
                                accent: palette.accent,
                                time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .overlay {
            // Versteckter Schalter (4 s mit der Maus auf Rüdiger)
            if brain.showSnoozeControl {
                Button {
                    brain.toggleSnooze()
                } label: {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.58))
                        VStack(spacing: 3) {
                            Image(systemName: brain.snoozed ? "sun.max.fill" : "moon.zzz.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(brain.snoozed ? "Schlummern\naus" : "Schlummern\nein")
                                .font(.system(size: 9.5, weight: .bold))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: brain.showSnoozeControl)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(dark ? 0.35 : 0.8), lineWidth: dropTargeted ? 3 : 2))
        .overlay(Circle().inset(by: 1.5).stroke(Color.black.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
        .contentShape(Circle())
        .onTapGesture { brain.pet() }
        // Datei auf Rüdiger ziehen → er lehnt ab (die Datei springt zurück)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { _ in
            brain.fileDropped()
            return false
        }
        .contextMenu {
            Button("Streicheln") { brain.pet() }
            Button("Leckerli geben") { brain.giveTreat() }
            if let openSettings {
                Divider()
                Button("Rüdiger-Einstellungen …") { openSettings() }
            }
        }
        .help("Rüdiger – klicken zum Streicheln")
    }
}

// MARK: - Einstellungen

struct CatSettingsSection: View {
    @ObservedObject var store: ConfigStore

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
                    Text("Frech → schwarz").tag(2)
                    Text("Schwarz").tag(3)
                }
                .pickerStyle(.segmented)
                Text("„Frech → schwarz“: anfangs frech – je mehr du ihn ignorierst oder nervst, desto schwärzer wird sein Humor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Liest neue Nachrichten und E-Mails vor", isOn: $store.config.settings.catMessages)
                Text("Statt der Einblendung am Icon liest Rüdiger Absender und Text vor – mit Kommentar. Ist Rüdiger aus (oder nicht zu sehen), erscheint wieder die Einblendung am Icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if CatGeometry.make(store.config.settings, clockOn: store.config.settings.showClock) == nil {
                    Text("Rüdiger sitzt im Viertelkreis zwischen Uhr und Leiste. Dafür muss die Uhr eingeschaltet sein und deutlich über die Leiste hinausragen (Uhr größer oder Leiste schmaler stellen).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        if store.config.settings.catEnabled {
            Section("Eigene Sprüche") {
                TextEditor(text: $store.config.settings.catCustomLines)
                    .font(.system(size: 12))
                    .frame(minHeight: 90)
                Text("Ein Spruch pro Zeile – Rüdiger mischt sie unter seine eigenen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Klick = streicheln · Rechtsklick = Leckerli · Datei draufziehen = lieber nicht. Ignorierst du ihn, wird er ungemütlich. Ist niemand am Mac, schläft er; im Ruhemodus ist er still. Nach 90 Minuten am Stück erinnert er dich an eine Pause.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
