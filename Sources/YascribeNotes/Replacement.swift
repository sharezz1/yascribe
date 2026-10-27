import Foundation
import YascribeTranscription

/// Reguły Replacement (F21, spec §5): włączone Aliasy słownika skompilowane do jednego wyrażenia. Deterministyczna podmiana
/// bez modelu, stosowana przy odczycie transkryptu (D8), więc musi być idempotentna i tania przy każdym wywołaniu.
/// `@unchecked`: `NSRegularExpression` jest niezmienny i bezpieczny wątkowo, ale nie jest oznaczony jako `Sendable`.
public struct ReplacementRules: @unchecked Sendable {
    private let regex: NSRegularExpression?
    /// Zapis Terma dla grupy przechwytującej `i + 1` (jedna grupa na wpis, w kolejności alternacji).
    private let terms: [String]
    /// Filtr wstępny (R17): klucze (`UserDictionary.key`) pierwszego słowa wpisów. Dopasowanie zaczyna się na granicy słowa, a pierwsze
    /// słowo wpisu kończy się granicą, więc musi być całym słowem tekstu o tym samym kluczu. `aliases`: tylko Aliasy (bez żadnego
    /// tekst się nie zmieni, wpisy Termów tylko chronią); `entries`: Aliasy i Termy (miejsca, od których próbujemy dopasowania).
    /// `nil` = któryś wpis zaczyna się od znaku spoza słowa: zawsze pełne przeszukanie.
    private let starts: (aliases: Set<String>, entries: Set<String>)?

