import Darwin
import Foundation
import MystatCore

public enum DockerError: Error, Equatable {
    /// No socket or connection refused: Docker Desktop is not running.
    case notRunning
    case timeout
    case http(Int)
    case decode
}

/// Docker Engine API. Only over the user's socket; tests use a fake.
public protocol DockerAPI: Sendable {
    /// Running (and restarting) containers.
    func containers() throws -> [DockerContainerRaw]
    func stats(_ id: String) throws -> DockerStatsRaw
    func diskUsage() throws -> DockerDFRaw
    func info() throws -> DockerInfoRaw
    /// Actions; a non-2xx response is not treated as an error, the caller interprets it.
    func post(_ pathAndQuery: String, timeout: TimeInterval) throws -> (status: Int, body: Data)
}

/// HTTP/1.0 over a Unix socket: each request is a separate connection, and the server closes it after the response (body until EOF).
/// Reads and writes have timeouts; the caller does not stay blocked even if Docker hangs.
public struct DockerClient: DockerAPI {
    public static let defaultPaths = [NSHomeDirectory() + "/.docker/run/docker.sock", "/var/run/docker.sock"]
    static let maxBody = 32 << 20

    let socketPaths: [String]

    public init(socketPaths: [String] = DockerClient.defaultPaths) { self.socketPaths = socketPaths }

    public func containers() throws -> [DockerContainerRaw] {
        try decode([ContainerJSON].self, get("/containers/json")).map {
            DockerContainerRaw(id: $0.Id, name: $0.Names?.first ?? $0.Id, image: $0.Image ?? "", state: $0.State ?? "", status: $0.Status ?? "",
                               project: $0.Labels?["com.docker.compose.project"], service: $0.Labels?["com.docker.compose.service"])
        }
    }

    public func stats(_ id: String) throws -> DockerStatsRaw {
        let s = try decode(StatsJSON.self, get("/containers/\(id)/stats?stream=false&one-shot=true"))
        return DockerStatsRaw(id: id, cpuTotal: s.cpu_stats?.cpu_usage?.total_usage ?? 0, systemTotal: s.cpu_stats?.system_cpu_usage ?? 0,
                              onlineCPUs: s.cpu_stats?.online_cpus ?? 0, memUsage: s.memory_stats?.usage ?? 0,
                              memInactiveFile: s.memory_stats?.stats?.inactive_file ?? s.memory_stats?.stats?.total_inactive_file ?? 0)
    }

    public func diskUsage() throws -> DockerDFRaw {
        let d = try decode(DFJSON.self, get("/system/df", timeout: 30))
        return DockerDFRaw(
            layersSize: d.LayersSize ?? 0,
            images: (d.Images ?? []).map { .init(size: max(0, $0.Size ?? 0), shared: max(0, $0.SharedSize ?? 0), containers: max(0, $0.Containers ?? 0)) },
            volumes: (d.Volumes ?? []).map { .init(size: max(0, $0.UsageData?.Size ?? 0), refCount: $0.UsageData?.RefCount ?? 0,
                                                   anonymous: $0.Labels?["com.docker.volume.anonymous"] != nil) },
            buildCache: (d.BuildCache ?? []).map { .init(size: $0.Size ?? 0, inUse: $0.InUse ?? false, shared: $0.Shared ?? false) },
            containersRw: (d.Containers ?? []).reduce(0) { $0 + max(0, $1.SizeRw ?? 0) })
    }

    public func info() throws -> DockerInfoRaw {
        let i = try decode(InfoJSON.self, get("/info"))
        return DockerInfoRaw(ncpu: i.NCPU ?? 0, memTotal: i.MemTotal ?? 0)
    }

    public func post(_ pathAndQuery: String, timeout: TimeInterval) throws -> (status: Int, body: Data) {
        try HTTPWire.parse(exchange(HTTPWire.request(method: "POST", path: pathAndQuery), timeout: timeout))
    }

    // MARK: - Transport

