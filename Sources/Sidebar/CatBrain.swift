import AppKit
import Combine
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Rüdigers Verhalten

enum CatPose: Equatable {
    /// noch nicht da (vor dem Auftritt)
    case absent
    /// schläft im Halbdunkel, bis der Auftritt beginnt (Sekunden bis dahin)
    case waiting(Double)
    case sleep, grumpy, ask, purr, angry
    /// genervt: Seitenblick, rollt mit den Augen, seufzt
    case annoyed
    /// Auftritt beim Start (Sekunden seit Beginn)
    case intro(Double)
    /// kleine Bewegung in der Ruhephase (Name der Animation, Sekunden seit Beginn)
    case clip(String, Double)
    /// läuft durchs Fenster (x = Mitte im 100er-Feld) – nur noch Ersatzzeichnung
    case walk(x: CGFloat, facingRight: Bool)

    /// Wartezeit vor dem Auftritt als Fortschritt 0 (gerade gestartet, dunkel) … 1 (gleich da)
    var waitProgress: Double? {
        if case .waiting(let left) = self { return 1 - min(1, max(0, left / CatTiming.introDelay)) }
        return nil
    }

    /// Name der Sprite-Animation
    var sprite: String? {
        switch self {
        case .absent, .walk: return nil
        case .sleep, .waiting: return "sleep"
        case .grumpy: return "idle"
        case .ask: return "ask"
        case .purr: return "purr"
        case .angry: return "angry"
        case .annoyed: return "annoyed"
        case .intro: return "intro"
        case .clip(let name, _): return name
        }
    }
}

/// Zeiten, die auch außerhalb des Hauptakteurs gebraucht werden
enum CatTiming {
    /// Sekunden von Start der Sidebar bis Rüdiger auftaucht
    static let introDelay: Double = 15
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

    /// So lange schläft Rüdiger im Halbdunkel, bis er nach dem Start der Sidebar auftaucht und dich begrüßt.
    let introStart = Date().addingTimeInterval(CatTiming.introDelay)
    static let introLength: Double = 3.6
    private(set) var introDone = false

    /// Maus/Eingabe gerade in der Sidebar → nicht dazwischenquatschen
    var sidebarBusy = false
    weak var store: ConfigStore?
    var locate: (@MainActor () -> CatLocation?)?

    private var settings = SidebarSettings()
    private var timer: Timer?
    private var moodSince = Date()
    private var nextEventAt = Date().addingTimeInterval(CatTiming.introDelay + 600)
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
    /// gerade laufende besondere Animation (Fressen, Wecker)
    private var special: (name: String, start: Date, length: Double, loop: Bool)?
    /// eine Datei wird gerade über Rüdiger gezogen
    @Published var feedHover = false {
        didSet { if feedHover && !oldValue { feedHoverStart = Date() } }
    }
    private var feedHoverStart = Date()
    /// Rüdiger wird gerade mit der Maus getragen (schaut überrascht)
    @Published var carried = false {
        didSet { if carried && !oldValue { carriedStart = Date() } }
    }
    private var carriedStart = Date()
    // Wetter: Ereignisse (Blitzeinschlag, Schnee abschütteln)
    enum WeatherEventKind { case strike, shake }
    private var weatherEvent: (kind: WeatherEventKind, start: Date)?
    private var nextStrike = Date().addingTimeInterval(40)
    private var nextShake = Date().addingTimeInterval(45)
    private var lastShake: Date?
    private var lastWeatherComment = Date.distantPast
    private var lastCommentedWeather: WeatherMood = .normal
    /// zeigt gerade ein Wetter (steuert, ob die Wetter-Ebene läuft)
    @Published private(set) var weatherActive = false
    /// Rüdiger sitzt gerade am Lehrer-Blatt (sein normaler Platz ist so lange leer)
    @Published var teaching = false
    /// Knopf „Text prüfen“: sichtbar (Maus in der Nähe) und in welche Richtung (x/y je ±1, y nach unten)
    @Published var homeworkBadge: CGPoint?
    /// Maus direkt auf dem Knopf
    @Published var homeworkHover = false
    /// zuletzt abgesetzt – für das kleine „Plumps“
    @Published private(set) var landedAt = Date.distantPast
    // Feierabend
    private var alarmDay: Int?
    private var alarmNudge: Date?
    // Akku
    private var lastBatteryCheck = Date.distantPast
    private var batteryWarned: Int = 101
    /// kleine Bewegungen in der Ruhephase – etwa alle 20 Sekunden eine
    private static let idleClips = ["idle_tilt", "idle_look", "idle_tongue", "idle_slowblink", "idle_ears", "idle_stretch"]
    private var idleClip: (name: String, start: Date, length: Double)?
    private var nextIdleClip = Date().addingTimeInterval(55)
    /// Aussehen während einer Geste (Pfote draußen)
    private var gesturePose: CatPose?
    private var gestureEnd = Date.distantPast

