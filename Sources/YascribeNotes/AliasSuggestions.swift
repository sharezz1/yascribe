import Foundation
import YascribeTranscription

/// Propozycja Aliasu dla istniejącego Terma (TASK-112), wyliczona z różnicy surowy transkrypt → korekta LLM.
public struct AliasSuggestion: Equatable, Sendable, Identifiable {
    /// Klucz odrzucenia (trwały): klucz Aliasu, `*` przy odmianie, klucz Terma.
    public var id: String
    public var termID: UUID
    public var term: String
    /// Rdzeń (z odmianą) albo cała fraza.
    public var alias: String
    public var inflects: Bool
    /// Alias albo któraś zaobserwowana forma to zwykłe słowo: Add wymaga potwierdzenia, alias dostaje flagę Risky.
    public var risky: Bool
    /// Zaobserwowane surowe formy (do 3, od najczęstszej).
    public var forms: [String]
    public var count: Int
    /// Id sesji (nazwy katalogów), posortowane.
    public var sessions: [String]

    public init(id: String, termID: UUID, term: String, alias: String, inflects: Bool, risky: Bool, forms: [String], count: Int, sessions: [String]) {
        self.id = id
        self.termID = termID
        self.term = term
        self.alias = alias
        self.inflects = inflects
        self.risky = risky
        self.forms = forms
        self.count = count
        self.sessions = sessions
    }
}

/// Sugestie Aliasów (TASK-112): powtarzające się podmiany 1–3 słów, w których korektor zamienił surową formę na Term (albo Term
/// z końcówką). Czysta funkcja, liczona w tle przez aplikację; walidacja to ten sam `upsert`, co przy ręcznym dodaniu.
public enum AliasSuggestions {
    public struct Source: Sendable {
        public var id: String
        public var raw: Transcript
        public var corrected: CorrectedTranscript
        public init(id: String, raw: Transcript, corrected: CorrectedTranscript) {
            self.id = id
            self.raw = raw
            self.corrected = corrected
        }
    }

    /// Najmniej wystąpień; ryzykowna sugestia musi też pochodzić z co najmniej tylu spotkań.
    static let minCount = 2
    static let minRiskySessions = 2

    private struct Group {
        var termID: UUID
        var term: String
        var alias: String
        var inflects: Bool
        var forms: [String: Int] = [:]
        var count = 0
        var sessions = Set<String>()
    }

