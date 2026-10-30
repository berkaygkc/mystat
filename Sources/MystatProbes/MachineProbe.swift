import Darwin
import Foundation
import IOKit
import MystatCore

/// Machine info for the sidebar's bottom line (read once).
public struct MachineProbe: Sendable {
    public init() {}

    public func machine() -> MachineInfo {
        let brand = Self.string("machdep.cpu.brand_string") ?? "Apple"
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boot, &size, nil, 0)
        return MachineInfo(model: Self.productName() ?? "Mac",
                           chip: brand.hasPrefix("Apple ") ? String(brand.dropFirst(6)) : brand,
                           pCores: Self.int("hw.perflevel0.physicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount,
                           eCores: Self.int("hw.perflevel1.physicalcpu") ?? 0,
                           memoryGB: Int(ProcessInfo.processInfo.physicalMemory >> 30),
                           boot: Date(timeIntervalSince1970: TimeInterval(boot.tv_sec)))
    }

    /// `IODeviceTree:/product` → `product-name` ("MacBook Pro (16-inch, 2024)" → "MacBook Pro").
    static func productName() -> String? {
        let e = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard e != 0 else { return nil }
        defer { IOObjectRelease(e) }
        guard let data = IORegistryEntryCreateCFProperty(e, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data
        else { return nil }
        let full = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        return full.split(separator: "(").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func int(_ name: String) -> Int? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : nil
    }
}
