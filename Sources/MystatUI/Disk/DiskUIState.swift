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
        if basket.toggle(p, in: tree) == .blockedByAncestor { ToastCenter.shared.show("Üst klasörü zaten seçili") }
    }

    public func open(_ p: [String]) {
        guard !isMapAnimating else { return }
        path = p
    }

    /// Sepetteki her şeyi örnek ağaçtan siler; bulunduğun klasör silindiyse var olan en yakın üst klasöre çıkar.
    public func performDelete(tree: DiskTree, source: some MetricsSource) {
        let items = basket.items.sorted { $0.path.count > $1.path.count }
        let total = items.reduce(0) { $0 + tree.remove(at: $1.path) }
        let wasTrash = mode == .trash
        basket.clear()
        freedGB += total
        source.applyDeletion(gb: total)
        var p = path
        while !p.isEmpty, tree.node(at: p) == nil { p.removeLast() }
        path = p
        relayoutToken += 1
        ToastCenter.shared.show("\(Fmt.size(total)) " + (wasTrash ? "çöpe taşındı (örnek)" : "boşaldı (örnek)"))
    }

    public func confirmDelete(tree: DiskTree, source: some MetricsSource) -> ConfirmRequest? {
        guard !basket.isEmpty else { return nil }
        let perm = mode == .permanent
        return ConfirmRequest(title: basket.confirmTitle(mode: mode), message: basket.confirmMessage(mode: mode),
                              confirm: perm ? "Kalıcı olarak sil" : "Çöpe taşı", destructive: perm,
                              onConfirm: { [weak self] in self?.performDelete(tree: tree, source: source) })
    }
}
