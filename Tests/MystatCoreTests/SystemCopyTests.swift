import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// System texts come from data: the sample data's sentences stay the same; in live mode fan, power and GPU come from real values.
@MainActor @Suite(.language("tr")) struct SystemCopyTests {
    var calm: Snapshot { SampleSource(seed: 1).snapshot }
    var heat: Snapshot { SampleSource(seed: 1, incident: true, kind: .heat).snapshot }

    @Test func sampleSystemCopyUnchanged() {
        let c = SectionText.system(calm), h = SectionText.system(heat)
        #expect(String(c.title.characters) == "Serin ve sessiz." && c.lede == "Çip 48°, fanlar duruyor. Prizdesin, pil tam dolu ve sağlığı iyi.")
        #expect(String(h.title.characters) == "Çip ısınıyor: 91°")
        #expect(h.lede == "Fanlar 4.800 dev/dk ile dönüyor. macOS henüz yavaşlatmaya başlamadı; yük sürerse başlayabilir. Prizdesin, pil tam dolu.")
        #expect(PanelPresentation.cells(calm).first { $0.section == "sys" }?.sub == "Fan sessiz, pil %100")
        #expect(PanelPresentation.cells(heat).first { $0.section == "sys" }?.sub == "Fan 4.800 dev/dk, ısınıyor")
        let energy = SystemPresentation.energyTop(calm.groups, n: 5).map { "\($0.name)=\(Fmt.dec1($0.watts)) W" }
        #expect(energy == ["Brave Browser=2,2 W", "Claude Code=1,7 W", "WindowServer=1,1 W", "Claude Code=0,7 W", "Next.js dev=0,6 W"])
        #expect(SystemPresentation.gpuFacts(calm.system).map { "\($0.0)=\($0.1)" }
                == ["En çok kullanan=WindowServer", "İkinci=Brave Browser", "Bellek=Paylaşımlı", "Ekranlar=2"])
    }

    @Test func fanTextCases() {
        var s = calm.system
        s.fanCount = 0
        #expect(SystemPresentation.fanText(s) == "fan yok")
        s.fanCount = 2; s.fanRPM = 0
        #expect(SystemPresentation.fanText(s) == "duruyor")
        s.fanRPM = 1356; s.fanMinRPM = 1350
        #expect(SystemPresentation.fanText(s) == "sessiz")
        s.fanRPM = 1471                                               // the idle second fan on this machine (minimum 1,350)
        #expect(SystemPresentation.fanText(s) == "sessiz")
        s.fanRPM = 1600
        #expect(SystemPresentation.fanText(s) == "1.600 dev/dk")
        s.fanRPM = 4800
        #expect(SystemPresentation.fanText(s) == "4.800 dev/dk")
    }

    @Test func energyTopSkipsSystemRow() {
        var gs = calm.groups
        gs.append(ProcessGroup(id: "sys:macos", name: "macOS", context: "sistem süreçleri", cpuCores: 3, memoryGB: 9, netMBps: 0, uptime: "",
                               processCount: 700, folder: nil, terminal: nil, port: nil, isOrphan: false, relatedID: nil, isDocker: false,
                               children: [], watts: 40))
        for i in gs.indices where gs[i].name == "Spark" { gs[i].watts = 0 }
        let top = SystemPresentation.energyTop(gs, n: 20)
        #expect(!top.contains { $0.id == "sys:macos" } && !top.contains { $0.watts == 0 })
        #expect(top.map(\.watts) == top.map(\.watts).sorted(by: >))
    }

    /// When warming up, the power phrase reflects the real state: on battery it never says "you are plugged in".
    @Test func heatLedeUsesRealPower() {
        var s = heat
        s.system.onAC = false
        s.system.charging = false
        s.system.battery = 62
        #expect(SectionText.system(s).lede.hasSuffix("Pildesin, pil %62."))
        s.system.fanCount = 0
        #expect(!SectionText.system(s).lede.contains("Fanlar"))
    }

    @Test func gpuPillLevels() {
        var s = calm.system
        s.gpuPercent = 28
        #expect(SystemPresentation.gpuPill(s) == ("Sakin", .ok))
        s.gpuPercent = 82
        #expect(SystemPresentation.gpuPill(s) == ("Yoğun", .warn))
    }

    /// "Top energy users · last 10 min": a group's watts are the average over the 10-minute window.
    @Test func energyListUsesTenMinuteAverage() {
        var h = GroupHistory()
        var g = calm.groups[0]
        let t0 = Date(timeIntervalSince1970: 1_793_163_600)
        g.watts = 2
        h.add([g], writtenBytes: [:], at: t0)
        g.watts = 4
        h.add([g], writtenBytes: [:], at: t0.addingTimeInterval(5))
        #expect(h.wattsAverage()[g.id] == 3)
        #expect(SystemPresentation.wattsText(g) == "4,0 W")
    }

    /// The idle second fan sits just above the minimum speed: the panel does not flip between "Fan quiet" and "Fan 1,467 rpm".
    @Test func panelFanQuietNearMinimum() {
        var s = calm
        s.system.fanRPM = 1471; s.system.fanMinRPM = 1350
        #expect(PanelPresentation.cells(s).first { $0.section == "sys" }?.sub == "Fan sessiz, pil %100")
    }

    /// In a critical thermal state the card does not contradict itself (it does not say "Warm" / "Not yet").
    @Test func heatCardFollowsThermal() {
        var s = calm.system
        s.thermal = .crit
        #expect(SystemPresentation.heatPill(s) == ("Sıcak", .crit) && SystemPresentation.slowdown(s) == "Var")
        s.thermal = .warn
        #expect(SystemPresentation.heatPill(s) == ("Ilık", .warn) && SystemPresentation.slowdown(s) == "Henüz yok")
        s.thermal = .ok
        #expect(SystemPresentation.heatPill(s) == ("Normal", .ok) && SystemPresentation.slowdown(s) == "Yok")
    }

    /// A fanless Mac (or a fan that reads 0): "Fans spinning at 0 rpm" / "fan fan none" must not be written.
    @Test func fanlessWording() {
        var s = heat
        s.system.fanCount = 0; s.system.fanRPM = 0
        #expect(!GroupPresentation.panelHeadline(s).lede.contains("Fanlar"))
        #expect(!MonitorPresentation.incidentSentence(s).contains("fanlar"))
        #expect(SystemPresentation.heatLabel(s.system) == "Çip ortalaması · fansız")
        #expect(SystemPresentation.heatLabel(calm.system) == "Çip ortalaması · fan duruyor")
        s.system.fanCount = 2
        #expect(PanelPresentation.cells(s).first { $0.section == "sys" }?.sub.contains("0 dev/dk") == false)
    }

    /// The power card states the charging status.
    @Test func powerLabelShowsCharging() {
        var s = calm.system
        #expect(SystemPresentation.powerLabel(s, sensors: true) == "Tam dolu · şu an 14 W harcanıyor")
        s.battery = 80; s.charging = true; s.watts = 30
        #expect(SystemPresentation.powerLabel(s, sensors: true) == "Şarj oluyor · şu an 30 W harcanıyor")
        s.onAC = false; s.charging = false
        #expect(SystemPresentation.powerLabel(s, sensors: true) == "Pil · şu an 30 W harcanıyor")
        #expect(SystemPresentation.powerLabel(s, sensors: false) == "Pil")
    }
}
