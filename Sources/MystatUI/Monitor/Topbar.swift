import MystatCore
import SwiftUI

/// Section name, time range and a clock with seconds.
struct Topbar: View {
    @Bindable var state: MonitorState

    var body: some View {
        HStack(spacing: 14) {
            Text(MonitorPresentation.sectionTitles[state.section.rawValue] ?? "")
                .font(.system(size: 15, weight: .semibold)).tracking(-0.15).foregroundStyle(Theme.ink)
            Spacer()
            Seg(TimeRange.allCases.map { ($0, $0.title) }, selection: $state.range)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.dateLine(ctx.date)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.ink3)
                    Text(Fmt.timeLine(ctx.date)).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.ink)
                }
            }
            .padding(.leading, 4)
        }
        .padding(.leading, 18).padding(.trailing, 22)
        .frame(height: 62)
    }
}
