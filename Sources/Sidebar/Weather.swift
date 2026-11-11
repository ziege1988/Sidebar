import AppKit
import Combine
import CryptoKit
import Foundation
import IOKit
import SwiftUI

// MARK: - Wetter
//
// Rüdiger spiegelt das Wetter an deinem Standort. Immer läuft höchstens EINE Animation (Rangfolge unten).
// Daten: Wetterdienst (Open-Meteo) für Standort, Gewitter und Schnee; optional deine eigene Station
// (Weather Underground) für Temperatur, Regen, Wind und UV. Alles läuft im Hintergrund und blockiert nie die
// Oberfläche; fehlen die Daten länger als 30 Minuten, ist Rüdiger einfach normal.

/// Wetterzustände – in der Reihenfolge ihrer Wichtigkeit (hoher Rang gewinnt)
enum WeatherMood: String, CaseIterable {
    case normal, wind, hot, sweat, frost, rain, snow, thunder

    var rank: Int {
        switch self {
        case .normal: return 0
        case .wind: return 1
        case .hot: return 2
        case .sweat: return 3
        case .frost: return 4
        case .rain: return 5
        case .snow: return 6
        case .thunder: return 7
        }
    }

    /// Sprite-Animation für diesen Zustand (nil = normale Bilder, nur Ebenen darüber)
    var clip: String? {
        switch self {
        case .rain: return "wet"
        case .frost: return "cold"
        case .wind: return "windy"
        default: return nil
        }
    }
}

struct WeatherInput {
    var temp: Double?
    var raining = false
    var wind: Double?
    var uv: Double?
    var code: Int?
    var snowing = false
}

struct WeatherThresholds {
    var hot: Double = 25
    var frost: Double = -3
    var wind: Double = 35
    var uv: Double = 5
}

enum WeatherLogic {
    static func isThunder(_ code: Int?) -> Bool { [95, 96, 99].contains(code ?? -1) }
    static func isSnow(_ code: Int?) -> Bool { [71, 73, 75, 77, 85, 86].contains(code ?? -1) }
    static func isRain(_ code: Int?) -> Bool {
        guard let code else { return false }
        return (51...67).contains(code) || (80...82).contains(code)
    }

    /// Rangfolge: Gewitter > Schnee > Regen > Frost > Schwitzen (UV) > Hitze > Wind > normal.
    /// `previous` gibt den Schwellen etwas Spielraum, damit nichts flackert.
    static func decide(_ i: WeatherInput, th: WeatherThresholds, previous: WeatherMood) -> WeatherMood {
        if isThunder(i.code) { return .thunder }
        if i.snowing || isSnow(i.code) { return .snow }
        if i.raining || isRain(i.code) { return .rain }
        if let t = i.temp, t < (previous == .frost ? th.frost + 1 : th.frost) { return .frost }
        if let uv = i.uv, uv >= (previous == .sweat ? th.uv - 0.5 : th.uv) { return .sweat }
        if let t = i.temp, t >= (previous == .hot ? th.hot - 1 : th.hot) { return .hot }
        if let w = i.wind, w >= (previous == .wind ? th.wind * 0.8 : th.wind) { return .wind }
        return .normal
    }
}

// MARK: - Schlüssel der Station (verschlüsselt in einer Datei, nur für dich lesbar)

enum WeatherSecret {
    private static let service = "app.sidebar.Sidebar.weather"

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sidebar", isDirectory: true).appendingPathComponent("weather-key")
    }

    private static var key: SymmetricKey {
        var uuid = "sidebar-fallback"
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        if entry != 0 {
            if let value = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String {
                uuid = value
            }
            IOObjectRelease(entry)
        }
        return SymmetricKey(data: SHA256.hash(data: Data((uuid + "|" + service).utf8)))
    }

    static func save(_ value: String) {
        let url = fileURL
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let sealed = try? AES.GCM.seal(Data(trimmed.utf8), using: key).combined else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? sealed.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func read() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: plain, encoding: .utf8)
    }
}

// MARK: - Daten holen

