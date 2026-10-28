import Foundation

extension Calendar {
    /// Testlerde sabit saat dilimli (Europe/Istanbul) Gregoryen takvim.
    static var trTest: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return cal
    }
}
