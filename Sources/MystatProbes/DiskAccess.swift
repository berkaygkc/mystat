import Darwin
import Foundation
import MystatCore

/// Full Disk Access detection. Tries a path that can only be opened with this permission; no permission prompt appears.
public enum DiskAccess {
    static let probes = [NSHomeDirectory() + "/Library/Safari", "/Library/Application Support/com.apple.TCC/TCC.db"]
    public static let settingsURL = DiskPresentation.settingsURL

    /// Folders that could trigger a TCC prompt if opened without permission (relative to the home root): Files and Folders, iCloud Drive and
    /// file providers, other apps' data, Contacts/Calendars/Reminders, Mail, Messages, Photos.
    /// Not scanned without Full Disk Access; they count as unreadable.
    static let promptPaths: Set<String> = [
        "Desktop", "Documents", "Downloads", "Library/Mobile Documents", "Library/CloudStorage",
        "Library/Containers", "Library/Group Containers", "Library/Application Support/AddressBook",
        "Library/Calendars", "Library/Reminders", "Library/Mail", "Library/Messages", "Library/Safari",
    ]

    public static func promptsWithoutAccess(_ relativePath: String) -> Bool {
        promptPaths.contains(relativePath) || relativePath.hasSuffix(".photoslibrary")
    }

    public static func hasFullDiskAccess() -> Bool {
        for p in probes {
            let fd = open(p, O_RDONLY | O_CLOEXEC)
            if fd >= 0 { close(fd); return true }
            if errno == EPERM || errno == EACCES { return false }
        }
        return false   // none exist: unknown, the note is shown
    }
}
