import Darwin
import Foundation
import MystatCore

/// Tam Disk Erişimi algılama. Yalnızca bu izinle açılabilen bir yol denenir; izin istemi çıkmaz.
public enum DiskAccess {
    static let probes = [NSHomeDirectory() + "/Library/Safari", "/Library/Application Support/com.apple.TCC/TCC.db"]
    public static let settingsURL = DiskPresentation.settingsURL

    public static func hasFullDiskAccess() -> Bool {
        for p in probes {
            let fd = open(p, O_RDONLY | O_CLOEXEC)
            if fd >= 0 { close(fd); return true }
            if errno == EPERM || errno == EACCES { return false }
        }
        return false   // hiçbiri yok: bilinmiyor, not gösterilir
    }
}
