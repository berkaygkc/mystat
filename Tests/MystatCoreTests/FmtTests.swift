import CoreGraphics
import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@Suite(.language("tr")) struct FmtTests {
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
        // The menu bar uses three-letter month and weekday names.
        #expect(Fmt.menubarDate(d(2026, 10, 28, 8, 45, 18), calendar: cal) == "28 Eki 2026 Çar")
        #expect(Fmt.menubarDate(d(2026, 11, 1, 0, 0, 5), calendar: cal) == "1 Kas 2026 Paz")
    }
    @Test func suffixes() {
        #expect(TurkishSuffix.possessive3(after: "12,7") == "'si"); #expect(TurkishSuffix.possessive3(after: "3") == "'ü")
        #expect(TurkishSuffix.possessive3(after: "10") == "'u"); #expect(TurkishSuffix.possessive3(after: "4,0") == "'ı")
        #expect(TurkishSuffix.possessive3(after: "100") == "'ü"); #expect(TurkishSuffix.possessive3(after: "6") == "'sı")
    }
    /// Real data may contain NaN/inf (division by zero, first sample); "—" is written without crashing.
    @Test func nonFiniteValuesShowDash() {
        #expect(Fmt.pct(.nan) == "—"); #expect(Fmt.dec1(.infinity) == "—"); #expect(Fmt.int(-.infinity) == "—")
        #expect(Fmt.size(.nan) == "—"); #expect(Fmt.cores(.nan) == "—")
    }

    /// Even if the region setting uses a Buddhist/Islamic calendar, the clock block is written in Gregorian.
    @Test func clockCalendarIsGregorian() {
        #expect(Fmt.calendar.identifier == .gregorian)
        var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let d = Date(timeIntervalSince1970: 1_793_166_318)   // 2026-10-28 08:45:18 +03
        #expect(Fmt.dateLine(d, calendar: Fmt.calendar) == "28 Ekim 2026 Çarşamba")
        #expect(Fmt.dateLine(d, calendar: buddhist) != "28 Ekim 2026 Çarşamba")   // proof that it is needed
    }
}

@Suite(.language("en")) struct FmtEnglishTests {
    @Test func numbers() {
        #expect(Fmt.pct(62) == "62%"); #expect(Fmt.int(1201) == "1,201"); #expect(Fmt.dec1(14.6) == "14.6")
        #expect(Fmt.cores(4.2) == "4.2"); #expect(Fmt.cores(0.03) == "<0.1"); #expect(Fmt.size(9.5) == "9.5 GB")
    }
    @Test func clockLines() {
        let cal = Calendar.trTest
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 14, minute: 2, second: 7))!
        #expect(Fmt.dateLine(d, calendar: cal) == "Thursday, October 29, 2026")
        #expect(Fmt.timeLine(d, calendar: cal) == "14:02:07")
        #expect(Fmt.menubarDate(d, calendar: cal) == "Thu, Oct 29, 2026")   // 24-hour in every language
    }
    @Test func uptimeUnits() {
        #expect(Fmt.uptime(14 * 60) == "14 min"); #expect(Fmt.uptime(134 * 60) == "2 h 14 min")
        #expect(Fmt.uptime(45 * 3600) == "45 h"); #expect(Fmt.uptime(73 * 3600) == "3 days"); #expect(Fmt.uptime(24 * 3600 * 1 + 3600 * 50) == "3 days")
    }
    @Test func statusTemplatesFollowLanguage() {
        #expect(StatusBlockLayout.dateTemplate == "Wed, May 13, 2026")
        #expect(StatusBlockLayout.cpuTemplate == "100%"); #expect(StatusBlockLayout.alertTemplate == "−88%")
        #expect(StatusBlockLayout.netTemplate == "↓88.8")
    }
    /// The clock column is sized by the widest English date: a shorter date block does not narrow it.
    @Test func templateWidthPerLanguage() {
        let measure: (String, CGFloat, Bool) -> CGFloat = { s, size, _ in CGFloat(s.count) * size * 0.6 }
        var a = StatusBlockModel.sample; a.date = "Friday, May 1, 2026"
        let clock = StatusBlockLayout.parts(a, measure: measure).first { $0.0 == .clock }!.1
        #expect(clock >= measure("Wed, May 13, 2026", StatusBlockLayout.dateSize, false))
    }
}

@Suite(.language("tr")) struct FmtTurkishUnitsTests {
    @Test func uptimeUnits() {
        #expect(Fmt.uptime(14 * 60) == "14 dk"); #expect(Fmt.uptime(134 * 60) == "2 sa 14 dk")
        #expect(Fmt.uptime(45 * 3600) == "45 sa"); #expect(Fmt.uptime(73 * 3600) == "3 gün")
        #expect(StatusBlockLayout.dateTemplate == "10 Tem 2026 Cum"); #expect(StatusBlockLayout.cpuTemplate == "%100")
        #expect(StatusBlockLayout.netTemplate == "↓88,8")
    }
}

/// Incident culprit values are read back from the format they are displayed in (bar lengths).
@Suite struct FmtNumberTests {
    @Test func parsesDisplayedValues() {
        L10n.$override.withValue("tr") {
            #expect(Fmt.number("4,2") == 4.2); #expect(Fmt.number("%62") == 62); #expect(Fmt.number("+2,1") == 2.1); #expect(Fmt.number("1.201") == 1201)
        }
        L10n.$override.withValue("en") {
            #expect(Fmt.number("4.2") == 4.2); #expect(Fmt.number("62%") == 62); #expect(Fmt.number("+2.1") == 2.1); #expect(Fmt.number("1,201") == 1201)
            #expect(Fmt.number("restarting") == nil)
        }
    }
}
