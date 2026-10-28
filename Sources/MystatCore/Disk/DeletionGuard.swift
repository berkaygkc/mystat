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
        return "\(path.last ?? "Ev klasörü") macOS için gerekli; içindekileri seçebilirsin."
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
            parts.append(Fmt.size(freedGB) + (trash ? " çöpe taşındı" : " boşaldı") + (simulated ? " (örnek)" : ""))
        }
        if !failed.isEmpty { parts.append("\(failed.count) öğe silinemedi") }
        if !changed.isEmpty { parts.append("\(changed.count) öğe taramadan sonra değişmiş; yeniden tara") }
        return parts.joined(separator: " · ")
    }
}
