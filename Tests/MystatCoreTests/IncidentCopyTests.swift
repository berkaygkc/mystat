import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// Incident texts are generated from data: the sample data's sentences come from its facts (`Last 24 h`, `Remaining`) and stay the same;
/// if the live incident lacks that fact, no false claim is written.
@MainActor @Suite(.language("tr")) struct IncidentCopyTests {
    func sample(_ k: IncidentKind) -> Snapshot { SampleSource(seed: 1, incident: true, kind: k).snapshot }
    func lede(_ s: Snapshot) -> String { GroupPresentation.panelHeadline(s).lede }

    @Test func sampleLedesAreUnchanged() {
        #expect(lede(sample(.cpu)) == "acmecorp projesinde 4,2 çekirdek kullanıyor. Aynı projenin Next.js sunucusu da ona eşlik ediyor.")
        #expect(lede(sample(.disk)) == "Son 24 saatte 14 GB azaldı. En çok Docker yazıyor; Docker'da 12,6 GB geri kazanılabilir.")
        #expect(lede(sample(.heat)) == "Fanlar 4.800 dev/dk ile dönüyor. macOS henüz yavaşlatmaya başlamadı.")
        #expect(lede(sample(.battery)) == "Prizde değilsin; bu hızla 1 sa 10 dk yeter. En çok Claude Code harcıyor.")
        #expect(SectionText.system(sample(.battery)).lede == "Prizde değilsin; pil %62. Bu hızla 1 sa 10 dk yeter.")
    }

    /// A live-like state: no sensors and no Docker; the incident has only the engine's facts.
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
        #expect(lede(a).hasPrefix("acmecorp projesinde ") && !lede(a).contains("eşlik"))    // single culprit
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

    /// Overview: in live mode, if there is no related server the "accompanied by" claim is not written, and if memory/disk is troubled the "normal" claim is not written.
    @Test func overviewLedeFollowsData() {
        let a = live(.cpu, culprits: ["claude-acmecorp"], values: ["4,2"], unit: "çekirdek", cpu: 91)
        let cores = Fmt.dec1(a.groups.first { $0.id == "claude-acmecorp" }!.cpuCores)
        #expect(MonitorPresentation.overviewLede(a) == "acmecorp projesinde \(cores) çekirdek kullanıyor. Bellek, disk ve ağ normal.")
        var b = a
        b.memory.pressureLevel = .warn
        #expect(!MonitorPresentation.overviewLede(b).contains("normal"))
        var calm = SampleSource(seed: 1).snapshot
        calm.capabilities = SourceCapabilities(docker: false, sensors: false, diskScan: false, netDetails: false)
        #expect(!MonitorPresentation.overviewLede(calm).contains("Docker"))
    }

    @Test func panelCpuCellFollowsTotal() {
        let a = live(.cpu, culprits: ["claude-acmecorp"], values: ["4,2"], unit: "çekirdek", cpu: 76)
        #expect(PanelPresentation.cells(a)[0].sub == "9 dakikadır %70 üzerinde")
        let b = live(.cpu, culprits: ["claude-acmecorp"], values: ["4,2"], unit: "çekirdek", cpu: 40)
        #expect(PanelPresentation.cells(b)[0].sub == "9 dakikadır yoğun")
    }

    /// There is memory pressure but no group has grown noticeably in the last 10 minutes.
    @Test func memoryWithoutCulprit() {
        var s = live(.memory, culprits: [], values: [], unit: "GB")
        s.memory.swapGB = 2.5
        let h = GroupPresentation.panelHeadline(s)
        #expect(String(h.title.characters) == "Bellek baskısı yükseldi.")
        #expect(h.lede == "Swap 2,5 GB'a çıktı.")
        #expect(MonitorPresentation.incidentSentence(s) == "Bellek baskısı 9 dakikadır orta.")
    }

    /// A Docker incident's text depends on the cause: busy, restarting continuously, unhealthy.
    @Test func dockerCopyFollowsCause() {
        func snap(_ health: String, _ name: String, _ value: String, project: String, level: Level, others: [Container] = []) -> Snapshot {
            var s = SampleSource(seed: 1).snapshot
            s.docker.containers = others
            s.incident = Incident(kind: .docker, level: level, startedAt: "10:00", minutes: 3, peakPercent: 62, culpritIDs: [name],
                                  culpritValues: [value], culpritUnit: "CPU",
                                  facts: [Fact("Proje", project), Fact("Süre", "3 dk"), Fact("Sağlık", health)])
            return s
        }
        let busy = snap("sağlıklı", "verifier", "%62", project: "deploy", level: .warn,
                        others: [Container(name: "verifier", image: "i", cpuPercent: 62, memoryMB: 1, healthy: true, uptime: "", project: "deploy"),
                                 Container(name: "pg", image: "i", cpuPercent: 35, memoryMB: 1, healthy: true, uptime: "", project: "deploy")])
        #expect(GroupPresentation.panelHeadline(busy).lede == "deploy projesinde %62 CPU kullanıyor.")
        #expect(StatusBlockLayout.alert(busy) == StatusMetric(label: "DOCKER", value: "%62", level: .warn))

        let loop = snap("yeniden başlıyor", "authgate", "yeniden başlıyor", project: "infra", level: .crit)
        let h = GroupPresentation.panelHeadline(loop)
        #expect(String(h.title.characters) == "authgate sürekli yeniden başlıyor.")
        #expect(h.lede == "infra projesinde; Docker onu tekrar tekrar başlatıyor.")
        #expect(MonitorPresentation.incidentSentence(loop) == "authgate 3 dakikadır yeniden başlıyor.")
        #expect(StatusBlockLayout.alert(loop) == StatusMetric(label: "DOCKER", value: "hata", level: .crit))

        let sick = snap("sağlıksız", "api", "sağlıksız", project: "deploy", level: .crit)
        #expect(String(GroupPresentation.panelHeadline(sick).title.characters) == "api sağlıksız.")
        #expect(GroupPresentation.panelHeadline(sick).lede == "deploy projesinde; sağlık denetimi başarısız.")
        #expect(MonitorPresentation.incidentSentence(sick) == "api 3 dakikadır sağlıksız.")
    }

    /// "error" appears only for a critical Docker incident; at warning level a non-percentage value is shown as is.
    @Test func dockerAlertHataOnlyWhenCritical() {
        var s = SampleSource(seed: 1).snapshot
        s.incident = Incident(kind: .docker, level: .warn, startedAt: "10:00", minutes: 1, peakPercent: 0, culpritIDs: ["web"],
                              culpritValues: ["—"], culpritUnit: "CPU", facts: [])
        #expect(StatusBlockLayout.alert(s)?.value == "—")
    }
}
