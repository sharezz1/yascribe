import Foundation
import YascribeTranscription

/// Reguły Replacement (F21, spec §5): włączone Aliasy słownika skompilowane do jednego wyrażenia. Deterministyczna podmiana
/// bez modelu, stosowana przy odczycie transkryptu (D8), więc musi być idempotentna i tania przy każdym wywołaniu.
/// `@unchecked`: `NSRegularExpression` jest niezmienny i bezpieczny wątkowo, ale nie jest oznaczony jako `Sendable`.
public struct ReplacementRules: @unchecked Sendable {
    private let regex: NSRegularExpression?
    /// Jedna pozycja na wpis alternacji, w jej kolejności: numer grupy przechwytującej wpisu, zapis Terma i (wpisy z odmianą) numer grupy końcówki.
    private let slots: [(group: Int, term: String, suffixGroup: Int?)]
    /// Filtr wstępny (R17): pierwsze słowo wpisu musi być całym słowem tekstu o tym samym kluczu (`UserDictionary.key`), a przy wpisie z odmianą
    /// o rdzeniu jednowyrazowym — słowem zaczynającym się od rdzenia (prefiks na skalarach NFD). `aliases`: tylko Aliasy (bez żadnego
    /// tekst się nie zmieni, wpisy Termów tylko chronią); `entries`: Aliasy i Termy (miejsca, od których próbujemy dopasowania).
    /// `nil` = któryś wpis zaczyna się od znaku spoza słowa: zawsze pełne przeszukanie.
    private let starts: (aliases: Starts, entries: Starts)?

    private struct Starts {
        var exact = Set<String>()
        var prefixes: [[Unicode.Scalar]] = []

        func matches(_ word: String) -> Bool {
            let key = UserDictionary.key(word)
            if exact.contains(key) { return true }
            guard !prefixes.isEmpty else { return false }
            let folded = Array(key.decomposedStringWithCanonicalMapping.unicodeScalars)
            return prefixes.contains { folded.starts(with: $0) }
        }
    }

    private struct Entry {
        var text: String
        var caseless: Bool
        var term: String
        var inflects: Bool
        /// Warstwa kolejności: 0 = tożsamość z odmianą, 1 = wpis bez odmiany, 2 = Alias z odmianą. Długość tekstu nie rozstrzyga między warstwami,
        /// bo składanie wielkości liter w ICU (ﬃ ≡ ffi) zmienia długość dopasowania.
        var tier: Int
        var isAlias: Bool
    }

