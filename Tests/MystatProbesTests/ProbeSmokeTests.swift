import Darwin
import Foundation
import MystatCore
import Testing
@testable import MystatProbes

/// Bu makinede gerçek sistem çağrıları makul değerler döndürmeli.
@Suite struct ProbeSmokeTests {
    @Test func machProbeIsPlausible() {
        let p = MachProbe()
        let ticks = p.coreTicks()
        #expect(ticks.count == ProcessInfo.processInfo.activeProcessorCount)
        #expect(ticks.allSatisfy { $0.user + $0.system + $0.idle > 0 })
        let vm = p.vm()
        #expect(vm.pageSize == UInt64(getpagesize()) && vm.pageSize == 16384)   // Apple Silicon
        #expect(vm.total == ProcessInfo.processInfo.physicalMemory)
        #expect([1, 2, 4].contains(vm.pressureLevel))
        #expect((0...100).contains(vm.memoryLevel))
        #expect(vm.`internal` > 0 && vm.wired > 0)
        let mem = MemoryMeter.state(vm)
        #expect(mem.percent > 5 && mem.percent < 100)
        #expect(p.loadAverage().count == 3)
    }

    @Test func cpuMeterOnRealTicks() async throws {
        let p = MachProbe()
        var m = CPUMeter()
        _ = m.update(p.coreTicks(), at: Date())
        try await Task.sleep(for: .milliseconds(300))
        let measured = m.update(p.coreTicks(), at: Date())
        let s = try #require(measured)
        #expect(s.percent >= 0 && s.percent <= 100)
        #expect(s.cores.count == ProcessInfo.processInfo.activeProcessorCount)
    }
}
