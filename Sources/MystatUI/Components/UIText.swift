import MystatCore

/// UI strings used by more than one view.
public enum UIText {
    /// Small uppercase line above a section title ("CPU", "NETWORK" ...); "NOW" on Overview.
    public static func sectionKicker(_ s: MonitorSection) -> String {
        s == .overview ? L10n.t("headline.kicker") : L10n.t("kicker.\(s.rawValue)")
    }

    public static var quit: String { L10n.t("panel.quit") }
}
