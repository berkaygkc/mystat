import Darwin
import Foundation

/// Disk haritasından silme (spec §6.4). Silmeden hemen önce öğenin taramadaki öğe olduğu dosya kimliğiyle (inode)
/// denetlenir; sembolik bağlantının yalnızca kendisi silinir, hedefine dokunulmaz.
public enum FileRemover {
    public enum Result: Sendable, Equatable {
        case removed(bytes: Int64)
        /// Yolda artık başka bir öğe var ya da öğe yok: dokunulmadı.
        case changed
        /// Silme yarıda kaldı; `freed` o ana kadar boşalan alan.
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

    /// Silinince boşalacak alan: klasörde tarayıcıyla (hardlink bir kez, bağlantı izlenmez, dataless sayılmaz), dosyada
    /// ayrılan bloklar. Başka adı da olan dosya (hardlink) silinince yer açılmaz.
    static func allocated(_ url: URL, _ st: stat) -> Int64 {
        switch st.st_mode & S_IFMT {
        case S_IFDIR: return DirectoryScanner(root: url.path, workers: 2).scan(onProgress: { _ in }, isCancelled: { false }).totals()[0]
        case S_IFREG: return st.st_nlink > 1 ? 0 : Int64(st.st_blocks) * 512
        default: return 0
        }
    }
}
