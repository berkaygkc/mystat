import MystatCore
import SwiftUI

/// Görünümler genel (`<Source: MetricsSource>`); uygulama kaynağı `any MetricsSource` olarak tutar.
/// Varoluşsal tip burada açılıp görünüm `AnyView` olarak döner.
@MainActor
public enum SourceViews {
    public static func panel(source: some MetricsSource, openMonitor: @escaping (MonitorSection?, String?) -> Void) -> AnyView {
        AnyView(PanelView(source: source, openMonitor: openMonitor))
    }

    public static func monitor(source: some MetricsSource, state: MonitorState) -> AnyView {
        AnyView(MonitorView(source: source, state: state))
    }
}
