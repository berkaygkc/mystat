import Foundation
import MystatCore
import Testing
@testable import MystatLive

/// SQLite geçmişi (spec §9.4): 10 dk ve 1 sa kovaları, 30 gün, < 50 MB.
@Suite(.serialized) struct HistoryStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_793_163_600)   // saat başı

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mystat-history-\(UUID().uuidString).sqlite")
    }

    /// Dakikada bir `.cpu = dakika % 60` yazar; son örneğin zamanını döndürür.
    func fill(_ s: HistoryStore, minutes: Int) -> Date {
        for m in 0..<minutes { s.append([(.cpu, Double(m % 60))], at: t0.addingTimeInterval(Double(m) * 60)) }
        return t0.addingTimeInterval(Double(minutes - 1) * 60)
    }

    @Test func storeRollsUpAndReadsH24() throws {
        let s = try HistoryStore(url: tempURL())
        let end = fill(s, minutes: 25 * 60)
        let h24 = s.series(.cpu, .h24, now: end)
        #expect(h24.count == 144)
        #expect(Array(h24.suffix(6)) == [4.5, 14.5, 24.5, 34.5, 44.5, 54.5])   // her nokta kendi 10 dakikasının ortalaması
        let d7 = s.series(.cpu, .d7, now: end)
        #expect(d7.count == 25 && d7.allSatisfy { $0 == 29.5 })
    }

    @Test func reopenKeepsData() throws {
        let url = tempURL()
        var end = Date()
        do { let s = try HistoryStore(url: url); end = fill(s, minutes: 3 * 60); s.close() }
        let again = try HistoryStore(url: url)
        #expect(again.series(.cpu, .h24, now: end).count >= 17)   // kapanmış kovalar diskte
    }

    /// Uygulama 3 gün kapalı kaldıysa eski veri "şimdi" gibi gösterilmez.
    @Test func staleRunIsNotShownAsRecent() throws {
        let s = try HistoryStore(url: tempURL())
        let end = fill(s, minutes: 120)
        #expect(s.series(.cpu, .h24, now: end.addingTimeInterval(3 * 86_400)).isEmpty)
    }

    @Test func pruneKeepsSizeUnderBudget() throws {
        let url = tempURL()
        let s = try HistoryStore(url: url)
        let keys: [SeriesKey] = [.cpu, .cpuSystem, .memUsed, .memPressure, .netDown, .netUp, .diskRead, .diskWrite, .battery]
        let minutes = 31 * 1440
        for m in 0..<minutes { s.append(keys.map { ($0, Double(m % 97)) }, at: t0.addingTimeInterval(Double(m) * 60)) }
        let end = t0.addingTimeInterval(Double(minutes) * 60)
        s.prune(now: end)
        s.close()
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        #expect(size < 50_000_000)
        let again = try HistoryStore(url: url)
        #expect(again.oldest(tier: 600).map { end.timeIntervalSince($0) <= 7 * 86_400 + 600 } == true)
        #expect(again.oldest(tier: 3600).map { end.timeIntervalSince($0) <= 30 * 86_400 + 3600 } == true)
    }

    @Test func incidentsAreRecorded() throws {
        let s = try HistoryStore(url: tempURL())
        s.recordIncident(Incident(kind: .cpu, level: .crit, startedAt: "08:41", minutes: 4, peakPercent: 97, culpritIDs: ["a"],
                                  culpritValues: ["4,2"], culpritUnit: "çekirdek", facts: []), at: t0)
        #expect(s.incidentCount() == 1)
    }

    /// Gece uykusu ya da yeniden başlatma geçmişi silmez: boşluk eksik nokta (NaN) olarak kalır, öncesi görünür.
    @Test func gapsStayAsMissingPoints() throws {
        let s = try HistoryStore(url: tempURL())
        _ = fill(s, minutes: 120)                                   // 0–2 sa
        let resume = t0.addingTimeInterval(5 * 3600)                // 3 sa uyku
        for m in 0..<60 { s.append([(.cpu, 50)], at: resume.addingTimeInterval(Double(m) * 60)) }
        let end = resume.addingTimeInterval(59 * 60)
        let h24 = s.series(.cpu, .h24, now: end)
        try #require(h24.count == 36)                               // ilk kovadan şimdiye 6 sa = 36 × 10 dk
        #expect(h24.prefix(12).allSatisfy(\.isFinite) && h24[12..<30].allSatisfy(\.isNaN) && h24.suffix(6).allSatisfy { $0 == 50 })
        let d7 = s.series(.cpu, .d7, now: end)
        try #require(d7.count == 6)
        #expect(d7[0] == 29.5 && d7[2].isNaN && d7[5] == 50)
    }

    /// Kapanırken yarım kova yazılır: yeniden başlatmada son 10 dakika / saat kaybolmaz.
    @Test func flushKeepsPartialBucket() throws {
        let url = tempURL()
        do {
            let s = try HistoryStore(url: url)
            for m in 0..<5 { s.append([(.cpu, 40)], at: t0.addingTimeInterval(Double(m) * 60)) }
            s.flush()
            s.close()
        }
        let again = try HistoryStore(url: url)
        #expect(again.series(.cpu, .h24, now: t0.addingTimeInterval(4 * 60)) == [40])
    }
}
