import Foundation
import Testing
@testable import MystatCore

/// Olay metinleri veriden üretilir: örnek verinin cümleleri olgularından (`Son 24 sa`, `Kalan`) gelir ve aynı kalır;
/// canlı olayda o olgu yoksa sahte iddia yazılmaz.
@MainActor @Suite struct IncidentCopyTests {
    func sample(_ k: IncidentKind) -> Snapshot { SampleSource(seed: 1, incident: true, kind: k).snapshot }
    func lede(_ s: Snapshot) -> String { GroupPresentation.panelHeadline(s).lede }

    @Test func sampleLedesAreUnchanged() {
        #expect(lede(sample(.cpu)) == "acmecorp projesinde 4,2 çekirdek kullanıyor. Aynı projenin Next.js sunucusu da ona eşlik ediyor.")
        #expect(lede(sample(.disk)) == "Son 24 saatte 14 GB azaldı. En çok Docker yazıyor; Docker'da 12,6 GB geri kazanılabilir.")
        #expect(lede(sample(.heat)) == "Fanlar 4.800 dev/dk ile dönüyor. macOS henüz yavaşlatmaya başlamadı.")
        #expect(lede(sample(.battery)) == "Prizde değilsin; bu hızla 1 sa 10 dk yeter. En çok Claude Code harcıyor.")
        #expect(SectionText.system(sample(.battery)).lede == "Prizde değilsin; pil %62. Bu hızla 1 sa 10 dk yeter.")
    }

    /// Canlıya benzeyen durum: sensör ve Docker yok, olayda yalnızca motorun olguları var.
    func live(_ k: IncidentKind, culprits: [String], values: [String], unit: String, cpu: Double = 91, thermal: Level = .ok) -> Snapshot {
        var s = SampleSource(seed: 1).snapshot
        s.capabilities = SourceCapabilities(docker: false, sensors: false, diskScan: false, netDetails: false)
        s.cpu.percent = cpu
        s.system.thermal = thermal
        s.incident = Incident(kind: k, level: .warn, startedAt: "08:41", minutes: 9, peakPercent: 25, culpritIDs: culprits,
                              culpritValues: values, culpritUnit: unit, facts: [])
        return s
    }

    @Test func cpuSentenceFollowsTotalOrGroup() {
        let a = live(.cpu, culprits: ["claude-acmecorp"], values: ["4,2"], unit: "çekirdek", cpu: 76)
        #expect(MonitorPresentation.incidentSentence(a) == "İşlemci 9 dakikadır %70'in üzerinde. Yükün çoğu acmecorp projesinden geliyor.")
        #expect(lede(a).hasPrefix("acmecorp projesinde ") && !lede(a).contains("eşlik"))    // tek sorumlu
        let b = live(.cpu, culprits: ["claude-acmecorp"], values: ["4,2"], unit: "çekirdek", cpu: 40)
        let cores = Fmt.dec1(b.groups.first { $0.id == "claude-acmecorp" }!.cpuCores)
        #expect(MonitorPresentation.incidentSentence(b) == "Claude Code 9 dakikadır \(cores) çekirdek kullanıyor.")
    }

    @Test func appLeadHasNoProjectPhrase() {
        let s = live(.cpu, culprits: ["brave"], values: ["0,9"], unit: "çekirdek")
        let brave = s.groups.first { $0.id == "brave" }!
        #expect(lede(s) == "Brave Browser \(Fmt.dec1(brave.cpuCores)) çekirdek kullanıyor.")
        #expect(MonitorPresentation.incidentSentence(s).hasSuffix("En çok Brave Browser yüklüyor."))
    }

    @Test func diskWithoutHistoryOrDocker() {
        let s = live(.disk, culprits: ["docker"], values: ["12"], unit: "GB yazdı")
        #expect(MonitorPresentation.incidentSentence(s) == "Diskte \(Fmt.int(s.disk.freeGB)) GB kaldı.")
        #expect(lede(s) == "En çok Docker yazıyor.")
    }

    @Test func heatWithoutSensors() {
        let s = live(.heat, culprits: [], values: [], unit: "çekirdek", thermal: .warn)
        #expect(MonitorPresentation.incidentSentence(s) == "Çip 9 dakikadır ısınıyor; termal durum ılık.")
        #expect(lede(s) == "macOS henüz yavaşlatmaya başlamadı.")
        #expect(lede(live(.heat, culprits: [], values: [], unit: "çekirdek", thermal: .crit)) == "macOS işlemciyi yavaşlatıyor.")
    }

    @Test func batteryWithoutRemaining() {
        var s = live(.battery, culprits: ["claude-acmecorp"], values: ["1,2"], unit: "çekirdek")
        s.system.batteryDrain30m = 25
        #expect(MonitorPresentation.incidentSentence(s) == "Pil 9 dakikada %25 eridi.")
        #expect(lede(s) == "Prizde değilsin. En çok Claude Code harcıyor.")
        #expect(SectionText.system(s).lede == "Prizde değilsin; pil %\(s.system.battery).")
    }
}
