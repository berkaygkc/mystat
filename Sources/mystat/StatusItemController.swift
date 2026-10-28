import AppKit
import MystatCore

/// Tek `NSStatusItem`. Model değişmediyse çizmez; genişlik uyarı öğesi değişince ya da bir değer şablonunu aşınca güncellenir.
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
        view.onLayoutChange = { [weak self] in self?.updateLength() }
    }

    var isHighlighted: Bool {
        get { view.highlighted }
        set { view.highlighted = newValue }
    }

    var button: NSStatusBarButton? { item.button }

    func refresh(now: Date) {
        let m = StatusBlockLayout.model(source.snapshot, now: now, calendar: .current)
        guard m != last else { return }
        last = m
        view.model = m
        updateLength()
    }

    /// Kaybolan uyarı geçiş bitene kadar yer kaplar (`drawnModel`); sonra blok daralır.
    private func updateLength() {
        if let w = StatusBlockLayout.newLength(view.drawnModel, current: item.length, measure: StatusBlockView.measure) { item.length = w }
    }

    @objc private func clicked() { onClick() }
}
