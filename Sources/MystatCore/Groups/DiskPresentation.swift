import Foundation

/// Disk haritasının erişim notları (spec §6.4).
public enum DiskPresentation {
    /// Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// Tarama öncesi: Tam Disk Erişimi yoksa ne olacağı. Tarama sonrası: okunamayan klasör varsa sayısı.
    public static func accessNote(fullDiskAccess: Bool, scanned: Bool, inaccessible: Int) -> String? {
        if scanned { return inaccessible > 0 ? "\(Fmt.int(Double(inaccessible))) klasör okunamadı (macOS korumalı)" : nil }
        return fullDiskAccess ? nil : "Tam tarama için mystat'a Tam Disk Erişimi ver. Vermezsen korumalı klasörler atlanır."
    }
}
