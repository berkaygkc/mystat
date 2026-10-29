import CoreWLAN
import Darwin
import Foundation
import MystatCore
import SystemConfiguration

/// Birincil arayüzün bağlantısı (spec §9.1: Wi‑Fi için CoreWLAN, IP/DNS için SystemConfiguration). Ağın adı (SSID)
/// macOS'ta yalnızca konum izni olan uygulamaya verilir; izin yoksa `ssid` nil.
public enum NetLinkProbe {
    /// Birincil arayüz yoksa (bağlantı yok) nil.
    public static func read() -> NetLink? {
        guard let store = SCDynamicStoreCreate(nil, "mystat" as CFString, nil, nil),
              let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let bsd = ipv4["PrimaryInterface"] as? String else { return nil }
        let dns = (SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any])?["ServerAddresses"] as? [String]
        let iface = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface])?.first { SCNetworkInterfaceGetBSDName($0) as String? == bsd }
        let name = iface.flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? } ?? bsd
        let wifi = wifiReading(bsd)
        return NetLink(bsdName: bsd, displayName: NetPresentation.displayName(name), localIP: NetDiskProbe().localIPv4(of: bsd),
                       router: ipv4["Router"] as? String, dns: dns ?? [], wifi: wifi, linkMbps: wifi == nil ? baudMbps(bsd) : nil)
    }

    static func wifiReading(_ bsd: String) -> WiFiReading? {
        guard let i = CWWiFiClient.shared().interface(withName: bsd), i.powerOn() else { return nil }
        let band: Double = switch i.wlanChannel()?.channelBand {
        case .band2GHz?: 2.4
        case .band5GHz?: 5
        case .band6GHz?: 6
        default: 0
        }
        return WiFiReading(ssid: i.ssid(), rssi: i.rssiValue(), noise: i.noiseMeasurement(), txRateMbps: i.transmitRate(),
                           channel: i.wlanChannel()?.channelNumber ?? 0, bandGHz: band)
    }

    /// Kablolu arayüzün hızı (`ifi_baudrate`, bit/sn); bilinmiyorsa nil.
    static func baudMbps(_ bsd: String) -> Double? {
        let index = if_nametoindex(bsd)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(index), IFDATA_GENERAL]
        var d = ifmibdata(); var len = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, 6, &d, &len, nil, 0) == 0, d.ifmd_data.ifi_baudrate > 0 else { return nil }
        return Double(d.ifmd_data.ifi_baudrate) / 1e6
    }
}
