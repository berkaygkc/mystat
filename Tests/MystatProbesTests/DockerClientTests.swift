import Darwin
import Foundation
import MystatCore
import Testing
@testable import MystatProbes

/// Tek bağlantı kabul eden sahte Docker soketi: yanıtı yazıp kapatır ya da (`reply == nil`) hiç yazmadan bekler.
final class FakeSocketServer: Sendable {
    let path: String
    private let fd: Int32

    init(reply: Data?, holdSeconds: Double = 5) throws {
        path = NSTemporaryDirectory() + "mystat-\(UInt32.random(in: 0...UInt32.max)).sock"
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in for (i, b) in bytes.enumerated() { buf[i] = UInt8(bitPattern: b) } }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) } } == 0
        guard ok, listen(fd, 1) == 0 else { throw DockerError.notRunning }
        let listener = fd
        DispatchQueue.global().async {
            let c = accept(listener, nil, nil)
            guard c >= 0 else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            _ = read(c, &buf, buf.count)
            if let reply { reply.withUnsafeBytes { _ = write(c, $0.baseAddress, reply.count) } } else { usleep(UInt32(holdSeconds * 1_000_000)) }
            close(c)
        }
    }

    deinit { close(fd); unlink(path) }
}

@Suite struct DockerClientTests {
    @Test func parsesHTTP10Response() throws {
        let r = try HTTPWire.parse(Data("HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n[]".utf8))
        #expect(r.status == 200 && String(decoding: r.body, as: UTF8.self) == "[]")
    }

    @Test func parsesChunkedBody() throws {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n"
        #expect(String(decoding: try HTTPWire.parse(Data(raw.utf8)).body, as: UTF8.self) == "Wikipedia")
    }

    @Test func non2xxIsHTTPError() throws {
        let server = try FakeSocketServer(reply: Data("HTTP/1.0 404 Not Found\r\n\r\n{\"message\":\"no such container\"}".utf8))
        #expect(throws: DockerError.http(404)) { try DockerClient(socketPaths: [server.path]).stats("yok") }
    }

    @Test func decodesContainerList() throws {
        let body = #"[{"Id":"abc","Names":["/deploy-web-1"],"Image":"nginx","State":"running","Status":"Up 2 days","Labels":{"com.docker.compose.project":"deploy","com.docker.compose.service":"web"}}]"#
        let server = try FakeSocketServer(reply: Data("HTTP/1.0 200 OK\r\n\r\n\(body)".utf8))
        let list = try DockerClient(socketPaths: [server.path]).containers()
        #expect(list == [DockerContainerRaw(id: "abc", name: "/deploy-web-1", image: "nginx", state: "running", status: "Up 2 days",
                                            project: "deploy", service: "web")])
    }

    @Test func missingSocketIsNotRunning() {
        #expect(throws: DockerError.notRunning) { try DockerClient(socketPaths: ["/tmp/yok-\(UUID().uuidString)"]).containers() }
    }

    @Test func silentServerTimesOut() throws {
        let server = try FakeSocketServer(reply: nil)
        let t0 = Date()
        #expect(throws: DockerError.timeout) { try DockerClient(socketPaths: [server.path]).containers() }
        #expect(Date().timeIntervalSince(t0) < 4)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: DockerClient.defaultPaths[0])))
    func liveDaemonSmoke() throws {
        let c = DockerClient()
        #expect(try c.info().ncpu > 0)
        let list = try c.containers()
        if let first = list.first(where: { $0.state == "running" }) { #expect(try c.stats(first.id).onlineCPUs > 0) }
        #expect(try c.diskUsage().layersSize > 0)
    }

    @Test func allocatedSizeOfSparseFile() throws {
        let path = NSTemporaryDirectory() + "mystat-raw-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: path, contents: Data(count: 1_000_000))
        defer { unlink(path) }
        #expect(truncate(path, 1_000_000_000) == 0)
        let gb = try #require(DockerDiskFile.allocatedGB(path: path))
        #expect(gb > 0.0009 && gb < 0.01)
        #expect(DockerDiskFile.allocatedGB(path: "/yok/\(UUID().uuidString)") == nil)
    }

    /// Adsız volume Docker'ın etiketiyle tanınır (prune süzgeciyle aynı küme); 64 onaltılık ad tek başına yetmez.
    @Test func anonymousVolumesByLabel() throws {
        let hex = String(repeating: "ab", count: 32)
        let body = #"{"LayersSize":0,"Images":[],"BuildCache":[],"Containers":[],"Volumes":["#
            + #"{"Name":"\#(hex)","Labels":{"com.docker.volume.anonymous":""},"UsageData":{"Size":100,"RefCount":0}},"#
            + #"{"Name":"\#(hex.uppercased().lowercased().replacingOccurrences(of: "a", with: "c"))","Labels":null,"UsageData":{"Size":200,"RefCount":0}},"#
            + #"{"Name":"deploy_pg-data","Labels":{"com.docker.compose.project":"deploy"},"UsageData":{"Size":300,"RefCount":0}}]}"#
        let server = try FakeSocketServer(reply: Data("HTTP/1.0 200 OK\r\n\r\n\(body)".utf8))
        #expect(try DockerClient(socketPaths: [server.path]).diskUsage().volumes.map(\.anonymous) == [true, false, false])
    }
}
