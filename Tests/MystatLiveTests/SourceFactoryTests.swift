import MystatCore
import Testing
@testable import MystatLive

/// Varsayılan canlı kaynak; `--sample` Faz 1'in örnek verisini açar (spec §3).
@MainActor @Suite struct SourceFactoryTests {
    @Test func sampleFlagSelectsSampleSource() {
        #expect(SourceFactory.make(arguments: ["mystat", "--sample"]) is SampleSource)
        #expect(SourceFactory.make(arguments: ["mystat"]) is LiveSource)
    }

    @Test func liveSourceDoesNotPretend() {
        let s = SourceFactory.make(arguments: ["mystat"])
        #expect(s.snapshot.capabilities == SourceCapabilities(docker: true, sensors: false, diskScan: true, netDetails: true))   // 2b: Docker, 2d: disk taraması, 2e: ağ ayrıntıları
        #expect(!s.snapshot.docker.running)                       // ilk okumadan önce sakin
        #expect(s.snapshot.groups.isEmpty && s.snapshot.incident == nil)
        #expect(s.stop(groupID: "yok", pids: [], force: false) == .notFound)
    }
}
