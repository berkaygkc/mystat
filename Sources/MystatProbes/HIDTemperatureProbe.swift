import Darwin
import Foundation
import MystatCore
import Synchronization

/// SSD sıcaklığı: HID sıcaklık servisleri (özel `IOHIDEventSystemClient*`; §9.1). Servis başına ≈ 0,7 ms olduğu için
/// çip sıcaklığı SMC'den okunur, buradan yalnızca "NAND" adlı servisler (60 sn'de bir).
public final class HIDTemperatureProbe: Sendable {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatValue = @convention(c) (AnyObject, Int32) -> Double

    private struct State { let client: AnyObject; let services: [AnyObject]; let copyEvent: CopyEvent; let floatValue: FloatValue }
    private let state: Mutex<State>
    static let temperatureEvent: Int64 = 15

    public init?() {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func sym<T>(_ n: String, _: T.Type) -> T? { dlsym(h, n).map { unsafeBitCast($0, to: T.self) } }
        guard let create = sym("IOHIDEventSystemClientCreate", ClientCreate.self), let match = sym("IOHIDEventSystemClientSetMatching", SetMatching.self),
              let copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServices.self),
              let property = sym("IOHIDServiceClientCopyProperty", CopyProperty.self), let event = sym("IOHIDServiceClientCopyEvent", CopyEvent.self),
              let float = sym("IOHIDEventGetFloatValue", FloatValue.self), let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        _ = match(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let all = copyServices(client)?.takeRetainedValue() as? [AnyObject] ?? []
        let nand = all.filter { (property($0, "Product" as CFString)?.takeRetainedValue() as? String)?.hasPrefix("NAND") == true }
        guard !nand.isEmpty else { return nil }
        state = Mutex(State(client: client, services: nand, copyEvent: event, floatValue: float))
    }

    /// Akla yatan değerlerin ortalaması; yoksa nil.
    public func ssd() -> Double? {
        state.withLock { s in
            let values = s.services.compactMap { svc in
                s.copyEvent(svc, Self.temperatureEvent, 0, 0).map { s.floatValue($0.takeRetainedValue(), Int32(Self.temperatureEvent << 16)) }
            }
            return SensorMeterBridge.average(values)
        }
    }
}

/// SensorMeter Task 4'te; buradaki geçici ortalama aynı kuralı kullanır (10…120).
enum SensorMeterBridge {
    static func average(_ v: [Double]) -> Double? {
        let ok = v.filter { $0.isFinite && (10...120).contains($0) }
        return ok.isEmpty ? nil : ok.reduce(0, +) / Double(ok.count)
    }
}
