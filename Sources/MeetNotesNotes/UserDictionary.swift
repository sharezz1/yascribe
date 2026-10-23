import Foundation

/// Słownik użytkownika (F21): Termy (poprawna pisownia) z Aliasami (jak model ASR je przekręca). Nazwa `UserDictionary`,
/// bo `Dictionary` koliduje ze Swiftem. Plik `dictionary.json` czyta `AppModel.read(_:_:)` (uszkodzony idzie na bok).

public enum TermPriority: String, Codable, CaseIterable, Sendable { case high, normal, low }

public struct DictionaryAlias: Codable, Equatable, Sendable {
    public var text: String
    /// Alias, który może być zwykłym słowem („ko pt"); z importu przychodzi wyłączony.
    public var risky: Bool
    public var enabled: Bool

    public init(_ text: String, risky: Bool = false, enabled: Bool = true) {
        self.text = text
        self.risky = risky
        self.enabled = enabled
    }
}

public struct DictionaryTerm: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var priority: TermPriority
    public var aliases: [DictionaryAlias]

    public init(_ text: String, priority: TermPriority = .normal, aliases: [DictionaryAlias] = [], id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.priority = priority
        self.aliases = aliases
    }
}

public enum DictionaryError: Error, Equatable {
    case emptyTerm
    case duplicateTerm(String)
    case aliasTaken(alias: String, by: String)
    case aliasIsTerm(alias: String, term: String)
    case emptyAlias
}

public struct UserDictionary: Codable, Equatable, Sendable {
    public var terms: [DictionaryTerm]

    public init(terms: [DictionaryTerm] = []) { self.terms = terms }

    /// Klucz porównań: NFC i pełne składanie wielkości liter, takie jak w dopasowaniu `(?i:)` Replacement (ICU): „Straße" ≡ „STRASSE",
    /// „ς" ≡ „σ". Samo `lowercased()` ich nie zrównuje, więc Alias „STRASSE" innego Terma przepisałby „Straße" przy drugim przejściu (R11).
    static func key(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil).precomposedStringWithCanonicalMapping
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    /// Term, który ma ten Alias (włącznie z wyłączonymi); `excluding` = Term edytowany teraz.
    public func owner(ofAlias alias: String, excluding: UUID? = nil) -> DictionaryTerm? {
        let k = Self.key(alias)
        return terms.first { $0.id != excluding && $0.aliases.contains { Self.key($0.text) == k } }
    }

    /// Zapis przez walidację (jak `PresetsFile.upsert`): NFC i przycięcie, unikalność Termów i Aliasów, a tekst Terma nie może być
    /// Aliasem żadnego Terma — inaczej Replacement nie byłby idempotentny. Alias równy własnemu Termowi (z wielkością liter) znika;
    /// różniący się samą wielkością liter zostaje (normalizuje zapis).
    public mutating func upsert(_ t: DictionaryTerm) throws(DictionaryError) {
        var term = t
        term.text = Self.clean(t.text)
        guard !term.text.isEmpty else { throw .emptyTerm }

        var seen = Set<String>()
        var aliases: [DictionaryAlias] = []
        for var alias in t.aliases {
            alias.text = Self.clean(alias.text)
            guard !alias.text.isEmpty else { throw .emptyAlias }
            if alias.text == term.text || !seen.insert(Self.key(alias.text)).inserted { continue }
            aliases.append(alias)
        }
        term.aliases = aliases

        let termKey = Self.key(term.text)
        let others = terms.filter { $0.id != term.id }
        if others.contains(where: { Self.key($0.text) == termKey }) { throw .duplicateTerm(term.text) }
        if let owner = owner(ofAlias: term.text, excluding: term.id) { throw .aliasIsTerm(alias: term.text, term: owner.text) }
        for alias in term.aliases {
            let k = Self.key(alias.text)
            if let other = others.first(where: { Self.key($0.text) == k }) { throw .aliasIsTerm(alias: alias.text, term: other.text) }
            if let owner = owner(ofAlias: alias.text, excluding: term.id) { throw .aliasTaken(alias: alias.text, by: owner.text) }
        }

        if let i = terms.firstIndex(where: { $0.id == term.id }) { terms[i] = term } else { terms.append(term) }
    }

    public mutating func remove(_ id: UUID) { terms.removeAll { $0.id == id } }
}
