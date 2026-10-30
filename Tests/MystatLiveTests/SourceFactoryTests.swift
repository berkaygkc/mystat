import MystatCore
import MystatTestSupport
import Testing
@testable import MystatLive

/// The default live source; `--sample` enables the sample data.
@MainActor @Suite(.language("tr")) struct SourceFactoryTests {
    @Test func sampleFlagSelectsSampleSource() {
        #expect(SourceFactory.make(arguments: ["mystat", "--sample"]) is SampleSource)
        #expect(SourceFactory.make(arguments: ["mystat"]) is LiveSource)
    }

    @Test func liveSourceDoesNotPretend() {
        let s = SourceFactory.make(arguments: ["mystat"])
        #expect(s.snapshot.capabilities == SourceCapabilities(docker: true, sensors: false, diskScan: true, netDetails: true))   // Docker, disk scan and network details are wired up
        #expect(!s.snapshot.docker.running)                       // calm before the first read
        #expect(s.snapshot.groups.isEmpty && s.snapshot.incident == nil)
        #expect(s.stop(groupID: "yok", pids: [], force: false) == .notFound)
    }
}