@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    /// Aktueller Zustand (mit Mindestdauer und Spielraum gegen Flackern)
    @Published private(set) var mood: WeatherMood = .normal
    /// Kurzer Statustext für die Einstellungen
    @Published private(set) var status = "Wetter ist aus."

    private var settings = SidebarSettings()
    private var stationTimer: Timer?
    private var forecastTimer: Timer?
    private var moodSince = Date.distantPast
    private var lastSuccess: Date?
    private var configKey = ""
    private var forecast: Forecast?
    private var station: Station?
    private var refreshing = false

    private struct Forecast {
        var temp: Double?
        var precipitation: Double?
        var snowfall: Double?
        var code: Int?
        var gust: Double?
        var uv: Double?
        var date: Date
    }

    private struct Station {
        var temp: Double?
        var rainRate: Double?
        var gust: Double?
        var uv: Double?
        var date: Date
    }

    private var powerSub: AnyCancellable?

    private init() {
        // Nach Sperre / Bildschirmschoner sofort frische Werte holen
        powerSub = PowerState.shared.$paused
            .removeDuplicates()
            .filter { !$0 }
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.kick() }
            }
    }

    // MARK: Einstellungen

    func apply(_ new: SidebarSettings) {
        settings = new
        let key = [String(new.weatherEnabled), String(new.weatherLat ?? 0), String(new.weatherLon ?? 0),
                   String(new.weatherUseStation), new.weatherStationID].joined(separator: "|")
        guard new.weatherEnabled else {
            stop()
            configKey = key
            return
        }
        if key != configKey || stationTimer == nil {
            configKey = key
            forecast = nil
            station = nil
            start()
        } else {
            reevaluate()
        }
    }

    /// Nach dem Ändern des Schlüssels oder der Station
    func settingsChanged() {
        guard settings.weatherEnabled else { return }
        kick()
    }

    /// Abruf im Hintergrund anstoßen
    private func kick(stationOnly: Bool = false) {
        Task { await self.refresh(stationOnly: stationOnly) }
    }

    private func start() {
        stop(keepStatus: true)
        let station = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.kick(stationOnly: true) }
        }
        let forecast = Timer(timeInterval: 900, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.kick() }
        }
        RunLoop.main.add(station, forMode: .common)
        RunLoop.main.add(forecast, forMode: .common)
        stationTimer = station
        forecastTimer = forecast
        status = "Wetter wird geladen …"
        kick()
    }

    private func stop(keepStatus: Bool = false) {
        stationTimer?.invalidate()
        forecastTimer?.invalidate()
        stationTimer = nil
        forecastTimer = nil
        if !keepStatus {
            mood = .normal
            status = "Wetter ist aus."
        }
    }

    // MARK: Abruf

    func refresh(stationOnly: Bool = false) async {
        guard settings.weatherEnabled, !PowerState.shared.paused, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        var problems: [String] = []

        if settings.weatherUseStation, !settings.weatherStationID.isEmpty, let key = WeatherSecret.read() {
            do {
                station = try await Self.fetchStation(id: settings.weatherStationID, key: key)
            } catch {
                station = nil
                problems.append("Station: \(error.localizedDescription)")
            }
        } else {
            station = nil
        }
        if !stationOnly || forecast == nil, let lat = settings.weatherLat, let lon = settings.weatherLon {
            do {
                forecast = try await Self.fetchForecast(lat: lat, lon: lon)
            } catch {
                problems.append("Wetterdienst: \(error.localizedDescription)")
            }
        }
        if station != nil || forecast != nil { lastSuccess = Date() }
        reevaluate(problems: problems)
    }

    /// Zustand aus den vorhandenen Daten neu berechnen
    private func reevaluate(problems: [String] = []) {
        guard settings.weatherEnabled else { return }
        let now = Date()
        // Zu alte Daten (über 30 Minuten) → normal
        if let last = lastSuccess, now.timeIntervalSince(last) > 1800 {
            adopt(.normal, now: now, force: true)
            status = "Keine aktuellen Wetterdaten."
            return
        }
        guard forecast != nil || station != nil else {
            status = problems.first ?? (settings.weatherLat == nil ? "Bitte einen Standort eintragen." : "Wetter wird geladen …")
            return
        }
        var input = WeatherInput()
        let freshStation = station.flatMap { now.timeIntervalSince($0.date) < 1800 ? $0 : nil }
        if let f = forecast {
            input.code = f.code
            input.snowing = (f.snowfall ?? 0) > 0.05
        }
        if let s = freshStation {
            input.temp = s.temp
            input.raining = (s.rainRate ?? 0) > 0
            input.wind = s.gust
            input.uv = s.uv
        } else if let f = forecast {
            input.temp = f.temp
            input.raining = (f.precipitation ?? 0) > 0.05
            input.wind = f.gust
            input.uv = f.uv
        }
        let th = WeatherThresholds(hot: settings.weatherHot, frost: settings.weatherFrost,
                                   wind: settings.weatherWind, uv: settings.weatherUV)
        let decided = WeatherLogic.decide(input, th: th, previous: mood)
        adopt(decided, now: now, force: false)
        let source = freshStation != nil ? "Station + Wetterdienst" : "Wetterdienst"
        let time = DateFormatter.localizedString(from: lastSuccess ?? now, dateStyle: .none, timeStyle: .short)
        status = "Quelle: \(source) · Stand \(time) Uhr" + (problems.isEmpty ? "" : " · " + problems.joined(separator: "; "))
    }

    /// Höherer Rang sofort, niedrigerer erst nach 5 Minuten (nichts soll flackern)
    private func adopt(_ new: WeatherMood, now: Date, force: Bool) {
        guard new != mood else { return }
        if force || new.rank > mood.rank || now.timeIntervalSince(moodSince) >= 300 {
            mood = new
            moodSince = now
        }
    }

    // MARK: Netzwerk

    private static func json(from url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WeatherError.http(http.statusCode)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WeatherError.format }
        return object
    }

    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func fetchStation(id: String, key: String) async throws -> Station {
        var c = URLComponents(string: "https://api.weather.com/v2/pws/observations/current")!
        c.queryItems = [URLQueryItem(name: "stationId", value: id.trimmingCharacters(in: .whitespaces)),
                        URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "units", value: "m"),
                        URLQueryItem(name: "numericPrecision", value: "decimal"), URLQueryItem(name: "apiKey", value: key)]
        let root = try await json(from: c.url!)
        guard let obs = (root["observations"] as? [[String: Any]])?.first else { throw WeatherError.noData }
        let metric = obs["metric"] as? [String: Any] ?? [:]
        var date = Date()
        if let text = obs["obsTimeUtc"] as? String, let parsed = ISO8601DateFormatter().date(from: text) { date = parsed }
        return Station(temp: number(metric["temp"]), rainRate: number(metric["precipRate"]),
                       gust: number(metric["windGust"]) ?? number(metric["windSpeed"]),
                       uv: number(obs["uv"]), date: date)
    }

    private static func fetchForecast(lat: Double, lon: Double) async throws -> Forecast {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [URLQueryItem(name: "latitude", value: String(lat)), URLQueryItem(name: "longitude", value: String(lon)),
                        URLQueryItem(name: "current", value: "temperature_2m,precipitation,snowfall,weather_code,wind_gusts_10m"),
                        URLQueryItem(name: "hourly", value: "uv_index"), URLQueryItem(name: "forecast_days", value: "1"),
                        URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "wind_speed_unit", value: "kmh")]
        let root = try await json(from: c.url!)
        guard let current = root["current"] as? [String: Any] else { throw WeatherError.noData }
        var uv: Double?
        if let hourly = root["hourly"] as? [String: Any], let times = hourly["time"] as? [String],
           let values = hourly["uv_index"] as? [Any], let now = current["time"] as? String {
            let hour = String(now.prefix(13))
            if let index = times.firstIndex(where: { $0.hasPrefix(hour) }), index < values.count { uv = number(values[index]) }
        }
        return Forecast(temp: number(current["temperature_2m"]), precipitation: number(current["precipitation"]),
                        snowfall: number(current["snowfall"]), code: number(current["weather_code"]).map { Int($0) },
                        gust: number(current["wind_gusts_10m"]), uv: uv, date: Date())
    }

    // MARK: Für die Einstellungen

    /// Ort oder Postleitzahl suchen
    func search(place: String) async -> (name: String, lat: Double, lon: Double)? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: place), URLQueryItem(name: "count", value: "1"),
                        URLQueryItem(name: "language", value: "de"), URLQueryItem(name: "format", value: "json")]
        guard let url = c.url, let root = try? await Self.json(from: url),
              let first = (root["results"] as? [[String: Any]])?.first,
              let lat = Self.number(first["latitude"]), let lon = Self.number(first["longitude"]) else { return nil }
        let name = [first["name"] as? String, first["admin1"] as? String, first["country_code"] as? String]
            .compactMap { $0 }.joined(separator: ", ")
        return (name, lat, lon)
    }

    /// Verbindung zur eigenen Station prüfen
    func testStation(id: String, key: String) async -> String {
        do {
            let s = try await Self.fetchStation(id: id, key: key)
            var parts: [String] = []
            if let t = s.temp { parts.append(String(format: "%.1f °C", t)) }
            if let uv = s.uv { parts.append(String(format: "UV %.0f", uv)) }
            if let g = s.gust { parts.append(String(format: "Böen %.0f km/h", g)) }
            return "✓ " + (parts.isEmpty ? "Verbindung ok" : parts.joined(separator: " · "))
        } catch {
            return "✗ " + error.localizedDescription
        }
    }
}

