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
    /// Değer şablonunu aşarsa (RAM %100, ↓123,4) öğe uzunluğu güncellenmeli; yoksa saat sağdan kırpılır.
    /// Normalde şablonlar sayesinde uzunluk değişmez ve dokunulmaz.
    @Test func lengthFollowsOverflowingValues() {
        let measure: (String, CGFloat, Bool) -> CGFloat = { s, size, _ in CGFloat(s.count) * size * 0.6 }
        let a = StatusBlockModel.sample
        let w = ceil(StatusBlockLayout.width(a, measure: measure))
        #expect(StatusBlockLayout.newLength(a, current: w, measure: measure) == nil)
        var full = a; full.metrics[1].value = "%100"
        let grown = StatusBlockLayout.newLength(full, current: w, measure: measure)
        #expect(grown != nil && grown! > w)
        var fast = a; fast.down = "↓123,4"
        #expect(StatusBlockLayout.newLength(fast, current: w, measure: measure) != nil)
        #expect(StatusBlockLayout.newLength(a, current: grown!, measure: measure) == w)   // geri daralır
    }
    /// Uyarı öğesi mockup `popin` ile belirir (0,45 sn, cubic-bezier(.2,.9,.3,1.2), 8 px sağdan, ölçek 0,9),
    /// tersiyle 0,3 sn'de kaybolur (spec §4 "Belirme ve kaybolma yumuşak bir geçişle olur").
    @Test func alertPopInAndOut() {
        let a0 = StatusBlockLayout.alertAppearance(.appear, elapsed: 0)
        #expect(a0.opacity == 0 && a0.dx == 8 && abs(a0.scale - 0.9) < 1e-9)
        let a1 = StatusBlockLayout.alertAppearance(.appear, elapsed: 0.45)
        #expect(a1.opacity == 1 && a1.dx == 0 && a1.scale == 1)
        let mid = StatusBlockLayout.alertAppearance(.appear, elapsed: 0.2)
        #expect(mid.opacity > 0.5 && mid.opacity <= 1 && mid.dx < 4)
        #expect(StatusBlockLayout.alertAppearance(.disappear, elapsed: 0).opacity == 1)
        #expect(StatusBlockLayout.alertAppearance(.disappear, elapsed: 0.3).opacity == 0)
        #expect(StatusBlockLayout.alertAnimationDone(.appear, elapsed: 0.45) && !StatusBlockLayout.alertAnimationDone(.disappear, elapsed: 0.2))
        // cubic-bezier(.2,.9,.3,1.2) aşar: ortalarda ölçek 1'in biraz üstüne çıkar
        let peak = stride(from: 0.0, through: 0.45, by: 0.01).map { StatusBlockLayout.alertAppearance(.appear, elapsed: $0).scale }.max()!
        #expect(peak > 1 && peak < 1.03)
    }
}
