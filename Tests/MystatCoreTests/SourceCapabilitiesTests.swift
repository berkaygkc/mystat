import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// Fields the source can't measure show no fake numbers; they show calm "not connected" text.
@MainActor @Suite(.language("tr")) struct SourceCapabilitiesTests {
    func live() -> Snapshot {
        var s = SampleSource(seed: 1).snapshot
        s.capabilities = SourceCapabilities(docker: false, sensors: false, diskScan: false, netDetails: false)
        return s
    }

    @Test func sampleHasEverything() {
        #expect(SampleSource(seed: 1).snapshot.capabilities == .all)
    }

    @Test func panelCellsWithoutDockerAndSensors() {
        let cells = PanelPresentation.cells(live())
        let docker = cells.first { $0.section == "docker" }!, sys = cells.first { $0.section == "sys" }!
        #expect(docker.big == "—" && docker.sub == "bağlanmadı")
        #expect(sys.big == "Normal" && sys.sub == "pil %100")
    }

    @Test func dockerSectionSaysNotConnected() {
        let h = SectionText.docker(live())
        #expect(h.title == "Docker'a bağlanılmadı." && h.soft.isEmpty && h.level == .ok)
        #expect(h.lede == "Container'lar ve Docker'ın diski burada görünecek.")
    }

    @Test func sidebarValuesWithoutDockerAndSensors() {
        #expect(MonitorPresentation.navValue("docker", live()).text == "—")
        #expect(MonitorPresentation.navValue("sys", live()).text == "")
    }

    @Test func networkLedeWithoutWiFiDetails() {
        var s = live()
        s.net.iface = "en0"; s.net.ssid = ""
        #expect(SectionText.networkLede(s).hasPrefix("en0 arayüzü. Bugün"))
        #expect(!SectionText.networkLede(s).contains("indiriyor"))   // no network details: no "top downloader" sentence
    }
    /// With no sensor, temperature and fan counts are not invented; thermal state and battery are reported.
    @Test func systemTextWithoutSensors() {
        var s = live()
        let calm = SectionText.system(s)
        #expect(String(calm.title.characters) == "Serin ve sessiz.")
        #expect(calm.lede == "Termal durum normal. Prizdesin, pil %100.")
        s.system.thermal = .warn
        #expect(String(SectionText.system(s).title.characters) == "Çip ısınıyor.")
        #expect(!SectionText.system(s).lede.contains("°"))
    }

    /// With no scan, map items (Library, Docker's disk) are not described.
    @Test func diskTextWithoutScan() {
        let h = SectionText.disk(live(), home: nil, freedGB: 0)
        #expect(h.lede == "Sistem gerektiğinde 12 GB'ı kendiliğinden boşaltabilir.")
        #expect(h.title == "%62 dolu.")
    }
}
