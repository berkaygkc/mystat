import SwiftUI

/// Onay penceresi içeriği (mockup'taki `.sheet`). Perde ve sunum `ConfirmHost` tarafından yapılır.
public struct ConfirmRequest: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let confirm: String
    public let destructive: Bool
    public let onConfirm: @MainActor () -> Void
    public init(title: String, message: String, confirm: String, destructive: Bool, onConfirm: @escaping @MainActor () -> Void) {
        self.title = title; self.message = message; self.confirm = confirm; self.destructive = destructive; self.onConfirm = onConfirm
    }
}

public struct ConfirmSheet: View {
    let req: ConfirmRequest
    let dismiss: () -> Void
    public init(_ req: ConfirmRequest, dismiss: @escaping () -> Void) { self.req = req; self.dismiss = dismiss }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(req.title).font(.system(size: 16, weight: .semibold)).tracking(-0.16).foregroundStyle(Theme.ink)
            Text(req.message).font(.system(size: 13)).lineSpacing(3).foregroundStyle(Theme.ink2).padding(.top, 7)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Btn("Vazgeç", action: dismiss)
                Btn(req.confirm, style: req.destructive ? .dangerFill : .primary) { dismiss(); req.onConfirm() }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
        .frame(width: 360)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Pencere üstünde %16 karartılmış perde ve ölçek animasyonuyla onay penceresi.
public struct ConfirmHost: ViewModifier {
    @Binding var request: ConfirmRequest?
    public func body(content: Content) -> some View {
        content.overlay {
            if let req = request {
                ZStack {
                    Color.black.opacity(0.16).onTapGesture { request = nil }
                    ConfirmSheet(req) { request = nil }
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .onKeyPress(.escape) { request = nil; return .handled }
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: request?.id)
    }
}

public extension View {
    func confirmHost(_ request: Binding<ConfirmRequest?>) -> some View { modifier(ConfirmHost(request: request)) }
}
