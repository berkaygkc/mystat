import Darwin
import Foundation
import IOKit
import MystatCore
import SystemConfiguration

/// Ağ arayüzü sayaçları, birincil arayüz ve IP, Data birimi kapasitesi, disk etkinliği.
public struct NetDiskProbe: Sendable {
    public init() {}

    /// Arayüz başına `sysctl IFMIB_IFDATA` (`netstat -ib` ile aynı 64 bit sayaçlar). `NET_RT_IFLIST2` macOS 26'da
    /// alınan baytı 32 bitte sarıp 1024'e yuvarlıyor; `getifaddrs` da 32 bit. İkisi de kullanılmaz.
    public func interfaces() -> [InterfaceCounters] {
        guard let list = if_nameindex() else { return [] }
        defer { if_freenameindex(list) }
        var out: [InterfaceCounters] = []
        var i = 0
        while list[i].if_index != 0 {
            var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(list[i].if_index), IFDATA_GENERAL]
            var d = ifmibdata()
            var len = MemoryLayout<ifmibdata>.size
            if sysctl(&mib, 6, &d, &len, nil, 0) == 0 {
                out.append(InterfaceCounters(name: String(cString: list[i].if_name), rx: d.ifmd_data.ifi_ibytes, tx: d.ifmd_data.ifi_obytes,
                                             up: d.ifmd_flags & UInt32(IFF_UP) != 0))
            }
            i += 1
        }
        return out
    }

    /// `State:/Network/Global/IPv4` → `PrimaryInterface` (ör. "en0").
    public func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "mystat" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
        return dict["PrimaryInterface"] as? String
    }

    public func localIPv4(of iface: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard String(cString: a.ifa_name) == iface, let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        return nil
    }

    /// Data birimi (spec §7.1). "Önemli kullanım için" kapasite, sistemin boşaltabileceği alanı da sayar.
    public func dataVolume() -> VolumeCapacity {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let v = try? URL(fileURLWithPath: "/System/Volumes/Data").resourceValues(forKeys: keys)
        return VolumeCapacity(total: UInt64(v?.volumeTotalCapacity ?? 0), available: UInt64(v?.volumeAvailableCapacity ?? 0),
                              availableImportant: UInt64(max(0, v?.volumeAvailableCapacityForImportantUsage ?? 0)))
    }

    /// Tüm `IOBlockStorageDriver`'ların `Statistics` toplamı.
    public func diskIO() -> DiskIOCounters {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS else {
            return DiskIOCounters(bytesRead: 0, bytesWritten: 0)
        }
        defer { IOObjectRelease(iter) }
        var r: UInt64 = 0, w: UInt64 = 0
        while case let e = IOIteratorNext(iter), e != 0 {
            defer { IOObjectRelease(e) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(e, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else { continue }
            r &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            w &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return DiskIOCounters(bytesRead: r, bytesWritten: w)
    }
}
