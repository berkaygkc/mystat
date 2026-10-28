import Foundation
import MystatCore
import Testing
@testable import MystatProbes

/// IOReport enerji, GPU ve SSD okuyucuları (root'suz, §9.1). Canlı testler okuyucu bu makinede açılabiliyorsa çalışır.
@Suite struct SensorProbeTests {
    @Test func unitScale() {
        #expect(UnitScale.joules(1500, unit: "mJ") == 1.5)
        #expect(UnitScale.joules(2_000_000, unit: "nJ") == 0.002)
        #expect(UnitScale.joules(3_000_000, unit: "uJ") == 3)
        #expect(UnitScale.joules(5, unit: "W") == nil)
    }

    @Test func parsesCreator() {
        #expect(GPUProbe.parseCreator("pid 410, WindowServer").map { "\($0.pid) \($0.name)" } == "410 WindowServer")
        #expect(GPUProbe.parseCreator("pid 27714, Brave Browser He").map(\.name) == "Brave Browser He")
        #expect(GPUProbe.parseCreator("kernel") == nil)
    }

    @Test(.enabled(if: IOReportProbe() != nil)) func liveIOReportSmoke() throws {
        let p = try #require(IOReportProbe())
        let a = p.energy()
        Thread.sleep(forTimeInterval: 0.5)
        let b = p.energy()
        let watts = (b.cpuJ - a.cpuJ) / 0.5
        #expect(b.cpuJ > a.cpuJ && watts > 0 && watts < 200)
        #expect(b.gpuJ >= a.gpuJ)
    }

    @Test(.enabled(if: GPUProbe.read() != nil)) func liveGPUSmoke() throws {
        let r = try #require(GPUProbe.read())
        #expect(r.cores > 0 && (0...100).contains(r.utilization) && !r.clients.isEmpty)
    }

    @Test(.enabled(if: HIDTemperatureProbe() != nil)) func liveSSDSmoke() throws {
        let t = try #require(HIDTemperatureProbe()?.ssd())
        #expect((10...100).contains(t))
    }
}
