import AppKit
import SwiftUI

// MARK: - Vorschaubilder (beim Bau: `Sidebar --selftest --snapshots <Ordner>`)
//
// Zeichnet die echten Ansichten der App (Sprechblase, Rüdiger beim Start, obere Leiste, Notiz-Kacheln)
// mit dem Code der App in PNG-Dateien. So lässt sich nach einem Update ansehen, wie es wirklich aussieht.

@MainActor
enum Snapshots {
    static func run(into directory: URL) -> [String] {
        var failures: [String] = []
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ConfigStore.shared
        var settings = store.config.settings
        settings.edge = .top
        settings.showClock = true
        settings.catEnabled = true
        settings.catFloating = false
        store.config.settings = settings
        let palette = Palette.resolve(settings.colorTheme, .dark)

        func save<V: View>(_ name: String, size: CGSize, dark: Bool = true, wallpaper: Bool = true, @ViewBuilder _ content: () -> V) {
            let root = ZStack(alignment: .topLeading) {
                if wallpaper {
                    LinearGradient(colors: dark ? [Color(red: 0.16, green: 0.25, blue: 0.38), Color(red: 0.33, green: 0.24, blue: 0.40)]
                                                : [Color(red: 0.80, green: 0.86, blue: 0.93), Color(red: 0.93, green: 0.88, blue: 0.84)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                content()
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.colorTheme, settings.colorTheme)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                failures.append("Vorschau \(name): kein Bild"); return
            }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                failures.append("Vorschau \(name): PNG fehlgeschlagen"); return
            }
            do { try data.write(to: directory.appendingPathComponent(name + ".png")) }
            catch { failures.append("Vorschau \(name): \(error.localizedDescription)") }
        }

        // 1 · Sprechblase mit Rüdiger (Hell und Dunkel)
        func bubble(_ text: String, style: CatBubbleStyle = .normal) -> some View {
            let layout = CatBubbleLayout.make(text, style: style, maxSize: CGSize(width: 360, height: 200))
            let margin: CGFloat = 46
            let bw = layout.bubbleSize.width, bh = layout.bubbleSize.height
            // Kugel links unten; die Blase sitzt seitlich oberhalb (wie in der App: 22 pt Abstand, etwas höher)
            let ball: CGFloat = 96
            let ballRect = CGRect(x: 6, y: bh * 0.7, width: ball, height: ball)
            let body = CGRect(x: ballRect.maxX + 22 + margin, y: margin, width: bw, height: bh)
            let size = CGSize(width: body.maxX + margin, height: ballRect.maxY + 14)
            // Spitze: wie in der App – vom Mittelpunkt der Blase zur Kugel, endet am Kugelrand
            let c = CGPoint(x: body.midX, y: body.midY)
            let dx = ballRect.midX - c.x, dy = ballRect.midY - c.y
            let distance = max((dx * dx + dy * dy).squareRoot(), 1)
            let edgeRadius = min(bw / 2 / max(abs(dx / distance), 0.001), bh / 2 / max(abs(dy / distance), 0.001))
            let reach = min(distance - ball / 2 - 3, edgeRadius + 40)
            let tail = CGPoint(x: c.x + dx / distance * max(reach, edgeRadius + 12),
                               y: c.y + dy / distance * max(reach, edgeRadius + 12))
            return ZStack(alignment: .topLeading) {
                SketchBubbleView(text: text, style: style, body: body, tail: tail, size: size,
                                 fontSize: layout.fontSize, textSize: layout.textSize, drawIn: false)
                CatView(palette: palette).frame(width: ball, height: ball).offset(x: ballRect.minX, y: ballRect.minY)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        CatBrain.shared.overridePose = .grumpy
        for (name, dark) in [("blase-dunkel", true), ("blase-hell", false)] {
            save(name, size: CGSize(width: 1240, height: 300), dark: dark) {
                HStack(alignment: .top, spacing: 8) {
                    bubble("Na toll. Regen. Und ich hab keinen Schirm.")
                    bubble("Das ist jetzt schon die dritte Mail!", style: .angry)
                    bubble("Mehr davon. Bitte.", style: .purr)
                }
                .padding(10)
            }
        }
        save("blase-lang", size: CGSize(width: 640, height: 340)) {
            bubble("Das ist jetzt schon die dritte Mail von Frau Meier heute und es ist erst Mittag, wirklich.").padding(10)
        }

        // 2 · Rüdiger beim Start: Wartezeit (dunkel → hell) und Auftritt
        let steps: [(String, CatPose)] = [
            ("start-1-0s", .waiting(CatTiming.introDelay)),
            ("start-2-5s", .waiting(CatTiming.introDelay * 0.66)),
            ("start-3-10s", .waiting(CatTiming.introDelay * 0.33)),
            ("start-4-14s", .waiting(0.6)),
            ("start-5-auftritt", .intro(1.4)),
        ]
        save("start", size: CGSize(width: 130 * CGFloat(steps.count) + 20, height: 150)) {
            HStack(spacing: 10) {
                ForEach(0..<steps.count, id: \.self) { i in
                    CatStill(palette: palette, pose: steps[i].1)
                }
            }
            .padding(10)
        }

        // 3 · Obere Leiste mit Uhr und Rüdiger
        CatBrain.shared.overridePose = .grumpy
        let state = SidebarState()
        let actions = SidebarActions(open: { _, _ in }, openSettings: {}, editItem: { _ in }, addLink: { _ in },
                                     chooseIcon: { _ in }, toggleFlyout: { _ in }, installUpdate: {}, openSearch: {},
                                     triggerAction: { _ in }, submitAction: { _, _ in }, drag: { _, _ in })
        let clock = ClockLayout.panelSize(settings)
        let barHeight = max(clock.height, CGFloat(settings.collapsedThickness))
        for (name, dark) in [("leiste-dunkel", true), ("leiste-hell", false)] {
            save(name, size: CGSize(width: 1280, height: barHeight + 40), dark: dark) {
                SidebarView(store: store, state: state, updater: Updater.shared, geometry: SidebarGeometry(), actions: actions)
                    .frame(width: 1280, height: barHeight)
            }
        }

        // 4 · Notizfenster mit Kacheln
        var notes = store.config.notes
        if notes.isEmpty {
            let samples = ["Rückruf Frau Meier, Do 14 Uhr, wegen der Unterlagen", "Milch, Eier, Brot, Kaffee",
                           "Steuerunterlagen sortieren und Belege prüfen", "Geburtstag nicht vergessen: Geschenk besorgen",
                           "Neues Layout für die Startseite überlegen"]
            notes = samples.enumerated().map { QuickNote(text: $0.element, tint: $0.offset) }
            store.config.notes = notes
        }
        for (name, dark) in [("notizen-dunkel", true), ("notizen-hell", false)] {
            save(name, size: CGSize(width: NotesView.size.width + 40, height: NotesView.size.height + 40), dark: dark) {
                NotesView(store: store, theme: settings.colorTheme, onClose: {}).padding(20)
            }
        }
        // 5 · Alle Animationen (Standbilder) und alle Wetterzustände mit dem Moppel
        let sprites = ["idle", "annoyed", "angry", "ask", "purr", "sleep", "wet", "cold", "windy", "eat_ready",
                       "eat", "intro", "struck", "shake", "alarm", "idle_tongue", "idle_stretch", "idle_look", "idle_tilt", "idle_slowblink"]
        func midTime(_ name: String) -> Double { (CatSprites.shared.sequence(name)?.duration ?? 1) * 0.45 }
        let spriteColumns = 5
        save("animationen", size: CGSize(width: 150 * CGFloat(spriteColumns) + 20, height: 150 * CGFloat((sprites.count + spriteColumns - 1) / spriteColumns) + 20), wallpaper: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<((sprites.count + spriteColumns - 1) / spriteColumns), id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<spriteColumns, id: \.self) { col in
                            let i = row * spriteColumns + col
                            if i < sprites.count { CatStill(palette: palette, pose: .clip(sprites[i], midTime(sprites[i]))).frame(width: 150, height: 150) }
                        }
                    }
                }
            }
            .padding(10)
        }
        let moods: [WeatherMood] = [.rain, .hot, .sweat, .wind, .thunder, .frost, .snow]
        save("wetter", size: CGSize(width: 150 * 4 + 20, height: 150 * 2 + 20)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { col in
                            let i = row * 4 + col
                            if i < moods.count {
                                WeatherPreviewScript.art(mood: moods[i], kindIndex: 0, local: 2, now: 2.3, accent: palette.accent)
                                    .frame(width: 96, height: 96).padding(27)
                            } else if i == 7 {
                                WeatherPreviewScript.art(mood: .thunder, kindIndex: 1, local: 1.6, now: 2.3, accent: palette.accent)
                                    .frame(width: 96, height: 96).padding(27)
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        CatBrain.shared.overridePose = nil
        return failures
    }
}

/// Rüdigers Fenster in fester Haltung (für die Vorschau)
struct CatStill: View {
    let palette: Palette
    let pose: CatPose
    var body: some View {
        let waiting = pose.waitProgress
        ZStack {
            Circle().fill(palette.accent.opacity(0.35)).blur(radius: 6).padding(-3)
            Circle().fill(Color.white.opacity(0.08))
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.12), palette.accent.opacity(0.5)],
                                         center: UnitPoint(x: 0.45, y: 0.36), startRadius: 2, endRadius: 60))
            if let waiting { Circle().fill(Color.black.opacity(0.42 * (1 - waiting))) }
            if let name = pose.sprite {
                let since: Double = {
                    switch pose {
                    case .intro(let s), .clip(_, let s): return s
                    default: return 0.5
                    }
                }()
                if let image = CatSprites.shared.image(name, at: since) {
                    GeometryReader { proxy in
                        let side = proxy.size.width * CGFloat(CatSprites.shared.span(name))
                        Image(nsImage: image).resizable().interpolation(.high)
                            .frame(width: side, height: side)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                            .opacity(waiting.map { 0.3 + 0.7 * $0 } ?? 1)
                            .brightness(waiting.map { -0.35 * (1 - $0) } ?? 0)
                    }
                }
            }
        }
        .frame(width: 110, height: 110)
        .padding(10)
    }
}
