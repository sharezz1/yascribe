import Foundation
import MeetNotesProviders

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
}
