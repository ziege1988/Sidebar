import AppKit
import IOKit.ps

// MARK: - Rüdigers Geräusche
//
// Selbst erzeugt (tools/sounds/make_sounds.py), liegen in Resources/Sounds. Dezent, Lautstärke einstellbar.
// Im Ruhemodus und im Schlummermodus bleibt Rüdiger still.

enum CatSound: String {
    case meow, meow2, mrrp, purr, hiss, chomp, alarm
    /// kein Geräusch
    case silent

    private static var cache: [CatSound: NSSound] = [:]

    @MainActor
    static func play(_ sound: CatSound, settings: SidebarSettings, force: Bool = false) {
        guard sound != .silent, settings.catSounds || force, settings.catVolume > 0.01 else { return }
        guard force || (!AlertState.shared.quiet && !CatBrain.shared.snoozed) else { return }
        let player: NSSound
        if let cached = cache[sound] {
            player = cached
        } else {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "Sounds"),
                  let loaded = NSSound(contentsOf: url, byReference: true) else { return }
            cache[sound] = loaded
            player = loaded
        }
        player.stop()
        player.volume = Float(min(max(settings.catVolume, 0), 1))
        player.play()
    }
}

// MARK: - Akku

enum Battery {
    struct State {
        let percent: Int
        let charging: Bool
    }

    /// `nil` bei Macs ohne Akku
    static func read() -> State? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return State(percent: Int((Double(current) / Double(max) * 100).rounded()), charging: onAC)
        }
        return nil
    }
}
