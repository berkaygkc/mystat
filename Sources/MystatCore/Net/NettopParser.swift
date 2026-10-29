import Foundation

/// Bir sürecin aralıktaki ağ trafiği (bayt).
public struct NetBytes: Sendable, Equatable {
    public var inBytes: UInt64, outBytes: UInt64
    public init(inBytes: UInt64, outBytes: UInt64) { self.inBytes = inBytes; self.outBytes = outBytes }
}

/// `nettop -P -L 0 -d -J bytes_in,bytes_out -x` çıktısı: her örnek bir başlık (",bytes_in,bytes_out,") ve
/// `ad.pid,gelen,giden,` satırları. Ad 15 karakterde kesik ve nokta, boşluk, parantez, virgül içerebilir; pid son
/// noktadan sonrası. Örnek bir sonraki başlıkta kapanır. Delta modunda ilk örnek süreçlerin başından birikmiş
/// toplamdır, atlanır.
public struct NettopParser: Sendable {
    private var current: [Int32: NetBytes]?
    private var closed = 0

    public init() {}

    public mutating func feed(_ raw: Substring) -> [Int32: NetBytes]? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix(",bytes_in") {
            defer { current = [:] }
            guard let done = current else { return nil }
            closed += 1
            return closed == 1 ? nil : done
        }
        guard current != nil else { return nil }
        var fields = line.split(separator: ",", omittingEmptySubsequences: false)
        if fields.last?.isEmpty == true { fields.removeLast() }
        guard fields.count >= 3, let out = UInt64(fields[fields.count - 1]), let inn = UInt64(fields[fields.count - 2]) else { return nil }
        let name = fields[..<(fields.count - 2)].joined(separator: ",")
        guard let dot = name.lastIndex(of: "."), let pid = Int32(name[name.index(after: dot)...]) else { return nil }
        let prev = current![pid] ?? NetBytes(inBytes: 0, outBytes: 0)
        current![pid] = NetBytes(inBytes: prev.inBytes &+ inn, outBytes: prev.outBytes &+ out)
        return nil
    }
}

/// Uygulama bazında ↓ hız (spec §6.3 "Kim kullanıyor").
public enum NetRates {
    /// pid başına ↓ MB/s (gelen bayt / aralık, ondalık MB).
    public static func perPid(_ sample: [Int32: NetBytes], interval: Double) -> [Int32: Double] {
        guard interval > 0 else { return [:] }
        return sample.mapValues { Double($0.inBytes) / 1e6 / interval }
    }

    /// Grupların `netMBps`'i o anki pid'lerinden toplanır; gruplarda olmayan pid'ler yok sayılır.
    public static func apply(_ rates: [Int32: Double], to groups: inout [ProcessGroup]) {
        for i in groups.indices { groups[i].netMBps = groups[i].pids.reduce(0) { $0 + (rates[$1] ?? 0) } }
    }
}