    /// `isCommonWord`: słowo istnieje w zwykłym słowniku (aplikacja: słownik systemowy pl/en); wołane tylko dla grup po progu.
    public static func find(in sources: [Source], dictionary: UserDictionary, dismissed: Set<String>,
                            fillerWords: [String], isCommonWord: (String) -> Bool) -> [AliasSuggestion] {
        let rules = ReplacementRules(dictionary)
        let fillers = Set(fillerWords.map(CorrectionGuard.key))
        // Najdłuższy Term wygrywa („KOPT Max" przed „KOPT").
        let terms = dictionary.terms.sorted { $0.text.count > $1.text.count }
        var groups: [String: Group] = [:]
        for source in sources {
            let raw = source.raw.utterances, fixed = source.corrected.transcript.utterances
            guard !source.corrected.failedCompletely, raw.count == fixed.count else { continue }
            for (r, f) in zip(raw, fixed) {
                // Korektor dostał tekst po Replacement (NotesModel): pary pokryte już Aliasem nie są różnicą.
                let o = words(rules.apply(to: r.text)), c = words(f.text)
                guard !o.isEmpty, !c.isEmpty else { continue }
                for step in CorrectionGuard.align(o.map(CorrectionGuard.key), c.map(CorrectionGuard.key)) {
                    guard case .changed(let oi, let ci) = step, (1...3).contains(oi.count), (1...3).contains(ci.count) else { continue }
                    let before = o[oi].map(trimmed), after = c[ci].map(trimmed)
                    guard !(before + after).contains(where: { $0.contains(where: \.isNumber) }),
                          !before.allSatisfy({ fillers.contains(CorrectionGuard.key($0)) }),
                          let pair = candidate(raw: before.joined(separator: " "), corrected: after.joined(separator: " "), terms: terms)
                    else { continue }
                    let id = UserDictionary.key(pair.alias) + (pair.inflects ? "*" : "") + "→" + UserDictionary.key(pair.term.text)
                    var g = groups[id] ?? Group(termID: pair.term.id, term: pair.term.text, alias: pair.alias, inflects: pair.inflects)
                    g.count += 1
                    g.sessions.insert(source.id)
                    g.forms[before.joined(separator: " "), default: 0] += 1
                    groups[id] = g
                }
            }
        }

        var out: [AliasSuggestion] = []
        for (id, g) in groups where g.count >= minCount && !dismissed.contains(id) {
            guard let term = dictionary.terms.first(where: { $0.id == g.termID }),
                  !term.aliases.contains(where: { UserDictionary.key($0.text) == UserDictionary.key(g.alias) }) else { continue }
            let forms = g.forms.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
            let risky = isCommon(g.alias, isCommonWord) || forms.contains { isCommon($0, isCommonWord) }
            if risky && g.sessions.count < minRiskySessions { continue }
            let s = AliasSuggestion(id: id, termID: g.termID, term: g.term, alias: g.alias, inflects: g.inflects, risky: risky,
                                    forms: Array(forms.prefix(3)), count: g.count, sessions: g.sessions.sorted())
            // Add musi przejść ten sam `upsert` co ręczne dodanie; inaczej sugestia byłaby przyciskiem, który zawsze zawodzi.
            guard (try? accept(s, in: dictionary)) != nil else { continue }
            out.append(s)
        }
        return out.sorted { ($1.count, $0.term, $0.alias) < ($0.count, $1.term, $1.alias) }
    }

    /// Słownik z dopisanym Aliasem (przez `upsert`); błąd walidacji przechodzi do wywołującego.
    public static func accept(_ s: AliasSuggestion, in d: UserDictionary) throws(DictionaryError) -> UserDictionary {
        guard var term = d.terms.first(where: { $0.id == s.termID }) else { throw .emptyTerm }
        term.aliases.append(DictionaryAlias(s.alias, risky: s.risky, enabled: true, inflects: s.inflects))
        var out = d
        try out.upsert(term)
        return out
    }

    /// Fraza jest zwykła, gdy każde jej słowo jest zwykłe („on track"); pojedyncze słowo — gdy samo jest zwykłe.
    private static func isCommon(_ phrase: String, _ isCommonWord: (String) -> Bool) -> Bool {
        phrase.split(separator: " ").allSatisfy { isCommonWord(String($0)) }
    }

    /// Strona poprawiona to Term albo Term + końcówka z liter; Alias = strona surowa bez tej samej końcówki, z odmianą.
    /// Bez odmiany tylko wtedy, gdy rdzeń nie przeszedłby `inflectionStemIsValid`, a końcówki nie ma (całe słowo).
    private static func candidate(raw: String, corrected: String, terms: [DictionaryTerm]) -> (alias: String, inflects: Bool, term: DictionaryTerm)? {
        let fixed = corrected.lowercased()
        guard UserDictionary.key(raw) != UserDictionary.key(corrected),
              let term = terms.first(where: { t in
                  let k = t.text.lowercased()
                  return fixed.hasPrefix(k) && fixed.dropFirst(k.count).allSatisfy(\.isLetter)
              }) else { return nil }
        let ending = String(fixed.dropFirst(term.text.lowercased().count))
        // Końcówka liczona na małych literach; `lowercased` zmieniające długość („İ") pomija parę.
        guard raw.lowercased().count == raw.count, raw.lowercased().hasSuffix(ending), raw.count > ending.count else { return nil }
        let stem = String(raw.dropLast(ending.count))
        if UserDictionary.inflectionStemIsValid(stem) { return (stem, true, term) }
        return ending.isEmpty ? (raw, false, term) : nil
    }

    private static func words(_ s: String) -> [String] { s.split(separator: " ", omittingEmptySubsequences: true).map(String.init) }

    private static func trimmed(_ token: String) -> String { token.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
}
