import Foundation
import YascribeTranscription

/// Deterministyczna kontrola zmian słów po modelu korekty. Linia poprawiona jest porównywana z oryginałem token po tokenie;
/// podejrzana zmiana (blok sąsiednich słów) wraca do oryginału, reszta poprawek zostaje. Cofamy:
/// - zmiany zapisu liczb i godzin (`13.30` → `13:30`, „dwunastej" → `12:00`, `2` → „dwa"): prompt każe zostawić zapis;
/// - nowe słowa z artefaktem (`_` w środku, zdublowana litera z ogonkiem `podepnąą`, trzy takie same litery z rzędu);
/// - wstawkę dwóch lub więcej nowych słów bez odpowiednika w oryginale (halucynacja typu „jest try to.").
/// - usunięcie słów bez zamiennika („jeszcze"); wolno usunąć przerywniki z `fillerWords`, same znaki, powtórzenie słowa stojącego
///   tuż obok (jąkanie „I, i, no i"; przy nim LCS i tak nie wie, który egzemplarz zniknął) i urwany początek („wrzucić tam wrzucamy"
///   → „wrzucamy"), gdy `fillerWords` niepusta.
/// - nowe słowo z błędem pisowni, gdy wszystkie zastąpione słowa były poprawne (`oddziałów` → `odziałów`); tylko z `isMisspelled`.
/// Poza cofaniem przywracamy końcówkę, gdy model zamienił odmienione słowo na Term w formie podstawowej
/// (`na Genesisa` → `na Genesys` daje `na Genesysa`); liczy się to jak cofnięcie.
/// Wielkość liter i interpunkcja na brzegach słów nie są zmianą (porównujemy klucze), więc zwykłe poprawki zostają.
/// shortcut: nie rozpoznajemy podstawienia Termu za niepodobne słowo (`Ogowanie` → `GoOne`): podobieństwo znaków nie odróżnia go od
/// dobrej poprawki `Gołana` → `GoOne`; przeniesione do pomiaru, gdy będzie miara fonetyczna.
public enum CorrectionGuard {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var reverted: Int
    }

    /// `isMisspelled`: słownik systemowy (aplikacja); `nil` = bez kontroli pisowni. `terms`: Termy ze słownika użytkownika
    /// (też ich odmienione formy) nie są uznawane za błąd. `fillerWords`: przerywniki, które model może usunąć (pusta = żadne).
    public static func apply(original: String, corrected: String, isMisspelled: (@Sendable (String) -> Bool)? = nil,
                             terms: [String] = [], fillerWords: [String] = []) -> Result {
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
                if suspicious(original: before, corrected: after, isMisspelled: isMisspelled, terms: terms)
                    || deletesWords(original: before, corrected: after, fillerWords: fillerWords,
                                    neighbours: o[max(0, oi.lowerBound - 2)..<oi.lowerBound].map(key) + o[oi.upperBound..<min(o.count, oi.upperBound + 2)].map(key),
                                    following: o[oi.upperBound..<min(o.count, oi.upperBound + 6)].map(key)) {
                    out += before; reverted += 1
                }
                else if before.count == after.count, let fixed = restoredEndings(original: before, corrected: after, terms: terms) { out += fixed; reverted += 1 }
                else { out += after }
            }
        }
        return reverted == 0 ? Result(text: corrected, reverted: 0) : Result(text: out.joined(separator: " "), reverted: reverted)
    }

    /// Klucz porównania: małe litery, bez interpunkcji na brzegach.
    static func key(_ token: String) -> String { TokenAlign.key(token) }

    typealias Step = TokenAlign.Step

    static func align(_ a: [String], _ b: [String]) -> [Step] { TokenAlign.align(a, b) }

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

    /// Blok bez zamiennika, w którym znika token z literami, niebędący przerywnikiem ani powtórzeniem sąsiada (dwa słowa z każdej strony).
    /// Wyjątek: urwany początek wypowiedzi („wrzucić tam wrzucamy" → „wrzucamy"): do 4 słów, a pierwsze wraca zaraz potem (`following`,
    /// ten sam początek słowa). Tylko przy włączonym usuwaniu przerywników (`fillerWords` niepusta).
    /// shortcut: „restart" poznajemy po wspólnych 4 literach początku słowa, nie po sensie; zbyt luźne przy pomiarze → zaostrzyć.
    static func deletesWords(original: [String], corrected: [String], fillerWords: [String], neighbours: [String] = [],
                             following: [String] = []) -> Bool {
        guard corrected.isEmpty, original.contains(where: {
            $0.contains(where: \.isLetter) && !FillerWords.isFiller($0, words: fillerWords) && !neighbours.contains(key($0))
        }) else { return false }
        let words = original.filter { $0.contains(where: \.isLetter) && !FillerWords.isFiller($0, words: fillerWords) }.map(key)
        guard !fillerWords.isEmpty, words.count <= 4, let first = words.first else { return true }
        return !following.contains { sameStart(first, $0) }
    }

    static func sameStart(_ a: String, _ b: String) -> Bool {
        a == b || (a.count >= 4 && b.count >= 4 && a.prefix(4) == b.prefix(4))
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

    /// Końcówki przypadków i przymiotników od nazw, najdłuższe najpierw (`Genesysowe` nie może stać się `Genesyse`).
    static let caseEndings = ["owego", "owych", "owym", "owej", "owe", "owa", "owy", "ach", "ami", "owi", "em", "om", "ie", "ów",
                              "a", "u", "y", "i", "ę", "ą", "e"].sorted { $0.count > $1.count }

    /// Słowo poprawione na Term w formie podstawowej dostaje końcówkę z oryginału (słowa parami, ten sam blok).
    /// Pomijamy: oryginał krótszy niż Term (`Genesa` to nie odmiana), Term kończący się tą końcówką (`Elekta` → `Lekta`).
    /// shortcut: Termy na samogłoskę (`Lekta` → `Lekty`) wymieniają ostatnią literę, tego nie odtwarzamy; dopisać, gdy wystąpi w pomiarze.
    static func restoredEndings(original: [String], corrected: [String], terms: [String]) -> [String]? {
        var out = corrected, changed = false
        for (k, (o, c)) in zip(original, corrected).enumerated() {
            let ok = key(o), ck = key(c)
            guard terms.contains(where: { $0.lowercased() == ck }), ok.count >= ck.count,
                  let ending = caseEndings.first(where: { ok.hasSuffix($0) && ok.count > $0.count }), !ck.hasSuffix(ending),
                  let r = c.range(of: ck, options: .caseInsensitive) else { continue }
            out[k] = c.replacingCharacters(in: r, with: c[r] + ending)
            changed = true
        }
        return changed ? out : nil
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
