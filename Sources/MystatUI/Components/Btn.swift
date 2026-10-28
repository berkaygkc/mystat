import SwiftUI

/// Mockup'taki `.btn` ailesi.
public struct Btn: View {
    public enum Style { case normal, primary, danger, dangerFill }
    let title: String, icon: String?, trailing: String?, style: Style, action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    public init(_ title: String, icon: String? = nil, trailing: String? = nil, style: Style = .normal, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.trailing = trailing; self.style = style; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11.5, weight: .semibold)) }
                Text(title).font(.system(size: 12.5, weight: .semibold))
                if let trailing { Image(systemName: trailing).font(.system(size: 10.5, weight: .semibold)) }
            }
            .padding(.horizontal, 13).frame(minHeight: 30)
            .frame(maxWidth: .infinity)
            .foregroundStyle(fg)
            .background(bg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(style == .normal || style == .danger ? Theme.btnEdge : .clear, lineWidth: 0.5))
            .brightness(hovering && enabled ? 0.03 : 0)
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var fg: Color {
        switch style { case .normal: Theme.ink; case .primary: Theme.inv; case .danger: Theme.red; case .dangerFill: .white }
    }
    private var bg: Color {
        switch style { case .normal, .danger: Theme.btn; case .primary: Theme.ink; case .dangerFill: Theme.red }
    }
}