enum WeatherError: LocalizedError {
    case http(Int), format, noData

    var errorDescription: String? {
        switch self {
        case .http(let code): return code == 401 || code == 403 ? "Schlüssel nicht akzeptiert (\(code))" : "Fehler \(code)"
        case .format: return "unerwartete Antwort"
        case .noData: return "keine Daten"
        }
    }
}

// MARK: - Sprüche

enum WeatherLines {
    static func lines(for mood: WeatherMood) -> [CatLine] {
        switch mood {
        case .rain: return rain
        case .hot: return hot
        case .sweat: return sweat
        case .wind: return wind
        case .thunder: return thunder
        case .frost: return frost
        case .snow: return snow
        case .normal: return []
        }
    }

    static let rain: [CatLine] = [
        .init(0, "Es regnet … ein Tag für Kuscheln."), .init(1, "Na toll. Regen. Und ich hab keinen Schirm."),
        .init(1, "Ich bin nicht aus Zucker – nass werd ich trotzdem."), .init(2, "Regen. Passt zu meiner Laune.")]
    static let hot: [CatLine] = [
        .init(0, "Was für ein schöner, warmer Tag!"), .init(1, "Sonnenbrille auf. Frag nicht."),
        .init(1, "Ich seh aus wie ein Gebrauchtwagenhändler."), .init(2, "Warm. Und trotzdem kein Eis für mich.")]
    static let sweat: [CatLine] = [
        .init(0, "Puh, die Sonne ist heute kräftig."), .init(1, "UV fünf. Ich schwitze Fell."),
        .init(1, "Ich bin ein Kater, kein Toaster."), .init(2, "Ein Kater im schwarzen Fell bei dieser Sonne. Danke, Natur.")]
    static let wind: [CatLine] = [
        .init(0, "Ganz schön windig heute!"), .init(1, "Meine Frisur! Und das Laub räumst du weg."),
        .init(1, "Wind. Mein Fell sieht aus wie dein Schreibtisch."), .init(2, "Der Wind pustet dir wenigstens den Kopf frei.")]
    static let thunder: [CatLine] = [
        .init(0, "Ein Gewitter … bleib lieber drinnen."), .init(1, "Wenn mich ein Blitz trifft, schick ich dir die Rechnung."),
        .init(1, "Donner. Ich bin völlig entspannt. Fast."), .init(2, "Ein Blitz würde meine Frisur wenigstens verbessern.")]
    static let frost: [CatLine] = [
        .init(0, "Brrr, es ist eiskalt!"), .init(1, "Ich bin ein Kater, kein Eiswürfel."),
        .init(1, "Frost. Mein Schnurrbart klappert."), .init(2, "Kälte. Wie dein Kontostand nach Weihnachten.")]
    static let snow: [CatLine] = [
        .init(0, "Es schneit! Wie schön."), .init(1, "Schnee. Auf meinem Kopf. Danke, Himmel."),
        .init(1, "Weiße Pracht – und ich trag sie auf dem Kopf."), .init(2, "Schnee. Morgen ist er matschig. Genau wie deine Pläne.")]
    static let struck: [CatLine] = [.init(0, "MEOOOWWW!!!")]
    static let shake: [CatLine] = [.init(1, "Brrr. Weg damit."), .init(1, "Schnee, hör auf, mich zu mögen.")]
}
