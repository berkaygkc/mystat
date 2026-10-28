import Observation
import SwiftUI

/// Alt ortada beliren cam bildirim (mockup'taki `toast`), 2,2 sn görünür.
@MainActor @Observable
public final class ToastCenter {
    public static let shared = ToastCenter()
    public private(set) var message: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    public func show(_ text: String) {
        message = text
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

public struct ToastOverlay: View {
    @State private var center = ToastCenter.shared
    public init() {}
    public var body: some View {
        VStack {
            Spacer()
            if let m = center.message {
                HStack(spacing: 8) {
                    Circle().fill(Theme.green).frame(width: 7, height: 7)
                    Text(m).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Theme.tipFill, in: Capsule())
                .glassEffect(.regular, in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 22)
            }
        }
        .animation(.easeOut(duration: 0.25), value: center.message)
        .allowsHitTesting(false)
    }
}
