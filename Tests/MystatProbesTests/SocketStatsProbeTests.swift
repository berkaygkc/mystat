import Darwin
import Foundation
import MystatCore
import Testing
@testable import MystatProbes

@Suite(.serialized) struct SocketStatsProbeTests {
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

    /// Elle kurulmuş tampon: başlık (24); her soket için xinpcb_n (104, uzak port 16'da, yerel 18'de, ağ sırası),
    /// xsocket_n (104, tutamaç 8'de, pid 68'de, kuşak 76'da), xsockstat_n (136, 4 sınıf); sondaki başlık.
    static func buffer(socketLen: UInt32 = 104) -> [UInt8] {
        var b = [UInt8]()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        func put<T>(_ v: T, at o: Int) { b.withUnsafeMutableBytes { $0.storeBytes(of: v, toByteOffset: o, as: T.self) } }
        func pad() { while b.count % 8 != 0 { b.append(0) } }
        u32(24); u32(2); u64(0); u64(0)                                   // xinpgen
        for (handle, pid, gen, lport, rxBase) in [(UInt64(0xABCD), Int32(4242), UInt64(77), UInt16(8080), UInt64(100)),
                                                  (UInt64(0), Int32(4243), UInt64(0), UInt16(5223), UInt64(10))] {
            let i0 = b.count; u32(104); u32(0x010); b += [UInt8](repeating: 0, count: 96)          // xinpcb_n
            put(UInt16(443).bigEndian, at: i0 + 16); put(lport.bigEndian, at: i0 + 18)
            let s0 = b.count; u32(socketLen); u32(0x001); u64(handle)                              // xsocket_n
            b += [UInt8](repeating: 0, count: Int(socketLen) - 16)
            put(pid, at: s0 + 68); put(gen, at: s0 + 76); pad()
            u32(136); u32(0x008)                                                                   // xsockstat_n
            for k in 0..<4 { u64(0); u64(rxBase * UInt64(k + 1)); u64(0); u64(5) }
        }
        u32(24); u32(1); u64(0); u64(0)                                   // sondaki xinpgen (sayı 1: soket türüyle karışmamalı)
        return b
    }

    @Test func parsesLayout() throws {
        let stats = try #require(Self.buffer().withUnsafeBytes { SocketStatsProbe.parse($0, proto: 6) })
        #expect(stats == [SocketStat(generation: 77, pid: 4242, rxBytes: 1000, proto: 6, localPort: 8080, foreignPort: 443),
                          SocketStat(generation: 0, pid: 4243, rxBytes: 100, proto: 6, localPort: 5223, foreignPort: 443)])
        #expect(stats[1].isUserSpaceFlow); #expect(!stats[0].isUserSpaceFlow)
    }

    @Test func rejectsUnexpectedLayout() {
        #expect(Self.buffer(socketLen: 112).withUnsafeBytes { SocketStatsProbe.parse($0, proto: 6) } == nil)
        #expect([UInt8]().withUnsafeBytes { SocketStatsProbe.parse($0, proto: 6) } == nil)
    }

    /// Süreçte başka (kapanmış, TIME_WAIT'teki) bir TCP soketi daha büyük sayaçla dursa da öz denetim kendi soketini
    /// bağlantı noktalarından bulur.
    @Test func receiveFactorIgnoresOtherSockets() throws {
        let (a, b, c) = Self.transfer(1_000_000)
        close(a); close(b); close(c)
        let f = try #require(SocketStatsProbe.receiveFactor())
        #expect(f == 1 || f == 2)
    }
}
