import Darwin
import Foundation
import MystatCore

/// Uygulama bazında ağ (spec §9.1 "nettop ya da eşdeğeri"): çekirdeğin soket listesi, `netstat`'ın kaynağı
/// (`net.inet.tcp.pcblist_n`, `net.inet.udp.pcblist_n`). `nettop` bu makinede Ağ bölümü açıkken dakikada ≈ 35 sn
/// işlemci tutuyordu; bu okuma 2 sn tempoda dakikada ≈ 0,02 sn (ölçüldü, 2026-10-29).
///
/// Kayıtlar SDK'da yok (xnu, 4 bayta paketli; macOS 26'da doğrulandı): her kayıt `{u32 uzunluk, u32 tür, …}`, 8'e
/// yuvarlı. `xsocket_n` 104 bayt, sahibin pid'i 68'de, etkin pid 72'de; `xsockstat_n` 136 bayt, 4 trafik sınıfının her
/// biri `{rxpackets, rxbytes, txpackets, txbytes}`; `xinpcb_n` 104 bayt, bağlantı noktaları 16 ve 18'de. Kayıt boyu
/// beklenenden farklıysa (düzen değişmiş) okuma hiç sonuç vermez. Network.framework'ün kullanıcı alanı akışları da
/// listede (tutamaç ve kuşak 0); bağlantı noktalarıyla ayırt edilir ve alınanı bir kez sayar.
public enum SocketStatsProbe {
    static let socketKind: UInt32 = 0x001, statsKind: UInt32 = 0x008, inpcbKind: UInt32 = 0x010
    static let socketLen = 104, statsLen = 136, inpcbLen = 104
    static let lastPidOffset = 68, effectivePidOffset = 72, generationOffset = 76, classCount = 4, classStride = 32, rxInClass = 8
    static let foreignPortOffset = 16, localPortOffset = 18   // xinpcb_n, ağ sırası

    /// Tüm TCP ve UDP soketleri; okunamazsa ya da düzen beklenenden farklıysa nil.
    public static func read() -> [SocketStat]? {
        guard let tcp = list("net.inet.tcp.pcblist_n", proto: 6), let udp = list("net.inet.udp.pcblist_n", proto: 17) else { return nil }
        return tcp + udp
    }

    static func list(_ name: String, proto: UInt8) -> [SocketStat]? {
        for _ in 0..<3 {   // okumalar arasında soket açılırsa tampon küçük kalabilir
            var len = 0
            guard sysctlbyname(name, nil, &len, nil, 0) == 0 else { return nil }
            len += len / 4 + 4096
            var buf = [UInt8](repeating: 0, count: len)
            if sysctlbyname(name, &buf, &len, nil, 0) == 0 { return buf.withUnsafeBytes { parse(UnsafeRawBufferPointer(rebasing: $0[..<len]), proto: proto) } }
            guard errno == ENOMEM else { return nil }
        }
        return nil
    }

    /// Bir soketin kayıtları sırayla gelir: xinpcb_n (bağlantı noktaları), xsocket_n (sahip, kuşak), …, xsockstat_n.
    /// Network.framework akışlarında tutamaç ve kuşak 0'dır.
    static func parse(_ raw: UnsafeRawBufferPointer, proto: UInt8) -> [SocketStat]? {
        guard raw.count >= 24 else { return nil }
        func u32(_ o: Int) -> UInt32 { raw.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
        func u64(_ o: Int) -> UInt64 { raw.loadUnaligned(fromByteOffset: o, as: UInt64.self) }
        func i32(_ o: Int) -> Int32 { raw.loadUnaligned(fromByteOffset: o, as: Int32.self) }
        func port(_ o: Int) -> UInt16 { UInt16(bigEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)) }
        func round8(_ v: Int) -> Int { (v + 7) & ~7 }
        var out: [SocketStat] = []
        var ports: (local: UInt16, foreign: UInt16) = (0, 0)
        var owner: (generation: UInt64, pid: Int32)?
        var off = round8(Int(u32(0)))
        while off + 8 <= raw.count {
            let len = Int(u32(off)), kind = u32(off + 4)
            guard len >= 8, off + len <= raw.count else { break }
            let last = off + round8(len) >= raw.count   // sondaki xinpgen: ikinci alanı soket sayısı, türle karışabilir
            switch kind {
            case inpcbKind:
                guard len == inpcbLen else { if last { break } else { return nil } }
                ports = (port(off + localPortOffset), port(off + foreignPortOffset))
            case socketKind:
                guard len == socketLen else { if last { break } else { return nil } }
                let e = i32(off + effectivePidOffset)
                owner = (u64(off + 8) == 0 ? 0 : u64(off + generationOffset), e != 0 ? e : i32(off + lastPidOffset))
            case statsKind:
                guard len == statsLen else { if last { break } else { return nil } }
                if let o = owner {
                    var rx: UInt64 = 0
                    for c in 0..<classCount { rx &+= u64(off + 8 + c * classStride + rxInClass) }
                    out.append(SocketStat(generation: o.generation, pid: o.pid, rxBytes: rx, proto: proto, localPort: ports.local, foreignPort: ports.foreign))
                    owner = nil; ports = (0, 0)
                }
            default: break
            }
            off += round8(len)
        }
        return out
    }

