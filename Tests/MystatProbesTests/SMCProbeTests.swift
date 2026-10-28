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
        #expect(SMCProbe.cachedMap(model: "Mac16,7", os: "26.1 (25B1)", defaults: d) == nil)   // macOS değişti: yeniden keşif
    }

    @Test(.enabled(if: SMCProbe() != nil)) func liveSMCSmoke() throws {
        let smc = try #require(SMCProbe())
        #expect((smc.value("FNum") ?? -1) >= 0)
        let map = smc.discover()
        let first = try #require(map.cpu.first)
        #expect((10...120).contains(smc.value(first) ?? 0))
    }
}
