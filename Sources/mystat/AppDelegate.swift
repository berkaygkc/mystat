import AppKit
import MystatCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var source: SampleSource!
    private var status: StatusItemController?
    private var ticker: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let kind = args.firstIndex(of: "--kind").flatMap { args.indices.contains($0 + 1) ? IncidentKind(rawValue: args[$0 + 1]) : nil } ?? .cpu
        source = SampleSource(seed: 1, incident: args.contains("--incident"), kind: kind)
        status = StatusItemController(source: source) { [weak self] in self?.togglePanel() }
        startTicker()
    }

    func togglePanel() {
        status?.isHighlighted.toggle()
    }

    /// Saat tam saniye sınırında yenilenir; örnek veri 2 sn'de bir ilerler.
    private func startTicker() {
        ticker = Task { [weak self] in
            var second = 0
            while !Task.isCancelled {
                let frac = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
                try? await Task.sleep(for: .seconds(1 - frac + 0.002))
                guard let self else { return }
                second += 1
                if second % 2 == 0 { self.source.tick() }
                self.status?.refresh(now: Date())
            }
        }
    }
}
