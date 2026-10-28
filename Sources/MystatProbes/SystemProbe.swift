import Foundation
import MystatCore

/// Canlı kaynağın sistemden okuduğu her şey. Yalnızca ham sayaç döndürür; anlam Core'da hesaplanır.
/// Testler sahte bir uygulamayla deterministik çalışır. Sonraki tasklar bu protokolü genişletir.
public protocol SystemProbe: Sendable {
    func coreTicks() -> [CoreTicks]
    func vm() -> VMCounters
    func loadAverage() -> [Double]
}
