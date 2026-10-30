import Foundation

/// Access notes for the disk map.
public enum DiskPresentation {
    /// System Settings → Privacy & Security → Full Disk Access.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// Before a scan: what happens without Full Disk Access. After a scan: the number of unreadable folders, if any.
    public static func accessNote(fullDiskAccess: Bool, scanned: Bool, inaccessible: Int) -> String? {
        if scanned { return inaccessible > 0 ? L10n.plural("disk.access.unreadable", inaccessible, ["n": Fmt.int(Double(inaccessible))]) : nil }
        return fullDiskAccess ? nil : L10n.t("disk.access.needFDA")
    }
}
