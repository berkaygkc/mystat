import Foundation
import Testing
@testable import MystatCore

/// Docker eylemlerinin onay ve bildirim metinleri (§7.4); volume temizliği kullanıcının kararıyla iki ayrı eylem.
@MainActor @Suite struct DockerPresentationTests {
    let disk = SampleSource(seed: 1).snapshot.docker.disk

    @Test func confirmTexts() {
        let anon = DockerPresentation.confirm(.pruneAnonymousVolumes, disk: disk)
        #expect(anon.title == "Kullanılmayan adsız volume'ler temizlensin mi?" && anon.confirm == "Temizle" && !anon.destructive)
        #expect(anon.message == "Hiçbir container'a bağlı olmayan 116 adsız volume silinecek; 7,1 GB boşalacak. Adlı volume'lere ve çalışan container'lara dokunulmaz.")
        let all = DockerPresentation.confirm(.pruneAllVolumes, disk: disk)
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
}
