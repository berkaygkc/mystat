import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// Confirmation and notification texts for Docker actions; volume cleanup is two separate actions so the user decides about volumes separately.
@MainActor @Suite(.language("tr")) struct DockerPresentationTests {
    let disk = SampleSource(seed: 1).snapshot.docker.disk

    @Test func confirmTexts() {
        let anon = DockerPresentation.confirm(.pruneAnonymousVolumes, disk: disk)
        #expect(anon.title == "Kullanılmayan adsız volume'ler temizlensin mi?" && anon.confirm == "Temizle" && !anon.destructive)
        #expect(anon.message == "Hiçbir container'a bağlı olmayan 116 adsız volume silinecek; 7,1 GB boşalacak. Adlı volume'lere ve çalışan container'lara dokunulmaz.")
        let all = DockerPresentation.confirm(.pruneNamedVolumes, disk: disk)
        #expect(all.title == "Adlı volume'ler de silinsin mi?" && all.confirm == "Adlıları da sil" && all.destructive)
        #expect(all.message == "Hiçbir container'a bağlı olmayan 61 adlı volume silinecek; 5,5 GB boşalacak. Durdurulmuş compose projelerinin veritabanı verileri bunların içinde olabilir; geri alınamaz.")
        let img = DockerPresentation.confirm(.pruneImages, disk: disk)
        #expect(img.title == "Kullanılmayan image'lar temizlensin mi?")
        #expect(img.message == "Hiçbir container'ın kullanmadığı 4 image silinecek; 2,8 GB boşalacak. Çalışan container'lar etkilenmez.")
        let r = DockerPresentation.confirm(.restart(id: "a", name: "verifier"), disk: disk)
        #expect(r.title == "verifier yeniden başlatılsın mı?" && r.message == "Container kısa bir süre kapanıp yeniden açılacak." && r.confirm == "Yeniden başlat")
        let st = DockerPresentation.confirm(.stop(id: "a", name: "verifier"), disk: disk)
        #expect(st.title == "verifier durdurulsun mu?" && st.confirm == "Durdur" && st.destructive)
        #expect(st.message == "Container durdurulacak; Docker Desktop'tan ya da compose ile yeniden başlatılabilir.")
    }

    @Test func dockerToasts() {
        #expect(DockerPresentation.toast(.restart(id: "a", name: "verifier"), .done(reclaimedGB: nil)) == "verifier yeniden başlatıldı")
        #expect(DockerPresentation.toast(.stop(id: "a", name: "verifier"), .done(reclaimedGB: nil)) == "verifier durduruldu")
        #expect(DockerPresentation.toast(.pruneImages, .done(reclaimedGB: 12.63)) == "12,6 GB temizlendi")
        #expect(DockerPresentation.toast(.pruneAnonymousVolumes, .done(reclaimedGB: 0)) == "Temizlenecek bir şey kalmamış")
        #expect(DockerPresentation.toast(.pruneImages, .failed("Docker çalışmıyor")) == "Docker çalışmıyor")
        #expect(DockerPresentation.progress(.pruneImages) == "Temizleniyor…" && DockerPresentation.progress(.restart(id: "a", name: "x")) == "Yeniden başlatılıyor…")
    }

    func c(_ name: String, _ project: String, cpu: Double, restarting: Bool = false, healthy: Bool = true) -> Container {
        Container(name: name, image: "i", cpuPercent: cpu, memoryMB: 512, healthy: healthy, uptime: "2 gün", project: project,
                  dockerID: name, restarting: restarting)
    }

    @Test func sampleProjectsArePinned() {
        let rows = DockerPresentation.projects(SampleSource(seed: 1).snapshot.docker)
        #expect(rows.map(\.name) == ["deploy"] && rows[0].summary == "15 container · hepsi çalışıyor" && !rows[0].troubled)
    }

    /// The problem project comes first, then by CPU; projectless ones go under "other containers"; containers are sorted by CPU descending.
    @Test func projectsGroupAndOrder() {
        var d = SampleSource(seed: 1).snapshot.docker
        d.containers = [c("pg", "deploy", cpu: 4), c("web", "deploy", cpu: 30), c("authgate", "initech", cpu: 0, restarting: true),
                        c("lane-pg", "", cpu: 50)]
        let rows = DockerPresentation.projects(d)
        #expect(rows.map(\.name) == ["initech", "diğer container'lar", "deploy"])
        #expect(rows[0].summary == "1 container · 1 sorunlu" && rows[0].troubled)
        #expect(rows[2].containers.map(\.name) == ["web", "pg"] && rows[2].cpuPercent == 34 && rows[2].memoryGB == 1)
        #expect(rows[2].summary == "2 container · hepsi çalışıyor")
    }

    @Test func diskNoteFormats() {
        var d = SampleSource(seed: 1).snapshot.docker
        #expect(DockerPresentation.diskNote(d) == "27 GB · son 30 gün +9 GB")
        d.trend30GB = nil
        #expect(DockerPresentation.diskNote(d) == "27 GB")
        d.disk.rawGB = nil
        d.trend30GB = -3
        #expect(DockerPresentation.diskNote(d) == "27 GB · son 30 gün −3 GB")          // data total is 27.0 GB
    }
}