    /// Çekirdek soketleri alınan baytı kaç kez sayıyor: loopback'te 256 KB TCP aktarımıyla ölçülür (macOS 26'da 2). Aynı
    /// ölçüm kayıt düzenini de doğrular: kabul edilen soket bağlantı noktalarından bulunamazsa ya da oran 1 ya da 2'ye yakın
    /// değilse nil. Tek iş parçacığında, engellemeden (gönderme ve alma iç içe), en çok 1,5 sn; SIGPIPE yok.
    public static func receiveFactor() -> Double? {
        let bytes = 256 * 1024
        let srv = socket(AF_INET, SOCK_STREAM, 0), cli = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(srv); close(cli) }
        guard srv >= 0, cli >= 0 else { return nil }
        var on: Int32 = 1
        for fd in [srv, cli] { setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) }
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1")
        var alen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ready = withUnsafeMutablePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(srv, $0, alen) == 0 && listen(srv, 1) == 0 && getsockname(srv, $0, &alen) == 0 && connect(cli, $0, alen) == 0
            }
        }
        guard ready else { return nil }
        let acc = accept(srv, nil, nil)
        guard acc >= 0 else { return nil }
        defer { close(acc) }
        setsockopt(acc, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        func localPort(_ fd: Int32) -> UInt16? {
            var sa = sockaddr_in(); var l = socklen_t(MemoryLayout<sockaddr_in>.size)
            let ok = withUnsafeMutablePointer(to: &sa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &l) == 0 } }
            return ok ? UInt16(bigEndian: sa.sin_port) : nil
        }
        guard let serverPort = localPort(srv), let clientPort = localPort(cli) else { return nil }

        let data = [UInt8](repeating: 1, count: bytes)
        var buf = [UInt8](repeating: 0, count: 65536)
        var sent = 0, got = 0
        let deadline = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + 1_500_000_000
        while got < bytes {
            guard clock_gettime_nsec_np(CLOCK_UPTIME_RAW) < deadline else { return nil }
            if sent < bytes {
                let n = data[sent...].withUnsafeBytes { send(cli, $0.baseAddress, min($0.count, 65536), MSG_DONTWAIT) }
                if n > 0 { sent += n } else if n < 0, errno != EAGAIN, errno != EINTR { return nil }
            }
            let r = recv(acc, &buf, buf.count, MSG_DONTWAIT)
            if r > 0 { got += r } else if r == 0 { return nil } else if errno != EAGAIN, errno != EINTR { return nil } else if sent == bytes { usleep(200) }
        }
        // Kabul edilen soket: yerel port sunucunun, uzak port istemcinin.
        guard let stats = list("net.inet.tcp.pcblist_n", proto: 6),
              let own = stats.first(where: { $0.pid == getpid() && $0.localPort == serverPort && $0.foreignPort == clientPort }) else { return nil }
        let ratio = Double(own.rxBytes) / Double(bytes)
        if (0.95...1.1).contains(ratio) { return 1 }
        if (1.9...2.2).contains(ratio) { return 2 }
        return nil
    }
}
