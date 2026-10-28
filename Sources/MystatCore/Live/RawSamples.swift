import Foundation

// Probe ↔ Core sözleşmesi: sistemden okunan ham sayaçlar. Anlam (yüzde, hız, grup) Core'da hesaplanır.

/// Bir çekirdeğin birikimli tick sayaçları (`host_processor_info`).
public struct CoreTicks: Sendable, Equatable {
    public var user, system, idle, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

/// Sanal bellek sayfa sayaçları (`host_statistics64`) ve ilgili sysctl'ler.
public struct VMCounters: Sendable, Equatable {
    public var pageSize: UInt64
    /// Fiziksel bellek (bayt).
    public var total: UInt64
    public var free, active, inactive, speculative, wired, compressor, purgeable, `internal`, external: UInt64
    /// `vm.swapusage.xsu_used` (bayt).
    public var swapUsed: UInt64
    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 uyarı, 4 kritik.
    public var pressureLevel: Int32
    /// `kern.memorystatus_level`: kullanılabilir bellek yüzdesi.
    public var memoryLevel: Int32

    public init(pageSize: UInt64, total: UInt64, free: UInt64, active: UInt64, inactive: UInt64, speculative: UInt64, wired: UInt64,
                compressor: UInt64, purgeable: UInt64, `internal`: UInt64, external: UInt64, swapUsed: UInt64, pressureLevel: Int32, memoryLevel: Int32) {
        self.pageSize = pageSize; self.total = total; self.free = free; self.active = active; self.inactive = inactive
        self.speculative = speculative; self.wired = wired; self.compressor = compressor; self.purgeable = purgeable
        self.`internal` = `internal`; self.external = external; self.swapUsed = swapUsed
        self.pressureLevel = pressureLevel; self.memoryLevel = memoryLevel
    }
}

/// Örnekler arası aralık bundan uzunsa (uyku/uyanma) fark atılır: 2 sn tempo × 3 (Review Focus #1).
public enum SampleGap {
    public static let maxInterval: TimeInterval = 6
}

/// Bir ağ arayüzünün 64 bit bayt sayaçları (`NET_RT_IFLIST2`).
public struct InterfaceCounters: Sendable, Equatable {
    public let name: String
    public let rx, tx: UInt64
    public let up: Bool
    public init(name: String, rx: UInt64, tx: UInt64, up: Bool) { self.name = name; self.rx = rx; self.tx = tx; self.up = up }
}

/// Data biriminin kapasitesi (bayt).
public struct VolumeCapacity: Sendable, Equatable {
    public let total, available, availableImportant: UInt64
    public init(total: UInt64, available: UInt64, availableImportant: UInt64) {
        self.total = total; self.available = available; self.availableImportant = availableImportant
    }
}

/// Tüm blok sürücülerinin birikimli okuma/yazma baytları (`IOBlockStorageDriver` → `Statistics`).
public struct DiskIOCounters: Sendable, Equatable {
    public let bytesRead, bytesWritten: UInt64
    public init(bytesRead: UInt64, bytesWritten: UInt64) { self.bytesRead = bytesRead; self.bytesWritten = bytesWritten }
}
