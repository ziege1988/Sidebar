# Sidebar für macOS

Eine schlanke, native Sidebar für macOS (Apple Silicon, macOS 14 Sonoma oder neuer).
Sie dockt an einer beliebigen Bildschirmkante an, zeigt eingeklappt nur Icons und
klappt beim Darüberfahren mit der Maus auf. Links sind in Gruppen sortiert
(z. B. **Fotografie**, **ADS**) und lassen sich wie kleine „Browser-Apps“ öffnen.

## Funktionen

- **Jeder Bildschirm, jede Seite:** links, rechts, oben oder unten, auf jedem
  angeschlossenen Monitor. Wird ein Monitor abgezogen, wechselt die Sidebar
  automatisch auf den Hauptbildschirm und kehrt zurück, sobald er wieder da ist.
- **Hover zum Aufklappen:** Eingeklappt sind nur Favicons sichtbar. Beim
  Darüberfahren erscheinen Namen und Gruppen. Mit 📌 bleibt die Sidebar offen.
- **Gruppen & Links:** Gruppen mit SF-Symbol, Links mit automatisch geladenem
  Favicon. Reihenfolge per Drag & Drop in den Einstellungen änderbar.
- **Schnell hinzufügen:** URL aus der Adressleiste des Browsers direkt auf eine
  Gruppe in der Sidebar ziehen.
- **Drei Öffnungsarten** (global einstellbar, pro Link überschreibbar):
  | Art | Verhalten |
  | --- | --- |
  | Standard-Browser | neuer Tab in Safari/Chrome/… |
  | Integriertes App-Fenster | eigenes Fenster in der Sidebar-App, mit Zurück/Vor/Neu laden, Downloads und Datei-Uploads. Logins werden gespeichert, getrennt vom Browser. |
  | Chrome-App-Fenster | Chrome/Edge/Brave/Vivaldi im `--app`-Modus: eigenes Fenster ohne Tabs und Adressleiste, **mit den Logins deines Browserprofils** |
- **Automatisch ausblenden:** eingeklappt bleibt nur ein 4 pt schmaler Rand.
- **Menüleisten-Symbol:** Einstellungen, Seite und Bildschirm wechseln,
  Sidebar ein-/ausblenden.
- **Bei Anmeldung starten** (optional).
- Kein Dock-Symbol im Hintergrund. Es erscheint nur, solange Einstellungen oder
  App-Fenster offen sind, damit sie per ⌘-Tab erreichbar bleiben.

## Installation

Voraussetzung: Xcode **oder** die Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ziege1988/Sidebar.git
cd Sidebar
./build.sh --install     # baut, kopiert nach /Programme und startet
```

Nur bauen, ohne zu installieren: `./build.sh` → `build/Sidebar.app`.

**Alternativ ohne Kompilieren:** Jeder Push baut die App über GitHub Actions
(Tab *Actions* → letzter Lauf → Artefakt *Sidebar-app*). Weil diese Version aus
dem Internet stammt und nicht notarisiert ist, beim ersten Start einmalig
Rechtsklick → *Öffnen* wählen oder `xattr -dr com.apple.quarantine /Applications/Sidebar.app` ausführen.

**Mit Xcode entwickeln:** `open Package.swift` und dann Run (⌘R).

## Bedienung

- Einstellungen: ⚙︎ unten in der Sidebar, über das Menüleisten-Symbol oder mit ⌘,
- Rechtsklick auf einen Link: öffnen als …, Adresse kopieren, bearbeiten, entfernen.
- Konfiguration: `~/Library/Application Support/Sidebar/config.json`
  (gut lesbares JSON, z. B. zum Sichern oder Übertragen auf einen anderen Mac).

## Bekannte Einschränkungen

- **macOS kann keinen Bildschirmbereich reservieren.** Anders als das Dock
  verschiebt die Sidebar keine anderen Fenster. Maximierte Fenster liegen also
  unter der eingeklappten Leiste. Abhilfe: „Automatisch ausblenden“ aktivieren
  oder Fenster etwas schmaler ziehen.
- **Favicons** werden über den Favicon-Dienst von Google geladen
  (`google.com/s2/favicons`, dabei wird nur die Domain übertragen) und lokal
  zwischengespeichert. Für interne Seiten ohne Favicon erscheint der
  Anfangsbuchstabe.
- **Google-Login im integrierten App-Fenster:** Die App gibt sich als Safari
  aus, damit Google den Login erlaubt. Sollte ein Dienst den eingebetteten
  Browser trotzdem ablehnen, für diesen Link „Chrome-App-Fenster“ oder
  „Standard-Browser“ wählen.
- Die App ist nur ad-hoc signiert (nicht notarisiert). Für die Weitergabe an
  andere wäre ein Apple-Developer-Zertifikat nötig.

## Projektstruktur

```
Package.swift                  Swift-Package (macOS 14+)
build.sh                       baut und signiert Sidebar.app
Resources/Info.plist           App-Metadaten (LSUIElement = kein Dock-Symbol)
Sources/Sidebar/
  App.swift                    Einstiegspunkt, Menüleisten-Symbol, Hauptmenü
  SidebarController.swift      Panel, Positionierung, Hover-Logik, Animation
  SidebarView.swift            Oberfläche der Sidebar (SwiftUI)
  SettingsView.swift           Einstellungen: Gruppen & Links, Darstellung
  WebAppWindow.swift           integrierte App-Fenster (WebKit)
  LinkOpener.swift             Öffnungsarten, Dock-Sichtbarkeit
  ConfigStore.swift            Laden/Speichern der Konfiguration
  Favicons.swift               Favicon-Cache
  Models.swift                 Datenmodell
```
