import Foundation
import Testing
@testable import MystatCore

@Suite struct NettopParserTests {
    static let header = ",bytes_in,bytes_out,"

    func feed(_ p: inout NettopParser, _ lines: [String]) -> [[Int32: NetBytes]] {
        lines.compactMap { p.feed(Substring($0)) }
    }

    @Test func parsesSamplesAfterHeader() {
        var p = NettopParser()
        let out = feed(&p, [Self.header, "kernel_task.0,9,9,", "Code.7728,100,1,",          // ilk örnek: süreç başından birikmiş, atlanır
                            Self.header, "kernel_task.0,251,269,", "Code Helper (Pl.8196,4292,180,",
                            "com.docker.back.11400,104142,54154,", "2.1.310.10767,5599,0,",
                            Self.header])
        #expect(out == [[0: NetBytes(inBytes: 251, outBytes: 269), 8196: NetBytes(inBytes: 4292, outBytes: 180),
                         11400: NetBytes(inBytes: 104142, outBytes: 54154), 10767: NetBytes(inBytes: 5599, outBytes: 0)]])
    }

    @Test func toleratesCarriageReturnsAndCommasInNames() {
        var p = NettopParser()
        let out = feed(&p, [Self.header + "\r", Self.header + "\r", "a,b.42,10,20,\r", "x.42,5,0,", Self.header])
        #expect(out == [[42: NetBytes(inBytes: 15, outBytes: 20)]])   // aynı pid toplanır
    }

    @Test func skipsBrokenLines() {
        var p = NettopParser()
        let out = feed(&p, ["önce.1,1,1,", Self.header, Self.header, "bozuk", "ad.abc,1,2,", "ad.12,x,2,", "", "ad.13,-4,2,", "ad.14,7,8,", Self.header])
        #expect(out == [[14: NetBytes(inBytes: 7, outBytes: 8)]])
    }

    @Test func consecutiveHeaders() {
        var p = NettopParser()
        let out = feed(&p, [Self.header, "a.1,1,1,", Self.header, Self.header])
        #expect(out == [[:]])
    }

    @Test func ratesPerPid() {
        let r = NetRates.perPid([7: NetBytes(inBytes: 4_000_000, outBytes: 1)], interval: 2)
        #expect(r == [7: 2.0])
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

    /// Kısa çalıştırmada (`-L 2`) son örneğin ardından başlık gelmez: süreç bitince `finish()` onu verir.
    @Test func finishReturnsLastSample() {
        var p = NettopParser()
        #expect(feed(&p, [Self.header, "a.1,9,9,", Self.header, "a.1,4,2,"]).isEmpty)
        #expect(p.finish() == [1: NetBytes(inBytes: 4, outBytes: 2)])
        var q = NettopParser()
        _ = feed(&q, [Self.header, "a.1,9,9,"])
        #expect(q.finish() == nil)   // tek örnek: birikmiş toplam, atlanır
    }
}
