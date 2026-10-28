import Darwin
import Foundation

/// Docker'ın sanal disk dosyası (`Docker.raw`) seyrek dosyadır: görünen boyutu (1 TB) değil, diskte kapladığı alan.
/// Başka uygulamanın kabında durduğu için okuma macOS izin istemi çıkarabilir; çağıran yalnızca Docker bölümü açıkken okur.
public enum DockerDiskFile {
    public static let defaultPath = NSHomeDirectory() + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"

    /// `st_blocks × 512` (ondalık GB); okunamazsa nil.
    public static func allocatedGB(path: String = defaultPath) -> Double? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Double(st.st_blocks) * 512 / 1e9
    }
}
