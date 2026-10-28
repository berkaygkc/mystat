import Foundation
import IOKit
import MystatCore
import Synchronization

/// AppleSMC: sıcaklık anahtarları, fan ve sistem gücü (kullanıcı yetkisiyle, §10). Anahtar okuması ≈ 0,33 ms (iki çağrı).
/// Çağrı yapısı 80 bayt: anahtar 0, `keyInfo.dataSize` 28, `dataType` 32, sonuç 40, komut 42, indeks 44, veri 48.
public final class SMCProbe: Sendable {
    private let conn: Mutex<io_connect_t>
    /// Anahtarın tipi ve boyutu değişmez: bilgi çağrısı bir kez, sonraki okumalar tek çağrı (maliyet yarıya iner).
    private let info = Mutex<[String: (type: String, size: UInt32)]>([:])
    private enum Command: UInt8 { case read = 5, keyAtIndex = 8, info = 9 }

    public init?() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var c: io_connect_t = 0
        guard IOServiceOpen(svc, mach_task_self_, 0, &c) == kIOReturnSuccess else { return nil }
        conn = Mutex(c)
    }

    deinit { conn.withLock { _ = IOServiceClose($0) } }

    public func value(_ key: String) -> Double? {
        conn.withLock { c in
            let known = info.withLock { $0[key] }
            guard let (type, size) = known ?? keyInfo(c, key) else { return nil }
            if known == nil { info.withLock { $0[key] = (type, size) } }
            guard let out = call(c, key: key, command: .read, size: size) else { return nil }
            return SMCValue.decode(type: type, bytes: Array(out[48..<(48 + Int(size))]))
        }
    }

    private func keyInfo(_ c: io_connect_t, _ key: String) -> (type: String, size: UInt32)? {
        guard let out = call(c, key: key, command: .info) else { return nil }
        let size = out[28...31].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard size > 0, size <= 32 else { return nil }
        return (String(decoding: out[32...35].reversed(), as: UTF8.self), size)
    }

    /// Tüm anahtarlar (≈ 3.300, 1–2 sn): yalnızca bir kez, ölçüm döngüsü dışında çağrılır; sonuç önbelleğe alınır.
    public func discover() -> SensorMap {
        let count = Int(value("#KEY") ?? 0)
        var temps: [String: Double] = [:]
        for i in 0..<count {
            guard let key = keyAt(UInt32(i)), key.hasPrefix("T"), let v = value(key) else { continue }
            temps[key] = v
        }
        return SensorMap.classify(temps, fans: Int(value("FNum") ?? 0))
    }

    private func keyAt(_ index: UInt32) -> String? {
        conn.withLock { c in
            var input = [UInt8](repeating: 0, count: 80)
            input[42] = Command.keyAtIndex.rawValue
            withUnsafeBytes(of: index) { for j in 0..<4 { input[44 + j] = $0[j] } }
            guard let out = exchange(c, input) else { return nil }
            return String(decoding: out[0...3].reversed(), as: UTF8.self)
        }
    }

    private func call(_ c: io_connect_t, key: String, command: Command, size: UInt32 = 0) -> [UInt8]? {
        let k = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        var input = [UInt8](repeating: 0, count: 80)
        withUnsafeBytes(of: k) { for j in 0..<4 { input[j] = $0[j] } }
        withUnsafeBytes(of: size) { for j in 0..<4 { input[28 + j] = $0[j] } }
        input[42] = command.rawValue
        return exchange(c, input)
    }

    private func exchange(_ c: io_connect_t, _ input: [UInt8]) -> [UInt8]? {
        var inB = input, out = [UInt8](repeating: 0, count: 80), outSize = 80
        let r = IOConnectCallStructMethod(c, 2, &inB, 80, &out, &outSize)
        return r == kIOReturnSuccess && out[40] == 0 ? out : nil
    }

    // MARK: - Önbellek (makine modeli + macOS sürümü)

    static let cacheKey = "mystat.sensorMap"
    /// Sınıflama kuralı değişince artırılır: eski önbellek yeniden keşfedilir.
    static let cacheVersion = 1
    private struct Cached: Codable { let version: Int, model: String, os: String, map: SensorMap }

    public static func cachedMap(model: String, os: String, defaults: UserDefaults) -> SensorMap? {
        guard let data = defaults.data(forKey: cacheKey), let c = try? JSONDecoder().decode(Cached.self, from: data),
              c.version == cacheVersion, c.model == model, c.os == os, !c.map.cpu.isEmpty else { return nil }
        return c.map
    }

    public static func storeMap(_ m: SensorMap, model: String, os: String, defaults: UserDefaults) {
        guard !m.cpu.isEmpty else { return }   // tek seferlik okuma hatası sensörleri macOS güncellemesine kadar kapatmasın
        if let data = try? JSONEncoder().encode(Cached(version: cacheVersion, model: model, os: os, map: m)) { defaults.set(data, forKey: cacheKey) }
    }
}
