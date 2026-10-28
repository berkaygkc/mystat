import Foundation
import MystatCore
import MystatProbes
import Synchronization
import Testing
@testable import MystatLive

/// Senaryolu sahte Docker: her `stats` çağrısında sayaçlar ilerler (Δsystem 14e9, Δcpu = yüzde × 1e7 ⇒ ×14×100 ile o yüzde).
final class FakeDockerAPI: DockerAPI {
    struct State {
        var down = false
        var list: [DockerContainerRaw] = []
        var cpu: [String: Double] = [:]          // id → yüzde
        var missing: Set<String> = []            // stats'ta 404
        var calls: [String: Int] = [:]
        var posts: [String] = []
        var statsCount: [String: UInt64] = [:]
        var reclaimed: Int64 = 0
        var postDelay: Double = 0
    }
    let state = Mutex(State())
    let df: DockerDFRaw

    init(df: DockerDFRaw = DockerDFRaw(layersSize: 8_764_000_000, images: [], volumes: [], buildCache: [], containersRw: 0)) { self.df = df }

    func n(_ k: String) -> Int { state.withLock { $0.calls[k] ?? 0 } }
    private func count(_ k: String) throws {
        let down = state.withLock { s in s.calls[k, default: 0] += 1; return s.down }
        if down { throw DockerError.notRunning }
    }

    func containers() throws -> [DockerContainerRaw] { try count("containers"); return state.withLock { $0.list } }
    func stats(_ id: String) throws -> DockerStatsRaw {
        try count("stats")
        return try state.withLock { s in
            if s.missing.contains(id) { throw DockerError.http(404) }
            let k = s.statsCount[id, default: 0] + 1
            s.statsCount[id] = k
            return DockerStatsRaw(id: id, cpuTotal: UInt64((s.cpu[id] ?? 0) * 1e7) * k, systemTotal: 14_000_000_000 * k,
                                  onlineCPUs: 14, memUsage: 512 << 20, memInactiveFile: 0)
        }
    }
    func diskUsage() throws -> DockerDFRaw { try count("df"); return df }
    func info() throws -> DockerInfoRaw { try count("info"); return DockerInfoRaw(ncpu: 14, memTotal: 16_748_445_696) }
    func post(_ pathAndQuery: String, timeout: TimeInterval) throws -> (status: Int, body: Data) {
        try count("post")
        let (delay, reclaimed) = state.withLock { s in s.posts.append(pathAndQuery); return (s.postDelay, s.reclaimed) }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return (200, Data("{\"SpaceReclaimed\":\(reclaimed)}".utf8))
    }

    static func raw(_ id: String, project: String? = "deploy", state: String = "running") -> DockerContainerRaw {
        DockerContainerRaw(id: id, name: "/\(project ?? "x")-\(id)-1", image: "img", state: state, status: "Up 2 days", project: project, service: id)
    }
}

@Suite struct DockerPollerTests {
    let t0 = Date(timeIntervalSince1970: 1_793_163_600)

    @Test func delayFollowsStateAndInterest() {
        #expect(DockerPoller.delay(running: false, containerCount: 0, interest: true) == 30)
        #expect(DockerPoller.delay(running: true, containerCount: 0, interest: true) == 60)
        #expect(DockerPoller.delay(running: true, containerCount: 15, interest: true) == 5)
        #expect(DockerPoller.delay(running: true, containerCount: 15, interest: false) == 15)
    }

    @Test func notRunningIsCalmAndReconnects() async {
        let api = FakeDockerAPI()
        api.state.withLock { $0.down = true; $0.list = [FakeDockerAPI.raw("web")] }
        let p = DockerPoller(api: api, rawFile: { nil })
        await p.poll(at: t0)
        #expect(p.latest.withLock { !$0.running && $0.containers.isEmpty })
        api.state.withLock { $0.down = false }
        await p.poll(at: t0.addingTimeInterval(30))
        #expect(p.latest.withLock { $0.running && $0.containers.count == 1 && $0.vmCores == 14 })
        #expect(api.n("info") == 2)   // ilki düştü, yeniden bağlanınca tekrar
    }

    @Test func firstPollShowsZeroThenRealCPU() async {
        let api = FakeDockerAPI()
        api.state.withLock { $0.list = [FakeDockerAPI.raw("verifier")]; $0.cpu = ["verifier": 62] }
        let p = DockerPoller(api: api, rawFile: { nil })
        await p.poll(at: t0)
        #expect(p.latest.withLock { $0.containers.first?.cpuPercent } == 0)
        await p.poll(at: t0.addingTimeInterval(5))
        #expect(p.latest.withLock { $0.containers.first.map { abs($0.cpuPercent - 62) < 1e-6 } } == true)
    }

    @Test func vanishedContainerIsSkipped() async {
        let api = FakeDockerAPI()
        api.state.withLock { $0.list = [FakeDockerAPI.raw("a"), FakeDockerAPI.raw("gone")]; $0.missing = ["gone"] }
        let p = DockerPoller(api: api, rawFile: { nil })
        await p.poll(at: t0)
        #expect(p.latest.withLock { $0.containers.map(\.dockerID) } == ["a"])
    }

    @Test func diskEveryTenMinutesOrOnRequest() async {
        let api = FakeDockerAPI()
        api.state.withLock { $0.list = [FakeDockerAPI.raw("a")] }
        let p = DockerPoller(api: api, rawFile: { nil })
        for t in [0.0, 300, 599] { await p.poll(at: t0.addingTimeInterval(t)) }
        #expect(api.n("df") == 1)
        await p.poll(at: t0.addingTimeInterval(600))
        #expect(api.n("df") == 2)
        await p.requestDisk(at: t0.addingTimeInterval(610))
        #expect(api.n("df") == 3)
        await p.requestDisk(at: t0.addingTimeInterval(640))
        #expect(api.n("df") == 3)
        #expect(p.latest.withLock { $0.disk?.imagesGB } == 8.764)
    }

    @Test func rawFileOnlyOnRequest() async {
        let reads = Mutex(0)
        let api = FakeDockerAPI()
        api.state.withLock { $0.list = [FakeDockerAPI.raw("a")] }
        let p = DockerPoller(api: api, rawFile: { reads.withLock { $0 += 1 }; return 29.9 })
        await p.poll(at: t0)
        #expect(reads.withLock { $0 } == 0 && p.latest.withLock { $0.disk?.rawGB } == nil)
        await p.requestDisk(at: t0.addingTimeInterval(1))
        #expect(reads.withLock { $0 } == 1 && p.latest.withLock { $0.disk?.rawGB } == 29.9)
    }

    @Test func noContainersSkipsDisk() async {
        let api = FakeDockerAPI()
        let p = DockerPoller(api: api, rawFile: { nil })
        await p.poll(at: t0)
        await p.poll(at: t0.addingTimeInterval(600))
        #expect(api.n("df") == 0 && p.latest.withLock { $0.running })
    }
}
