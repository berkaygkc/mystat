import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// Docker metinleri: örnek verinin cümleleri aynı kalır (karakterizasyon); Docker çalışmıyorsa sakin durum.
@MainActor @Suite(.language("tr")) struct DockerCopyTests {
    var calm: Snapshot { SampleSource(seed: 1).snapshot }
    var busy: Snapshot { SampleSource(seed: 1, incident: true, kind: .docker).snapshot }

    @Test func sampleDockerCopyUnchanged() {
        let h = SectionText.docker(calm)
        #expect(h.title == "15 container ayakta," && h.soft == "hepsi sakin.")
        #expect(h.lede == "Container'lar toplam %4 CPU ve 2,5 GB bellek kullanıyor. Docker'ın diski 27 GB; 12,6 GB'ı geri kazanılabilir.")
        let hi = SectionText.docker(busy)
        #expect(hi.lede == "acmecorp-verifier tek başına %62 CPU kullanıyor; container'ların toplamı %65. Docker'ın diski 27 GB, 12,6 GB'ı geri kazanılabilir.")
        let c = PanelPresentation.cells(calm).first { $0.section == "docker" }!
        #expect(c.big == "15" && c.sub == "container · <0,1 çekirdek")
        let ph = GroupPresentation.panelHeadline(busy)
        #expect(String(ph.title.characters) == "acmecorp-verifier 6 dakikadır yoğun.")
        #expect(ph.lede == "deploy projesinde %62 CPU kullanıyor. Diğer container'lar sakin.")
        #expect(PanelPresentation.culprits(busy).first?.context == "deploy")
        #expect(MonitorPresentation.overviewLede(calm) == "Makine rahat. En yoğun uygulama Brave Browser, Docker 15 container ile sessizce ayakta. Diskte 175 GB boş yer var.")
        #expect(MonitorPresentation.incidentSentence(busy) == "acmecorp-verifier 6 dakikadır %62 CPU kullanıyor.")
    }

    @Test func dockerNotRunningIsCalm() {
        var s = calm
        s.docker.running = false
        s.docker.containers = []
        let h = SectionText.docker(s)
        #expect(h.title == "Docker çalışmıyor." && h.level == .ok)
        #expect(h.lede == "Docker Desktop açılınca container'lar ve Docker'ın diski burada görünür.")
        let c = PanelPresentation.cells(s).first { $0.section == "docker" }!
        #expect(c.big == "—" && c.sub == "çalışmıyor" && c.level == .ok)
        #expect(!MonitorPresentation.overviewLede(s).contains("Docker"))
        #expect(MonitorPresentation.navValue("docker", s).text == "—")
    }

    /// Sanal disk dosyası okunamazsa Docker'ın verisi (image + volume + build cache + container) söylenir.
    @Test func unreadableRawFileUsesDataTotal() {
        var s = calm
        s.docker.disk.rawGB = nil
        #expect(SectionText.docker(s).lede.hasSuffix("Docker'ın verisi 27,0 GB; 12,6 GB'ı geri kazanılabilir."))
    }

    /// Disk dolu olayı Docker kapalıyken "Docker'da 0,0 GB geri kazanılabilir" demez.
    @Test func diskIncidentSkipsDockerWhenDown() {
        var s = SampleSource(seed: 1, incident: true, kind: .disk).snapshot
        #expect(GroupPresentation.panelHeadline(s).lede.contains("Docker'da 12,6 GB geri kazanılabilir"))
        s.docker = .notRunning
        #expect(!GroupPresentation.panelHeadline(s).lede.contains("Docker'da"))
    }
}
