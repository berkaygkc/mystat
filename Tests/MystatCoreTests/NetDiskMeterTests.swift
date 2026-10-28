import Foundation
import Testing
@testable import MystatCore

/// Ağ ve disk hızları, bugünkü toplamlar ve disk doluluğu (spec §7.1).
@Suite struct NetDiskMeterTests {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Istanbul")!; return c }
    let t0 = Date(timeIntervalSince1970: 1_793_166_318)   // 2026-10-28 08:45:18 +03

    func en0(_ rx: UInt64, _ tx: UInt64) -> [InterfaceCounters] {
        [InterfaceCounters(name: "lo0", rx: 9_999_999, tx: 9_999_999, up: true), InterfaceCounters(name: "en0", rx: rx, tx: tx, up: true)]
    }

    @Test func rateIsDecimalMBps() {
        var m = NetMeter(primary: "en0")
        #expect(m.update(en0(1_000_000, 0), at: t0, calendar: cal) == nil)
        let r = m.update(en0(5_000_000, 600_000), at: t0.addingTimeInterval(2), calendar: cal)!
        #expect(abs(r.down - 2.0) < 1e-9 && abs(r.up - 0.3) < 1e-9)
        #expect(abs(r.todayDown - 0.004) < 1e-9)                     // GB, ondalık
    }

    /// Arayüz yeniden başlayınca sayaç geri gider: eksi hız yok, o örnek atlanır (Review Focus #3).
    @Test func counterResetIsSkipped() {
        var m = NetMeter(primary: "en0")
        _ = m.update(en0(9_000_000, 9_000_000), at: t0, calendar: cal)
        #expect(m.update(en0(1_000, 1_000), at: t0.addingTimeInterval(2), calendar: cal) == nil)
        let r = m.update(en0(3_001_000, 1_000), at: t0.addingTimeInterval(4), calendar: cal)!
        #expect(abs(r.down - 1.5) < 1e-9 && r.up == 0)
    }

    /// Uykudan sonraki ilk fark atılır (Review Focus #1).
    @Test func sleepGapSkipped() {
        var m = NetMeter(primary: "en0")
        _ = m.update(en0(0, 0), at: t0, calendar: cal)
        #expect(m.update(en0(500_000_000, 0), at: t0.addingTimeInterval(7200), calendar: cal) == nil)
    }

    @Test func todayResetsAtLocalMidnight() {
        let late = Date(timeIntervalSince1970: 1_793_221_198)   // 2026-10-28 23:59:58 +03
        var m = NetMeter(primary: "en0", today: .init(day: "2026-10-28", downGB: 12.4, upGB: 1.8))
        _ = m.update(en0(0, 0), at: late, calendar: cal)
        let before = m.update(en0(1_000_000_000, 0), at: late.addingTimeInterval(1), calendar: cal)!
        #expect(abs(before.todayDown - 13.4) < 1e-9)
        let after = m.update(en0(1_002_000_000, 0), at: late.addingTimeInterval(3), calendar: cal)!
        #expect(abs(after.todayDown - 0.002) < 1e-9 && m.today.day == "2026-10-29")
    }

    @Test func fallsBackToSumOfEthernetLike() {
        var m = NetMeter(primary: nil)
        let a = [InterfaceCounters(name: "en0", rx: 0, tx: 0, up: true), InterfaceCounters(name: "en5", rx: 0, tx: 0, up: true),
                 InterfaceCounters(name: "utun3", rx: 0, tx: 0, up: true)]
        _ = m.update(a, at: t0, calendar: cal)
        let b = [InterfaceCounters(name: "en0", rx: 2_000_000, tx: 0, up: true), InterfaceCounters(name: "en5", rx: 2_000_000, tx: 0, up: true),
                 InterfaceCounters(name: "utun3", rx: 50_000_000, tx: 0, up: true)]
        #expect(abs(m.update(b, at: t0.addingTimeInterval(2), calendar: cal)!.down - 2.0) < 1e-9)   // utun (VPN) çift sayılmaz
    }

    @Test func diskIORates() {
        var m = DiskIOMeter()
        #expect(m.update(DiskIOCounters(bytesRead: 0, bytesWritten: 0), at: t0) == nil)
        let r = m.update(DiskIOCounters(bytesRead: 16_400_000, bytesWritten: 9_400_000), at: t0.addingTimeInterval(2))!
        #expect(abs(r.read - 8.2) < 1e-9 && abs(r.write - 4.7) < 1e-9)
    }

    @Test func diskCapacityBreakdown() {
        let s = DiskMeter.state(VolumeCapacity(total: 500_000_000_000, available: 175_000_000_000, availableImportant: 187_000_000_000),
                                io: (read: 8.2, write: 4.7))
        #expect(abs(s.usedGB - 313) < 1e-9 && abs(s.purgeableGB - 12) < 1e-9 && abs(s.freeGB - 175) < 1e-9)
        #expect(abs(s.percent - 62.6) < 1e-9)
        #expect(s.readMBps == 8.2 && s.writeMBps == 4.7)
    }
}
