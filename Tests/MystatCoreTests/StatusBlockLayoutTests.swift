import CoreGraphics
import Foundation
import Testing
@testable import MystatCore

@MainActor @Suite struct StatusBlockLayoutTests {
    @Test func alertMetricPerKind() {
        let cal = Calendar.trTest; let now = Date()
        let a = { (k: IncidentKind) in StatusBlockLayout.model(SampleSource(seed: 1, incident: true, kind: k).snapshot, now: now, calendar: cal).alert }
        #expect(a(.battery) == StatusMetric(label: "PİL", value: "−%25", level: .warn))
        #expect(a(.docker) == StatusMetric(label: "DOCKER", value: "%62", level: .warn))
        #expect(a(.heat) == StatusMetric(label: "ISI", value: "91°", level: .warn))
        #expect(a(.memory) == nil)   // bellek olayında yeni öğe çıkmaz, RAM metriği renklenir
    }
    @Test func modelCalmAndIncident() {
        let cal = Calendar.trTest; let now = cal.date(from: .init(year: 2026, month: 10, day: 28, hour: 8, minute: 45, second: 18))!
        let calm = StatusBlockLayout.model(SampleSource(seed: 1).snapshot, now: now, calendar: cal)
        #expect(calm.alert == nil); #expect(calm.metrics.map(\.label) == ["CPU", "RAM", "DİSK"])
        #expect(calm.date == "28 Ekim 2026 Çarşamba"); #expect(calm.time == "08:45:18"); #expect(calm.down.hasPrefix("↓"))
        let hot = StatusBlockLayout.model(SampleSource(seed: 1, incident: true).snapshot, now: now, calendar: cal)
        #expect(hot.alert == StatusMetric(label: "ISI", value: "91°", level: .warn)); #expect(hot.metrics[0].level == .crit)
        let mem = StatusBlockLayout.model(SampleSource(seed: 1, incident: true, kind: .memory).snapshot, now: now, calendar: cal)
        #expect(mem.metrics[1].level == .crit)
        let disk = StatusBlockLayout.model(SampleSource(seed: 1, incident: true, kind: .disk).snapshot, now: now, calendar: cal)
        #expect(disk.metrics[2].level == .crit)
    }
    @Test func widthIsStable() {
        let measure: (String, CGFloat, Bool) -> CGFloat = { s, size, _ in CGFloat(s.count) * size * 0.6 }
        let a0 = StatusBlockModel.sample
        var a = a0; a.metrics[0].value = "%9"
        var b = a0; b.metrics[0].value = "%100"; b.down = "↓12,4"; b.date = "1 Mayıs 2026 Cuma"
        #expect(StatusBlockLayout.width(a, measure: measure) == StatusBlockLayout.width(b, measure: measure))
        var c = a0; c.alert = StatusMetric(label: "ISI", value: "91°", level: .warn)
        #expect(StatusBlockLayout.width(c, measure: measure) > StatusBlockLayout.width(a0, measure: measure))
    }
}
