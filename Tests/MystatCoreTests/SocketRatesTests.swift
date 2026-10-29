import Foundation
import Testing
@testable import MystatCore

@Suite struct SocketRatesTests {
    func s(_ handle: UInt64, _ pid: Int32, _ rx: UInt64) -> SocketStat { SocketStat(handle: handle, pid: pid, rxBytes: rx) }

    @Test func firstReadIsBaseline() {
        var r = SocketRates(receiveFactor: 2)
        #expect(r.update([s(1, 7, 5_000_000)], at: 100) == nil)
    }

    /// Çekirdek alınanı iki kez sayıyor (ölçüldü): 2 sn'de 8 MB sayaç farkı → 2 MB/s.
    @Test func deltasPerPidDividedByFactor() {
        var r = SocketRates(receiveFactor: 2)
        _ = r.update([s(1, 7, 1_000_000), s(2, 7, 0), s(3, 9, 500)], at: 100)
        let out = r.update([s(1, 7, 7_000_000), s(2, 7, 2_000_000), s(3, 9, 500)], at: 102)
        #expect(out == [7: 2.0, 9: 0])
    }

    @Test func newSocketCountsFullyClosedIgnoredResetCounts() {
        var r = SocketRates(receiveFactor: 1)
        _ = r.update([s(1, 7, 1_000_000), s(2, 8, 900)], at: 0)
        // 1 kapandı (yok sayılır), 2'nin sayacı sıfırlandı (tutamaç yeniden kullanıldı: güncel değer sayılır), 3 yeni
        let out = r.update([s(2, 8, 300), s(3, 9, 4_000_000)], at: 2)
        #expect(out == [8: 0.00015, 9: 2.0])
    }

    @Test func nonPositiveIntervalGivesNothing() {
        var r = SocketRates(receiveFactor: 1)
        _ = r.update([s(1, 7, 0)], at: 5)
        #expect(r.update([s(1, 7, 100)], at: 5) == nil)
    }

    @Test func applyToGroups() {
        func g(_ id: String, _ pids: [Int32]) -> ProcessGroup {
            var x = ProcessGroup(id: id, name: id, context: "", cpuCores: 0, memoryGB: 0, netMBps: 9, uptime: "", processCount: pids.count,
                                 folder: nil, terminal: nil, port: nil, isOrphan: false, relatedID: nil, isDocker: false, children: [])
            x.pids = pids
            return x
        }
        var groups = [g("A", [10, 11]), g("B", [12])]
        NetRates.apply([10: 1, 11: 0.5, 99: 7], to: &groups)
        #expect(groups.map(\.netMBps) == [1.5, 0])
    }
}
