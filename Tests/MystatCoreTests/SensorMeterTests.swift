import Foundation
import Testing
@testable import MystatCore

/// Sensör ve enerji hesapları: akla yatmayan değer atılır, boşluk ve sayaç geri gidişi watt göstermez.
@Suite struct SensorMeterTests {
    let t0 = Date(timeIntervalSince1970: 1_793_163_600)

    @Test func averageDropsImplausible() {
        #expect(SensorMeter.average([53.0, -9201, 0, 3.4, 150.2, 61.0, .nan]) == 57)
        #expect(SensorMeter.average([-9201]) == nil && SensorMeter.average([]) == nil)
    }

    @Test func powerFromJoules() {
        var m = PowerMeter()
        #expect(m.update(EnergyCounters(cpuJ: 100, gpuJ: 10, aneJ: 0, dramJ: 0), at: t0) == nil)
        let w = m.update(EnergyCounters(cpuJ: 133.8, gpuJ: 11.16, aneJ: 0, dramJ: 0), at: t0.addingTimeInterval(2))
        #expect(w.map { abs($0.cpu - 16.9) < 1e-9 && abs($0.gpu - 0.58) < 1e-9 } == true)
        #expect(m.update(EnergyCounters(cpuJ: 999, gpuJ: 99, aneJ: 0, dramJ: 0), at: t0.addingTimeInterval(7202)) == nil)   // uyku
        #expect(m.update(EnergyCounters(cpuJ: 10, gpuJ: 1, aneJ: 0, dramJ: 0), at: t0.addingTimeInterval(7204)) == nil)     // geri gitti
    }

    @Test func gpuShareByApp() {
        var g = GPUShare()
        func r(_ ws: UInt64, _ b1: UInt64, _ b2: UInt64, wsName: String = "WindowServer") -> GPUReading {
            GPUReading(utilization: 28, cores: 20, clients: [GPUClient(pid: 410, name: wsName, gpuTimeNs: ws),
                                                             GPUClient(pid: 500, name: "Brave Browser He", gpuTimeNs: b1),
                                                             GPUClient(pid: 500, name: "Brave Browser He", gpuTimeNs: b2)])
        }
        #expect(g.update(r(1_000_000_000, 5_000_000, 7_000_000), at: t0) == nil)
        let s = g.update(r(1_400_000_000, 105_000_000, 67_000_000), at: t0.addingTimeInterval(2))
        #expect(s?.map(\.name) == ["WindowServer", "Brave Browser He"])
        #expect(s.map { abs($0[0].percent - 20) < 1e-9 && abs($0[1].percent - 8) < 1e-9 } == true)
        // aynı pid başka ada geçti (pid yeniden kullanıldı): eski sayaç devralınmaz
        let t = g.update(r(5_000_000, 105_000_000, 67_000_000, wsName: "yeni"), at: t0.addingTimeInterval(4))
        #expect(t?.contains { $0.name == "yeni" } == false)
    }

    func rec(_ pid: Int32, energy: UInt64, start: Date) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, uid: 501, name: "p\(pid)", path: "/Applications/X.app/Contents/MacOS/X", args: [], cwd: nil,
                      start: start, hasTTY: false, cpuTime: 0, footprint: 0, energy: energy, diskWritten: 0)
    }

    @Test func energyFromNanojoules() {
        var e = EnergyMeter()
        let old = t0.addingTimeInterval(-3600)
        _ = e.update([rec(5, energy: 10_000_000_000, start: old)], at: t0, maxGap: 15)
        let w = e.update([rec(5, energy: 13_000_000_000, start: old)], at: t0.addingTimeInterval(2), maxGap: 15)
        #expect(w?[5].map { abs($0 - 1.5) < 1e-9 } == true)
        // pid 5 yeni bir sürece geçti (aralıkta doğdu): eskisinin sayacı devralınmaz
        let r = e.update([rec(5, energy: 1_000_000_000, start: t0.addingTimeInterval(3))], at: t0.addingTimeInterval(4), maxGap: 15)
        #expect(r?[5].map { abs($0 - 0.5) < 1e-9 } == true)
    }

    @Test func groupWattsSum() {
        let a = rec(10, energy: 0, start: t0), b = rec(11, energy: 0, start: t0)
        let g = ProcessGrouper.groups([a, b], cores: [:], ports: [:], system: (0, 0), now: t0, home: "/Users/u", owner: 501, watts: [10: 1.5, 11: 0.7])
        #expect(g.first { $0.id == "app:/Applications/X.app" }.map { abs($0.watts - 2.2) < 1e-9 } == true)
    }

    /// Sensörler ≈ 6 sn'de bir okunur (2 sn'lik turlarda 5 sn eşiği): 6,05 sn'lik aralık uyku sayılmamalı.
    @Test func sensorCadenceIsNotAGap() {
        var m = PowerMeter()
        _ = m.update(EnergyCounters(cpuJ: 100, gpuJ: 10, aneJ: 0, dramJ: 0), at: t0)
        #expect(m.update(EnergyCounters(cpuJ: 148.4, gpuJ: 19.68, aneJ: 0, dramJ: 0), at: t0.addingTimeInterval(6.05)) != nil)
        var g = GPUShare()
        let r = { (ns: UInt64) in GPUReading(utilization: 30, cores: 20, clients: [GPUClient(pid: 1, name: "a", gpuTimeNs: ns)]) }
        _ = g.update(r(0), at: t0)
        #expect(g.update(r(600_000_000), at: t0.addingTimeInterval(6.05))?.first?.name == "a")
        #expect(g.update(r(700_000_000), at: t0.addingTimeInterval(3600)) == nil)    // gerçek boşluk yine atılır
    }
}
