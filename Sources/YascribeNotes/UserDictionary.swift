import Foundation

/// Słownik użytkownika (F21): Termy (poprawna pisownia) z Aliasami (jak model ASR je przekręca). Nazwa `UserDictionary`,
/// bo `Dictionary` koliduje ze Swiftem. Plik `dictionary.json` czyta `AppModel.read(_:_:)` (uszkodzony idzie na bok).

public enum TermPriority: String, Codable, CaseIterable, Sendable { case high, normal, low }

public struct DictionaryAlias: Codable, Equatable, Sendable {
    public var text: String
    /// Alias, który może być zwykłym słowem („pu do"); z importu przychodzi wyłączony.
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
    /// Tekst zaczyna się od `#` albo zawiera tabulator, znak sterujący lub koniec linii: eksport TSV i `vocab_core.txt` nie odtworzyłby go (komentarz, rozdzielacz).
    case invalidCharacters(String)
}

public struct UserDictionary: Codable, Equatable, Sendable {
    public var terms: [DictionaryTerm]

    public init(terms: [DictionaryTerm] = []) { self.terms = terms }

    /// Klucz porównań: NFC i pełne składanie wielkości liter, takie jak w dopasowaniu `(?i:)` Replacement (ICU): „Straße" ≡ „STRASSE",
    /// „ς" ≡ „σ". Samo `lowercased()` ich nie zrównuje, więc Alias „STRASSE" innego Terma przepisałby „Straße" przy drugim przejściu (R11).
    public static func key(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil).precomposedStringWithCanonicalMapping
    }

    /// `#` na początku (komentarz w plikach importu) albo tabulator / znak sterujący / separator linii w środku; tekst już po `clean`.
    /// Zbiór zakazany to wszystko, co parser (`Character.isNewline`: CR, LF, VT, FF, U+0085, U+2028, U+2029) albo eksport (TAB) mógłby
    /// rozciąć, plus pozostałe znaki sterujące (kategoria Cc) — jedna definicja, której niezmiennik pilnuje test (F8).
    static func isReserved(_ s: String) -> Bool {
        s.hasPrefix("#") || s.unicodeScalars.contains(where: isForbiddenScalar)
    }

    static func isForbiddenScalar(_ c: Unicode.Scalar) -> Bool {
        switch c.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: true
        default: false
        }
    }

    static func clean(_ s: String) -> String {
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
        guard !Self.isReserved(term.text) else { throw .invalidCharacters(term.text) }

        var seen = Set<String>()
        var aliases: [DictionaryAlias] = []
        for var alias in t.aliases {
            alias.text = Self.clean(alias.text)
            guard !alias.text.isEmpty else { throw .emptyAlias }
            guard !Self.isReserved(alias.text) else { throw .invalidCharacters(alias.text) }
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

public extension UserDictionary {
    /// Alias, który różni się od swojego Terma tylko wielkością liter (np. „Pudo" → „PUDO"): podmiana normalizuje zapis i jest poprawna,
    /// choć liczenie bez rozróżniania wielkości liter nadal widzi Alias w wyniku. Odbiór `dictionary-check` nie wymaga tu zera (F9).
    static func aliasOnlyNormalizesCase(alias: String, term: String) -> Bool {
        key(alias) == key(term)
    }
}
