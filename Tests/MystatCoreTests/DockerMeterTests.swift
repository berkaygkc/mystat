import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// Engine API ham değerlerinden container CPU'su, bellek, durum ve Docker'ın diski (`docker stats` / `docker system df` tanımları).
@Suite(.language("tr")) struct DockerMeterTests {
    func raw(_ id: String, name: String = "/deploy-web-1", state: String = "running", status: String = "Up 2 days",
             project: String? = nil, service: String? = nil) -> DockerContainerRaw {
        DockerContainerRaw(id: id, name: name, image: "nginx:1.27", state: state, status: status, project: project, service: service)
    }
    func stats(_ id: String, cpu: UInt64, system: UInt64, usage: UInt64 = 0, inactive: UInt64 = 0) -> DockerStatsRaw {
        DockerStatsRaw(id: id, cpuTotal: cpu, systemTotal: system, onlineCPUs: 14, memUsage: usage, memInactiveFile: inactive)
    }

    @Test func cpuFromDeltas() {
        var m = DockerMeter()
        #expect(m.containers([raw("a")], stats: [stats("a", cpu: 5_000_000_000, system: 100_000_000_000)]).first?.cpuPercent == 0)
        let c = m.containers([raw("a")], stats: [stats("a", cpu: 6_000_000_000, system: 114_000_000_000)])
        #expect(c.first.map { abs($0.cpuPercent - 100) < 1e-9 } == true)
    }

    @Test func counterGoingBackIsZero() {
        var m = DockerMeter()
        _ = m.containers([raw("a")], stats: [stats("a", cpu: 6_000_000_000, system: 100_000_000_000)])
        #expect(m.containers([raw("a")], stats: [stats("a", cpu: 5_000_000_000, system: 114_000_000_000)]).first?.cpuPercent == 0)
    }

    @Test func recreatedContainerStartsFresh() {
        var m = DockerMeter()
        _ = m.containers([raw("old")], stats: [stats("old", cpu: 1_000_000_000, system: 100_000_000_000)])
        let c = m.containers([raw("new")], stats: [stats("new", cpu: 9_000_000_000, system: 114_000_000_000)])
        #expect(c.count == 1 && c[0].dockerID == "new" && c[0].cpuPercent == 0)
    }

    @Test func memoryExcludesInactiveFile() {
        var m = DockerMeter()
        let c = m.containers([raw("a")], stats: [stats("a", cpu: 0, system: 0, usage: 30_474_240, inactive: 110_592)])
        #expect(c.first.map { abs($0.memoryMB - 28.957) < 0.001 } == true)
    }

    @Test func composeNameAndState() {
        var m = DockerMeter()
        let list = [raw("a", name: "/deploy-acmecorp-verifier-1", status: "Up 2 days (healthy)", project: "deploy", service: "acmecorp-verifier"),
                    raw("b", name: "/authgate", state: "restarting", status: "Restarting (1) 5 seconds ago"),
                    raw("c", name: "/api", status: "Up 3 hours (unhealthy)")]
        let c = m.containers(list, stats: [])
        #expect(c[0].name == "acmecorp-verifier" && c[0].project == "deploy" && c[0].healthy && c[0].uptime == Fmt.uptime(2 * 86_400))
        #expect(c[1].name == "authgate" && c[1].project == "" && c[1].restarting)
        #expect(!c[2].healthy && c[2].uptime == Fmt.uptime(3 * 3600))
        #expect(c.allSatisfy { $0.cpuPercent == 0 && $0.memoryMB == 0 })            // stats gelmedi
        #expect(DockerMeter.uptime(status: "Up About an hour") == Fmt.uptime(3600))
        #expect(DockerMeter.uptime(status: "Up Less than a second") == Fmt.uptime(0))
        #expect(DockerMeter.uptime(status: "Up 3 weeks") == Fmt.uptime(21 * 86_400))
    }

    @Test func diskMatchesDockerCLI() {
        let df = DockerDFRaw(layersSize: 8_764_000_000,
                             images: [.init(size: 1_887_000_000, shared: 0, containers: 1), .init(size: 500_000_000, shared: 100_000_000, containers: 2),
                                      .init(size: 300_000_000, shared: 0, containers: 0)],
                             volumes: [.init(size: 7_050_000_000, refCount: 0, anonymous: true), .init(size: 5_580_000_000, refCount: 0, anonymous: false),
                                       .init(size: 4_780_000_000, refCount: 1, anonymous: false)],
                             buildCache: [.init(size: 200, inUse: true, shared: false), .init(size: 300, inUse: false, shared: false),
                                          .init(size: 400, inUse: false, shared: true)],
                             containersRw: 1_716_000)
        let d = DockerMeter.disk(df, rawGB: 29.9)
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        #expect(near(d.imagesGB, 8.764) && near(d.imagesReclaimGB, 6.477) && d.imagesCount == 3 && d.imagesUnusedCount == 1)
        #expect(near(d.volumesGB, 17.41) && near(d.volumesReclaimGB, 12.63) && d.volumesCount == 3 && d.volumesUnusedCount == 2)
        #expect(near(d.volumesAnonReclaimGB, 7.05) && d.volumesAnonUnusedCount == 1)
        #expect(near(d.buildCacheGB, 9e-7) && near(d.buildCacheReclaimGB, 3e-7) && near(d.containersGB, 0.001716) && d.rawGB == 29.9)
    }

    /// 15–30 sn açılıp çöken container "restarting" durumunda neredeyse hiç yakalanmaz (Docker'ın geri çekilmesi
    /// 10 sn'lik çalışmada sıfırlanır): çalışma süresi geriye gidince yeniden başlama sayılır, 5 dk'da 2 kez → sürekli.
    @Test func crashLoopFromUptimeResets() {
        var m = DockerMeter()
        let t = Date(timeIntervalSince1970: 1_793_163_600)
        func poll(_ status: String, _ dt: Double) -> Container {
            m.containers([raw("kc", name: "/authgate", status: status)], stats: [], at: t.addingTimeInterval(dt))[0]
        }
        #expect(!poll("Up 20 seconds", 0).restarting)
        #expect(!poll("Up 5 seconds", 15).restarting)                 // tek yeniden başlama (elle de olabilir)
        #expect(!poll("Up 20 seconds", 30).restarting)
        #expect(poll("Up 4 seconds", 45).restarting)                  // 5 dk'da ikinci
        #expect(poll("Restarting (1) 2 seconds ago", 50).restarting)
        #expect(poll("Up 19 seconds", 60).restarting)                 // pencere içinde sürer
        #expect(!poll("Up 6 minutes", 400).restarting)                // 5 dk sakin
    }
}
