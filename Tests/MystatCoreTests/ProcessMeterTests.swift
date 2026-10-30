import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// Cores derived from per-process CPU time deltas (1.0 = one full core).
@Suite(.language("tr")) struct ProcessMeterTests {
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

    /// A process that exited or whose pid was reused produces no phantom value; negative values never occur.
    @Test func exitedAndReusedPidsAreIgnored() {
        var m = ProcessMeter()
        _ = m.update([rec(10, cpu: 9_000_000_000), rec(11, cpu: 1_000)], at: t0)
        let c = m.update([rec(10, cpu: 100, start: start.addingTimeInterval(500)), rec(12, cpu: 5_000_000_000)], at: t0.addingTimeInterval(2))!
        #expect(c[10] == nil && c[11] == nil && c[12] == nil)                 // pid 10 was reused, 11 exited, 12 is new
        #expect(c.values.allSatisfy { $0 >= 0 })
        let d = m.update([rec(10, cpu: 2_000_000_100, start: start.addingTimeInterval(500))], at: t0.addingTimeInterval(4))!
        #expect(abs(d[10]! - 1.0) < 1e-9)
    }

    /// CPU of processes we may not inspect (another user) cannot be read; it is left out of the measurement.
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

    /// A process born between two samples: all of its CPU time was spent in that interval (so build jobs are not attributed to "macOS").
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

    /// The time of reaped, dead children is credited to the parent; the part already counted in the previous sample is not counted again.
    @Test func reapedChildrenCountOnParent() {
        var m = ProcessMeter()
        _ = m.update([parent(child: 0), kid(11, of: 10, cpu: 1_000_000_000)], at: t0)
        let c = m.update([parent(child: 3_000_000_000)], at: t0.addingTimeInterval(2))   // 11 exited: 1 s had been counted, 2 s is new
        #expect(c?[10].map { abs($0 - 1) < 1e-9 } == true)
    }

    /// If the parent reaps the child late, the already-counted portion is carried over to the next round.
    @Test func lateReapingIsNotDoubleCounted() {
        var m = ProcessMeter()
        _ = m.update([parent(child: 0), kid(11, of: 10, cpu: 1_000_000_000)], at: t0)
        let a = m.update([parent(child: 0)], at: t0.addingTimeInterval(2))
        #expect(a?[10] == 0)
        let b = m.update([parent(child: 3_000_000_000)], at: t0.addingTimeInterval(4))
        #expect(b?[10].map { abs($0 - 1) < 1e-9 } == true)
    }
}
