import MystatCore
import MystatTestSupport
import Testing
@testable import MystatUI

/// Sorumluya tıklamak olayın kendi bölümüne gider (spec §7.2.1 "Detay hedefi"), hep İşlemci'ye değil.
@MainActor @Suite(.language("tr")) struct MonitorNavigationTests {
    @Test func culpritOpensTheIncidentsSection() {
        let s = MonitorState()
        s.show(.mem, group: "docker")
        #expect(s.section == .mem && s.selected[.memory] == "docker")
        s.show(.disk, group: "docker")
        #expect(s.section == .disk)
        s.show(.docker, group: "acmecorp-verifier")
        #expect(s.section == .docker)
        s.show(.sys, group: "claude-acmecorp")
        #expect(s.section == .sys)
        s.show(.cpu, group: "next-web")
        #expect(s.section == .cpu && s.selected[.cpu] == "next-web" && s.expanded.contains("next-web"))
        s.show(.net, group: "docker")
        #expect(s.section == .net && s.selected[.network] == "docker")
    }

    @Test func sectionWithoutGroupJustNavigates() {
        let s = MonitorState()
        s.show(.docker, group: nil)
        #expect(s.section == .docker)
    }
}
