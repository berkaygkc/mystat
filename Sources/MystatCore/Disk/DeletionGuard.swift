import Foundation

/// Haritadan silinemeyecek klasörler (spec §6.4). Klasörün kendisi korunur; içindekiler seçilebilir.
/// Yollar ev köküne göre; boş yol ev klasörünün kendisi.
public enum DeletionGuard {
    public static let protected: Set<String> = [
        "", "Library", "Library/Application Support", "Library/Preferences", "Library/Keychains", "Library/Containers",
        "Library/Group Containers", "Library/Mobile Documents", "Library/Mail", "Library/Messages",
        "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Applications", "Public",
    ]

    /// nil: silinebilir; aksi halde kullanıcıya gösterilecek neden.
    public static func reason(path: [String]) -> String? {
        guard protected.contains(path.joined(separator: "/")) else { return nil }
        return L10n.t("disk.protected", ["name": path.last ?? L10n.t("disk.homeFolder")])
    }
}

/// Silmenin sonucu: boşalan alan, silinemeyenler ve taramadan sonra değiştiği için dokunulmayanlar.
public struct DeleteOutcome: Sendable, Equatable {
    public let freedGB: Double
    public let failed: [String]
    public let changed: [String]
    /// Örnek veride benzetim.
    public let simulated: Bool

    public init(freedGB: Double, failed: [String], changed: [String], simulated: Bool = false) {
        self.freedGB = freedGB; self.failed = failed; self.changed = changed; self.simulated = simulated
    }

    public func toast(trash: Bool) -> String {
        var parts: [String] = []
        if freedGB > 0 || (failed.isEmpty && changed.isEmpty) {
            parts.append(L10n.t(trash ? "disk.toast.trashed" : "disk.toast.freed", ["size": Fmt.size(freedGB)]) + (simulated ? L10n.t("disk.toast.sample") : ""))
        }
        if !failed.isEmpty { parts.append(L10n.plural("disk.toast.failed", failed.count)) }
        if !changed.isEmpty { parts.append(L10n.plural("disk.toast.changed", changed.count)) }
        return parts.joined(separator: " · ")
    }
}
