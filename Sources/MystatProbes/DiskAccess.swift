import Darwin
import Foundation
import MystatCore

/// Tam Disk Erişimi algılama. Yalnızca bu izinle açılabilen bir yol denenir; izin istemi çıkmaz.
public enum DiskAccess {
    static let probes = [NSHomeDirectory() + "/Library/Safari", "/Library/Application Support/com.apple.TCC/TCC.db"]
    public static let settingsURL = DiskPresentation.settingsURL

    /// İzinsizken açılınca TCC istemi çıkarabilecek klasörler (ev köküne göre): Dosyalar ve Klasörler, iCloud Drive ve
    /// dosya sağlayıcıları, başka uygulamaların verileri, Kişiler/Takvimler/Anımsatıcılar, Mail, Mesajlar, Fotoğraflar.
    /// Tam Disk Erişimi yokken taranmaz, okunamayan sayılır (§10).
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
        return false   // hiçbiri yok: bilinmiyor, not gösterilir
    }
}
