/// Which fields the source can actually measure. Fields that are not wired up show no fake numbers;
/// the presentation layer writes a calm "not connected" text instead.
public struct SourceCapabilities: Sendable, Equatable {
    public var docker: Bool
    public var sensors: Bool
    public var diskScan: Bool
    public var netDetails: Bool

    public init(docker: Bool, sensors: Bool, diskScan: Bool, netDetails: Bool) {
        self.docker = docker; self.sensors = sensors; self.diskScan = diskScan; self.netDetails = netDetails
    }

    public static let all = SourceCapabilities(docker: true, sensors: true, diskScan: true, netDetails: true)
}

public extension Level {
    /// The thermal state's wording when there is no sensor.
    var thermalWord: String { L10n.t("thermal.\(self == .ok ? "ok" : self == .warn ? "warn" : "crit")") }
}
