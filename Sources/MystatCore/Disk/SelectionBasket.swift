import Foundation

public enum SelState: Sendable, Equatable { case none, selected, implied }
public enum DeleteMode: Sendable, Equatable { case permanent, trash }
public enum ToggleResult: Sendable, Equatable { case added, removed, blockedByAncestor, notSelectable }

public struct BasketItem: Sendable, Equatable {
    public let path: [String]
    public let name: String
    public let size: Double
    public let kind: NodeKind
    /// Filesystem identity in the scan tree; used to check that the item has not changed before deletion.
    public let fileID: UInt64?
    /// Number of cloud-only items inside (for the warning before deletion).
    public let cloudItems: Int

    public init(path: [String], name: String, size: Double, kind: NodeKind, fileID: UInt64? = nil, cloudItems: Int = 0) {
        self.path = path; self.name = name; self.size = size; self.kind = kind; self.fileID = fileID; self.cloudItems = cloudItems
    }
}

/// Bulk selection basket of the disk map. No item is counted twice.
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
            map[k] = BasketItem(path: path, name: n.name, size: n.size, kind: n.kind, fileID: n.fileID, cloudItems: n.cloudItems)
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
    public var cloudItems: Int { map.values.reduce(0) { $0 + $1.cloudItems } }
    public mutating func clear() { map.removeAll() }
    public mutating func remove(_ path: [String]) { map[Self.key(path)] = nil }

    public func buttonTitle(mode: DeleteMode) -> String {
        let n = map.count
        if n > 1 { return L10n.t(mode == .permanent ? "disk.button.permanentMany" : "disk.button.trashMany", ["n": String(n)]) }
        return L10n.t(mode == .permanent ? "disk.button.permanent" : "disk.button.trash")
    }

    public func confirmMessage(mode: DeleteMode) -> String {
        let list = items
        var prefix = ""
        if list.count > 1 {
            prefix = list.prefix(3).map(\.name).joined(separator: ", ") + (list.count > 3 ? L10n.plural("disk.confirm.more", list.count - 3) : "") + ". "
        }
        let body = L10n.t(mode == .permanent ? "disk.confirm.permanent" : "disk.confirm.trash", ["size": Fmt.size(totalGB)])
        let cloud = cloudItems > 0
            ? L10n.plural(mode == .permanent ? "disk.confirm.cloudPermanent" : "disk.confirm.cloudTrash", cloudItems, ["n": Fmt.int(Double(cloudItems))])
            : ""
        return prefix + body + cloud
    }

    public func confirmTitle(mode: DeleteMode) -> String {
        let subject = map.count > 1 ? L10n.plural("disk.items", map.count) : (items.first?.name ?? "")
        return L10n.t(mode == .permanent ? "disk.confirm.title.permanent" : "disk.confirm.title.trash", ["subject": subject])
    }
}
