import AppKit
import MystatCore

/// Tek `NSStatusItem`. Model değişmediyse çizmez; genişlik yalnızca uyarı öğesi değişince güncellenir.
@MainActor
final class StatusItemController: NSObject {
    let item: NSStatusItem
    private let view: StatusBlockView
    private let source: SampleSource
    private let onClick: () -> Void
    private var last: StatusBlockModel?

    init(source: SampleSource, onClick: @escaping () -> Void) {
        self.source = source
        self.onClick = onClick
        let model = StatusBlockLayout.model(source.snapshot, now: Date(), calendar: .current)
        item = NSStatusBar.system.statusItem(withLength: ceil(StatusBlockLayout.width(model, measure: StatusBlockView.measure)))
        view = StatusBlockView(model: model)
        super.init()
        if let button = item.button {
            (button.cell as? NSButtonCell)?.highlightsBy = []
            button.target = self
            button.action = #selector(clicked)
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]
            button.addSubview(view)
        }
        last = model
    }

    var isHighlighted: Bool {
        get { view.highlighted }
        set { view.highlighted = newValue }
    }

    var button: NSStatusBarButton? { item.button }

    func refresh(now: Date) {
        let m = StatusBlockLayout.model(source.snapshot, now: now, calendar: .current)
        guard m != last else { return }
        if m.alert?.label != last?.alert?.label {
            item.length = ceil(StatusBlockLayout.width(m, measure: StatusBlockView.measure))
        }
        last = m
        view.model = m
    }

    @objc private func clicked() { onClick() }
}
