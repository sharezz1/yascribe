import Foundation
import MeetNotesTranscription

/// Reguły Replacement (F21, spec §5): włączone Aliasy słownika skompilowane do jednego wyrażenia. Deterministyczna podmiana
/// bez modelu, stosowana przy odczycie transkryptu (D8), więc musi być idempotentna i tania przy każdym wywołaniu.
/// `@unchecked`: `NSRegularExpression` jest niezmienny i bezpieczny wątkowo, ale nie jest oznaczony jako `Sendable`.
public struct ReplacementRules: @unchecked Sendable {
    private let regex: NSRegularExpression?
    /// Zapis Terma dla grupy przechwytującej `i + 1` (jedna grupa na wpis, w kolejności alternacji).
    private let terms: [String]

    /// Aliasy włączone i niepuste (plik `dictionary.json` mógł ominąć `upsert`: pusty Alias wstawiałby Term na każdej granicy słowa),
    /// w NFC, od najdłuższego: alternacja bierze pierwszą pasującą gałąź, więc „on track" musi stać przed „in".
    public init(_ d: UserDictionary) {
        let aliases = d.terms.flatMap { term in
            term.aliases.filter { $0.enabled }.map { (text: Self.nfc($0.text), caseless: true, term: Self.nfc(term.text)) }
        }.filter { !$0.text.isEmpty }
        guard !aliases.isEmpty else { terms = []; regex = nil; return }
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
    }

    /// Brak włączonych Aliasów: Replacement nic nie robi (transkrypt i polecenia bajt w bajt jak bez słownika).
    public var isEmpty: Bool { regex == nil }

    /// Przejścia aż do punktu stałego (R10), najwyżej 5; bez zbieżności zwraca ostatni wynik. Wstawiony Term może razem z sąsiednim
    /// tekstem utworzyć nowy Alias („x y" → „A y", a „A y" to Alias B), więc jedno przejście nie jest idempotentne. Tekst bez zmian
    /// kosztuje jedno przejście.
    public func apply(to text: String) -> String {
        guard let regex else { return text }
        var current = text
        for _ in 0..<5 {
            let next = Self.once(current, regex, terms)
            if next == current { return next }
            current = next
        }
        return current
    }

    /// Jedno przejście, bez ponownego skanowania wstawionych Termów. Dopasowanie na tekście w NFC (Alias z NFD ze schowka trafia
    /// w tekst NFC i odwrotnie); tekst bez dopasowań wraca nietknięty, z dopasowaniem — w NFC.
    private static func once(_ text: String, _ regex: NSRegularExpression, _ terms: [String]) -> String {
        let source = text.precomposedStringWithCanonicalMapping as NSString
        let matches = regex.matches(in: source as String, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }
        var out = ""
        var last = 0
        for m in matches {
            out += source.substring(with: NSRange(location: last, length: m.range.location - last))
            // Grupa, nie `lowercased()` dopasowania: ICU bez wielkości liter dopasowuje też „ß"/„SS", których klucze się różnią.
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
