import AppKit
import MystatCore
import MystatLive
import MystatUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Varsayılan canlı kaynak; `--sample` ile Faz 1'in örnek verisi (`SourceFactory`).
    private(set) var source: (any MetricsSource)!
    private var status: StatusItemController?
    private var panel: PanelController?
    private var monitor: MonitorWindowController?
    private var keyMonitor: Any?
    private var ticker: Task<Void, Never>?
    /// Panel ya da monitör açıkken süreçler 2 sn'de bir, kapalıyken 5 sn'de bir okunur (spec §9.2).
    private var panelOpen = false { didSet { source.setDetailInterest(panelOpen || monitorVisible) } }
    private var monitorVisible = false { didSet { source.setDetailInterest(panelOpen || monitorVisible) } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        source = SourceFactory.make(arguments: args)
        status = StatusItemController(source: source) { [weak self] in self?.togglePanel() }
        panel = PanelController(source: source) { [weak self] section, group in self?.openMonitor(section, group) }
        panel?.onVisibilityChange = { [weak self] open in
            self?.status?.isHighlighted = open
            self?.panelOpen = open
        }
        monitor = MonitorWindowController(source: source)
        monitor?.onVisibilityChange = { [weak self] visible in self?.monitorVisible = visible }
        installKeys()
        #if DEBUG
        if args.contains("--scan-ready") { monitor?.state.disk.scan = .ready(scannedAt: Date()) }   // haritayı taramasız denemek için
        #endif
        if let i = args.firstIndex(of: "--section"), args.indices.contains(i + 1), let sec = MonitorSection(rawValue: args[i + 1]) {
            openMonitor(sec, nil)
        }
        startTicker()
        LoginItem.ensureRegistered()
    }

    func togglePanel() {
        guard let button = status?.button else { return }
        panel?.toggle(relativeTo: button)
    }

    func openMonitor(_ section: MonitorSection?, _ groupID: String?) {
        monitor?.show(section: section, groupID: groupID)
    }

    /// ⌘Q çık, ⌘W pencereyi/paneli kapat, ⌘M monitör — yalnızca uygulama içinde (sistem geneli değil).
    /// DEBUG'da inceleme tuşları: ⌥⌘I olay aç/kapa, ⌥⌘K olay türü.
    private func installKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch AppShortcut.match(chars: e.charactersIgnoringModifiers, modifiers: mods) {
            case .quit?: NSApp.terminate(nil); return nil
            case .closeWindow?:
                if self.panel?.isOpen == true { self.panel?.close() } else { NSApp.keyWindow?.performClose(nil) }
                return nil
            case .openMonitor?: self.panel?.close(returnFocus: false); self.openMonitor(nil, nil); return nil
            case nil: break
            }
            #if DEBUG
            if mods == [.command, .option], e.keyCode == 34, let sample = self.source as? SampleSource {                       // I (yalnızca örnek veri)
                sample.incident.toggle(); self.status?.refresh(now: Date()); return nil
            }
            if mods == [.command, .option], e.keyCode == 40, let sample = self.source as? SampleSource {                       // K
                let all = IncidentKind.allCases
                sample.incidentKind = all[(all.firstIndex(of: sample.incidentKind)! + 1) % all.count]
                self.status?.refresh(now: Date()); return nil
            }
            #endif
            return e
        }
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
                if second % 2 == 0 { (self.source as? SampleSource)?.tick() }   // canlı kaynak kendi temposunda ölçer
                self.status?.refresh(now: Date())
            }
        }
    }
}
