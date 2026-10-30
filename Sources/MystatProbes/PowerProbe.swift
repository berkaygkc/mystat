import Foundation
import IOKit
import IOKit.ps
import MystatCore

/// Thermal state (`ProcessInfo.thermalState`) and battery (IOPowerSources + AppleSmartBattery). Needs no root.
public struct PowerProbe: Sendable {
    public init() {}

    public func thermal() -> Level {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .ok
        case .fair: .warn
        default: .crit
        }
    }

    /// nil on a desktop Mac (no battery).
    public func battery() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0, max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
            let smart = Self.smartBattery()
            return BatteryReading(percent: max > 0 ? Double(cur) / Double(max) * 100 : 0,
                                  charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                  onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                                  adapterWatts: adapter?[kIOPSPowerAdapterWattsKey] as? Int,
                                  adapterUSBC: (adapter?["Name"] as? String)?.contains("USB-C") ?? (adapter != nil),
                                  cycles: smart["CycleCount"] as? Int, designCapacity: smart["DesignCapacity"] as? Int,
                                  maxCapacity: smart["NominalChargeCapacity"] as? Int ?? smart["AppleRawMaxCapacity"] as? Int)   // System Settings "Maximum Capacity"
        }
        return nil
    }

    static func smartBattery() -> [String: Any] {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return [:] }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
        return props?.takeRetainedValue() as? [String: Any] ?? [:]
    }
}
