import Foundation

public struct Crumb: Sendable, Equatable {
    public let name: String
    public let path: [String]
    public let isEllipsis: Bool
}

/// Disk path: if it exceeds 6 parts, "Home › … › last 4".
public enum Breadcrumbs {
    public static func make(_ path: [String]) -> [Crumb] {
        let all = [Crumb(name: L10n.t("disk.home"), path: [], isEllipsis: false)]
            + path.indices.map { Crumb(name: path[$0], path: Array(path[...$0]), isEllipsis: false) }
        guard all.count > 6 else { return all }
        let hidden = all[1..<(all.count - 4)]
        return [all[0], Crumb(name: "…", path: hidden.last!.path, isEllipsis: true)] + all.suffix(4)
    }
}
