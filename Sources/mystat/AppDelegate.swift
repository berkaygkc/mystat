import AppKit
import MystatCore
import MystatLive
import MystatUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Live source by default; with `--sample`, the sample data (`SourceFactory`).
    private(set) var source: (any MetricsSource)!
    private var status: StatusItemController?
    private var panel: PanelController?
    private var monitor: MonitorWindowController?
    private var keyMonitor: Any?
    private var ticker: Task<Void, Never>?
    /// Processes are read every 2 s while the panel or monitor is open, every 5 s when closed.
    private var panelOpen = false { didSet { source.setDetailInterest(panelOpen || monitorVisible) } }
    private var monitorVisible = false { didSet { source.setDetailInterest(panelOpen || monitorVisible) } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        // Language before sampling starts: so the first texts are also produced in the right language.
        let language = LanguageSettings()
        LanguageSettings.current = language
        if Localizer.shared.languages.isEmpty { NSLog("mystat: Locales folder not found; texts will show as keys") }
        source = SourceFactory.make(arguments: args)
        status = StatusItemController(source: source) { [weak self] in self?.togglePanel() }
        panel = PanelController(source: source) { [weak self] section, group in self?.openMonitor(section, group) }
        panel?.onVisibilityChange = { [weak self] open in
            self?.status?.isHighlighted = open
            self?.panelOpen = open
        }
        monitor = MonitorWindowController(source: source)
        monitor?.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.monitorVisible = visible
            self.source.setMonitorOccluded(!visible)   // network details stop, the disk tree stays
            if visible { self.source.setVisibleSection(self.monitor?.state.section.rawValue) }
        }
        monitor?.onClose = { [weak self] in self?.source.setVisibleSection(nil) }
        language.onChange = { [weak self] in self?.languageChanged() }
        installKeys()
        #if DEBUG
        if args.contains("--log-values") { startValueLog() }
        #endif
        if args.contains("--panel") {   // cost measurement: panel open (the status button's window does not exist yet at launch)
            Task { @MainActor [weak self] in try? await Task.sleep(for: .seconds(1)); self?.togglePanel() }
        }
        if let i = args.firstIndex(of: "--section"), args.indices.contains(i + 1), let sec = MonitorSection(rawValue: args[i + 1]) {
            openMonitor(sec, nil)
        }
        startTicker()
        LoginItem.ensureRegistered()
    }

    func applicationWillTerminate(_ notification: Notification) {
        (source as? LiveSource)?.flushHistory()
    }

    /// The panel and monitor root views rebuild themselves via `LanguageRoot`; the rest is handled here.
    private func languageChanged() {
        status?.refresh(now: Date())
        panel?.relayout()
        monitor?.state.confirm = nil   // so an open confirmation dialog does not stay in the old language
        source.languageChanged()
    }

    func togglePanel() {
        guard let button = status?.button else { return }
        panel?.toggle(relativeTo: button)
    }

    func openMonitor(_ section: MonitorSection?, _ groupID: String?) {
        monitor?.show(section: section, groupID: groupID)
    }

    /// ⌘Q quit, ⌘W close window/panel, ⌘M monitor — only inside the app (not system-wide).
    /// Debug keys in DEBUG: ⌥⌘I toggle incident, ⌥⌘K incident kind.
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
            if mods == [.command, .option], e.keyCode == 34, let sample = self.source as? SampleSource {                       // I (sample data only)
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

    /// The clock refreshes on the whole-second boundary; sample data advances every 2 s.
    #if DEBUG
    /// For tools/consistency.sh: one line per measurement (stdout).
    private func startValueLog() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                print(LiveSource.logLine(self.source.snapshot))
                fflush(stdout)
            }
        }
    }
    #endif

    private func startTicker() {
        ticker = Task { [weak self] in
            var second = 0
            while !Task.isCancelled {
                let frac = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
                try? await Task.sleep(for: .seconds(1 - frac + 0.002))
                guard let self else { return }
                second += 1
                if second % 2 == 0 { (self.source as? SampleSource)?.tick() }   // the live source samples at its own pace
                self.status?.refresh(now: Date())
            }
        }
    }
}
