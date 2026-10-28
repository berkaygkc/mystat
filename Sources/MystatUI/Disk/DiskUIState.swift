import MystatCore
import Observation
import SwiftUI

/// Disk bölümünün durumu: konum, toplu seçim, silme modu (spec §6.4). Tarama kaynağın (`MetricsSource.diskScan`).
@MainActor @Observable
public final class DiskUIState {
    public var path: [String] = []
    public var basket = SelectionBasket()
    public var mode: DeleteMode = .permanent
    public var freedGB: Double = 0
    public var hoverName: String?
    /// Silme sonrası harita yeniden yerleşsin diye artar.
    public private(set) var relayoutToken = 0
    /// Harita geçiş yaparken gezinme yok sayılır (mockup `openDisk`); haritanın modeli yazar.
    @ObservationIgnored public internal(set) var isMapAnimating = false

    public init() {}

    public func toggle(_ p: [String], tree: DiskTree) {
        switch basket.toggle(p, in: tree) {
        case .blockedByAncestor: ToastCenter.shared.show("Üst klasörü zaten seçili")
        case .notSelectable: if let r = DeletionGuard.reason(path: p) { ToastCenter.shared.show(r) }
        case .added, .removed: break
        }
    }

    public func open(_ p: [String]) {
        guard !isMapAnimating else { return }
        path = p
    }

    /// Sepetteki her şeyi kaynağa sildirir; bulunduğun klasör silindiyse var olan en yakın üst klasöre çıkar.
    public func performDelete(tree: DiskTree, source: some MetricsSource) async {
        let items = basket.items, mode = mode
        basket.clear()
        ToastCenter.shared.show(mode == .trash ? "Çöpe taşınıyor…" : "Siliniyor…")
        let out = await source.delete(items, mode: mode)
        freedGB += out.freedGB
        var p = path
        while !p.isEmpty, tree.node(at: p) == nil { p.removeLast() }
        path = p
        relayoutToken += 1
        ToastCenter.shared.show(out.toast(trash: mode == .trash))
    }

    public func confirmDelete(tree: DiskTree, source: some MetricsSource) -> ConfirmRequest? {
        guard !basket.isEmpty else { return nil }
        let perm = mode == .permanent
        return ConfirmRequest(title: basket.confirmTitle(mode: mode), message: basket.confirmMessage(mode: mode),
                              confirm: perm ? "Kalıcı olarak sil" : "Çöpe taşı", destructive: perm,
                              onConfirm: { [weak self] in Task { await self?.performDelete(tree: tree, source: source) } })
    }
}
