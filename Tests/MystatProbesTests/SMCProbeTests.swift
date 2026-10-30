import Foundation
import MystatCore
import Testing
@testable import MystatProbes

@Suite struct SMCProbeTests {
    @Test func mapCacheRoundTrip() throws {
        let d = try #require(UserDefaults(suiteName: "mystat-test-\(UUID().uuidString)"))
        let m = SensorMap(cpu: ["Te04", "Tp1i"], gpu: ["Tg05"], battery: "TB0T", fans: 2)
        SMCProbe.storeMap(m, model: "Mac16,7", os: "26.0 (25A1)", defaults: d)
        #expect(SMCProbe.cachedMap(model: "Mac16,7", os: "26.0 (25A1)", defaults: d) == m)
        #expect(SMCProbe.cachedMap(model: "Mac16,7", os: "26.1 (25B1)", defaults: d) == nil)   // macOS changed: rediscover
    }

    @Test(.enabled(if: SMCProbe() != nil)) func liveSMCSmoke() throws {
        let smc = try #require(SMCProbe())
        #expect((smc.value("FNum") ?? -1) >= 0)
        let map = smc.discover()
        let first = try #require(map.cpu.first)
        #expect((10...120).contains(smc.value(first) ?? 0))
    }

    /// If a one-off read failure leaves an empty map, it is not written to the cache; when the classification changes, the old cache is not used.
    @Test func cacheRejectsEmptyAndOldVersion() throws {
        let d = try #require(UserDefaults(suiteName: "mystat-test-\(UUID().uuidString)"))
        SMCProbe.storeMap(SensorMap(cpu: [], gpu: [], battery: nil, fans: 0), model: "Mac16,7", os: "26.0", defaults: d)
        #expect(SMCProbe.cachedMap(model: "Mac16,7", os: "26.0", defaults: d) == nil)
        let old = #"{"model":"Mac16,7","os":"26.0","map":{"cpu":["Tp1i"],"gpu":[],"fans":2}}"#   // unversioned (old) record
        d.set(Data(old.utf8), forKey: "mystat.sensorMap")
        #expect(SMCProbe.cachedMap(model: "Mac16,7", os: "26.0", defaults: d) == nil)
    }
}
