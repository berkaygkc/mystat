import Darwin
import Foundation

/// Docker's virtual disk file (`Docker.raw`) is a sparse file: use the space it occupies on disk, not its apparent size (1 TB).
/// Since it lives in another app's container, reading it may trigger a macOS permission prompt; the caller reads it only while the Docker section is open.
public enum DockerDiskFile {
    public static let defaultPath = NSHomeDirectory() + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"

    /// `st_blocks × 512` (decimal GB); nil if unreadable.
    public static func allocatedGB(path: String = defaultPath) -> Double? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Double(st.st_blocks) * 512 / 1e9
    }
}
