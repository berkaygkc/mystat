import Foundation
import MystatCore
import MystatTestSupport
import Testing
@testable import MystatLive

/// SQLite history: 10 min and 1 h buckets, 30 days, < 50 MB.
@Suite(.serialized, .language("tr")) struct HistoryStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_793_163_600)   // top of the hour

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mystat-history-\(UUID().uuidString).sqlite")
    }

    /// Writes `.cpu = minute % 60` once a minute; returns the time of the last sample.
    func fill(_ s: HistoryStore, minutes: Int) -> Date {
        for m in 0..<minutes { s.append([(.cpu, Double(m % 60))], at: t0.addingTimeInterval(Double(m) * 60)) }
        return t0.addingTimeInterval(Double(minutes - 1) * 60)
    }

    @Test func storeRollsUpAndReadsH24() throws {
        let s = try HistoryStore(url: tempURL())
        let end = fill(s, minutes: 25 * 60)
        let h24 = s.series(.cpu, .h24, now: end)
        #expect(h24.count == 144)
        #expect(Array(h24.suffix(6)) == [4.5, 14.5, 24.5, 34.5, 44.5, 54.5])   // each point is the average of its own 10 minutes
        let d7 = s.series(.cpu, .d7, now: end)
        #expect(d7.count == 25 && d7.allSatisfy { $0 == 29.5 })
    }

    @Test func reopenKeepsData() throws {
        let url = tempURL()
        var end = Date()
        do { let s = try HistoryStore(url: url); end = fill(s, minutes: 3 * 60); s.close() }
        let again = try HistoryStore(url: url)
        #expect(again.series(.cpu, .h24, now: end).count >= 17)   // closed buckets are on disk
    }

    /// If the app stayed closed for 3 days, old data is not shown as if it were "now".
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

    /// Overnight sleep or a restart does not erase history: the gap stays as missing points (NaN) and what came before remains visible.
    @Test func gapsStayAsMissingPoints() throws {
        let s = try HistoryStore(url: tempURL())
        _ = fill(s, minutes: 120)                                   // 0–2 h
        let resume = t0.addingTimeInterval(5 * 3600)                // 3 h of sleep
        for m in 0..<60 { s.append([(.cpu, 50)], at: resume.addingTimeInterval(Double(m) * 60)) }
        let end = resume.addingTimeInterval(59 * 60)
        let h24 = s.series(.cpu, .h24, now: end)
        try #require(h24.count == 36)                               // 6 h from the first bucket to now = 36 × 10 min
        #expect(h24.prefix(12).allSatisfy(\.isFinite) && h24[12..<30].allSatisfy(\.isNaN) && h24.suffix(6).allSatisfy { $0 == 50 })
        let d7 = s.series(.cpu, .d7, now: end)
        try #require(d7.count == 6)
        #expect(d7[0] == 29.5 && d7[2].isNaN && d7[5] == 50)
    }

    /// A partial bucket is written on shutdown: the last 10 minutes / hour are not lost on restart.
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

    /// Docker data for the daily trend: the local-day average of 1 h buckets; a day with no data is NaN.
    @Test func dailyAveragesPerLocalDay() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let day0 = cal.startOfDay(for: t0)
        func fill(_ s: HistoryStore, days: [Int]) -> Date {
            var last = day0
            for d in days { for h in 0..<24 {
                last = day0.addingTimeInterval(Double(d) * 86_400 + Double(h) * 3600 + 60)
                s.append([(.dockerDisk, 20 + Double(d))], at: last)
            } }
            return last
        }
        let a = try HistoryStore(url: tempURL())
        #expect(a.daily(.dockerDisk, days: 30, now: fill(a, days: [0, 1, 2]), calendar: cal) == [20, 21, 22])
        let b = try HistoryStore(url: tempURL())
        let gap = b.daily(.dockerDisk, days: 30, now: fill(b, days: [0, 2]), calendar: cal)
        #expect(gap.count == 3 && gap[0] == 20 && gap[1].isNaN && gap[2] == 22)
    }

    @Test func trendNeedsTwoDays() {
        #expect(HistoryStore.trend([26]) == nil)
        #expect(HistoryStore.trend([.nan, 26]) == nil)
        #expect(HistoryStore.trend([20, .nan, 29]) == 9)
    }
}
