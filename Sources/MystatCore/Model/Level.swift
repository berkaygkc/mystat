import Foundation

/// Alert level. Colors: ok uncolored, warn orange, crit red.
public enum Level: Sendable, Equatable, Comparable {
    case ok, warn, crit
}

/// Level from an instantaneous value. Sustain rules live in the incident engine.
public enum Thresholds {
    public static func cpuTotal(_ pct: Double) -> Level { pct >= 85 ? .crit : pct >= 70 ? .warn : .ok }
    public static func groupCores(_ c: Double) -> Level { c >= 4 ? .crit : c >= 2 ? .warn : .ok }
    public static func diskFree(_ gb: Double) -> Level { gb < 10 ? .crit : gb < 20 ? .warn : .ok }
    public static func dockerContainer(_ pct: Double) -> Level { pct >= 50 ? .warn : .ok }
}
