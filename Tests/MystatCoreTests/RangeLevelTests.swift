import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@Suite(.language("tr")) struct RangeLevelTests {
    @Test func rangeShape() {
        #expect(TimeRange.allCases.map(\.pointCount) == [120, 120, 144, 168])
        #expect(TimeRange.m10.title == "10 dk")
        #expect(TimeRange.h1.axisLabels == ["1 sa önce", "30 dk", "şimdi"])
    }
    @Test func hoverLabels() {
        let cal = Calendar.trTest
        let now = cal.date(from: .init(year: 2026, month: 10, day: 28, hour: 9, minute: 30))!
        #expect(TimeRange.m10.hoverLabel(index: 119, now: now, calendar: cal) == "şimdi")
        #expect(TimeRange.m10.hoverLabel(index: 110, now: now, calendar: cal) == "45 sn önce")
        #expect(TimeRange.m10.hoverLabel(index: 79, now: now, calendar: cal) == "3 dk 20 sn önce")
        #expect(TimeRange.m10.hoverLabel(index: 95, now: now, calendar: cal) == "2 dk önce")
        #expect(TimeRange.h24.hoverLabel(index: 137, now: now, calendar: cal) == "08:30")
        #expect(TimeRange.d7.hoverLabel(index: 143, now: now, calendar: cal) == "Salı 09:00")
    }
    @Test func levels() {
        #expect(Thresholds.cpuTotal(69.9) == .ok); #expect(Thresholds.cpuTotal(70) == .warn); #expect(Thresholds.cpuTotal(85) == .crit)
        #expect(Thresholds.groupCores(2) == .warn); #expect(Thresholds.diskFree(9) == .crit)
    }
}
