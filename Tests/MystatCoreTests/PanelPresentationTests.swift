import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@MainActor @Suite(.language("tr")) struct PanelPresentationTests {
    @Test func calmCells() {
        let c = PanelPresentation.cells(SampleSource(seed: 1).snapshot)
        #expect(c.map(\.label) == ["İşlemci", "Bellek", "Disk", "Ağ", "Docker", "Sistem"])
        #expect(c[0].big == "%14"); #expect(c[0].sub == "14 çekirdek, sakin")
        #expect(c[1].sub == "37,6 / 48 GB, baskı düşük")
        #expect(c[2].sub == "175 GB boş")
        #expect(c[3].big == "14,6"); #expect(c[3].unit == "MB/s"); #expect(c[3].sub == "↑ 1,9 MB/s · Wi‑Fi")
        #expect(c[4].big == "15"); #expect(c[4].sub == "container · <0,1 çekirdek")
        #expect(c[5].big == "48°"); #expect(c[5].sub == "Fan sessiz, pil %100")
        #expect(c.allSatisfy { $0.level == .ok })
    }
    @Test func incidentCells() {
        let c = PanelPresentation.cells(SampleSource(seed: 1, incident: true).snapshot)
        #expect(c[0].level == .crit); #expect(c[0].sub == "4 dakikadır %90 üzerinde")
        #expect(c[5].level == .warn); #expect(c[5].sub == "Fan 4.800 dev/dk, ısınıyor")
        #expect(PanelPresentation.cells(SampleSource(seed: 1, incident: true, kind: .battery).snapshot)[5].sub == "Pil %62, prizde değil")
    }
    @Test func culpritRows() {
        let r = PanelPresentation.culprits(SampleSource(seed: 1, incident: true).snapshot)
        #expect(r.map(\.name) == ["Claude Code", "Next.js dev", "Docker"])
        #expect(r[1].context == "acmecorp/web · :3011"); #expect(r[0].value == "4,2"); #expect(r[0].unit == "çekirdek")
        let d = PanelPresentation.culprits(SampleSource(seed: 1, incident: true, kind: .docker).snapshot)
        #expect(d.first?.name == "acmecorp-verifier"); #expect(d.first?.context == "deploy"); #expect(d.first?.groupID == "docker")
    }
}
