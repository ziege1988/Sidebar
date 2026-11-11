import SwiftUI

/// Einstellungen → Wetter
struct WeatherSettingsSection: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject private var service = WeatherService.shared
    @Environment(\.colorScheme) private var scheme
    @State private var apiKey = WeatherSecret.read() ?? ""
    @State private var searching = false
    @State private var searchResult = ""
    @State private var testing = false
    @State private var testResult = ""

    private var enabled: Bool { store.config.settings.weatherEnabled }

    var body: some View {
        Section("Wetter") {
            Toggle("Wetter-Effekte anzeigen", isOn: $store.config.settings.weatherEnabled)
            Text("Rüdiger reagiert auf das Wetter an deinem Standort: Regen, Hitze, Gewitter, Schnee … Es läuft immer nur eine Animation – bei mehreren Ereignissen gewinnt das wichtigste (Gewitter, Schnee, Regen, Frost, UV, Hitze, Wind).")
                .font(.caption)
                .foregroundStyle(.secondary)
            if enabled {
                Text(service.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if enabled {
            Section("Standort") {
                HStack {
                    TextField("Ort oder Postleitzahl", text: $store.config.settings.weatherPlace)
                        .onSubmit { search() }
                    Button("Suchen") { search() }
                        .disabled(searching || store.config.settings.weatherPlace.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !searchResult.isEmpty {
                    Text(searchResult)
                        .font(.caption)
                        .foregroundStyle(searchResult.hasPrefix("✓") ? Color.green : Color.orange)
                } else if !store.config.settings.weatherPlaceName.isEmpty {
                    Text("✓ " + store.config.settings.weatherPlaceName)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Text("Für Schnee, Gewitter und – ohne eigene Station – alle Werte. An den Wetterdienst (Open-Meteo) gehen nur die Koordinaten des Ortes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Eigene Wetterstation (optional)") {
                Toggle("Meine Station verwenden", isOn: $store.config.settings.weatherUseStation)
                if store.config.settings.weatherUseStation {
                    TextField("Station (Weather Underground)", text: $store.config.settings.weatherStationID,
                              prompt: Text("z. B. IABCDE12"))
                    SecureField("API-Schlüssel", text: $apiKey)
                        .onChange(of: apiKey) { _, new in
                            WeatherSecret.save(new)
                            WeatherService.shared.settingsChanged()
                        }
                    HStack {
                        Button("Testen") { test() }
                            .disabled(testing || store.config.settings.weatherStationID.isEmpty || apiKey.isEmpty)
                        if !testResult.isEmpty {
                            Text(testResult)
                                .font(.caption)
                                .foregroundStyle(testResult.hasPrefix("✓") ? Color.green : Color.orange)
                        }
                    }
                }
                Text("Mit eigener Station kommen Temperatur, Regen, Wind und UV von dort (genauer), Gewitter und Schnee weiter vom Wetterdienst. Ohne Station oder bei einem Ausfall nimmt Rüdiger den Wetterdienst. Der Schlüssel wird verschlüsselt auf diesem Mac gespeichert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Vorschau") {
            HStack {
                Text("Alle Wetter-Animationen ansehen")
                Spacer()
                Button("Vorschau") {
                    WeatherPreviewController.shared.show(accent: Palette.resolve(store.config.settings.colorTheme, scheme).accent)
                }
            }
            Text("Ein kleines Fenster zeigt Rüdiger – jede Animation läuft 10 Sekunden.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if enabled {
            Section {
                DisclosureGroup("Schwellen") {
                    LabeledContent("Sonnenbrille ab \(Int(store.config.settings.weatherHot)) °C") {
                        Slider(value: $store.config.settings.weatherHot, in: 15...40, step: 1)
                    }
                    LabeledContent("Frost unter \(Int(store.config.settings.weatherFrost)) °C") {
                        Slider(value: $store.config.settings.weatherFrost, in: -15...5, step: 1)
                    }
                    LabeledContent("Wind ab \(Int(store.config.settings.weatherWind)) km/h (Böen)") {
                        Slider(value: $store.config.settings.weatherWind, in: 15...80, step: 5)
                    }
                    LabeledContent("Schwitzen ab UV \(Int(store.config.settings.weatherUV))") {
                        Slider(value: $store.config.settings.weatherUV, in: 3...9, step: 1)
                    }
                }
            }
        }
    }

    @MainActor
    private func search() {
        let place = store.config.settings.weatherPlace.trimmingCharacters(in: .whitespaces)
        guard !place.isEmpty else { return }
        searching = true
        searchResult = ""
        Task { @MainActor in
            let found = await WeatherService.shared.search(place: place)
            searching = false
            if let found {
                store.config.settings.weatherPlaceName = found.name
                store.config.settings.weatherLat = found.lat
                store.config.settings.weatherLon = found.lon
                searchResult = "✓ " + found.name
            } else {
                searchResult = "Nichts gefunden – bitte anders schreiben (z. B. mit Postleitzahl)."
            }
        }
    }

    @MainActor
    private func test() {
        testing = true
        testResult = ""
        let id = store.config.settings.weatherStationID
        let key = apiKey
        Task { @MainActor in
            testResult = await WeatherService.shared.testStation(id: id, key: key)
            testing = false
        }
    }
}