    /// Aliasy włączone i niepuste (plik `dictionary.json` mógł ominąć `upsert`: pusty Alias wstawiałby Term na każdej granicy słowa),
    /// w NFC, od najdłuższego: alternacja bierze pierwszą pasującą gałąź, więc „on track" musi stać przed „on".
    public init(_ d: UserDictionary) {
        let aliases = d.terms.flatMap { term in
            term.aliases.filter { $0.enabled }.map { (text: Self.nfc($0.text), caseless: true, term: Self.nfc(term.text)) }
        }.filter { !$0.text.isEmpty }
        guard !aliases.isEmpty else { terms = []; regex = nil; starts = nil; return }
        // Tekst każdego Terma jako wpis tożsamościowy (z wielkością liter, R9): „Kopt Max" dopasowany w całości nie jest skanowany
        // dalej, więc zawarty w nim Alias „kopt" nie zrobi z niego „Kopt Max Max" przy drugim zastosowaniu (idempotencja).
        let identities = d.terms.map { (text: Self.nfc($0.text), caseless: false, term: Self.nfc($0.text)) }.filter { !$0.text.isEmpty }
        let entries = (aliases + identities).sorted { $0.text.count > $1.text.count }
        terms = entries.map(\.term)
        // Literały (bez znaczenia `.`, `+`, `(`) i granice słów Unicode: litera, cyfra albo znak łączący (akcent) przedłuża słowo.
        let alternation = entries.map { "(" + ($0.caseless ? "(?i:" : "(?:") + NSRegularExpression.escapedPattern(for: $0.text) + "))" }
            .joined(separator: "|")
        // `try?`: wzorzec składa się z ucieczkowanych literałów i stałych granic, więc kompilacja nie może zawieść.
        regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}\\p{M}])(?:\(alternation))(?![\\p{L}\\p{N}\\p{M}])")
        let firsts = entries.map { Self.words(in: $0.text).first.flatMap { $0.offset == 0 ? UserDictionary.key($0.text) : nil } }
        starts = firsts.contains(nil) ? nil
            : (Set(zip(entries, firsts).filter { $0.0.caseless }.compactMap(\.1)), Set(firsts.compactMap { $0 }))
    }

    /// Brak włączonych Aliasów: Replacement nic nie robi (transkrypt i polecenia bajt w bajt jak bez słownika).
    public var isEmpty: Bool { regex == nil }

    /// Przejścia aż do punktu stałego (R10), najwyżej 5; bez zbieżności zwraca ostatni wynik. Wstawiony Term może razem z sąsiednim
    /// tekstem utworzyć nowy Alias („x y" → „A y", a „A y" to Alias B), więc jedno przejście nie jest idempotentne. Tekst bez zmian
    /// kosztuje jedno przejście.
    public func apply(to text: String) -> String { apply(to: text, preFilter: true) }

    /// `preFilter: false` (pełne przeszukanie wyrażeniem) tylko dla testu równoważności z filtrem.
    func apply(to text: String, preFilter: Bool) -> String {
        // shortcut: tekst pominięty przez filtr wraca bez NFC, choć wpis Terma by go znormalizował (R19); kanonicznie równy (`==`, klucze), więc bez różnicy dla użytkownika.
        guard let regex, !preFilter || mayMatch(text) else { return text }
        var current = text
        for _ in 0..<5 {
            let next = Self.once(current, regex, terms, from: preFilter ? starts?.entries : nil)
            if next == current { return next }
            current = next
        }
        return current
    }

    /// Czy w tekście jest słowo o kluczu pierwszego słowa któregoś Aliasu; przy filtrze wyłączonym — zawsze tak.
    func mayMatch(_ text: String) -> Bool {
        guard let starts else { return true }
        return Self.words(in: text.precomposedStringWithCanonicalMapping).contains { starts.aliases.contains(UserDictionary.key($0.text)) }
    }

    /// Maksymalne ciągi liter, cyfr i znaków łączących — te same klasy co granice słów w wyrażeniu (`\p{L}\p{N}\p{M}`) — z przesunięciem
    /// w jednostkach UTF-16 (jak `NSRange`).
    private static func words(in s: String) -> [(text: String, offset: Int)] {
        var out: [(text: String, offset: Int)] = []
        var word = String.UnicodeScalarView()
        var start = 0
        var offset = 0
        for scalar in s.unicodeScalars {
            if isWord(scalar) {
                if word.isEmpty { start = offset }
                word.append(scalar)
            } else if !word.isEmpty {
                out.append((String(word), start))
                word = String.UnicodeScalarView()
            }
            offset += scalar.utf16.count
        }
        if !word.isEmpty { out.append((String(word), start)) }
        return out
    }

    private static func isWord(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber, .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    /// Licznik wywołań `once` (przebiegów wyrażenia) dla testu filtra wstępnego. Zmienna zadania: równoległe testy jej nie widzą,
    /// ale dziedziczą ją zadania potomne, więc licznik jest pod blokadą.
    final class RegexRuns: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func increment() { lock.withLock { value += 1 } }
    }
    @TaskLocal static var regexRuns: RegexRuns?

    /// Jedno przejście, bez ponownego skanowania wstawionych Termów. Dopasowanie na tekście w NFC (Alias z NFD ze schowka trafia
    /// w tekst NFC i odwrotnie); tekst bez dopasowań wraca nietknięty, z dopasowaniem — w NFC. Z `from` wyrażenie próbuje tylko od
    /// początków słów o kluczu z tego zbioru, od lewej (zakotwiczone, z widocznym tekstem przed zakresem dla lookbehind): najbardziej
    /// lewe dopasowanie zaczyna się na takim słowie, więc wynik jest ten sam co przy pełnym przeszukaniu, a ICU nie skanuje każdej pozycji.
    private static func once(_ text: String, _ regex: NSRegularExpression, _ terms: [String], from starts: Set<String>?) -> String {
        regexRuns?.increment()
        let source = text.precomposedStringWithCanonicalMapping as NSString
        let string = source as String
        var matches: [NSTextCheckingResult] = []
        if let starts {
            var end = 0
            for word in words(in: string) where word.offset >= end && starts.contains(UserDictionary.key(word.text)) {
                let range = NSRange(location: word.offset, length: source.length - word.offset)
                guard let m = regex.firstMatch(in: string, options: [.anchored, .withTransparentBounds], range: range) else { continue }
                matches.append(m)
                end = NSMaxRange(m.range)
            }
        } else {
            matches = regex.matches(in: string, range: NSRange(location: 0, length: source.length))
        }
        guard !matches.isEmpty else { return text }
        var out = ""
        var last = 0
        for m in matches {
            out += source.substring(with: NSRange(location: last, length: m.range.location - last))
            // Indeks grupy, nie ponowne porównanie dopasowanego tekstu z Aliasami: grupa wskazuje wpis wprost.
            if let i = (1...terms.count).first(where: { m.range(at: $0).location != NSNotFound }) { out += terms[i - 1] }
            last = NSMaxRange(m.range)
        }
        return out + source.substring(from: last)
    }

    /// Dla Aliasów i Termów (jak `UserDictionary.clean`), nie dla tekstu wypowiedzi: ten nie jest przycinany.
    private static func nfc(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }
}

/// Replacement na transkrypcie: zmienia wyłącznie `Utterance.text`; słowa, czasy, mówca i flagi zostają surowe.
public enum Replacement {
    public static func apply(_ t: Transcript, rules: ReplacementRules) -> Transcript {
        guard !rules.isEmpty else { return t }
        var out = t
        for i in out.utterances.indices { out.utterances[i].text = rules.apply(to: out.utterances[i].text) }
        return out
    }
}
