import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// Bellek içi seriler (10 dk: 5 sn × 120, 1 sa: 30 sn × 120) ve grup halkaları (spec §9.4).
@MainActor @Suite(.language("tr")) struct SeriesBufferTests {
    let t0 = Date(timeIntervalSince1970: 1_793_163_600)   // 5 ve 30 sn'nin katı

    @Test func m10BucketsAverage() {
        var b = SeriesBuffer()
        b.add(.cpu, 10, at: t0)
        b.add(.cpu, 20, at: t0.addingTimeInterval(2))
        b.add(.cpu, 99, at: t0.addingTimeInterval(6))          // sonraki kova (açık, henüz kapanmadı)
        #expect(b.series(.cpu, .m10) == [15, 99])
    }

    @Test func capsAtPointCount() {
        var b = SeriesBuffer()
        var t = 0.0
        while t < 900 { b.add(.cpu, t, at: t0.addingTimeInterval(t)); t += 2 }    // 15 dk
        #expect(b.series(.cpu, .m10).count == 120)
        #expect(b.series(.cpu, .h1).count == 30)
    }

    /// 2 saatlik boşluk düz çizgiyle doldurulmaz; seri boşluktan sonra yeniden başlar (Review Focus #1).
    @Test func gapRestartsSeries() {
        var b = SeriesBuffer()
        for i in 0..<30 { b.add(.netDown, 5, at: t0.addingTimeInterval(Double(i) * 2)) }
        b.add(.netDown, 7, at: t0.addingTimeInterval(7200))
        #expect(b.series(.netDown, .m10) == [7] && b.series(.netDown, .h1) == [7])
    }

    func group(_ id: String, cores: Double, memGB: Double) -> ProcessGroup {
        ProcessGroup(id: id, name: id, context: "", cpuCores: cores, memoryGB: memGB, netMBps: 0, uptime: "", processCount: 1,
                     folder: nil, terminal: nil, port: nil, isOrphan: false, relatedID: nil, isDocker: false, children: [])
    }

    @Test func groupCoresAndMemoryGrowth() {
        var h = GroupHistory()
        for i in 0...300 {   // 10 dk, 2 sn
            let t = t0.addingTimeInterval(Double(i) * 2)
            h.add([group("docker", cores: 0.5, memGB: 8 + Double(i) / 300 * 2.1), group("brave", cores: 0.2, memGB: 3)], writtenBytes: [:], at: t)
        }
        #expect(h.cores("docker").count == 300 && h.cores("docker").last == 0.5)
        let g = h.memoryGrowthGB()
        #expect(abs((g["docker"] ?? 0) - 2.1) < 0.02 && (g["brave"] ?? 0) < 0.01)
    }

    @Test func groupDiskWritesOverLastHour() {
        var h = GroupHistory()
        for m in 0..<70 {   // 70 dk boyunca dakikada 1 GB
            for s in stride(from: 0, to: 60, by: 5) {
                h.add([group("docker", cores: 0, memGB: 1)], writtenBytes: ["docker": s == 0 ? 1_000_000_000 : 0],
                      at: t0.addingTimeInterval(Double(m * 60 + s)))
            }
        }
        #expect(abs((h.diskWrittenGB1h()["docker"] ?? 0) - 60) < 0.001)
    }

    @Test func vanishedGroupsAreForgotten() {
        var h = GroupHistory()
        h.add([group("a", cores: 1, memGB: 1)], writtenBytes: [:], at: t0)
        for i in 1...400 { h.add([], writtenBytes: [:], at: t0.addingTimeInterval(Double(i) * 2)) }
        #expect(h.cores("a").isEmpty)
    }
}
