import AppKit
import CoreGraphics
import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@MainActor @Suite(.language("tr")) struct StatusBlockLayoutTests {
    @Test func alertMetricPerKind() {
        let cal = Calendar.trTest; let now = Date()
        let a = { (k: IncidentKind) in StatusBlockLayout.model(SampleSource(seed: 1, incident: true, kind: k).snapshot, now: now, calendar: cal).alert }
        #expect(a(.battery) == StatusMetric(label: "PİL", value: "−%25", level: .warn))
        #expect(a(.docker) == StatusMetric(label: "DOCKER", value: "%62", level: .warn))
        #expect(a(.heat) == StatusMetric(label: "ISI", value: "91°", level: .warn))
        #expect(a(.memory) == nil)   // a memory incident adds no new item; the RAM metric is tinted instead
    }
    @Test func modelCalmAndIncident() {
        let cal = Calendar.trTest; let now = cal.date(from: .init(year: 2026, month: 10, day: 28, hour: 8, minute: 45, second: 18))!
        let calm = StatusBlockLayout.model(SampleSource(seed: 1).snapshot, now: now, calendar: cal)
        #expect(calm.alert == nil); #expect(calm.metrics.map(\.label) == ["CPU", "RAM", "DİSK"])
        #expect(calm.date == "28 Eki 2026 Çar"); #expect(calm.time == "08:45")   // no seconds in the menu bar (idle cost); #expect(calm.down.hasPrefix("↓"))
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
        var b = a0; b.metrics[0].value = "%100"; b.down = "↓12,4"; b.date = "1 May 2026 Cum"
        #expect(StatusBlockLayout.width(a, measure: measure) == StatusBlockLayout.width(b, measure: measure))
        var c = a0; c.alert = StatusMetric(label: "ISI", value: "91°", level: .warn)
        #expect(StatusBlockLayout.width(c, measure: measure) > StatusBlockLayout.width(a0, measure: measure))
    }
    /// If a value exceeds its template (RAM 100%, ↓123.4) the item length must be updated; otherwise the clock is clipped on the right.
    /// Normally the templates keep the length constant and it is left alone.
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
        #expect(StatusBlockLayout.newLength(a, current: grown!, measure: measure) == w)   // narrows back
    }
    /// The alert item appears with a pop-in (0.45 s, cubic-bezier(.2,.9,.3,1.2), 8 px from the right, scale 0.9)
    /// and disappears with the reverse in 0.3 s, so appearing and disappearing both use a soft transition.
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
        // cubic-bezier(.2,.9,.3,1.2) overshoots: mid-way the scale rises slightly above 1
        let peak = stride(from: 0.0, through: 0.45, by: 0.01).map { StatusBlockLayout.alertAppearance(.appear, elapsed: $0).scale }.max()!
        #expect(peak > 1 && peak < 1.03)
    }

    /// No sensors in live data: a warm thermal state alone does not open an item; during an incident the state is written instead of a temperature.
    @Test func liveAlertFollowsIncidentWithoutSensors() {
        var s = SampleSource(seed: 1).snapshot
        s.capabilities = SourceCapabilities(docker: false, sensors: false, diskScan: false, netDetails: false)
        s.system.chipTemp = 0
        s.system.thermal = .warn
        #expect(StatusBlockLayout.alert(s) == nil)
        s.incident = Incident(kind: .heat, level: .warn, startedAt: "10:00", minutes: 2, peakPercent: 0, culpritIDs: [], culpritValues: [],
                              culpritUnit: "çekirdek", facts: [])
        #expect(StatusBlockLayout.alert(s) == StatusMetric(label: "ISI", value: "Ilık", level: .warn))
    }
}

/// The menu bar reserves the width of `_meta.dateTemplate` so the block doesn't jump when the date changes. The template
/// must be at least as wide as every real date, in every language, measured with the menu bar's own font.
@Suite struct DateTemplateTests {
    @Test func templateCoversEveryDate() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: StatusBlockLayout.dateSize, weight: .medium)   // StatusBlockView.dateFont
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        let cal = Calendar.trTest
        for lang in Localizer.shared.languages {
            L10n.$override.withValue(lang.code) {
                let template = width(StatusBlockLayout.dateTemplate)
                var day = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
                var widest = ("", CGFloat(0))
                for _ in 0..<(366 * 3) {
                    let s = Fmt.menubarDate(day, calendar: cal)
                    if width(s) > widest.1 { widest = (s, width(s)) }
                    day = cal.date(byAdding: .day, value: 1, to: day)!
                }
                #expect(widest.1 <= template + 0.5, "\(lang.code): \(widest.0) is wider than \(StatusBlockLayout.dateTemplate)")
            }
        }
    }
}
