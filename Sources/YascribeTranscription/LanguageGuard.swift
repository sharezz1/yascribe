import Foundation
import YascribeProviders

/// 🔴 Strażnik języka na wyjściu (spec fazy 1, §1.5, P11). Dla modeli, które same
/// wybierają język, to jedyna obrona przed konfabulacją z rozdz. 14: fragment,
/// który w presecie polskim czyta się jak angielski, zostaje oznaczony i nie
/// trafia do notatki jako fakt.
///
/// Heurystyka ze słów funkcyjnych, w fazie 1 tylko dla pary polski/angielski.
/// Dla innych języków strażnik milczy — lepiej nie oznaczyć niż oznaczyć źle.
public enum LanguageGuard {
    static let polishStop: Set<String> = ["i", "w", "na", "nie", "się", "to", "że", "jest", "z", "do", "jak", "ale",
                                          "co", "tak", "po", "o", "czy", "mamy", "jestem", "no", "tu", "już", "być",
                                          "od", "za", "dla", "ten", "ta", "te", "sobie", "tym", "tego", "przez", "są"]
    static let englishStop: Set<String> = ["the", "and", "is", "to", "of", "you", "that", "it", "in", "for", "am",
                                           "are", "be", "this", "we", "with", "have", "not", "on", "at", "will", "can",
                                           "there", "here", "what", "very", "so", "do", "my", "your", "a", "an"]
    static let polishLetters = Set("ąćęłńóśźż")

    /// Język, na który wygląda tekst, jeśli wyraźnie różny od oczekiwanego; inaczej `nil`.
    public static func mismatch(_ text: String, expected: LanguageCode) -> LanguageCode? {
        guard expected == .polish || expected == .english else { return nil }
        let words = ProbeClips.normalize(text).split(separator: " ").map(String.init)
        guard words.count >= 4 else { return nil } // za krótko, żeby orzekać
        let pl = words.filter { polishStop.contains($0) }.count
        let en = words.filter { englishStop.contains($0) }.count
        let hasPolishLetters = text.lowercased().contains { polishLetters.contains($0) }
        switch expected {
        case .polish:
            return !hasPolishLetters && en >= 2 && en > pl * 2 ? .english : nil
        case .english:
            return hasPolishLetters && pl >= 2 && pl > en ? .polish : nil
        default:
            return nil
        }
    }

    /// Auto: wypowiedź, w której większość liter nie jest łacińska, to bełkot (tryb wielojęzyczny na polskim → cyrylica).
    /// Zwraca język dominującego obcego alfabetu (`ru`, `el`, `ja`…, a dla nieznanego `zz`); za mało liter albo większość
    /// łacińska → `nil` (jeden cudzy wyraz w polskim zdaniu nie jest bełkotem).
    public static func nonLatinScript(_ text: String) -> LanguageCode? {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard letters.count >= 4 else { return nil }
        let foreign = letters.filter { !isLatin($0) }
        guard foreign.count * 2 > letters.count else { return nil }
        let code: String
        switch foreign[foreign.startIndex].value {
        case 0x0400...0x052F: code = "ru"
        case 0x0370...0x03FF: code = "el"
        case 0x0590...0x05FF: code = "he"
        case 0x0600...0x06FF: code = "ar"
        case 0x0900...0x097F: code = "hi"
        case 0x0E00...0x0E7F: code = "th"
        case 0x3040...0x30FF: code = "ja"
        case 0xAC00...0xD7AF: code = "ko"
        case 0x4E00...0x9FFF: code = "zh"
        default: code = "zz"
        }
        return try? LanguageCode(code)
    }

    static func isLatin(_ s: Unicode.Scalar) -> Bool { s.value <= 0x024F || (0x1E00...0x1EFF).contains(s.value) }
}
