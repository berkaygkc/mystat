import Foundation

/// Wi-Fi reading (CoreWLAN). The network name is only available with location permission.
public struct WiFiReading: Sendable, Equatable {
    public var ssid: String?
    public var rssi: Int, noise: Int   // dBm
    public var txRateMbps: Double
    public var channel: Int
    public var bandGHz: Double         // 2.4, 5, 6

    public init(ssid: String?, rssi: Int, noise: Int, txRateMbps: Double, channel: Int, bandGHz: Double) {
        self.ssid = ssid; self.rssi = rssi; self.noise = noise; self.txRateMbps = txRateMbps; self.channel = channel; self.bandGHz = bandGHz
    }
}

/// Connection of the primary interface (the "Connection" card).
public struct NetLink: Sendable, Equatable {
    public var bsdName: String         // "en0"
    public var displayName: String     // "Wi‑Fi", "Ethernet"
    public var localIP: String?, router: String?
    public var dns: [String]
    public var wifi: WiFiReading?
    /// Speed of a wired interface (ifi_baudrate); nil if unknown.
    public var linkMbps: Double?

    public init(bsdName: String, displayName: String, localIP: String?, router: String?, dns: [String], wifi: WiFiReading?, linkMbps: Double?) {
        self.bsdName = bsdName; self.displayName = displayName; self.localIP = localIP; self.router = router; self.dns = dns
        self.wifi = wifi; self.linkMbps = linkMbps
    }
}

/// Why the Wi-Fi network name is missing: location permission pending, denied, or the interface is not Wi-Fi.
public enum SSIDAccess: Sendable, Equatable { case known, needsPermission, denied, notWiFi }

/// Texts for the "Connection" card of the Network section.
public enum NetPresentation {
    public static func facts(_ l: NetLink) -> [Fact] {
        var out: [Fact] = []
        if let w = l.wifi {
            let band = w.bandGHz.rounded() == w.bandGHz ? Fmt.int(w.bandGHz) : Fmt.dec1(w.bandGHz)
            out.append(Fact(L10n.t("net.fact.band"), w.channel > 0 ? L10n.t("net.fact.band.value", ["band": band, "channel": String(w.channel)]) : Fmt.missing))
            out.append(Fact(L10n.t("net.fact.linkSpeed"), w.txRateMbps > 0 ? L10n.t("unit.mbps", ["v": Fmt.int(w.txRateMbps)]) : Fmt.missing))
            out.append(Fact(L10n.t("net.fact.signal"), w.rssi < 0 ? "\(signalWord(rssi: w.rssi)) · \u{2212}\(-w.rssi) dBm" : Fmt.missing))
        } else if let m = l.linkMbps, m > 0 {
            out.append(Fact(L10n.t("net.fact.linkSpeed"), L10n.t("unit.mbps", ["v": Fmt.int(m)])))
        }
        out.append(Fact(L10n.t("net.fact.localIP"), l.localIP ?? Fmt.missing))
        out.append(Fact(L10n.t("net.fact.router"), l.router ?? Fmt.missing))
        out.append(Fact(L10n.t("net.fact.dns"), l.dns.isEmpty ? Fmt.missing : l.dns.prefix(3).joined(separator: ", ")))
        out.append(Fact(L10n.t("net.fact.interface"), l.bsdName))
        return out
    }

    public static func signalWord(rssi: Int) -> String {
        L10n.t(rssi >= -55 ? "net.signal.veryGood" : rssi >= -67 ? "net.signal.good" : rssi >= -75 ? "net.signal.fair" : "net.signal.weak")
    }

    /// Note that replaces the "Who's using it" list; nil: the list is shown.
    public static func perAppNote(available: Bool, ready: Bool, empty: Bool) -> String? {
        if !available { return L10n.t("net.perApp.unavailable") }
        if !ready { return L10n.t("net.perApp.measuring") }
        return empty ? L10n.t("net.perApp.empty") : nil
    }

    /// Router latency; "—" if not measured.
    public static func latencyText(_ ms: Double) -> String { ms.isFinite ? Fmt.int(ms) + " ms" : Fmt.missing }

    /// System Settings → Privacy & Security → Location Services.
    public static let locationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!

    /// Row in the Connection card when the network name is missing: explanation and button.
    public static func accessLine(_ a: SSIDAccess) -> (text: String, action: String)? {
        switch a {
        case .needsPermission: (L10n.t("net.ssid.needs"), L10n.t("net.ssid.allow"))
        case .denied: (L10n.t("net.ssid.denied"), L10n.t("net.ssid.openSettings"))
        case .known, .notWiFi: nil
        }
    }

    /// System name ("Wi-Fi") → non-breaking hyphen (U+2011) so the row does not wrap.
    public static func displayName(_ systemName: String) -> String {
        systemName.replacingOccurrences(of: "-", with: "\u{2011}")
    }
}
