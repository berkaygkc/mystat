import Foundation
import MystatCore
import Synchronization

/// Real sensor readers. SMC key discovery takes ≈ 1–2 s: if not cached, it runs once in a separate task and is
/// stored by machine model + macOS version; sensors are treated as absent meanwhile.
final class SensorProbes: Sendable {
    let smc = SMCProbe()
    let hid = HIDTemperatureProbe()
    let report = IOReportProbe()
    private let map = Mutex<SensorMap?>(nil)
    private let discovering = Mutex(false)

    func sensorMap() -> SensorMap? {
        if let m = map.withLock({ $0 }) { return m }
        guard let smc, discovering.withLock({ d in defer { d = true }; return !d }) else { return nil }
        let model = Self.sysctl("hw.model"), os = ProcessInfo.processInfo.operatingSystemVersionString
        if let cached = SMCProbe.cachedMap(model: model, os: os, defaults: .standard) {
            map.withLock { $0 = cached }
            return cached
        }
        Task.detached(priority: .utility) { [self] in
            let found = smc.discover()
            SMCProbe.storeMap(found, model: model, os: os, defaults: .standard)
            map.withLock { $0 = found }
        }
        return nil
    }

    func values(_ keys: [String]) -> [String: Double] {
        guard let smc else { return [:] }
        var out: [String: Double] = [:]
        for k in keys { out[k] = smc.value(k) }
        return out
    }

    static func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "" }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
