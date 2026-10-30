import SwiftUI

/// Segmented picker: small segments on a capsule background.
public struct Seg<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    public init(_ items: [(T, String)], selection: Binding<T>) { self.items = items; self._selection = selection }
    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let (value, title) = items[i]
                let on = value == selection
                Text(title)
                    .font(.system(size: 12, weight: on ? .semibold : .medium))
                    .foregroundStyle(on ? Theme.ink : Theme.ink2)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.segOn)
                                .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { selection = value } }
            }
        }
        .padding(2)
        .background(Theme.seg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