    private init() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Nach dem Tragen abgesetzt
    func landed() {
        landedAt = Date()
    }

    func apply(_ settings: SidebarSettings) {
        self.settings = settings
        if !settings.catEnabled { CatBubbleController.shared.hide() }
    }

    /// Rüdiger ist zu sehen und übernimmt das Vorlesen neuer Nachrichten (statt der Einblendung am Icon)
    var takesOverMessages: Bool {
        settings.catEnabled && settings.catMessages && introDone && !teaching && locate?() != nil
    }

    /// Lehrer-Blatt öffnen
    func openHomework() {
        homeworkBadge = nil
        homeworkHover = false
        HomeworkController.shared.open()
    }

    /// Bereich des Knopfs „Text prüfen“ auf dem Bildschirm (für Klicks und Mausnähe)
    func homeworkBadgeRect(for cat: NSRect, corner: CGPoint) -> NSRect {
        let d = cat.width
        let center = NSPoint(x: cat.midX + corner.x * HomeworkBadge.offset * d,
                             y: cat.midY - corner.y * HomeworkBadge.offset * d)
        let side = HomeworkBadge.size + 4
        return NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// Kurzer Satz in Rüdigers normaler Sprechblase
    func remark(_ text: String) {
        guard settings.catEnabled, let location = locate?() else { return }
        lastSpoke = Date()
        CatBubbleController.shared.show(text, style: .purr, at: location)
    }

    // MARK: Aussehen

    func pose(at date: Date) -> CatPose {
        let since = date.timeIntervalSince(introStart)
        if since < 0 { return .waiting(-since) }
        // Auftritt: taucht in der Blase auf, schaut sich um und winkt
        if since < Self.introLength { return CatSprites.shared.has("intro") ? .intro(since) : .ask }
        if carried { return .clip("eat_ready", date.timeIntervalSince(carriedStart)) }
        if let gesturePose, date < gestureEnd { return gesturePose }
        // Füttern (Datei schwebt über ihm / er frisst) und Feierabend-Wecker
        if let special {
            let since = date.timeIntervalSince(special.start)
            if since >= 0, special.loop || since < special.length { return .clip(special.name, since) }
        }
        if feedHover { return .clip("eat_ready", date.timeIntervalSince(feedHoverStart)) }
        if snoozed || mood == .sleeping { return .sleep }
        if furious { return .angry }
        // Wetter (nur im normalen Wachzustand – seine eigenen Reaktionen gehen vor)
        if let weather = weatherPose(at: date) { return weather }
        // kleine Bewegung in der Ruhephase (Kopf neigen, Zunge raus, Blinzeln …)
        if mood == .awake, let clip = idleClip {
            let since = date.timeIntervalSince(clip.start)
            if since >= 0, since < clip.length { return .clip(clip.name, since) }
        }
        switch mood {
        case .asking: return .ask
        case .purring: return .purr
        case .annoyed(let level): return level >= 2 ? .angry : .annoyed
        default: return .grumpy
        }
    }

    // MARK: Wetter

    /// Welches Wetter Rüdiger gerade zeigt. Nur im normalen Wachzustand: Streicheln, Füttern, Wecker, Nachrichten,
    /// Lehrer-Blatt, Genervtsein und Schlafen gehen vor – es läuft nie mehr als eine Animation.
    func activeWeather() -> WeatherMood {
        guard settings.weatherEnabled, introDone, !teaching, !carried, !feedHover, !snoozed, !furious,
              mood == .awake, special == nil, gesturePose == nil else { return .normal }
        return WeatherService.shared.mood
    }

    /// Wetter-Ebene für einen Zeitpunkt
    func weatherFrame(at date: Date) -> WeatherFrame {
        let weather = activeWeather()
        var frame = WeatherFrame(mood: weather, t: date.timeIntervalSinceReferenceDate, strikeT: nil, shakeT: nil, snowCap: 1)
        if let event = weatherEvent {
            let since = date.timeIntervalSince(event.start)
            if event.kind == .strike, weather == .thunder, since >= 0, since < 4 { frame.strikeT = since }
            if event.kind == .shake, weather == .snow, since >= 0, since < 2.6 { frame.shakeT = since }
        }
        if weather == .snow, let shake = lastShake {
            // nach dem Schütteln wächst die Schneehaube langsam nach
            let since = date.timeIntervalSince(shake)
            frame.snowCap = since < 0.5 ? 1 : min(1, max(0, (since - 2.6) / 40))
        }
        return frame
    }

    private func weatherPose(at date: Date) -> CatPose? {
        let weather = activeWeather()
        guard weather != .normal else { return nil }
        if let event = weatherEvent {
            let since = date.timeIntervalSince(event.start)
            if event.kind == .strike, weather == .thunder, since >= 0, since < 4 { return .clip("struck", since) }
            if event.kind == .shake, weather == .snow, since >= 0, since < 2.6 { return .clip("shake", since) }
        }
        if let clip = weather.clip { return .clip(clip, date.timeIntervalSinceReferenceDate) }
        // normale Bilder – die Wetter-Ebene liegt darüber, keine kleinen Ruhebewegungen dazwischen
        return .grumpy
    }

    /// Jede Sekunde: Gewitter weckt ihn, Blitzeinschlag und Schütteln auslösen, Sprüche beim Wetterwechsel
    private func handleWeather(_ now: Date) {
        guard settings.weatherEnabled else {
            weatherEvent = nil
            if weatherActive { weatherActive = false }
            return
        }
        // Ein Gewitter holt ihn aus dem Schlaf
        if WeatherService.shared.mood == .thunder, mood == .sleeping {
            napUntil = nil
            set(.awake)
            activeSince = now
        }
        let weather = activeWeather()
        let active = weather != .normal
        if weatherActive != active { weatherActive = active }

        if let event = weatherEvent, now.timeIntervalSince(event.start) > 5 { weatherEvent = nil }
        if weatherEvent == nil, locate?() != nil {
            if weather == .thunder, now >= nextStrike {
                weatherEvent = (kind: .strike, start: now)
                nextStrike = now.addingTimeInterval(.random(in: 180...480))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    MainActor.assumeIsolated {
                        self?.say(WeatherLines.struck, style: .angry, force: true, raw: true)
                    }
                }
            } else if weather == .snow, now >= nextShake {
                weatherEvent = (kind: .shake, start: now)
                lastShake = now
                nextShake = now.addingTimeInterval(.random(in: 60...120))
                if Double.random(in: 0..<1) < 0.4 { say(WeatherLines.shake) }
            }
        }
        // Frecher Spruch beim Wetterwechsel – höchstens alle zwei Stunden
        if weather != lastCommentedWeather {
            lastCommentedWeather = weather
            if weather != .normal, now.timeIntervalSince(lastWeatherComment) > 7200 {
                lastWeatherComment = now
                say(WeatherLines.lines(for: weather))
            }
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

    /// Datei wurde Rüdiger gefüttert. `added`: Anzahl neuer Dateien im Ablagefach (0 = nichts Fressbares)
    func fed(added: Int) {
        feedHover = false
        guard settings.catEnabled else { return }
        guard added > 0 else {
            fileDropped()
            return
        }
        napUntil = nil
        set(.awake)
        let length = CatSprites.shared.sequence("eat")?.duration ?? 2.5
        special = ("eat", Date(), length, false)
        // erst ein Rülpser, dann sein Kommentar
        let comment = added >= 5 ? CatLines.ateLots : (added > 1 ? CatLines.ateMany : CatLines.ate)
        DispatchQueue.main.asyncAfter(deadline: .now() + length - 0.9) { [weak self] in
            MainActor.assumeIsolated {
                self?.say(CatLines.burp, style: .purr, force: true, raw: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + length + 2.2) { [weak self] in
            MainActor.assumeIsolated {
                self?.say(comment, values: ["n": "\(added)"], force: true)
            }
        }
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

    // MARK: Feierabend-Wecker

    private func checkEndOfDay(_ now: Date) {
        guard settings.catEndOfDay, !snoozed, !AlertState.shared.quiet else { return }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)       // 1 = Sonntag
        if settings.catEndWeekdays && (weekday == 1 || weekday == 7) { return }
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        guard let target = calendar.date(bySettingHour: settings.catEndHour, minute: settings.catEndMinute, second: 0, of: now)
        else { return }
        let idle = Self.idleSeconds()
        if alarmDay != day, now >= target, now.timeIntervalSince(target) < 2 * 3600, idle < 300 {
            alarmDay = day
            alarmNudge = now.addingTimeInterval(30 * 60)
            ring(CatLines.endOfDay)
        } else if let nudge = alarmNudge, now >= nudge {
            alarmNudge = nil
            if idle < 300 { ring(CatLines.endOfDayAgain) }      // immer noch da?
        }
    }

    private func ring(_ lines: [CatLine], test: Bool = false) {
        napUntil = nil
        if !snoozed { set(.awake) }
        let length = CatSprites.shared.sequence("alarm")?.duration ?? 3
        special = ("alarm", Date(), length, false)
        say(lines, values: ["time": Date().formatted(date: .omitted, time: .shortened)], style: .angry, force: true,
            ignoreQuiet: test)
    }

    /// Wecker zum Ausprobieren (Einstellungen) – klappt auch im Ruhe- und Schlummermodus.
    /// `false`, wenn Rüdiger gerade nicht zu sehen ist.
    @discardableResult
    func testAlarm() -> Bool {
        guard settings.catEnabled, locate?() != nil else { return false }
        ring(CatLines.endOfDay, test: true)
        return true
    }

    // MARK: Akku

    private func checkBattery() {
        guard settings.catBattery, let battery = Battery.read() else { return }
        if battery.charging {
            if batteryWarned <= 20 { say(CatLines.pluggedIn, force: true) }
            batteryWarned = 101
            return
        }
        for level in [5, 10, 20] where battery.percent <= level && batteryWarned > level {
            batteryWarned = level
            let lines = level == 5 ? CatLines.battery5 : (level == 10 ? CatLines.battery10 : CatLines.battery20)
            say(lines, values: ["p": "\(battery.percent)"], style: level <= 10 ? .angry : .normal, force: true)
            return
        }
    }

    // MARK: Gesten

    /// Pfote kommt aus dem Fenster und kratzt bzw. winkt abfällig.
    func performGesture(_ gesture: CatGesture) {
        guard let location = locate?() else { return }
        // Während der Geste spielt das Gesten-Fenster die Sprite-Bilder ab (er beugt sich heraus) –
        // im eigenen Fenster bleibt so lange nur der Hintergrund.
        guard CatGestureController.shared.perform(gesture, at: location) else { return }
        gesturePose = .absent
        gestureEnd = Date().addingTimeInterval(gesture.catTime)
    }

    /// Beim Beenden: abfälliger Spruch mit Geste. `false`, wenn Rüdiger gerade nicht da ist.
    func sayGoodbye() -> Bool {
        guard settings.catEnabled, introDone, !snoozed, !AlertState.shared.quiet, locate?() != nil else { return false }
        napUntil = nil
        set(.awake)
        performGesture(.flick)
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
            queue { brain in
                brain.say(CatLines.flood, style: .angry, force: true)
                brain.performGesture(.scratch)
            }
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
        // gesperrt / Bildschirmschoner: Rüdiger denkt nicht (Feierabend-Wecker usw. holt er danach nach)
        guard settings.catEnabled, !PowerState.shared.paused, !teaching else { return }
        let now = Date()

        // Auftritt: beim Winken begrüßt er dich
        if !introDone {
            if now.timeIntervalSince(introStart) >= 2.0 {
                introDone = true
                set(.awake)
                activeSince = now
                if !snoozed { say(CatLines.intro, force: true) }
                scheduleNext()
            }
            return
        }
        if furious && now > furiousUntil { furious = false }
        // Ruhephase: ab und zu eine kleine Bewegung
        if mood == .awake, !furious, now >= nextIdleClip, now >= gestureEnd {
            let choices = Self.idleClips.filter { $0 != idleClip?.name }
            if let name = choices.randomElement(), let sequence = CatSprites.shared.sequence(name) {
                idleClip = (name, now, sequence.duration)
            }
            nextIdleClip = now.addingTimeInterval(.random(in: 16...24))
        }
        if gesturePose != nil && now > gestureEnd { gesturePose = nil }
        if let special, !special.loop, now.timeIntervalSince(special.start) > special.length { self.special = nil }
        checkEndOfDay(now)
        if now.timeIntervalSince(lastBatteryCheck) > 60 {
            lastBatteryCheck = now
            checkBattery()
        }
        if snoozed {
            if mood != .sleeping { set(.sleeping) }
            return
        }
        handleWeather(now)
        // Einmalig nach dem Update: auf „Text prüfen“ hinweisen
        if !settings.catHomeworkHint, now.timeIntervalSince(introStart) > 90, !sidebarBusy,
           !AlertState.shared.quiet, now.timeIntervalSince(lastSpoke) > 20, locate?() != nil {
            store?.config.settings.catHomeworkHint = true
            remark("Neu: Ich korrigiere jetzt auch Texte. Fahr mit der Maus zu mir – dann siehst du das Heft.")
        } else if settings.catHomeworkHint, !settings.catWeatherHint, !settings.weatherEnabled,
                  now.timeIntervalSince(introStart) > 120, !sidebarBusy, !AlertState.shared.quiet,
                  now.timeIntervalSince(lastSpoke) > 20, locate?() != nil {
            store?.config.settings.catWeatherHint = true
            remark("Neu: Ich kann das Wetter spiegeln. Einstellungen → Wetter – dort gibt's auch eine Vorschau.")
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
                if level + 1 == 2 { performGesture(.scratch) }
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
        } else if roll < 0.8 {
            say(CatLines.scratch)
            performGesture(.scratch)
        } else if roll < 0.92 {
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
                     force: Bool = false, raw: Bool = false, ignoreQuiet: Bool = false) {
        guard settings.catEnabled, ignoreQuiet || !AlertState.shared.quiet else { return }
        guard force || canSpeak, let location = locate?() else { return }
        var text = raw ? (lines.first?.text ?? "") : pick(lines)
        for (key, value) in values { text = text.replacingOccurrences(of: "{\(key)}", with: value) }
        text = addressed(text, raw: raw)
        lastSpoke = Date()
        CatBubbleController.shared.show(text, style: style, at: location)
    }

    /// Spricht dich ab und zu mit Namen an („Streichel mich, Christian!“) und füllt {du}
    private func addressed(_ text: String, raw: Bool) -> String {
        let name = settings.userName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return text.replacingOccurrences(of: ", {du}", with: "").replacingOccurrences(of: "{du}, ", with: "")
                .replacingOccurrences(of: "{du}", with: "")
        }
        if text.contains("{du}") { return text.replacingOccurrences(of: "{du}", with: name) }
        guard !raw, !text.contains("\n"), Double.random(in: 0..<1) < 0.3 else { return text }
        // vor dem Satzzeichen am Ende einfügen
        var body = text
        var end = ""
        while let last = body.last, ".!?…".contains(last) {
            end = String(last) + end
            body.removeLast()
        }
        if body.hasSuffix(" ") { body.removeLast() }
        return body + ", " + name + (end.isEmpty ? "." : end)
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
    /// Dateien ins Ablagefach legen – liefert die Anzahl neu abgelegter Dateien
    var onFeed: (([DropPayload]) -> Int)?
    /// Rüdiger wird mit der Maus gepackt (ziehen statt klicken)
    var onCarry: (() -> Void)?
    /// nur schwebend: Menüpunkt „Zurück in die Sidebar“
    var onReturnToDock: (() -> Void)?
    @ObservedObject private var brain = CatBrain.shared
    @ObservedObject private var power = PowerState.shared
    @State private var dropTargeted = false
    @State private var squash = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            // Glasblase in der Farbwelt (Rand und Lichtreflexe liegen in den Sprite-Bildern)
            Circle()
                .fill(palette.accent.opacity(dark ? 0.35 : 0.45))
                .blur(radius: 6)
                .padding(-3)
            Circle().fill(Color.white.opacity(dark ? 0.08 : 0.88))
            Circle().fill(RadialGradient(colors: [Color.white.opacity(dark ? 0.12 : 0.5), palette.accent.opacity(dark ? 0.5 : 0.55)],
                                         center: UnitPoint(x: 0.45, y: 0.36), startRadius: 2, endRadius: 60))
            // Schläft er, reichen 12 Bilder pro Sekunde; sieht niemand hin, steht die Animation still
            TimelineView(.animation(minimumInterval: (brain.snoozed || brain.mood == .sleeping) ? 1.0 / 12.0 : 1.0 / 30.0,
                                    paused: power.paused)) { timeline in
                let pose = brain.pose(at: timeline.date)
                // Vor dem Auftritt: Kugel im Halbdunkel, Rüdiger schläft kaum sichtbar und wird nach und nach heller
                let waiting = pose.waitProgress
                if let name = pose.sprite, let image = CatSprites.shared.frame(name, pose: pose, at: timeline.date) {
                    // Das Bild ist etwas größer als die Blase, damit Ohrenspitzen herausragen können
                    ZStack {
                        if let waiting {
                            Circle().fill(Color.black.opacity(0.42 * (1 - waiting)))
                        }
                        GeometryReader { proxy in
                            let side = proxy.size.width * CGFloat(CatSprites.shared.span(name))
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: side, height: side)
                                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                                .opacity(waiting.map { 0.3 + 0.7 * $0 } ?? 1)
                                .brightness(waiting.map { -0.35 * (1 - $0) } ?? 0)
                        }
                    }
                } else {
                    // Ersatz, falls die Bilder fehlen
                    Canvas { context, size in
                        CatPainter.draw(in: &context, size: size, pose: pose, dark: dark,
                                        accent: palette.accent,
                                        time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                    .clipShape(Circle())
                }
            }
            // Wetter-Ebene (Regen, Schnee, Sonnenbrille, Blitz …) – nur wenn gerade Wetter angezeigt wird
            if brain.weatherActive {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: power.paused)) { timeline in
                    let weather = brain.weatherFrame(at: timeline.date)
                    GeometryReader { proxy in
                        WeatherCanvas(frame: weather)
                            .frame(width: proxy.size.width * 1.3, height: proxy.size.height * 1.3)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }
                .allowsHitTesting(false)
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
        .overlay(Circle().stroke(Color.white.opacity(dropTargeted ? 0.95 : 0), lineWidth: 3))
        // Getragen: etwas größer · abgesetzt: kurz platt gedrückt („Plumps“)
        .scaleEffect(x: squash ? 1.12 : (brain.carried ? 1.07 : 1),
                     y: squash ? 0.86 : (brain.carried ? 1.07 : 1), anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.45), value: squash)
        .animation(.easeOut(duration: 0.15), value: brain.carried)
        .onChange(of: brain.landedAt) { _, _ in
            guard onCarry != nil else { return }
            squash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { squash = false }
        }
        .contentShape(Circle())
        .onTapGesture { brain.pet() }
        .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global)
            // Weitertragen übernimmt das Fenster selbst (folgt der Maus bis zum Loslassen)
            .onChanged { _ in onCarry?() })
        // Datei auf Rüdiger ziehen → er lehnt ab (die Datei springt zurück)
        // Datei auf Rüdiger ziehen → er frisst sie und legt sie ins Ablagefach
        .linkDropTarget(isTargeted: $dropTargeted) { payloads in
            brain.fed(added: onFeed?(payloads) ?? 0)
        }
        .onChange(of: dropTargeted) { _, targeted in brain.feedHover = targeted }
        .contextMenu {
            Button("Streicheln") { brain.pet() }
            Button("Leckerli geben") { brain.giveTreat() }
            Button("Text prüfen …") { brain.openHomework() }
            if let onReturnToDock {
                Button("Zurück in die Sidebar") { onReturnToDock() }
            }
            if let openSettings {
                Divider()
                Button("Rüdiger-Einstellungen …") { openSettings() }
            }
        }
        .help("Rüdiger – klicken zum Streicheln")
        // Sitzt er am Lehrer-Blatt, ist sein Platz leer
        .opacity(brain.teaching ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: brain.teaching)
        .allowsHitTesting(!brain.teaching)
        // Knopf „Text prüfen“ – nur bei Maus in der Nähe
        .overlay {
            if let corner = brain.homeworkBadge, !brain.teaching {
                GeometryReader { proxy in
                    HomeworkBadge(hovered: brain.homeworkHover) { brain.openHomework() }
                        .position(x: proxy.size.width / 2 + corner.x * HomeworkBadge.offset * proxy.size.width,
                                  y: proxy.size.height / 2 + corner.y * HomeworkBadge.offset * proxy.size.height)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.1), value: brain.homeworkBadge != nil)
    }
}

// MARK: - Einstellungen

struct CatSettingsSection: View {
    @ObservedObject var store: ConfigStore
    @State private var alarmTestFailed = false

    /// Uhrzeit des Feierabends als Datum (für den Zeitwähler)
    private var endTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: store.config.settings.catEndHour,
                                  minute: store.config.settings.catEndMinute, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.config.settings.catEndHour = parts.hour ?? 18
            store.config.settings.catEndMinute = parts.minute ?? 0
        })
    }

