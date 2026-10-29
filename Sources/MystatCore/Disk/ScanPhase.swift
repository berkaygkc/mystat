import Foundation

/// Disk taraması: yalnızca elle başlar, 1 saat geçerlidir (spec §6.4).
public enum ScanPhase: Sendable, Equatable {
    case none
    case scanning(progress: Double, scannedGB: Double, currentPath: String)
    case ready(scannedAt: Date)

    public static let validity: TimeInterval = 3600

    public func effective(now: Date) -> ScanPhase {
        if case .ready(let at) = self, now.timeIntervalSince(at) >= Self.validity { return .none }
        return self
    }

    public func validityText(now: Date) -> String? {
        guard case .ready(let at) = effective(now: now) else { return nil }
        let minutes = Int(((Self.validity - now.timeIntervalSince(at)) / 60).rounded(.up))
        return L10n.t("disk.scan.validity", ["m": String(minutes)])
    }
}
