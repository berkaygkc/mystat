/// Kaynağın hangi alanları gerçekten ölçebildiği. Bağlanmamış alanlar sahte sayı göstermez;
/// sunum katmanı sakin "bağlı değil" metni yazar (Faz 2a: Docker 2b, sensörler 2c, disk taraması 2d, ağ ayrıntısı 2e).
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
    /// Sensör yokken termal durumun sözcüğü.
    var thermalWord: String { L10n.t("thermal.\(self == .ok ? "ok" : self == .warn ? "warn" : "crit")") }
}
