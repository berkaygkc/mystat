import Darwin
import Foundation

/// Deletion from the disk map. Right before deleting, the item is checked against the file identity (inode) of the item in the scan;
/// for a symbolic link only the link itself is deleted, its target is not touched.
public enum FileRemover {
    public enum Result: Sendable, Equatable {
        case removed(bytes: Int64)
        /// The path now holds a different item or nothing: left untouched.
        case changed
        /// Deletion was interrupted; `freed` is the space freed so far.
        case failed(String, freed: Int64)
    }

    public static func remove(_ url: URL, expectedFileID: UInt64, toTrash: Bool,
                              trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> Result {
        var st = stat()
        guard lstat(url.path, &st) == 0 else {
            return errno == ENOENT || errno == ENOTDIR ? .changed : .failed(String(cString: strerror(errno)), freed: 0)
        }
        guard UInt64(st.st_ino) == expectedFileID else { return .changed }
        let bytes = allocated(url, st)
        do {
            if toTrash { try trash(url) } else { try FileManager.default.removeItem(at: url) }
            return .removed(bytes: bytes)
        } catch {
            var after = stat()
            let left = lstat(url.path, &after) == 0 ? allocated(url, after) : 0
            return .failed(error.localizedDescription, freed: max(0, bytes - left))
        }
    }

    /// Space that deleting would free: for a folder, computed with the scanner (hardlink once, links not followed, dataless not counted); for a file,
    /// the allocated blocks. Deleting a file that has another name too (hardlink) frees no space.
    static func allocated(_ url: URL, _ st: stat) -> Int64 {
        switch st.st_mode & S_IFMT {
        case S_IFDIR: return DirectoryScanner(root: url.path, workers: 2).scan(onProgress: { _ in }, isCancelled: { false }).totals()[0]
        case S_IFREG: return st.st_nlink > 1 ? 0 : Int64(st.st_blocks) * 512
        default: return 0
        }
    }
}
