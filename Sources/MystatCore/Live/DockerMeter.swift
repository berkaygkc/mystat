import Foundation

/// Container CPU and memory follow the definitions of `docker stats`, disk follows the formulas of `docker system df` (decimal GB).
/// CPU: `Δcpu / Δsystem × onlineCPUs × 100` (100% = 1 core). Previous counters are kept by container id:
/// a container recreated with the same name does not inherit the old one's values; its first measurement shows 0 (no spike).
/// Continuous restarting: if the uptime goes backwards between rounds it counts as a restart; 2 restarts within 5 min, or a
/// "restarting" state. Looking only at the state is not enough, because Docker's back-off is reset in a 10 s run.
public struct DockerMeter: Sendable {
    private var last: [String: (cpu: UInt64, system: UInt64)] = [:]
    private var uptimes: [String: Double] = [:]
    private var restarts: [String: [Date]] = [:]
    static let restartWindow: TimeInterval = 300

    public init() {}

    public mutating func containers(_ list: [DockerContainerRaw], stats: [DockerStatsRaw], at now: Date = Date()) -> [Container] {
        let byID = Dictionary(stats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var next: [String: (cpu: UInt64, system: UInt64)] = [:]
        var nextUptimes: [String: Double] = [:], nextRestarts: [String: [Date]] = [:]
        let out = list.map { r -> Container in
            var times = (restarts[r.id] ?? []).filter { now.timeIntervalSince($0) < Self.restartWindow }
            if let up = Self.uptimeSeconds(status: r.status) {
                if let before = uptimes[r.id], up < before { times.append(now) }
                nextUptimes[r.id] = up
            } else if let before = uptimes[r.id] {
                nextUptimes[r.id] = before
            }
            nextRestarts[r.id] = times
            var cpu = 0.0, mem = 0.0
            if let s = byID[r.id] {
                if let p = last[r.id], s.cpuTotal >= p.cpu, s.systemTotal > p.system {
                    cpu = Double(s.cpuTotal - p.cpu) / Double(s.systemTotal - p.system) * Double(max(1, s.onlineCPUs)) * 100
                }
                next[r.id] = (s.cpuTotal, s.systemTotal)
                mem = Double(s.memUsage > s.memInactiveFile ? s.memUsage - s.memInactiveFile : 0) / 1_048_576
            }
            let plain = r.name.hasPrefix("/") ? String(r.name.dropFirst()) : r.name
            return Container(name: r.project != nil ? (r.service ?? plain) : plain, image: r.image, cpuPercent: cpu, memoryMB: mem,
                             healthy: Self.healthy(status: r.status), uptime: Self.uptime(status: r.status),
                             project: r.project ?? "", dockerID: r.id, restarting: r.state == "restarting" || times.count >= 2)
        }
        last = next
        uptimes = nextUptimes
        restarts = nextRestarts
        return out
    }

    public static func disk(_ df: DockerDFRaw, rawGB: Double?) -> DockerDisk {
        let gb = { (b: Int64) in Double(b) / 1e9 }
        let used = df.images.filter { $0.containers > 0 }.reduce(Int64(0)) { $0 + ($1.size - $1.shared) }
        let unusedVolumes = df.volumes.filter { $0.refCount == 0 }
        let anon = unusedVolumes.filter(\.anonymous)
        return DockerDisk(imagesGB: gb(df.layersSize), imagesReclaimGB: max(0, gb(df.layersSize - used)), imagesCount: df.images.count,
                          volumesGB: gb(df.volumes.reduce(0) { $0 + max(0, $1.size) }),
                          volumesReclaimGB: gb(unusedVolumes.reduce(0) { $0 + max(0, $1.size) }), volumesCount: df.volumes.count,
                          buildCacheGB: gb(df.buildCache.reduce(0) { $0 + $1.size }), rawGB: rawGB,
                          imagesUnusedCount: df.images.filter { $0.containers == 0 }.count, volumesUnusedCount: unusedVolumes.count,
                          volumesAnonReclaimGB: gb(anon.reduce(0) { $0 + max(0, $1.size) }), volumesAnonUnusedCount: anon.count,
                          buildCacheReclaimGB: gb(df.buildCache.filter { !$0.inUse && !$0.shared }.reduce(0) { $0 + $1.size }),
                          containersGB: gb(df.containersRw))
    }

    /// Docker's human-readable uptime ("Up 2 days (healthy)", "Up About an hour") → `Fmt.uptime`. "—" if not running.
    static func uptime(status: String) -> String { Fmt.uptime(uptimeSeconds(status: status) ?? .nan) }

    /// Docker's uptime text increases monotonically ("59 seconds" → "About a minute" → "2 minutes" …); nil if not running.
    static func uptimeSeconds(status: String) -> Double? {
        guard status.hasPrefix("Up ") else { return nil }
        var text = status.dropFirst(3)
        if let paren = text.range(of: " (") { text = text[..<paren.lowerBound] }
        if text == "Less than a second" { return 0 }
        let words = text.split(separator: " ").filter { $0 != "About" }
        guard words.count == 2 else { return nil }
        let n = words[0] == "a" || words[0] == "an" ? 1 : Double(words[0])
        let units: [String: Double] = ["second": 1, "minute": 60, "hour": 3600, "day": 86_400, "week": 604_800, "month": 2_592_000, "year": 31_536_000]
        let unit = words[1].hasSuffix("s") ? String(words[1].dropLast()) : String(words[1])
        guard let n, let u = units[unit] else { return nil }
        return n * u
    }

    static func healthy(status: String) -> Bool { !status.contains("(unhealthy)") }
}
