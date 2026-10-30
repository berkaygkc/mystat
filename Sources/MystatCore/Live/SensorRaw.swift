import Foundation

/// Raw values read from sensors (probe ↔ core contract).

/// SMC value formats. On Apple Silicon most are `flt ` (Float32, little-endian); integers are big-endian.
public enum SMCValue {
    public static func decode(type: String, bytes b: [UInt8]) -> Double? {
        func need(_ n: Int) -> Bool { b.count >= n }
        switch type {
        case "flt ": return need(4) ? Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }) : nil
        case "ui8 ": return need(1) ? Double(b[0]) : nil
        case "ui16": return need(2) ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
        case "ui32": return need(4) ? Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])) : nil
        case "fpe2": return need(2) ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4 : nil
        case "sp78": return need(2) ? Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256 : nil
        default: return nil
        }
    }
}

/// Discovered SMC keys. Names are undocumented; they are classified by prefix:
/// CPU `Tp`/`Te`, GPU `Tg`, battery `TB0T`. Only keys yielding values between 10 and 120 °C are used (e.g. `Tp01` = 3.4 is not a temperature).
public struct SensorMap: Sendable, Codable, Equatable {
    public var cpu: [String], gpu: [String], battery: String?
    public var fans: Int

    public init(cpu: [String], gpu: [String], battery: String?, fans: Int) {
        self.cpu = cpu; self.gpu = gpu; self.battery = battery; self.fans = fans
    }

    static let plausible = 10.0...120.0

    public static func classify(_ temps: [String: Double], fans: Int) -> SensorMap {
        let ok = temps.filter { plausible.contains($0.value) }.keys
        return SensorMap(cpu: ok.filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }.sorted(), gpu: ok.filter { $0.hasPrefix("Tg") }.sorted(),
                         battery: ok.contains("TB0T") ? "TB0T" : nil, fans: fans)
    }

    /// At most `n` evenly spaced keys (including first and last): the same set on every read, bounded cost.
    public func sample(_ keys: [String], max n: Int) -> [String] {
        guard keys.count > n, n > 1 else { return keys }
        return (0..<n).map { keys[Int((Double($0) * Double(keys.count - 1) / Double(n - 1)).rounded())] }
    }
}

/// IOReport "Energy Model": cumulative joules since subscription.
public struct EnergyCounters: Sendable, Equatable {
    public var cpuJ, gpuJ, aneJ, dramJ: Double
    public init(cpuJ: Double, gpuJ: Double, aneJ: Double, dramJ: Double) { self.cpuJ = cpuJ; self.gpuJ = gpuJ; self.aneJ = aneJ; self.dramJ = dramJ }
}

/// A client using the GPU: `IOUserClientCreator` ("pid 410, WindowServer") and cumulative GPU time.
public struct GPUClient: Sendable, Equatable {
    public let pid: Int32, name: String
    public let gpuTimeNs: UInt64
    public init(pid: Int32, name: String, gpuTimeNs: UInt64) { self.pid = pid; self.name = name; self.gpuTimeNs = gpuTimeNs }
}

public struct GPUReading: Sendable, Equatable {
    public let utilization: Double
    public let cores: Int
    public let clients: [GPUClient]
    public init(utilization: Double, cores: Int, clients: [GPUClient]) { self.utilization = utilization; self.cores = cores; self.clients = clients }
}
