import Foundation

/// Przerywniki w poprawionym transkrypcie („yyy", „mhm"): deterministyczny filtr słów z listy,
/// bez modelu. Działa na tekście po korekcie (F20 P2); surowy transkrypt zostaje nietknięty.
public enum FillerWords {
    /// Same dźwięki bez znaczenia (nie „no", „tak", „wiesz", „znaczy"): polskie i angielskie. Lista użytkownika w Settings zastępuje tę.
    public static let defaults = ["yyy", "eee", "ehm", "yhm", "mhm", "mmm", "hmm", "ym", "um", "uh", "er", "erm", "uhm"]

    /// „yyy, eee, mhm" → słowa (przecinki, średniki i końce linii; małe litery, bez powtórzeń).
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { ",;\n".contains($0) }).compactMap { part in
            let w = normalize(String(part))
            return w.isEmpty || !seen.insert(w).inserted ? nil : w
        }
    }

    public static func format(_ words: [String]) -> String { words.joined(separator: ", ") }

    /// Małe litery, bez interpunkcji i spacji na brzegach („Mhm," → „mhm").
    static func normalize(_ token: String) -> String {
        token.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)).lowercased()
    }

    /// „yyyy" → „y": rozciągnięty przerywnik („yyyyy", „eeee") pasuje do wpisu „yyy" / „eee".
    private static func collapsed(_ s: String) -> String {
        var out = ""
        for c in s where out.last != c { out.append(c) }
        return out
    }

    /// Dokładne dopasowanie albo rozciągnięcie (co najmniej 2 znaki: pojedyncze „m" z „5 m" nie jest przerywnikiem „mm").
    private static func matches(_ core: String, _ words: [String]) -> Bool {
        words.contains { $0 == core || (core.count >= 2 && collapsed($0) == collapsed(core)) }
    }

    private static func endsSentence(_ token: String) -> Bool { token.last.map { ".!?…".contains($0) } ?? false }

    /// Usuwa słowa z listy. Kropka lub znak zapytania usuniętego słowa przechodzi na poprzednie („Wiem yyy." → „Wiem."), a po usuniętym
    /// początku zdania następne słowo dostaje wielką literę („Yyy, to jest" → „To jest"). Tekst złożony wyłącznie z przerywników zostaje
    /// bez zmian (nie tworzymy pustych wypowiedzi). `words` puste = bez zmian.
    public static func remove(_ text: String, words: [String]) -> String {
        let list = words.map(normalize).filter { !$0.isEmpty }
        guard !list.isEmpty else { return text }
        var out: [String] = []
        var capitalizeNext = false
        var changed = false
        for token in text.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            let core = normalize(token)
            if !core.isEmpty, matches(core, list) {
                changed = true
                if token.first?.isUppercase == true, out.isEmpty || endsSentence(out[out.count - 1]) { capitalizeNext = true }
                if let last = out.last, let end = token.last, ".!?…".contains(end), !endsSentence(last) {
                    out[out.count - 1] = last.trimmingCharacters(in: CharacterSet(charactersIn: ",;:")) + String(end)
                }
                continue
            }
            var kept = token
            if capitalizeNext, let first = kept.first { kept = first.uppercased() + kept.dropFirst() }
            capitalizeNext = false
            out.append(kept)
        }
        guard changed, !out.isEmpty else { return text }
        return out.joined(separator: " ")
    }
}
