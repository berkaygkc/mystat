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
        #expect(s.snapshot.capabilities == SourceCapabilities(docker: false, sensors: false, diskScan: false, netDetails: false))
        #expect(s.snapshot.groups.isEmpty && s.snapshot.incident == nil)
        #expect(s.stop(groupID: "yok", force: false) == .notFound)
    }
}
