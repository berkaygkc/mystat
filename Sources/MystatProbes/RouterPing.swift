import Darwin
import Foundation

/// Latency to the router (not to an external server). Uses an ICMP socket that needs no root (`SOCK_DGRAM`).
public enum RouterPing {
    /// nil if there is no reply, the address is invalid, or time runs out. In milliseconds.
    public static func ping(_ ipv4: String, timeout: TimeInterval = 1) -> Double? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ipv4, &addr.sin_addr) == 1 else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let seq = UInt16.random(in: 1...UInt16.max), ident = UInt16(truncatingIfNeeded: getpid())
        var pkt = [UInt8](repeating: 0, count: 16)
        pkt[0] = 8   // echo request
        pkt[4] = UInt8(ident >> 8); pkt[5] = UInt8(ident & 0xff); pkt[6] = UInt8(seq >> 8); pkt[7] = UInt8(seq & 0xff)
        var sum: UInt32 = 0
        for i in stride(from: 0, to: pkt.count, by: 2) { sum += UInt32(pkt[i]) << 8 | UInt32(pkt[i + 1]) }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        let check = ~UInt16(sum); pkt[2] = UInt8(check >> 8); pkt[3] = UInt8(check & 0xff)

        let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let deadline = t0 + UInt64(timeout * 1e9)
        let sent = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, pkt, pkt.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard sent == pkt.count else { return nil }
        var buf = [UInt8](repeating: 0, count: 512)
        while true {
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            guard now < deadline else { return nil }
            let left = deadline - now
            var tv = timeval(tv_sec: Int(left / 1_000_000_000), tv_usec: Int32((left % 1_000_000_000) / 1000))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let n = recv(fd, &buf, buf.count, 0)
            guard n > 0 else { return nil }   // timed out or error
            // The reply arrives with the IP header (first nibble 4); skip to the ICMP header.
            let off = buf[0] >> 4 == 4 ? Int(buf[0] & 0x0f) * 4 : 0
            guard n >= off + 8, buf[off] == 0, buf[off + 6] == pkt[6], buf[off + 7] == pkt[7] else { continue }   // a different reply
            return Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0) / 1e6
        }
    }
}
