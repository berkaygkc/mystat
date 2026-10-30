import AppKit
import MystatCore

/// A single `NSStatusItem`. Does not redraw if the model is unchanged; the width updates when the alert item changes or a value exceeds its template.
@MainActor
final class StatusItemController: NSObject {
    let item: NSStatusItem
    private let view: StatusBlockView
    private let source: any MetricsSource
    private let onClick: () -> Void
    private var last: StatusBlockModel?

    init(source: any MetricsSource, onClick: @escaping () -> Void) {
        self.source = source
        self.onClick = onClick
        let model = StatusBlockLayout.model(source.snapshot, now: Date(), calendar: Fmt.calendar)
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
        view.onLayoutChange = { [weak self] in self?.updateLength() }
    }

    var isHighlighted: Bool {
        get { view.highlighted }
        set { view.highlighted = newValue }
    }

    var button: NSStatusBarButton? { item.button }

    func refresh(now: Date) {
        let m = StatusBlockLayout.model(source.snapshot, now: now, calendar: Fmt.calendar)
        guard m != last else { return }
        last = m
        view.model = m
        updateLength()
    }

    /// A fading alert occupies space until the transition ends (`drawnModel`); then the block shrinks.
    private func updateLength() {
        if let w = StatusBlockLayout.newLength(view.drawnModel, current: item.length, measure: StatusBlockView.measure) { item.length = w }
    }

    @objc private func clicked() { onClick() }
}
