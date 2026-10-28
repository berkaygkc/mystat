import Foundation
import Testing
@testable import MystatCore

/// Süreç CPU süresi farkından çekirdek (spec §7.1: 1,0 = bir çekirdeğin tamamı).
@Suite struct ProcessMeterTests {
    let t0 = Date(timeIntervalSince1970: 1_793_166_318)
    let start = Date(timeIntervalSince1970: 1_793_000_000)

    func rec(_ pid: Int32, cpu: UInt64, start s: Date? = nil, restricted: Bool = false) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, uid: 501, name: "p\(pid)", path: nil, args: [], cwd: nil, start: s ?? start, hasTTY: false,
                      cpuTime: cpu, footprint: 0, energy: 0, diskWritten: 0, restricted: restricted)
    }

    @Test func coresFromCpuTimeDelta() {
        var m = ProcessMeter()
        #expect(m.update([rec(10, cpu: 1_000_000_000)], at: t0) == nil)
        let c = m.update([rec(10, cpu: 4_000_000_000)], at: t0.addingTimeInterval(2))!
        #expect(abs(c[10]! - 1.5) < 1e-9)
    }

    /// Biten ve yeniden kullanılan pid hayalet değer üretmez; eksi değer asla yok (Review Focus #2).
    @Test func exitedAndReusedPidsAreIgnored() {
        var m = ProcessMeter()
        _ = m.update([rec(10, cpu: 9_000_000_000), rec(11, cpu: 1_000)], at: t0)
        let c = m.update([rec(10, cpu: 100, start: start.addingTimeInterval(500)), rec(12, cpu: 5_000_000_000)], at: t0.addingTimeInterval(2))!
        #expect(c[10] == nil && c[11] == nil && c[12] == nil)                 // pid 10 yeniden kullanıldı, 11 bitti, 12 yeni
        #expect(c.values.allSatisfy { $0 >= 0 })
        let d = m.update([rec(10, cpu: 2_000_000_100, start: start.addingTimeInterval(500))], at: t0.addingTimeInterval(4))!
        #expect(abs(d[10]! - 1.0) < 1e-9)
    }

    /// İzin verilmeyen süreçlerin (başka kullanıcı) CPU'su okunamaz; ölçüme girmez.
    @Test func restrictedRecordsAreSkipped() {
        var m = ProcessMeter()
        _ = m.update([rec(1, cpu: 0, restricted: true)], at: t0)
        #expect(m.update([rec(1, cpu: 0, restricted: true)], at: t0.addingTimeInterval(2))?[1] == nil)
    }

    @Test func lightModeFiveSecondCadenceStillMeasures() {
        var m = ProcessMeter()
        _ = m.update([rec(10, cpu: 0)], at: t0)
        #expect(abs(m.update([rec(10, cpu: 2_500_000_000)], at: t0.addingTimeInterval(5))![10]! - 0.5) < 1e-9)
    }
}
