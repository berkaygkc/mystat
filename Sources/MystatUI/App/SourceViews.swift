import MystatCore
import SwiftUI

/// The views are generic (`<Source: MetricsSource>`); the app holds the source as `any MetricsSource`.
/// The existential type is opened here and the view is returned as `AnyView`.
@MainActor
public enum SourceViews {
    public static func panel(source: some MetricsSource, openMonitor: @escaping (MonitorSection?, String?) -> Void) -> AnyView {
        AnyView(LanguageRoot(content: PanelView(source: source, openMonitor: openMonitor)))
    }

    public static func monitor(source: some MetricsSource, state: MonitorState) -> AnyView {
        AnyView(LanguageRoot(content: MonitorView(source: source, state: state)))
    }
}
