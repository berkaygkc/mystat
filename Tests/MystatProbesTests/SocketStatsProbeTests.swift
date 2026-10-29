import Darwin
import Foundation
import MystatCore
import Testing
@testable import MystatProbes

@Suite struct SocketStatsProbeTests {
    /// Loopback'te bağlı bir TCP çifti; `send` baytı istemciden sunucuya aktarılır ve okunur.
    static func transfer(_ bytes: Int) -> (Int32, Int32, Int32) {
        let srv = socket(AF_INET, SOCK_STREAM, 0)
        var a = sockaddr_in(); a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = bind(srv, $0, len); _ = listen(srv, 1); _ = getsockname(srv, $0, &len) } }
        let cli = socket(AF_INET, SOCK_STREAM, 0)
        withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = connect(cli, $0, len) } }
        let acc = accept(srv, nil, nil)
        let data = [UInt8](repeating: 3, count: bytes)
        DispatchQueue.global().async { var off = 0; while off < bytes { let n = data[off...].withUnsafeBytes { send(cli, $0.baseAddress, $0.count, 0) }; if n <= 0 { break }; off += n } }
        var buf = [UInt8](repeating: 0, count: 65536), got = 0
        while got < bytes { let n = recv(acc, &buf, buf.count, 0); if n <= 0 { break }; got += n }
        return (srv, cli, acc)
    }

    @Test func ownLoopbackTransferVisible() throws {
        let (a, b, c) = Self.transfer(1_000_000)
        defer { close(a); close(b); close(c) }
        let stats = try #require(SocketStatsProbe.read())
        let mine = stats.filter { $0.pid == getpid() }.map(\.rxBytes).max() ?? 0
        #expect(mine >= 1_000_000 && mine <= 2_200_000, "\(mine)")
        #expect(stats.count > 3)
    }

    @Test func receiveFactorIsOneOrTwo() throws {
        let f = try #require(SocketStatsProbe.receiveFactor())
        #expect(f == 1 || f == 2)
    }

    /// Elle kurulmuş tampon: başlık (24), soket (104, pid 68'de), istatistik (136, alınan 16+32k'de), sondaki başlık.
    static func buffer(socketLen: UInt32 = 104) -> [UInt8] {
        var b = [UInt8]()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        u32(24); u32(1); u64(0); u64(0)                                   // xinpgen
        let s0 = b.count; u32(socketLen); u32(0x001); u64(0xABCD)          // xsocket_n
        b += [UInt8](repeating: 0, count: Int(socketLen) - 16)
        b.withUnsafeMutableBytes { $0.storeBytes(of: Int32(4242), toByteOffset: s0 + 68, as: Int32.self) }
        while b.count % 8 != 0 { b.append(0) }
        u32(136); u32(0x008)                                              // xsockstat_n: 4 sınıf × {rxp, rxb, txp, txb}
        for k in 0..<4 { u64(0); u64(UInt64(100 * (k + 1))); u64(0); u64(5) }
        u32(24); u32(1); u64(0); u64(0)                                   // sondaki xinpgen (sayı 1: soket türüyle karışmamalı)
        return b
    }

    @Test func parsesLayout() throws {
        let stats = try #require(Self.buffer().withUnsafeBytes { SocketStatsProbe.parse($0) })
        #expect(stats == [SocketStat(handle: 0xABCD, pid: 4242, rxBytes: 1000)])
    }

    @Test func rejectsUnexpectedLayout() {
        #expect(Self.buffer(socketLen: 112).withUnsafeBytes { SocketStatsProbe.parse($0) } == nil)
        #expect([UInt8]().withUnsafeBytes { SocketStatsProbe.parse($0) } == nil)
    }
}