    var body: some View {
        Section("Rüdiger") {
            Toggle("Rüdiger anzeigen", isOn: $store.config.settings.catEnabled)
            if store.config.settings.catEnabled {
                TextField("Dein Name", text: $store.config.settings.userName, prompt: Text("z. B. Christian"))
                Text("Rüdiger spricht dich ab und zu mit Namen an. Leer lassen, wenn nicht.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
        }
        if store.config.settings.catEnabled {
            Section("Platz") {
                Picker("Rüdiger sitzt", selection: $store.config.settings.catFloating) {
                    Text("In der Sidebar").tag(false)
                    Text("Schwebend").tag(true)
                }
                .pickerStyle(.segmented)
                if store.config.settings.catFloating {
                    Toggle("Immer im Vordergrund", isOn: $store.config.settings.catFloatOnTop)
                    Text(store.config.settings.catFloatOnTop
                         ? "Rüdiger bleibt über allen Fenstern."
                         : "Geöffnete Programme können Rüdiger verdecken – er bleibt dann im Hintergrund.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Rüdiger mit der Maus packen und irgendwo absetzen – auch auf einem anderen Bildschirm. Klickbar ist nur sein Kreis. Zurück in die Sidebar: auf den gestrichelten Kreis an der Uhr ziehen. Sein Platz bleibt gespeichert, auch nach einem Neustart.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tipp: Rüdiger von seinem Platz an der Uhr wegziehen – dann schwebt er frei.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if CatGeometry.make(store.config.settings, clockOn: store.config.settings.showClock) == nil {
                        Text("Rüdiger sitzt im Bogen zwischen Uhr und Leiste. Dafür muss die Uhr eingeschaltet sein und deutlich über die Leiste hinausragen (Uhr größer oder Leiste schmaler stellen) – oder „Schwebend“ wählen.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        if store.config.settings.catEnabled {
            Section("Feierabend-Wecker") {
                Toggle("Rüdiger klingelt zum Feierabend", isOn: $store.config.settings.catEndOfDay)
                if store.config.settings.catEndOfDay {
                    DatePicker("Feierabend um", selection: endTime, displayedComponents: .hourAndMinute)
                    Toggle("Nur Montag bis Freitag", isOn: $store.config.settings.catEndWeekdays)
                    HStack {
                        Button("Wecker ausprobieren") { alarmTestFailed = !CatBrain.shared.testAlarm() }
                        if alarmTestFailed {
                            Text("Rüdiger ist gerade nicht zu sehen (Uhr aus, Sidebar ausgeblendet oder kein Platz an der Uhr).")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("Zur eingestellten Zeit wackelt er wie ein Wecker und schickt dich heim. Bist du 30 Minuten später immer noch da, meldet er sich noch einmal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Nachrichten, Ablagefach & Mac") {
                Toggle("Liest neue Nachrichten und E-Mails vor", isOn: $store.config.settings.catMessages)
                Text("Statt der Einblendung am Icon liest Rüdiger Absender und Text vor – mit Kommentar. Ist Rüdiger aus, erscheint wieder die Einblendung am Icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Kommentiert den Akku (20 %, 10 %, 5 %)", isOn: $store.config.settings.catBattery)
                Text("Dateien auf Rüdiger ziehen: Er frisst sie und legt sie ins Ablagefach (die Dateien bleiben, wo sie sind).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Eigene Sprüche") {
                TextEditor(text: $store.config.settings.catCustomLines)
                    .font(.system(size: 12))
                    .frame(minHeight: 90)
                Text("Ein Spruch pro Zeile – Rüdiger mischt sie unter seine eigenen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Text prüfen: Maus in Rüdigers Nähe → Heft anklicken (oder Rechtsklick → „Text prüfen …“). Er streicht rot an und gibt eine Note – verbessern musst du selbst, erst dann lässt sich der Text kopieren. Alles wird lokal auf dem Mac geprüft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Klick = streicheln · Rechtsklick = Leckerli · Datei draufziehen = füttern. Ignorierst du ihn, wird er ungemütlich. Ist niemand am Mac, schläft er; im Ruhemodus ist er still. Nach 90 Minuten am Stück erinnert er dich an eine Pause.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
