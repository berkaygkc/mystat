import Darwin
import Foundation
import MystatCore
import Synchronization

/// Energy unit → joules.
public enum UnitScale {
    public static func joules(_ value: Int64, unit: String) -> Double? {
        switch unit { case "mJ": Double(value) * 1e-3; case "uJ": Double(value) * 1e-6; case "nJ": Double(value) * 1e-9; default: nil }
    }
}

/// IOReport "Energy Model" (private `libIOReport`, needs no root). Subscribes to only four of the 278 channels.
public final class IOReportProbe: Sendable {
    private typealias CopyChannels = @convention(c) (CFString, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSub = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary,
                                                 UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> OpaquePointer?
    private typealias CreateSamples = @convention(c) (OpaquePointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleInt = @convention(c) (CFDictionary, Int32) -> Int64

    private struct State {
        let sub: OpaquePointer
        let subbed: CFMutableDictionary
        let createSamples: CreateSamples, name: ChannelString, unit: ChannelString, value: SimpleInt
    }
    private let state: Mutex<State>
    static let wanted: Set<String> = ["CPU Energy", "GPU Energy", "ANE", "DRAM"]

    public init?() {
        guard let h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        func sym<T>(_ n: String, _: T.Type) -> T? { dlsym(h, n).map { unsafeBitCast($0, to: T.self) } }
        guard let copy = sym("IOReportCopyChannelsInGroup", CopyChannels.self), let create = sym("IOReportCreateSubscription", CreateSub.self),
              let samples = sym("IOReportCreateSamples", CreateSamples.self), let name = sym("IOReportChannelGetChannelName", ChannelString.self),
              let unit = sym("IOReportChannelGetUnitLabel", ChannelString.self), let value = sym("IOReportSimpleGetIntegerValue", SimpleInt.self),
              let all = copy("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return nil }
        // Only the requested channels: sampling cost grows with the number of channels.
        let filtered = NSMutableDictionary(dictionary: all as NSDictionary)
        let channels = (filtered["IOReportChannels"] as? [CFDictionary] ?? []).filter { Self.wanted.contains((name($0)?.takeUnretainedValue() as String?) ?? "") }
        guard !channels.isEmpty else { return nil }
        filtered["IOReportChannels"] = channels
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = create(nil, filtered as CFMutableDictionary, &subbed, 0, nil), let s = subbed?.takeRetainedValue() else { return nil }
        state = Mutex(State(sub: sub, subbed: s, createSamples: samples, name: name, unit: unit, value: value))
    }

    public func energy() -> EnergyCounters {
        state.withLock { s in
            var e = EnergyCounters(cpuJ: 0, gpuJ: 0, aneJ: 0, dramJ: 0)
            guard let sample = s.createSamples(s.sub, s.subbed, nil)?.takeRetainedValue() as NSDictionary?,
                  let channels = sample["IOReportChannels"] as? [CFDictionary] else { return e }
            for c in channels {
                guard let n = s.name(c)?.takeUnretainedValue() as String?, let u = s.unit(c)?.takeUnretainedValue() as String?,
                      let j = UnitScale.joules(s.value(c, 0), unit: u) else { continue }
                switch n { case "CPU Energy": e.cpuJ += j; case "GPU Energy": e.gpuJ += j; case "ANE": e.aneJ += j; case "DRAM": e.dramJ += j; default: break }
            }
            return e
        }
    }
}
