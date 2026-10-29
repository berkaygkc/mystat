import Foundation

/// Wi‑Fi okuması (CoreWLAN). Ağın adı yalnızca konum izni varsa gelir.
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

/// Birincil arayüzün bağlantısı (spec §6.3 "Bağlantı" kartı).
public struct NetLink: Sendable, Equatable {
    public var bsdName: String         // "en0"
    public var displayName: String     // "Wi‑Fi", "Ethernet"
    public var localIP: String?, router: String?
    public var dns: [String]
    public var wifi: WiFiReading?
    /// Kablolu arayüzün hızı (ifi_baudrate); bilinmiyorsa nil.
    public var linkMbps: Double?

    public init(bsdName: String, displayName: String, localIP: String?, router: String?, dns: [String], wifi: WiFiReading?, linkMbps: Double?) {
        self.bsdName = bsdName; self.displayName = displayName; self.localIP = localIP; self.router = router; self.dns = dns
        self.wifi = wifi; self.linkMbps = linkMbps
    }
}

/// Wi‑Fi ağının adı neden yok: konum izni bekleniyor, reddedildi ya da arayüz Wi‑Fi değil.
public enum SSIDAccess: Sendable, Equatable { case known, needsPermission, denied, notWiFi }

/// Ağ bölümünün "Bağlantı" kartı metinleri (mockup `secNet`).
public enum NetPresentation {
    public static func facts(_ l: NetLink) -> [Fact] {
        var out: [Fact] = []
        if let w = l.wifi {
            let band = w.bandGHz.rounded() == w.bandGHz ? Fmt.int(w.bandGHz) : Fmt.dec1(w.bandGHz)
            out.append(Fact("Bant", w.channel > 0 ? "\(band) GHz · kanal \(w.channel)" : Fmt.missing))
            out.append(Fact("Bağlantı hızı", w.txRateMbps > 0 ? Fmt.int(w.txRateMbps) + " Mb/sn" : Fmt.missing))
            out.append(Fact("Sinyal", w.rssi < 0 ? "\(signalWord(rssi: w.rssi)) · \u{2212}\(-w.rssi) dBm" : Fmt.missing))
        } else if let m = l.linkMbps, m > 0 {
            out.append(Fact("Bağlantı hızı", Fmt.int(m) + " Mb/sn"))
        }
        out.append(Fact("Yerel IP", l.localIP ?? Fmt.missing))
        out.append(Fact("Yönlendirici", l.router ?? Fmt.missing))
        out.append(Fact("DNS", l.dns.isEmpty ? Fmt.missing : l.dns.prefix(3).joined(separator: ", ")))
        out.append(Fact("Arayüz", l.bsdName))
        return out
    }

    public static func signalWord(rssi: Int) -> String {
        rssi >= -55 ? "Çok iyi" : rssi >= -67 ? "İyi" : rssi >= -75 ? "Orta" : "Zayıf"
    }

    /// Sistem Ayarları → Gizlilik ve Güvenlik → Konum Servisleri.
    public static let locationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!

    /// Ağın adı yoksa Bağlantı kartındaki satır: açıklama ve düğme.
    public static func accessLine(_ a: SSIDAccess) -> (text: String, action: String)? {
        switch a {
        case .needsPermission: ("Ağ adı için konum izni gerekiyor.", "İzin ver")
        case .denied: ("Ağ adını görmek için Sistem Ayarları'nda konum izni ver.", "Ayarları aç")
        case .known, .notWiFi: nil
        }
    }

    /// Sistem adı ("Wi-Fi") → satırda kırılmayan tire (U+2011), mockup'taki gibi.
    public static func displayName(_ systemName: String) -> String {
        systemName.replacingOccurrences(of: "-", with: "\u{2011}")
    }
}
