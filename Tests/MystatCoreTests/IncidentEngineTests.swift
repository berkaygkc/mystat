import Foundation
import Testing
@testable import MystatCore

/// Süreklilik süreli olaylar (spec §7.2): anlık sıçrama sayılmaz, 30 sn sakinlikte biter, kritik öne çıkar.
@MainActor @Suite struct IncidentEngineTests {
    let t0 = Date(timeIntervalSince1970: 1_793_163_660)   // 2026-10-28 08:01:00 +03
    let base = SampleSource(seed: 1).snapshot

    func inputs(cpu: Double = 14, groups: [ProcessGroup]? = nil, pressure: Level = .ok, swapGrowing: Bool = false,
                freeGB: Double = 175, thermal: Level = .ok, drain: Double? = nil) -> IncidentInputs {
        var c = base.cpu; c.percent = cpu
        var m = base.memory; m.pressureLevel = pressure
        var d = base.disk; d.freeGB = freeGB
        return IncidentInputs(cpu: c, memory: m, swapGrowing: swapGrowing, disk: d, groups: groups ?? base.groups, thermal: thermal,
                              batteryDrain30m: drain, onAC: drain == nil, memoryGrowthGB: ["docker": 2.1, "next-web": 1.4],
                              diskWrittenGB1h: ["docker": 12, "next-web": 3.1])
    }

    /// `seconds` boyunca 2 sn'de bir aynı girdi; son sonucu döndürür.
    func run(_ e: inout IncidentEngine, _ i: IncidentInputs, from: Double, seconds: Double) -> Incident? {
        var last: Incident?
        var t = from
        while t <= from + seconds { last = e.update(i, at: t0.addingTimeInterval(t)); t += 2 }
        return last
    }

    @Test func cpuNeedsOneMinute() {
        var e = IncidentEngine()
        #expect(run(&e, inputs(cpu: 90), from: 0, seconds: 58) == nil)
        let inc = run(&e, inputs(cpu: 90), from: 60, seconds: 2)
        #expect(inc?.kind == .cpu && inc?.level == .crit && inc?.startedAt == "08:01")
    }

    @Test func briefSpikeIsIgnored() {
        var e = IncidentEngine()
        #expect(run(&e, inputs(cpu: 95), from: 0, seconds: 10) == nil)
        #expect(run(&e, inputs(cpu: 20), from: 12, seconds: 120) == nil)
    }

    @Test func warnBetweenSeventyAndEightyFive() {
        var e = IncidentEngine()
        #expect(run(&e, inputs(cpu: 75), from: 0, seconds: 62)?.level == .warn)
    }

    @Test func endsAfterThirtyCalmSeconds() {
        var e = IncidentEngine()
        _ = run(&e, inputs(cpu: 90), from: 0, seconds: 62)
        #expect(run(&e, inputs(cpu: 20), from: 64, seconds: 28) != nil)
        #expect(run(&e, inputs(cpu: 20), from: 94, seconds: 2) == nil)
    }

    /// Toplam CPU düşükken tek grup 2 dk boyunca ≥ 4 çekirdek → kritik CPU olayı, sorumlu o grup.
    @Test func singleGroupCPU() {
        var e = IncidentEngine()
        var gs = base.groups
        gs[0].cpuCores = 4.5
        #expect(run(&e, inputs(cpu: 40, groups: gs), from: 0, seconds: 118) == nil)
        let inc = run(&e, inputs(cpu: 40, groups: gs), from: 120, seconds: 2)
        #expect(inc?.level == .crit && inc?.culpritIDs.first == gs[0].id && inc?.culpritUnit == "çekirdek")
    }

    @Test func culpritsAreTopThreeByCores() {
        var e = IncidentEngine()
        let inc = run(&e, inputs(cpu: 92), from: 0, seconds: 62)!
        let top = base.groups.sorted { $0.cpuCores > $1.cpuCores }.prefix(3).map(\.id)
        #expect(inc.culpritIDs == Array(top))
        #expect(inc.facts.map(\.label) == ["Başladı", "Zirve", "Şu an", "Isı"])
    }

    @Test func critBeatsOlderWarnAndOlderWinsTies() {
        var e = IncidentEngine()
        _ = run(&e, inputs(freeGB: 15), from: 0, seconds: 40)                       // disk dikkat (anında)
        #expect(run(&e, inputs(cpu: 90, freeGB: 15), from: 42, seconds: 62)?.kind == .cpu)   // CPU kritik öne
        var f = IncidentEngine()
        _ = run(&f, inputs(freeGB: 15), from: 0, seconds: 40)
        #expect(run(&f, inputs(cpu: 75, freeGB: 15), from: 42, seconds: 62)?.kind == .disk)  // ikisi dikkat: eski olan
    }

    /// 2 saatlik uyku: süreklilik sıfırlanır, olay "2 saattir" sürmez (Review Focus #1).
    @Test func sleepGapResetsContinuity() {
        var e = IncidentEngine()
        _ = run(&e, inputs(cpu: 90), from: 0, seconds: 30)
        #expect(run(&e, inputs(cpu: 90), from: 7230, seconds: 30) == nil)
        let inc = run(&e, inputs(cpu: 90), from: 7262, seconds: 30)
        #expect(inc != nil && (inc?.minutes ?? 99) <= 1)
    }

    @Test func peakIsMaxSeen() {
        var e = IncidentEngine()
        _ = run(&e, inputs(cpu: 97), from: 0, seconds: 62)
        #expect(run(&e, inputs(cpu: 88), from: 64, seconds: 10)?.peakPercent == 97)
    }

    @Test func memoryDiskHeatBattery() {
        var e = IncidentEngine()
        let mem = run(&e, inputs(pressure: .crit), from: 0, seconds: 32)
        #expect(mem?.kind == .memory && mem?.culpritIDs == ["docker", "next-web"] && mem?.culpritValues == ["+2,1", "+1,4"])
        var d = IncidentEngine()
        let disk = d.update(inputs(freeGB: 8), at: t0)
        #expect(disk?.kind == .disk && disk?.level == .crit && disk?.culpritUnit == "GB yazdı" && disk?.culpritValues.first == "12")
        var h = IncidentEngine()
        #expect(run(&h, inputs(thermal: .warn), from: 0, seconds: 32)?.kind == .heat)
        var b = IncidentEngine()
        let bat = b.update(inputs(drain: 25), at: t0)
        #expect(bat?.kind == .battery && bat?.level == .warn && bat?.peakPercent == 25)
        #expect(b.update(inputs(drain: 40), at: t0.addingTimeInterval(2))?.level == .crit)
    }

    @Test func tensGenitive() {
        #expect(TurkishSuffix.genitive(after: "90") == "'ın" && TurkishSuffix.genitive(after: "70") == "'in")
        #expect(TurkishSuffix.genitive(after: "80") == "'in" && TurkishSuffix.genitive(after: "60") == "'ın")
    }
}
