import AppKit
import MystatCore
import Observation
import SwiftUI

/// Monitör penceresinin gezinme ve seçim durumu.
@MainActor @Observable
public final class MonitorState {
    public var section: MonitorSection = .overview
    public var range: TimeRange = .m10
    public var selected: [GroupMetric: String] = [.cpu: "claude-acmecorp", .memory: "docker", .network: "docker"]
    public var expanded: Set<String> = ["claude-acmecorp"]
    public var confirm: ConfirmRequest?
    public let disk = DiskUIState()
    /// Bölüm değişince içerik en üste kaydırılsın diye artar.
    public private(set) var scrollToken = 0

    public init() {}

    public func go(_ s: MonitorSection) {
        section = s
        scrollToken += 1
    }

    public func select(_ metric: GroupMetric, _ id: String) {
        selected[metric] = id
        if metric == .cpu { expanded.insert(id) }
        let target: MonitorSection = metric == .memory ? .mem : metric == .network ? .net : .cpu
        if section != target { go(target) }
    }

    public func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Teşhisi panoya kopyalar ve bildirim gösterir.
    public func copyDiagnosis(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastCenter.shared.show("Teşhis panoya kopyalandı")
    }
}
