import Foundation

/// Uyarı seviyesi. Renkler: ok renksiz, warn turuncu, crit kırmızı.
public enum Level: Sendable, Equatable, Comparable {
    case ok, warn, crit
}

/// Anlık değerden seviye (spec §7.2). Süreklilik kuralları Faz 2'de uyarı motorunda.
public enum Thresholds {
    public static func cpuTotal(_ pct: Double) -> Level { pct >= 85 ? .crit : pct >= 70 ? .warn : .ok }
    public static func groupCores(_ c: Double) -> Level { c >= 4 ? .crit : c >= 2 ? .warn : .ok }
    public static func diskFree(_ gb: Double) -> Level { gb < 10 ? .crit : gb < 20 ? .warn : .ok }
    public static func dockerContainer(_ pct: Double) -> Level { pct >= 50 ? .warn : .ok }
}
