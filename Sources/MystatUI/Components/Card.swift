import SwiftUI

/// Card: translucent surface with a 0.5 pt border.
public struct Card<Content: View>: View {
    let radius: CGFloat
    let content: Content
    public init(radius: CGFloat = 16, @ViewBuilder content: () -> Content) { self.radius = radius; self.content = content() }
    public var body: some View {
        content
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.cardEdge, lineWidth: 0.5))
    }
}
