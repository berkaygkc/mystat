import Foundation

/// Sayıdan sonra gelen ekler. Ek, sayının okunuşundaki son kelimeye göre seçilir.
public enum TurkishSuffix {
    /// 3. tekil iyelik eki: "12,7" → "'si" (yedi), "3" → "'ü" (üç), "4,0" → "'ı" (sıfır).
    public static func possessive3(after number: String) -> String {
        let last = number.split(separator: ",").last.map(String.init) ?? number
        let digits = last.filter(\.isNumber)
        guard let n = Int(digits) else { return "'i" }
        if n == 0 { return "'ı" }
        let units = ["", "'i", "'si", "'ü", "'ü", "'i", "'sı", "'si", "'i", "'u"]
        let tens = ["", "'u", "'si", "'u", "'ı", "'si", "'ı", "'i", "'i", "'ı"]
        if n % 10 != 0 { return units[n % 10] }
        if (n / 10) % 10 != 0 { return tens[(n / 10) % 10] }
        if (n / 100) % 10 != 0 { return "'ü" }   // yüz
        return "'i"                               // bin
    }
}
