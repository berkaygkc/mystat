import AppKit
import MystatCore
import Observation
import SwiftUI

/// Navigation and selection state of the monitor window.
@MainActor @Observable
public final class MonitorState {
    public var section: MonitorSection = .overview
    public var range: TimeRange = .m10
    public var selected: [GroupMetric: String] = [.cpu: "claude-acmecorp", .memory: "docker", .network: "docker"]
    public var expanded: Set<String> = ["claude-acmecorp"]
    public var confirm: ConfirmRequest?
    public let disk = DiskUIState()
    /// Incremented on every section change so the content scrolls back to the top.
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

    /// Navigates to a section, selecting a group in it if there is one (the panel, incident block and suggestions go through here).
    /// CPU, Memory and Network select a group; other sections have no group list, so only the section opens.
    public func show(_ target: MonitorSection, group: String?) {
        switch (target, group) {
        case (.cpu, let id?): select(.cpu, id)
        case (.mem, let id?): select(.memory, id)
        case (.net, let id?): select(.network, id)
        default: if section != target { go(target) }
        }
    }

    public func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Copies the diagnosis to the clipboard and shows a toast.
    public func copyDiagnosis(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastCenter.shared.show(L10n.t("toast.diagnosisCopied"))
    }
}
