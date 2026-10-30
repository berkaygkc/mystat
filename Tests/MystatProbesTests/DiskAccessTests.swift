import Foundation
import Testing
@testable import MystatProbes

@Suite struct DiskAccessTests {
    /// The value depends on the environment (Terminal's Full Disk Access); it returns a Bool without triggering a permission prompt.
    @Test func fdaProbeDoesNotCrash() {
        let a = DiskAccess.hasFullDiskAccess(), b = DiskAccess.hasFullDiskAccess()
        #expect(a == b)
        #expect(DiskAccess.settingsURL.scheme == "x-apple.systempreferences")
    }

    @Test func promptFolders() {
        for p in ["Desktop", "Documents", "Downloads", "Library/Containers", "Library/Group Containers", "Library/Mobile Documents",
                  "Library/CloudStorage", "Library/Mail", "Library/Reminders", "Library/Calendars", "Pictures/Fotoğraflar.photoslibrary"] {
            #expect(DiskAccess.promptsWithoutAccess(p), "\(p)")
        }
        for p in ["", "Library", "Library/Caches", "Documents/proje", "Pictures", ".npm"] { #expect(!DiskAccess.promptsWithoutAccess(p), "\(p)") }
    }
}
