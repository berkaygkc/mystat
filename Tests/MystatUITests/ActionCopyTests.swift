import MystatCore
import Testing
@testable import MystatUI

@MainActor @Suite struct ActionCopyTests {
    @Test func stopTexts() {
        let g = SampleSource(seed: 1).snapshot.groups.first { $0.id == "next-web" }!
        let soft = Actions.stop(g, force: false), hard = Actions.stop(g, force: true)
        #expect(soft.title == "Next.js dev · acmecorp/web · :3011 durdurulsun mu?")
        #expect(soft.message == "3 süreç kapanması için uyarılacak. Cevap vermezse zorla kapatmayı seçebilirsin.")
        #expect(hard.title.hasSuffix("zorla kapatılsın mı?")); #expect(hard.destructive); #expect(hard.confirm == "Zorla kapat")
    }
    @Test func pruneTexts() {
        let v = DockerActions.prune(volumes: true, gb: 12.6)
        #expect(v.title == "Kullanılmayan volume'ler temizlensin mi?")
        #expect(v.message == "Hiçbir container'a bağlı olmayan 177 volume silinecek; 12,6 GB boşalacak. Çalışan container'lar etkilenmez.")
    }
    @Test func copyDiagnosisShowsToast() {
        let state = MonitorState()
        state.copyDiagnosis("deneme")
        #expect(ToastCenter.shared.message == "Teşhis panoya kopyalandı")
    }
}
