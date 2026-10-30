import Foundation

/// Folders that cannot be deleted from the map. The folder itself is protected; its contents can be selected.
/// Paths are relative to the home root; the empty path is the home folder itself.
public enum DeletionGuard {
    public static let protected: Set<String> = [
        "", "Library", "Library/Application Support", "Library/Preferences", "Library/Keychains", "Library/Containers",
        "Library/Group Containers", "Library/Mobile Documents", "Library/Mail", "Library/Messages",
        "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Applications", "Public",
    ]

    /// nil: deletable; otherwise the reason to show the user.
    public static func reason(path: [String]) -> String? {
        guard protected.contains(path.joined(separator: "/")) else { return nil }
        return L10n.t("disk.protected", ["name": path.last ?? L10n.t("disk.homeFolder")])
    }
}

/// Result of a deletion: freed space, items that could not be deleted, and items left untouched because they changed after the scan.
public struct DeleteOutcome: Sendable, Equatable {
    public let freedGB: Double
    public let failed: [String]
    public let changed: [String]
    /// Simulated in sample data.
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
