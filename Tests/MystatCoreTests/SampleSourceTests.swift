import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

@MainActor @Suite(.language("tr")) struct SampleSourceTests {
    @Test func calmVsIncident() {
        let calm = SampleSource(seed: 7); let hot = SampleSource(seed: 7, incident: true)
        #expect(calm.snapshot.incident == nil); #expect(calm.snapshot.cpu.percent < 30)
        #expect(hot.snapshot.cpu.percent >= 85)
        #expect(hot.snapshot.incident?.culpritIDs.prefix(2) == ["claude-acmecorp", "next-web"])
    }
    @Test func seriesShape() {
        let s = SampleSource(seed: 7, incident: true)
        for r in TimeRange.allCases { #expect(s.series(.cpu, range: r).count == r.pointCount) }
        #expect(s.series(.cpu, range: .m10).suffix(10).allSatisfy { $0 >= 80 })
        #expect(s.series(.cpu, range: .m10) == SampleSource(seed: 7, incident: true).series(.cpu, range: .m10))
    }
    @Test func groupsAndContainers() {
        let s = SampleSource(seed: 1)
        #expect(s.snapshot.groups.count == 9); #expect(s.snapshot.docker.containers.count == 15)
        #expect(s.snapshot.groups.first { $0.id == "next-web" }?.isOrphan == true)
    }
    @Test func mulberryMatchesJavaScript() {
        // mockup'taki rng(1) ilk değeri: Node ile hesaplandı
        var r = Mulberry32(seed: 1)
        #expect(abs(r.next() - 0.6270739405881613) < 1e-12)
    }
    @Test func incidentKinds() {
        for k in IncidentKind.allCases {
            let s = SampleSource(seed: 1, incident: true, kind: k)
            #expect(s.snapshot.incident?.kind == k)
            #expect(s.snapshot.incident?.culpritIDs.count == s.snapshot.incident?.culpritValues.count)
        }
        #expect(SampleSource(seed: 1, incident: true, kind: .disk).snapshot.disk.freeGB == 8)
    }

    /// Örnekte de WindowServer sistemin süreci: durdurulamaz, diğerleri durdurulur (spec §7.4).
    @Test func systemGroupIsNotStoppable() {
        let s = SampleSource(seed: 1)
        #expect(s.snapshot.groups.filter(\.foreign).map(\.id) == ["windowserver"])
        #expect(s.stop(groupID: "windowserver", pids: [], force: false) == .notPermitted(reason: StopOutcome.foreignReason))
        #expect(s.stop(groupID: "next-web", pids: [], force: false) == .done(count: 3))
    }
}