    private func get(_ path: String, timeout: TimeInterval = 3) throws -> Data {
        let r = try HTTPWire.parse(exchange(HTTPWire.request(method: "GET", path: path), timeout: timeout))
        guard (200..<300).contains(r.status) else { throw DockerError.http(r.status) }
        return r.body
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw DockerError.decode }
    }

    private func exchange(_ request: Data, timeout: TimeInterval) throws -> Data {
        guard let path = socketPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { throw DockerError.notRunning }
        let fd = try Self.connect(path, timeout: timeout)
        defer { close(fd) }
        let sent = request.withUnsafeBytes { write(fd, $0.baseAddress, request.count) }
        guard sent == request.count else { throw errno == EAGAIN ? DockerError.timeout : DockerError.notRunning }
        let deadline = Date().addingTimeInterval(timeout)
        var out = Data(), buf = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(fd, &buf, buf.count)
            if n == 0 { return out }
            if n < 0 { throw errno == EAGAIN || errno == EWOULDBLOCK ? DockerError.timeout : DockerError.notRunning }
            out.append(buf, count: n)
            guard out.count <= Self.maxBody else { throw DockerError.decode }
            guard Date() < deadline else { throw DockerError.timeout }
        }
    }

    private static func connect(_ path: String, timeout: TimeInterval) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DockerError.notRunning }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); throw DockerError.notRunning }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in for (i, b) in bytes.enumerated() { buf[i] = UInt8(bitPattern: b) } }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) } }
        guard r == 0 else { close(fd); throw DockerError.notRunning }
        return fd
    }
}

/// Minimal HTTP/1.0 request and response parsing (chunked bodies too).
enum HTTPWire {
    static func request(method: String, path: String) -> Data {
        Data("\(method) \(path) HTTP/1.0\r\nHost: docker\r\nContent-Length: 0\r\n\r\n".utf8)
    }

    static func parse(_ raw: Data) throws -> (status: Int, body: Data) {
        let sep = Data("\r\n\r\n".utf8)
        guard let end = raw.range(of: sep) else { throw DockerError.decode }
        let head = String(decoding: raw[raw.startIndex..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2, let status = Int(parts[1]) else { throw DockerError.decode }
        let body = Data(raw[end.upperBound...])
        let chunked = lines.dropFirst().contains { $0.lowercased().hasPrefix("transfer-encoding:") && $0.lowercased().contains("chunked") }
        return (status, chunked ? try dechunk(body) : body)
    }

    private static func dechunk(_ d: Data) throws -> Data {
        var out = Data(), i = d.startIndex
        let crlf = Data("\r\n".utf8)
        while let lineEnd = d[i...].range(of: crlf) {
            let sizeText = String(decoding: d[i..<lineEnd.lowerBound], as: UTF8.self).split(separator: ";").first ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { throw DockerError.decode }
            if size == 0 { return out }
            let start = lineEnd.upperBound
            guard d.distance(from: start, to: d.endIndex) >= size else { throw DockerError.decode }
            let stop = d.index(start, offsetBy: size)
            out.append(d[start..<stop])
            i = d.index(stop, offsetBy: 2, limitedBy: d.endIndex) ?? d.endIndex
        }
        return out
    }
}

// MARK: - JSON (only the fields used; missing ones are 0)

private struct ContainerJSON: Decodable {
    let Id: String
    let Names: [String]?
    let Image: String?, State: String?, Status: String?
    let Labels: [String: String]?
}

private struct StatsJSON: Decodable {
    struct CPU: Decodable {
        struct Usage: Decodable { let total_usage: UInt64? }
        let cpu_usage: Usage?
        let system_cpu_usage: UInt64?
        let online_cpus: Int?
    }
    struct Memory: Decodable {
        struct Stats: Decodable { let inactive_file: UInt64?; let total_inactive_file: UInt64? }
        let usage: UInt64?
        let stats: Stats?
    }
    let cpu_stats: CPU?
    let memory_stats: Memory?
}

private struct DFJSON: Decodable {
    struct Image: Decodable { let Size: Int64?; let SharedSize: Int64?; let Containers: Int? }
    struct Volume: Decodable {
        struct Usage: Decodable { let Size: Int64?; let RefCount: Int? }
        let Labels: [String: String]?
        let UsageData: Usage?
    }
    struct Cache: Decodable { let Size: Int64?; let InUse: Bool?; let Shared: Bool? }
    struct Container: Decodable { let SizeRw: Int64? }
    let LayersSize: Int64?
    let Images: [Image]?, Volumes: [Volume]?, BuildCache: [Cache]?, Containers: [Container]?
}

private struct InfoJSON: Decodable { let NCPU: Int?; let MemTotal: Int64? }
