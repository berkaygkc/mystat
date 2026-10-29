import Darwin
import Foundation
import MystatCore

/// Uygulama bazında ağ (spec §9.1 "nettop ya da eşdeğeri"): çekirdeğin soket listesi, `netstat`'ın kaynağı
/// (`net.inet.tcp.pcblist_n`, `net.inet.udp.pcblist_n`). `nettop` bu makinede Ağ bölümü açıkken dakikada ≈ 35 sn
/// işlemci tutuyordu; bu okuma 2 sn tempoda dakikada ≈ 0,02 sn (ölçüldü, 2026-10-29).
///
/// Kayıtlar SDK'da yok (xnu, 4 bayta paketli; macOS 26'da doğrulandı): her kayıt `{u32 uzunluk, u32 tür, …}`, 8'e
/// yuvarlı. `xsocket_n` 104 bayt, sahibin pid'i 68'de, etkin pid 72'de; `xsockstat_n` 136 bayt, 4 trafik sınıfının her
/// biri `{rxpackets, rxbytes, txpackets, txbytes}`. Kayıt boyu beklenenden farklıysa (düzen değişmiş) okuma hiç sonuç
/// vermez; yanlış sayı gösterilmez.
public enum SocketStatsProbe {
    static let socketKind: UInt32 = 0x001, statsKind: UInt32 = 0x008
    static let socketLen = 104, statsLen = 136
    static let lastPidOffset = 68, effectivePidOffset = 72, classCount = 4, classStride = 32, rxInClass = 8

    /// Tüm TCP ve UDP soketleri; okunamazsa ya da düzen beklenenden farklıysa nil.
    public static func read() -> [SocketStat]? {
        guard let tcp = list("net.inet.tcp.pcblist_n"), let udp = list("net.inet.udp.pcblist_n") else { return nil }
        return tcp + udp
    }

    static func list(_ name: String) -> [SocketStat]? {
        for _ in 0..<3 {   // okumalar arasında soket açılırsa tampon küçük kalabilir
            var len = 0
            guard sysctlbyname(name, nil, &len, nil, 0) == 0 else { return nil }
            len += len / 4 + 4096
            var buf = [UInt8](repeating: 0, count: len)
            if sysctlbyname(name, &buf, &len, nil, 0) == 0 { return buf.withUnsafeBytes { parse(UnsafeRawBufferPointer(rebasing: $0[..<len])) } }
            guard errno == ENOMEM else { return nil }
        }
        return nil
    }

    static func parse(_ raw: UnsafeRawBufferPointer) -> [SocketStat]? {
        guard raw.count >= 24 else { return nil }
        func u32(_ o: Int) -> UInt32 { raw.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
        func u64(_ o: Int) -> UInt64 { raw.loadUnaligned(fromByteOffset: o, as: UInt64.self) }
        func i32(_ o: Int) -> Int32 { raw.loadUnaligned(fromByteOffset: o, as: Int32.self) }
        func round8(_ v: Int) -> Int { (v + 7) & ~7 }
        var out: [SocketStat] = []
        var owner: (handle: UInt64, pid: Int32)?
        var off = round8(Int(u32(0)))
        while off + 8 <= raw.count {
            let len = Int(u32(off)), kind = u32(off + 4)
            guard len >= 8, off + len <= raw.count else { break }
            let last = off + round8(len) >= raw.count   // sondaki xinpgen: ikinci alanı soket sayısı, türle karışabilir
            switch kind {
            case socketKind:
                guard len == socketLen else { if last { break } else { return nil } }
                let e = i32(off + effectivePidOffset)
                owner = (u64(off + 8), e != 0 ? e : i32(off + lastPidOffset))
            case statsKind:
                guard len == statsLen else { if last { break } else { return nil } }
                if let o = owner {
                    var rx: UInt64 = 0
                    for c in 0..<classCount { rx &+= u64(off + 8 + c * classStride + rxInClass) }
                    out.append(SocketStat(handle: o.handle, pid: o.pid, rxBytes: rx))
                    owner = nil
                }
            default: break
            }
            off += round8(len)
        }
        return out
    }

    /// Çekirdek alınan baytı kaç kez sayıyor: loopback'te 256 KB TCP aktarımıyla ölçülür (macOS 26'da 2). Aynı ölçüm
    /// kayıt düzenini de doğrular: kendi soketimiz bulunamazsa ya da oran 1 ya da 2'ye yakın değilse nil.
    public static func receiveFactor() -> Double? {
        let bytes = 256 * 1024
        let srv = socket(AF_INET, SOCK_STREAM, 0), cli = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(srv); close(cli) }
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1")
        var alen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(srv, $0, alen) == 0 && listen(srv, 1) == 0 && getsockname(srv, $0, &alen) == 0 }
        }
        guard srv >= 0, cli >= 0, bound else { return nil }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        for fd in [srv, cli] { setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size)) }
        guard withUnsafePointer(to: &a, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(cli, $0, alen) } }) == 0 else { return nil }
        let acc = accept(srv, nil, nil)
        guard acc >= 0 else { return nil }
        defer { close(acc) }
        setsockopt(acc, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        // Gönderen ayrı iş parçacığında (alıcı okumadıkça gönderme tamponu dolar).
        let sender = Thread {
            let data = [UInt8](repeating: 1, count: bytes)
            var off = 0
            while off < bytes { let n = data[off...].withUnsafeBytes { send(cli, $0.baseAddress, $0.count, 0) }; if n <= 0 { break }; off += n }
        }
        sender.start()
        var buf = [UInt8](repeating: 0, count: 65536), got = 0
        while got < bytes { let n = recv(acc, &buf, buf.count, 0); if n <= 0 { break }; got += n }
        guard got == bytes, let stats = list("net.inet.tcp.pcblist_n") else { return nil }
        let rx = stats.filter { $0.pid == getpid() }.map(\.rxBytes).max() ?? 0
        let ratio = Double(rx) / Double(bytes)
        if (0.95...1.1).contains(ratio) { return 1 }
        if (1.9...2.2).contains(ratio) { return 2 }
        return nil
    }
}
