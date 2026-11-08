import AppKit
import IOKit.ps

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
