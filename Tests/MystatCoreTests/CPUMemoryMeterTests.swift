import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// Ham sayaçlardan CPU ve bellek (spec §7.1; Activity Monitor ile aynı tanımlar).
@Suite(.language("tr")) struct CPUMemoryMeterTests {
    let t0 = Date(timeIntervalSince1970: 1_793_166_318)

    @Test func cpuPercentFromTickDeltas() {
        var m = CPUMeter()
        #expect(m.update([CoreTicks(user: 100, system: 50, idle: 850, nice: 0), CoreTicks(user: 0, system: 0, idle: 1000, nice: 0)], at: t0) == nil)
        let s = m.update([CoreTicks(user: 160, system: 70, idle: 870, nice: 0), CoreTicks(user: 50, system: 0, idle: 1050, nice: 0)],
                         at: t0.addingTimeInterval(2))!
        #expect(s.cores.map { $0.rounded() } == [80, 50])            // (60+20)/100, 50/100
        #expect(abs(s.percent - 65) < 0.01)
        #expect(abs(s.systemPercent - 10) < 0.01)
    }

    /// Uyku sonrası ilk fark atılır (Review Focus #1); sonraki örnek normal.
    @Test func cpuSkipsAfterSleepGap() {
        var m = CPUMeter()
        let a = [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)]
        _ = m.update(a, at: t0)
        #expect(m.update([CoreTicks(user: 10, system: 0, idle: 90, nice: 0)], at: t0.addingTimeInterval(7200)) == nil)
        #expect(m.update([CoreTicks(user: 60, system: 0, idle: 140, nice: 0)], at: t0.addingTimeInterval(7202)) != nil)
    }

    /// Sayaç geri giderse (çekirdek eklendi/sıfırlandı) eksi yüzde yok.
    @Test func cpuCounterResetIsSkipped() {
        var m = CPUMeter()
        _ = m.update([CoreTicks(user: 500, system: 0, idle: 500, nice: 0)], at: t0)
        #expect(m.update([CoreTicks(user: 10, system: 0, idle: 10, nice: 0)], at: t0.addingTimeInterval(2)) == nil)
    }

    @Test func memoryMatchesActivityMonitorDefinition() {
        let gib = 1_073_741_824.0
        let c = VMCounters(pageSize: 16384, total: 48 << 30, free: 100_000, active: 0, inactive: 0, speculative: 0, wired: 200_000,
                           compressor: 300_000, purgeable: 50_000, internal: 1_250_000, external: 400_000,
                           swapUsed: 1 << 30, pressureLevel: 1, memoryLevel: 59)
        let s = MemoryMeter.state(c)
        #expect(abs(s.apps - 1_200_000 * 16384 / gib) < 0.001)                 // uygulama = internal − purgeable
        #expect(abs(s.wired - 200_000 * 16384 / gib) < 0.001)
        #expect(abs(s.compressed - 300_000 * 16384 / gib) < 0.001)
        #expect(abs(s.percent - Double(1_700_000 * 16384) / Double(48 << 30) * 100) < 0.001)
        #expect(s.totalGB == 48 && abs(s.usedGB + s.free - 48) < 0.001)
        #expect(s.pressureLevel == .ok && abs(s.pressurePercent - 41) < 0.001)
        #expect(s.swapGB == 1)
    }

    @Test func memoryPressureLevels() {
        var c = VMCounters(pageSize: 16384, total: 48 << 30, free: 0, active: 0, inactive: 0, speculative: 0, wired: 0,
                           compressor: 0, purgeable: 0, internal: 0, external: 0, swapUsed: 0, pressureLevel: 2, memoryLevel: 30)
        #expect(MemoryMeter.state(c).pressureLevel == .warn)
        c.pressureLevel = 4
        #expect(MemoryMeter.state(c).pressureLevel == .crit)
    }
}