    /// Aliasy włączone i niepuste (plik `dictionary.json` mógł ominąć `upsert`: pusty Alias wstawiałby Term na każdej granicy słowa),
    /// w NFC, od najdłuższego w warstwie: alternacja bierze pierwszą pasującą gałąź, więc „on track" musi stać przed „on".
    public init(_ d: UserDictionary) {
        // Odmiana tylko dla rdzeni, które przeszłyby `upsert`; inaczej (ręcznie edytowany plik) Alias działa jak całe słowo.
        let ambiguous = Set(UserDictionary.inflectionConflicts(in: d.terms).map { UserDictionary.key($0.alias) })
        var aliases = d.terms.flatMap { term in
            term.aliases.filter { $0.enabled }.map { a -> Entry in
                let text = Self.nfc(a.text)
                let inflects = a.inflecting && UserDictionary.inflectionStemIsValid(text) && !ambiguous.contains(UserDictionary.key(text))
                return Entry(text: text, caseless: true, term: Self.nfc(term.text), inflects: inflects, tier: inflects ? 2 : 1, isAlias: true)
            }
        }.filter { !$0.text.isEmpty }
        guard !aliases.isEmpty else { slots = []; regex = nil; starts = nil; return }
        // Tekst każdego Terma jako wpis tożsamościowy (z wielkością liter, R9): „Kopt Max" dopasowany w całości nie jest skanowany
        // dalej, więc zawarty w nim Alias „kopt" nie zrobi z niego „Kopt Max Max" przy drugim zastosowaniu (idempotencja).
        var identities = d.terms.map { Entry(text: Self.nfc($0.text), caseless: false, term: Self.nfc($0.text), inflects: false, tier: 1, isAlias: false) }
            .filter { !$0.text.isEmpty }
        // Wynik Alias z odmianą to Term + końcówka, który może znów zaczynać się rdzeniem („OpenTof*" → „OpenTofu" + „em"). Term, którego któryś
        // ogon (od początku słowa) zaczyna się od rdzenia, dostaje tożsamość z odmianą stojącą na początku alternacji: jego formy zostają nietknięte.
        let stems = aliases.filter(\.inflects).map { UserDictionary.foldedScalars($0.text) }
        if !stems.isEmpty {
            for t in d.terms where UserDictionary.wordTails(of: Self.nfc(t.text)).contains(where: { tail in
                let folded = UserDictionary.foldedScalars(tail)
                return stems.contains { folded.starts(with: $0) }
            }) {
                let text = Self.nfc(t.text)
                if !text.isEmpty { identities.append(Entry(text: text, caseless: false, term: text, inflects: true, tier: 0, isAlias: false)) }
            }
        }
        aliases.append(contentsOf: identities)
        let entries = aliases.sorted { ($0.tier, $1.text.count) < ($1.tier, $0.text.count) }
        // Literały (bez znaczenia `.`, `+`, `(`) i granice słów Unicode: litera, cyfra albo znak łączący (akcent) przedłuża słowo.
        var group = 1
        var slots: [(group: Int, term: String, suffixGroup: Int?)] = []
        var branches: [String] = []
        for e in entries {
            let literal = NSRegularExpression.escapedPattern(for: e.text)
            let body = (e.caseless ? "(?i:" : "(?:") + literal + ")"
            if e.inflects {
                branches.append("(" + body + "([\\p{L}\\p{M}]*))")
                slots.append((group, e.term, group + 1))
                group += 2
            } else {
                branches.append("(" + body + ")")
                slots.append((group, e.term, nil))
                group += 1
            }
        }
        self.slots = slots
        // `try?`: wzorzec składa się z ucieczkowanych literałów i stałych granic, więc kompilacja nie może zawieść.
        regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}\\p{M}])(?:\(branches.joined(separator: "|")))(?![\\p{L}\\p{N}\\p{M}])")
        var firsts: [(word: String, prefix: Bool)?] = []
        for e in entries {
            let ws = Self.words(in: e.text)
            firsts.append(ws.first.flatMap { $0.offset == 0 ? ($0.text, e.inflects && ws.count == 1) : nil })
        }
        if firsts.contains(where: { $0 == nil }) { starts = nil; return }
        var a = Starts(), all = Starts()
        for (e, f) in zip(entries, firsts) {
            guard let f else { continue }
            if f.prefix {
                let folded = UserDictionary.foldedScalars(f.word)
                all.prefixes.append(folded)
                if e.isAlias { a.prefixes.append(folded) }
            } else {
                all.exact.insert(UserDictionary.key(f.word))
                if e.isAlias && e.caseless { a.exact.insert(UserDictionary.key(f.word)) }
            }
        }
        starts = (a, all)
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
            let next = Self.once(current, regex, slots, from: preFilter ? starts?.entries : nil)
            if next == current { return next }
            current = next
        }
        return current
    }

    /// Czy w tekście jest słowo o kluczu pierwszego słowa któregoś Aliasu; przy filtrze wyłączonym — zawsze tak.
    func mayMatch(_ text: String) -> Bool {
        guard let starts else { return true }
        return Self.words(in: text.precomposedStringWithCanonicalMapping).contains { starts.aliases.matches($0.text) }
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

    static func isWord(_ scalar: Unicode.Scalar) -> Bool {
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
    private static func once(_ text: String, _ regex: NSRegularExpression, _ slots: [(group: Int, term: String, suffixGroup: Int?)], from starts: Starts?) -> String {
        regexRuns?.increment()
        let source = text.precomposedStringWithCanonicalMapping as NSString
        let string = source as String
        var matches: [NSTextCheckingResult] = []
        if let starts {
            var end = 0
            for word in words(in: string) where word.offset >= end && starts.matches(word.text) {
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
            // Indeks grupy, nie ponowne porównanie dopasowanego tekstu z Aliasami: grupa wskazuje wpis wprost. Wpis z odmianą: Term + przechwycona końcówka.
            if let slot = slots.first(where: { m.range(at: $0.group).location != NSNotFound }) {
                out += slot.term
                if let g = slot.suffixGroup { out += source.substring(with: m.range(at: g)) }
            }
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
