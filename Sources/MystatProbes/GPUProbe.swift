import Foundation
import IOKit
import MystatCore

/// GPU: kullanım ve çekirdek sayısı `IOAccelerator`'dan (§9.1); uygulama başına GPU süresi istemci kayıtlarından
/// (`IOUserClientCreator`, `AppUsage[].accumulatedGPUTime`). Root gerektirmez; tarama ≈ 1,6 ms (100 istemci).
public enum GPUProbe {
    public static func read() -> GPUReading? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(it) }
        let acc = IOIteratorNext(it)
        guard acc != 0 else { return nil }
        defer { IOObjectRelease(acc) }
        let stats = IORegistryEntryCreateCFProperty(acc, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
        guard let util = (stats?["Device Utilization %"] as? NSNumber)?.doubleValue else { return nil }
        let cores = (IORegistryEntryCreateCFProperty(acc, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue ?? 0
        var clients: [GPUClient] = []
        var kids: io_iterator_t = 0
        if IORegistryEntryGetChildIterator(acc, kIOServicePlane, &kids) == kIOReturnSuccess {
            defer { IOObjectRelease(kids) }
            while case let k = IOIteratorNext(kids), k != 0 {
                defer { IOObjectRelease(k) }
                guard let creator = IORegistryEntryCreateCFProperty(k, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                      let who = parseCreator(creator),
                      let usage = IORegistryEntryCreateCFProperty(k, "AppUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]]
                else { continue }
                let ns = usage.reduce(UInt64(0)) { $0 &+ ((($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value) ?? 0) }
                clients.append(GPUClient(pid: who.pid, name: who.name, gpuTimeNs: ns))
            }
        }
        return GPUReading(utilization: util, cores: cores, clients: clients)
    }

    /// "pid 410, WindowServer" → (410, "WindowServer"); ad çekirdekte kırpılmış olabilir ("Brave Browser He").
    public static func parseCreator(_ s: String) -> (pid: Int32, name: String)? {
        guard s.hasPrefix("pid "), let comma = s.firstIndex(of: ","), let pid = Int32(s[s.index(s.startIndex, offsetBy: 4)..<comma]) else { return nil }
        return (pid, s[s.index(after: comma)...].trimmingCharacters(in: .whitespaces))
    }
}
