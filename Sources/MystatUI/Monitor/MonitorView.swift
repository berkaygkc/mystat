import MystatCore
import SwiftUI

/// Monitör penceresinin kökü (mockup monitor.html).
public struct MonitorView<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState

    public init(source: Source, state: MonitorState) { self.source = source; self.state = state }

    public var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Sidebar(source: source, state: state).padding(8)
                VStack(spacing: 0) {
                    Topbar(state: state)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Color.clear.frame(height: 0).id("top")
                                SectionContent(source: source, state: state)
                            }
                            .padding(.leading, 22).padding(.trailing, 28).padding(.top, 4).padding(.bottom, 32)
                        }
                        .scrollIndicators(.automatic)
                        .onChange(of: state.scrollToken) { proxy.scrollTo("top", anchor: .top) }
                    }
                }
            }
            ToastOverlay()
        }
        .background(Theme.win)
        .confirmHost($state.confirm)
        .onChange(of: state.section, initial: true) { source.setVisibleSection(state.section.rawValue) }   // Docker'ın diski açılınca (§9.2)
    }
}

/// Seçili bölümün içeriği.
struct SectionContent<Source: MetricsSource>: View {
    let source: Source
    let state: MonitorState
    var body: some View {
        switch state.section {
        case .overview: OverviewSection(source: source, state: state)
        case .cpu: CPUSection(source: source, state: state)
        case .mem: MemorySection(source: source, state: state)
        case .net: NetworkSection(source: source, state: state)
        case .docker: DockerSection(source: source, state: state)
        case .sys: SystemSection(source: source, state: state)
        case .disk: DiskSection(source: source, state: state)
        }
    }
}
