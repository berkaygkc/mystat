import Foundation

public enum SelState: Sendable, Equatable { case none, selected, implied }
public enum DeleteMode: Sendable, Equatable { case permanent, trash }
public enum ToggleResult: Sendable, Equatable { case added, removed, blockedByAncestor, notSelectable }

public struct BasketItem: Sendable, Equatable {
    public let path: [String]
    public let name: String
    public let size: Double
    public let kind: NodeKind
    /// Tarama ağacında dosya sistemi kimliği; silmeden önce öğenin değişmediği bununla denetlenir.
    public let fileID: UInt64?

    public init(path: [String], name: String, size: Double, kind: NodeKind, fileID: UInt64? = nil) {
        self.path = path; self.name = name; self.size = size; self.kind = kind; self.fileID = fileID
    }
}

/// Disk haritasının toplu seçim sepeti (spec §6.4). Hiçbir öğe iki kez sayılmaz.
public struct SelectionBasket: Sendable, Equatable {
    private var map: [String: BasketItem] = [:]
    public init() {}

    private static func key(_ p: [String]) -> String { p.joined(separator: "/") }

    @MainActor
    public mutating func toggle(_ path: [String], in tree: DiskTree) -> ToggleResult {
        guard DeletionGuard.reason(path: path) == nil, let n = tree.node(at: path), n.kind != .other else { return .notSelectable }
        let k = Self.key(path)
        switch state(of: path) {
        case .implied: return .blockedByAncestor
        case .selected: map[k] = nil; return .removed
        case .none:
            for d in map.keys where d.hasPrefix(k + "/") { map[d] = nil }
            map[k] = BasketItem(path: path, name: n.name, size: n.size, kind: n.kind, fileID: n.fileID)
            return .added
        }
    }

    public func state(of path: [String]) -> SelState {
        if map[Self.key(path)] != nil { return .selected }
        for i in 1..<max(1, path.count) where map[Self.key(Array(path.prefix(i)))] != nil { return .implied }
        return .none
    }

    public var items: [BasketItem] { map.values.sorted { $0.size > $1.size } }
    public var totalGB: Double { map.values.reduce(0) { $0 + $1.size } }
    public var isEmpty: Bool { map.isEmpty }
    public mutating func clear() { map.removeAll() }
    public mutating func remove(_ path: [String]) { map[Self.key(path)] = nil }

    public func buttonTitle(mode: DeleteMode) -> String {
        let n = map.count
        if n > 1 { return "\(n) öğeyi " + (mode == .permanent ? "kalıcı sil" : "çöpe taşı") }
        return mode == .permanent ? "Kalıcı olarak sil" : "Çöpe taşı"
    }

    public func confirmMessage(mode: DeleteMode) -> String {
        let list = items
        var prefix = ""
        if list.count > 1 {
            prefix = list.prefix(3).map(\.name).joined(separator: ", ") + (list.count > 3 ? " ve \(list.count - 3) öğe daha" : "") + ". "
        }
        let tail = mode == .permanent ? " yer hemen boşalacak. Bu işlem geri alınamaz." : " çöpe gidecek; çöpü boşaltana kadar geri alabilirsin."
        return prefix + Fmt.size(totalGB) + tail
    }

    public func confirmTitle(mode: DeleteMode) -> String {
        let subject = map.count > 1 ? "\(map.count) öğe" : (items.first?.name ?? "")
        return subject + (mode == .permanent ? " kalıcı olarak silinsin mi?" : " çöpe taşınsın mı?")
    }
}
