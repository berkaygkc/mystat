import Dispatch
import Foundation
import MystatCore
import MystatProbes
import Synchronization

/// Reads Docker at its own pace and keeps the last reading in `latest`; `Sampler` only picks that up each round.
/// Socket I/O is blocking (3 s timeout): the actor runs on its own serial queue and does not hold up Swift's shared threads
/// or the sampling loop.
public actor DockerPoller {
    public struct Reading: Sendable {
        public var running = false
        public var containers: [Container] = []
        public var vmMemoryGB = 0.0, vmCores = 0
        public var disk: DockerDisk?
        public var diskAt: Date?
    }

    /// Latest state, read by the sampling loop.
    public nonisolated let latest = Mutex(Reading())
    /// Whether the panel or monitor is open (interval 5 s / 15 s).
    public nonisolated let interest = Mutex(false)

    private let queue = DispatchSerialQueue(label: "mystat.docker")
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let api: any DockerAPI
    private let rawFile: @Sendable () -> Double?
    private var meter = DockerMeter()
    private var connected = false
    private var timeouts = 0
    private var rawGB: Double?
    private var lastRequest: Date?
    private var loop: Task<Void, Never>?
    /// Running actions: actor calls are queued, so the double-click check is done before entering the actor.
    private nonisolated let inFlight = Mutex(Set<DockerAction>())

    public init(api: some DockerAPI = DockerClient(), rawFile: @escaping @Sendable () -> Double? = { DockerDiskFile.allocatedGB() }) {
        self.api = api
        self.rawFile = rawFile
    }

    public func start() {
        loop?.cancel()
        loop = Task {
            while !Task.isCancelled {
                poll(at: Date())
                let r = latest.withLock { $0 }
                try? await Task.sleep(for: .seconds(Self.delay(running: r.running, containerCount: r.containers.count,
                                                                interest: interest.withLock { $0 })))
            }
        }
    }

    public func stop() { loop?.cancel() }

    /// Docker absent: 30 s; no containers at all (Resource Saver; don't wake the VM): 60 s; otherwise 5 s while watched, 15 s when not.
    public nonisolated static func delay(running: Bool, containerCount: Int, interest: Bool) -> TimeInterval {
        guard running else { return 30 }
        guard containerCount > 0 else { return 60 }
        return interest ? 5 : 15
    }

    public func poll(at now: Date) {
        do {
            if !connected {
                let info = try api.info()
                latest.withLock { $0.vmCores = info.ncpu; $0.vmMemoryGB = Double(info.memTotal) / 1_073_741_824 }
                connected = true
            }
            let list = try api.containers()
            var stats: [DockerStatsRaw] = [], gone = Set<String>(), late = Set<String>()
            for c in list {
                do { stats.append(try api.stats(c.id)) }
                catch DockerError.http { gone.insert(c.id) }   // deleted between the list and the stats call
                catch { late.insert(c.id) }                    // a single container was late: Docker is not considered "not running"
            }
            let previous = Dictionary(latest.withLock { $0.containers }.map { ($0.dockerID, $0) }, uniquingKeysWith: { a, _ in a })
            let containers = meter.containers(list.filter { !gone.contains($0.id) }, stats: stats, at: now).map { c in
                late.contains(c.dockerID) ? previous[c.dockerID] ?? c : c                     // for a late container, use its previous value
            }
            timeouts = 0
            latest.withLock { $0.running = true; $0.containers = containers }
            let diskAt = latest.withLock { $0.diskAt }
            if !containers.isEmpty, diskAt.map({ now.timeIntervalSince($0) >= 600 }) ?? true { refreshDisk(at: now) }
        } catch DockerError.timeout {
            timeouts += 1
            if timeouts >= 2 { down() }
        } catch {
            down()
        }
    }

    /// Docker section opened: read the disk and virtual disk file (so any permission prompt appears in context); no more often than every 60 s.
    public func requestDisk(at now: Date) {
        guard lastRequest.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastRequest = now
        rawGB = rawFile()
        if latest.withLock({ $0.running }) { refreshDisk(at: now) }
    }

    /// Actions. A second request is not sent while the same action is running.
    public nonisolated func perform(_ action: DockerAction) async -> DockerActionOutcome {
        guard inFlight.withLock({ $0.insert(action).inserted }) else { return .failed(L10n.t("docker.error.inProgress")) }
        defer { inFlight.withLock { _ = $0.remove(action) } }
        return await run(action)
    }

    private func run(_ action: DockerAction) -> DockerActionOutcome {
        func filters(_ json: String) -> String {   // everything except RFC 3986 unreserved characters is encoded
            "?filters=" + (json.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? "")
        }
        let (path, timeout): (String, TimeInterval) = switch action {
        case .restart(let id, _): ("/containers/\(id)/restart?t=10", 30)
        case .stop(let id, _): ("/containers/\(id)/stop?t=10", 30)
        // With a label: an unfiltered prune also deletes named data volumes on old engines (< 23.0) and on Podman.
        case .pruneAnonymousVolumes: ("/volumes/prune" + filters(#"{"label":["com.docker.volume.anonymous"]}"#), 120)
        case .pruneNamedVolumes: ("/volumes/prune" + filters(#"{"all":["true"],"label!":["com.docker.volume.anonymous"]}"#), 120)
        case .pruneImages: ("/images/prune" + filters(#"{"dangling":["false"]}"#), 120)
        }
        let outcome: DockerActionOutcome
        do {
            let r = try api.post(path, timeout: timeout)
            switch r.status {
            case 200..<300, 304:
                let reclaimed = (try? JSONDecoder().decode(Reclaimed.self, from: r.body)).map { Double($0.SpaceReclaimed ?? 0) / 1e9 }
                outcome = .done(reclaimedGB: action.isPrune ? reclaimed ?? 0 : nil)
            case 404: outcome = .failed(L10n.t("docker.error.notFound"))
            default: outcome = .failed(L10n.t("docker.error.rejected", ["status": String(r.status)]))
            }
        } catch DockerError.notRunning {
            return .failed(L10n.t("docker.error.notRunning"))
        } catch DockerError.timeout {
            return .failed(L10n.t("docker.error.noResponse"))
        } catch {
            return .failed(L10n.t("docker.error.failed"))
        }
        let now = Date()
        poll(at: now)
        if action.isPrune { refreshDisk(at: now) }
        return outcome
    }

    private struct Reclaimed: Decodable { let SpaceReclaimed: Int64? }

    private func refreshDisk(at now: Date) {
        guard let df = try? api.diskUsage() else { return }
        let disk = DockerMeter.disk(df, rawGB: rawGB)
        latest.withLock { $0.disk = disk; $0.diskAt = now }
    }

    private func down() {
        connected = false
        timeouts = 0
        meter = DockerMeter()
        latest.withLock { $0 = Reading() }
    }
}
