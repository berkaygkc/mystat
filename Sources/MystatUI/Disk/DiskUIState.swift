import MystatCore
import Observation
import SwiftUI

/// State of the Disk section: location, bulk selection, delete mode. Scanning belongs to the source (`MetricsSource.diskScan`).
@MainActor @Observable
public final class DiskUIState {
    public var path: [String] = []
    public var basket = SelectionBasket()
    public var mode: DeleteMode = .permanent
    public var freedGB: Double = 0
    public var hoverName: String?
    /// Incremented after a deletion so the map re-lays out.
    public private(set) var relayoutToken = 0
    /// Navigation is ignored while the map is transitioning; the map's model writes this.
    @ObservationIgnored public internal(set) var isMapAnimating = false

    public init() {}

    public func toggle(_ p: [String], tree: DiskTree) {
        switch basket.toggle(p, in: tree) {
        case .blockedByAncestor: ToastCenter.shared.show(L10n.t("disk.toast.parentSelected"))
        case .notSelectable: if let r = DeletionGuard.reason(path: p) { ToastCenter.shared.show(r) }
        case .added, .removed: break
        }
    }

    public func open(_ p: [String]) {
        guard !isMapAnimating else { return }
        path = p
    }

    /// Has the source delete everything in the basket; if the current folder was deleted, moves up to the closest existing ancestor.
    public func performDelete(tree: DiskTree, source: some MetricsSource) async {
        if case .scanning = source.diskScan { ToastCenter.shared.show(Self.busyText); return }
        let items = basket.items, mode = mode
        basket.clear()
        ToastCenter.shared.show(L10n.t(mode == .trash ? "disk.toast.trashing" : "disk.toast.deleting"))
        let out = await source.delete(items, mode: mode)
        if mode == .permanent { freedGB += out.freedGB }   // moving to the Trash does not free space
        var p = path
        while !p.isEmpty, tree.node(at: p) == nil { p.removeLast() }
        path = p
        relayoutToken += 1
        ToastCenter.shared.show(out.toast(trash: mode == .trash))
    }

    static var busyText: String { L10n.t("disk.busy") }

    public func confirmDelete(tree: DiskTree, source: some MetricsSource) -> ConfirmRequest? {
        guard !basket.isEmpty else { return nil }
        if case .scanning = source.diskScan { ToastCenter.shared.show(Self.busyText); return nil }
        let perm = mode == .permanent
        return ConfirmRequest(title: basket.confirmTitle(mode: mode), message: basket.confirmMessage(mode: mode),
                              confirm: L10n.t(perm ? "disk.button.permanent" : "disk.button.trash"), destructive: perm,
                              onConfirm: { [weak self] in Task { await self?.performDelete(tree: tree, source: source) } })
    }
}
