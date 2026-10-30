import Foundation

/// Suffixes that follow a number. The suffix is chosen by the last word in the number's spoken form.
public enum TurkishSuffix {
    /// Third-person possessive suffix: 12,7 ("yedi") → "'si", 3 ("uc", with umlaut) → rounded front vowel, 4,0 ("sifir", dotless i) → unrounded back vowel.
    public static func possessive3(after number: String) -> String {
        let last = number.split(separator: ",").last.map(String.init) ?? number
        let digits = last.filter(\.isNumber)
        guard let n = Int(digits) else { return "'i" }
        if n == 0 { return "'ı" }
        let units = ["", "'i", "'si", "'ü", "'ü", "'i", "'sı", "'si", "'i", "'u"]
        let tens = ["", "'u", "'si", "'u", "'ı", "'si", "'ı", "'i", "'i", "'ı"]
        if n % 10 != 0 { return units[n % 10] }
        if (n / 10) % 10 != 0 { return tens[(n / 10) % 10] }
        if (n / 100) % 10 != 0 { return "'ü" }   // "hundred"
        return "'i"                               // "thousand"
    }

    /// Genitive suffix: 90 ("doksan") takes the back-vowel form, 70 ("yetmis") the front-vowel form, 2 ("iki") the form with a buffer "n".
    public static func genitive(after number: String) -> String {
        let last = number.split(separator: ",").last.map(String.init) ?? number
        guard let n = Int(last.filter(\.isNumber)) else { return "'in" }
        if n == 0 { return "'ın" }
        let units = ["", "'in", "'nin", "'ün", "'ün", "'in", "'nın", "'nin", "'in", "'un"]
        let tens = ["", "'un", "'nin", "'un", "'ın", "'nin", "'ın", "'in", "'in", "'ın"]
        if n % 10 != 0 { return units[n % 10] }
        if (n / 10) % 10 != 0 { return tens[(n / 10) % 10] }
        if (n / 100) % 10 != 0 { return "'ün" }   // "hundred"
        return "'in"                               // "thousand"
    }
}
