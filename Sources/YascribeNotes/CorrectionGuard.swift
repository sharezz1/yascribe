import Foundation

/// Deterministyczna kontrola zmian słów po modelu korekty. Linia poprawiona jest porównywana z oryginałem token po tokenie;
/// podejrzana zmiana (blok sąsiednich słów) wraca do oryginału, reszta poprawek zostaje. Cofamy:
/// - zmiany zapisu liczb i godzin (`13.30` → `13:30`, „dwunastej" → `12:00`, `2` → „dwa"): prompt każe zostawić zapis;
/// - nowe słowa z artefaktem (`_` w środku, zdublowana litera z ogonkiem `podepnąą`, trzy takie same litery z rzędu);
/// - wstawkę dwóch lub więcej nowych słów bez odpowiednika w oryginale (halucynacja typu „jest try to.").
/// - nowe słowo z błędem pisowni, gdy wszystkie zastąpione słowa były poprawne (`oddziałów` → `odziałów`); tylko z `isMisspelled`.
/// Wielkość liter i interpunkcja na brzegach słów nie są zmianą (porównujemy klucze), więc zwykłe poprawki zostają.
/// shortcut: nie rozpoznajemy podstawienia Termu za niepodobne słowo (`Ogowanie` → `GoOne`): podobieństwo znaków nie odróżnia go od
/// dobrej poprawki `Gołana` → `GoOne`; przeniesione do pomiaru, gdy będzie miara fonetyczna.
public enum CorrectionGuard {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var reverted: Int
    }

    /// `isMisspelled`: słownik systemowy (aplikacja); `nil` = bez kontroli pisowni. `terms`: Termy ze słownika użytkownika
    /// (też ich odmienione formy) nie są uznawane za błąd.
    public static func apply(original: String, corrected: String, isMisspelled: (@Sendable (String) -> Bool)? = nil,
                             terms: [String] = []) -> Result {
        let o = original.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let c = corrected.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !o.isEmpty, !c.isEmpty else { return Result(text: corrected, reverted: 0) }
        var out: [String] = []
        var reverted = 0
        for step in align(o.map(key), c.map(key)) {
            switch step {
            case .same(_, let j): out.append(c[j])
            case .changed(let oi, let ci):
                let before = Array(o[oi]), after = Array(c[ci])
                if suspicious(original: before, corrected: after, isMisspelled: isMisspelled, terms: terms) { out += before; reverted += 1 } else { out += after }
            }
        }
        return reverted == 0 ? Result(text: corrected, reverted: 0) : Result(text: out.joined(separator: " "), reverted: reverted)
    }

    /// Klucz porównania: małe litery, bez interpunkcji na brzegach.
    static func key(_ token: String) -> String {
        token.trimmingCharacters(in: .punctuationCharacters.union(.symbols)).lowercased()
    }

    enum Step { case same(Int, Int), changed(Range<Int>, Range<Int>) }

    /// Najdłuższy wspólny podciąg kluczy (LCS); bloki między wspólnymi tokenami to zmiany. Linie mają do kilkuset słów.
    static func align(_ a: [String], _ b: [String]) -> [Step] {
        let n = a.count, m = b.count
        var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var steps: [Step] = []
        var i = 0, j = 0, oi = 0, ci = 0
        func flush() { if oi < i || ci < j { steps.append(.changed(oi..<i, ci..<j)) }; oi = i; ci = j }
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                flush(); steps.append(.same(i, j)); i += 1; j += 1; oi = i; ci = j
            } else if j < m, i == n || table[i][j + 1] >= table[i + 1][j] { j += 1 }
            else { i += 1 }
        }
        flush()
        return steps
    }

    static func suspicious(original: [String], corrected: [String], isMisspelled: (@Sendable (String) -> Bool)? = nil,
                           terms: [String] = []) -> Bool {
        func hasDigit(_ ts: [String]) -> Bool { ts.contains { $0.contains(where: \.isNumber) } }
        if hasDigit(original) || hasDigit(corrected) { return true }
        if original.isEmpty && corrected.filter({ $0.contains(where: \.isLetter) }).count >= 2 { return true }
        if corrected.contains(where: hasArtifact) { return true }
        guard let isMisspelled else { return false }
        let words = original.map(spellable)
        let known = !words.isEmpty && words.allSatisfy { $0 == nil || !isMisspelled($0!) } && words.contains { $0 != nil }
        return known && corrected.contains { token in
            guard let w = spellable(token), !isTerm(w, terms), isMisspelled(w) else { return false }
            return true
        }
    }

    /// Słowo do sprawdzenia pisowni: same litery, co najmniej 4, nie same wielkie (skróty). Inne tokeny pomijamy.
    static func spellable(_ token: String) -> String? {
        let w = token.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) // wielkość liter zostaje: nazwy własne
        guard w.count >= 4, w.allSatisfy(\.isLetter), w != w.uppercased() else { return nil }
        return w
    }

    /// Term ze słownika albo jego odmieniona forma (wspólny początek bez dwóch ostatnich liter).
    static func isTerm(_ word: String, _ terms: [String]) -> Bool {
        let w = word.lowercased()
        return terms.contains { t in
            let t = t.lowercased()
            let stem = t.count >= 5 ? String(t.dropLast(2)) : String(t.dropLast(1))
            return t == w || (stem.count >= 3 && w.hasPrefix(stem))
        }
    }

    /// Znak `_`, znak zastępczy, trzy takie same litery z rzędu albo dwie takie same litery z ogonkiem (`ąą`, `łł`).
    static func hasArtifact(_ token: String) -> Bool {
        if token.contains("_") || token.contains("\u{FFFD}") { return true }
        let chars = Array(token.lowercased())
        for i in chars.indices.dropFirst() where chars[i].isLetter && chars[i] == chars[i - 1] {
            if !(chars[i].isASCII) { return true }
            if i >= 2, chars[i] == chars[i - 2] { return true }
        }
        return false
    }
}
