import MystatCore
import MystatTestSupport
import Testing
@testable import MystatUI

@MainActor @Suite(.language("tr")) struct ActionCopyTests {
    @Test func stopTexts() {
        let src = SampleSource(seed: 1)
        let g = src.snapshot.groups.first { $0.id == "next-web" }!
        let soft = Actions.stop(g, force: false, source: src), hard = Actions.stop(g, force: true, source: src)
        #expect(soft.title == "Next.js dev · acmecorp/web · :3011 durdurulsun mu?")
        #expect(soft.message == "3 süreç kapanması için uyarılacak. Cevap vermezse zorla kapatmayı seçebilirsin.")
        #expect(hard.title.hasSuffix("zorla kapatılsın mı?")); #expect(hard.destructive); #expect(hard.confirm == "Zorla kapat")
    }
    /// The toast reports the real outcome: closed, permission denied, or already closed.
    @Test func stopToastFollowsOutcome() {
        let src = SampleSource(seed: 1)
        let g = src.snapshot.groups.first { $0.id == "next-web" }!
        #expect(Actions.stopToast(g, force: false, .done(count: 3)) == "Next.js dev durduruldu")
        #expect(Actions.stopToast(g, force: true, .done(count: 3)) == "Next.js dev zorla kapatıldı")
        #expect(Actions.stopToast(g, force: false, .notPermitted(reason: StopOutcome.foreignReason)) == StopOutcome.foreignReason)
        #expect(Actions.stopToast(g, force: false, .notFound) == "Next.js dev zaten kapanmış")
        Actions.stop(g, force: false, source: src).onConfirm()
        #expect(ToastCenter.shared.message == "Next.js dev durduruldu")
    }
    @Test func pruneTexts() {
        let src = SampleSource(seed: 1)
        let v = DockerActions.request(.pruneAnonymousVolumes, disk: src.snapshot.docker.disk, source: src)
        #expect(v.title == "Kullanılmayan adsız volume'ler temizlensin mi?" && !v.destructive)   // named data volumes of stopped projects get their own button, so there are two separate volume buttons
        #expect(DockerActions.request(.pruneNamedVolumes, disk: src.snapshot.docker.disk, source: src).destructive)
    }
    @Test func copyDiagnosisShowsToast() {
        let state = MonitorState()
        state.copyDiagnosis("deneme")
        #expect(ToastCenter.shared.message == "Teşhis panoya kopyalandı")
    }
}
