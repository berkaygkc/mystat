import Foundation
import Testing
@testable import MystatCore

@Suite struct FmtTests {
    @Test func percents() { #expect(Fmt.pct(14.4) == "%14"); #expect(Fmt.pct(100) == "%100") }
    @Test func decimals() { #expect(Fmt.dec1(4.2) == "4,2"); #expect(Fmt.int(4800) == "4.800") }
    @Test func cores() { #expect(Fmt.cores(0.03) == "<0,1"); #expect(Fmt.cores(0) == "0,0"); #expect(Fmt.cores(3.14) == "3,1") }
    @Test func mem() { #expect(Fmt.mem(10.2) == "10 GB"); #expect(Fmt.mem(2.5) == "2,5 GB") }
    @Test func sizes() {
        #expect(Fmt.size(236) == "236 GB"); #expect(Fmt.size(9.5) == "9,5 GB")
        #expect(Fmt.size(0.105) == "105 MB"); #expect(Fmt.size(0.0042) == "4,2 MB"); #expect(Fmt.size(0.0000004) == "1 KB")
    }
    @Test func clockLines() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let d = { (y: Int, m: Int, day: Int, h: Int, mi: Int, s: Int) in cal.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: mi, second: s))! }
        #expect(Fmt.dateLine(d(2026, 10, 28, 8, 45, 18), calendar: cal) == "28 Ekim 2026 Çarşamba")
        #expect(Fmt.dateLine(d(2026, 11, 1, 0, 0, 5), calendar: cal) == "1 Kasım 2026 Pazar")
        #expect(Fmt.dateLine(d(2026, 12, 31, 23, 59, 59), calendar: cal) == "31 Aralık 2026 Perşembe")
        #expect(Fmt.timeLine(d(2026, 11, 1, 0, 0, 5), calendar: cal) == "00:00:05")
    }
    @Test func suffixes() {
        #expect(TurkishSuffix.possessive3(after: "12,7") == "'si"); #expect(TurkishSuffix.possessive3(after: "3") == "'ü")
        #expect(TurkishSuffix.possessive3(after: "10") == "'u"); #expect(TurkishSuffix.possessive3(after: "4,0") == "'ı")
        #expect(TurkishSuffix.possessive3(after: "100") == "'ü"); #expect(TurkishSuffix.possessive3(after: "6") == "'sı")
    }
}
