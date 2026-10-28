import Foundation
import MystatCore
import Synchronization

/// Gerçek sensör okuyucuları. SMC anahtar keşfi ≈ 1–2 sn: önbellekte yoksa ayrı bir görevde bir kez yapılır,
/// makine modeli + macOS sürümüyle saklanır; o sırada sensörler "yok" sayılır.
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
