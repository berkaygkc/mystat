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

    /// İki örnek arasında doğan süreç: CPU süresinin tamamı bu aralıkta harcandı (derleme işleri "macOS"a yazılmasın).
    @Test func newbornProcessCountsFully() {
        var m = ProcessMeter()
        _ = m.update([rec(1, cpu: 0)], at: t0)
        let born = rec(2, cpu: 1_000_000_000, start: t0.addingTimeInterval(1))
        let c = m.update([rec(1, cpu: 0), born], at: t0.addingTimeInterval(2))
        #expect(c?[2].map { abs($0 - 0.5) < 1e-9 } == true)
    }

    func kid(_ pid: Int32, of parent: Int32, cpu: UInt64) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: parent, uid: 501, name: "cc", path: nil, args: [], cwd: nil, start: start, hasTTY: false,
                      cpuTime: cpu, footprint: 0, energy: 0, diskWritten: 0)
    }
    func parent(child: UInt64) -> ProcessRecord {
        ProcessRecord(pid: 10, ppid: 1, uid: 501, name: "make", path: nil, args: [], cwd: nil, start: start, hasTTY: false,
                      cpuTime: 0, footprint: 0, energy: 0, diskWritten: 0, childCPUTime: child)
    }

    /// Ölüp toplanan çocukların süresi ebeveyne yazılır; önceki örnekte sayılmış kısmı tekrar sayılmaz.
    @Test func reapedChildrenCountOnParent() {
        var m = ProcessMeter()
        _ = m.update([parent(child: 0), kid(11, of: 10, cpu: 1_000_000_000)], at: t0)
        let c = m.update([parent(child: 3_000_000_000)], at: t0.addingTimeInterval(2))   // 11 bitti: 1 sn sayılmıştı, 2 sn yeni
        #expect(c?[10].map { abs($0 - 1) < 1e-9 } == true)
    }

    /// Ebeveyn çocuğu geç toplarsa sayılmış kısım bir sonraki tura taşınır.
    @Test func lateReapingIsNotDoubleCounted() {
        var m = ProcessMeter()
        _ = m.update([parent(child: 0), kid(11, of: 10, cpu: 1_000_000_000)], at: t0)
        let a = m.update([parent(child: 0)], at: t0.addingTimeInterval(2))
        #expect(a?[10] == 0)
        let b = m.update([parent(child: 3_000_000_000)], at: t0.addingTimeInterval(4))
        #expect(b?[10].map { abs($0 - 1) < 1e-9 } == true)
    }
}
