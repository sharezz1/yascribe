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
    public struct Source: Equatable, Sendable {
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

    /// Grupa: jeden rdzeń (surowa forma bez końcówki) i jeden Term.
    private struct Group {
        var termID: UUID
        var term: String
        var stem: String
        /// Któreś wystąpienie miało końcówkę: tylko wtedy Alias dostaje odmianę (`*`). Same formy podstawowe = Alias dokładny.
        var hasEnding = false
        var forms: [String: Int] = [:]
        /// Poprawione formy z końcówką („Nimbuie”) — sprawdzane, czy nie są zwykłym słowem („portfel” przy Termie „Port”).
        var endedTargets = Set<String>()
        var count = 0
        var sessions = Set<String>()
    }

    /// `isCommonWord`: słowo istnieje w zwykłym słowniku (aplikacja: słownik systemowy pl/en); wołane tylko dla grup po progu.
    /// shortcut: wejście korektora odtwarzamy bieżącym słownikiem; Alias usunięty po korekcie przypisze jego podmiany korektorowi —
    /// zapis tekstu wysłanego korektorowi, gdy to będzie widać w sugestiach.
    public static func find(in sources: [Source], dictionary: UserDictionary, dismissed: Set<String>,
                            fillerWords: [String], isCommonWord: (String) -> Bool) -> [AliasSuggestion] {
        let rules = ReplacementRules(dictionary)
        let fillers = Set(fillerWords.map(CorrectionGuard.key))
        // Najdłuższy Term wygrywa („KOPT Max" przed „KOPT").
        let terms = dictionary.terms.sorted { $0.text.count > $1.text.count }
        var groups: [String: Group] = [:]
        // Słowa, które korektor zostawił bez zmiany: rdzeń z odmianą, który by je przepisał, jest ryzykowny („szko*” i „szkoła”).
        var kept = Set<String>()
        for source in sources {
            if Task.isCancelled { return [] }
            let raw = source.raw.utterances, fixed = source.corrected.transcript.utterances
            guard !source.corrected.failedCompletely, raw.count == fixed.count else { continue }
            for (r, f) in zip(raw, fixed) {
                // Korektor dostał tekst po Replacement (NotesModel): pary pokryte już Aliasem nie są różnicą.
                let o = words(rules.apply(to: r.text)), c = words(f.text)
                let ok = o.map(CorrectionGuard.key), ck = c.map(CorrectionGuard.key)
                guard !o.isEmpty, !c.isEmpty else { continue }
                if ok == ck { kept.formUnion(ok); continue }
                for step in CorrectionGuard.align(ok, ck) {
                    switch step {
                    case .same(let i, _): kept.insert(ok[i])
                    case .changed(let oi, let ci):
                        guard (1...3).contains(oi.count), (1...3).contains(ci.count),
                              let pair = widened(oi, ci, o, c, ok, ck, terms: terms, fillers: fillers) else { continue }
                        let id = UserDictionary.key(pair.stem) + "→" + UserDictionary.key(pair.term.text)
                        var g = groups[id] ?? Group(termID: pair.term.id, term: pair.term.text, stem: pair.stem)
                        g.count += 1
                        g.sessions.insert(source.id)
                        g.forms[pair.raw, default: 0] += 1
                        if !pair.ending.isEmpty { g.hasEnding = true; g.endedTargets.insert(pair.corrected) }
                        groups[id] = g
                    }
                }
            }
        }

        // Ten sam rdzeń poprawiany na różne Termy: dane są sprzeczne, Add dla któregokolwiek przepisałby wszystkie wystąpienia.
        var termsPerStem: [String: Set<UUID>] = [:]
        for g in groups.values { termsPerStem[UserDictionary.key(g.stem), default: []].insert(g.termID) }

        var out: [AliasSuggestion] = []
        for g in groups.values where g.count >= minCount && termsPerStem[UserDictionary.key(g.stem)]?.count == 1 {
            let inflects = g.hasEnding
            if inflects && !UserDictionary.inflectionStemIsValid(g.stem) { continue }
            let id = UserDictionary.key(g.stem) + (inflects ? "*" : "") + "→" + UserDictionary.key(g.term)
            guard !dismissed.contains(id), let term = dictionary.terms.first(where: { $0.id == g.termID }),
                  !term.aliases.contains(where: { UserDictionary.key($0.text) == UserDictionary.key(g.stem) }),
                  // Term + „końcówka” to zwykłe słowo: korekta dotyczyła tego słowa, nie Terma („pordfel → portfel” przy „Port”).
                  !g.endedTargets.contains(where: isCommonWord) else { continue }
            let forms = g.forms.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
            let stemKey = g.stem.lowercased()
            let risky = isCommon(g.stem, isCommonWord) || forms.contains { isCommon($0, isCommonWord) }
                || (inflects && kept.contains { $0.hasPrefix(stemKey) })
            if risky && g.sessions.count < minRiskySessions { continue }
            let s = AliasSuggestion(id: id, termID: g.termID, term: g.term, alias: g.stem, inflects: inflects, risky: risky,
                                    forms: Array(forms.prefix(3)), count: g.count, sessions: g.sessions.sorted())
            // Add musi przejść ten sam `upsert` co ręczne dodanie; inaczej sugestia byłaby przyciskiem, który zawsze zawodzi.
            guard (try? accept(s, in: dictionary)) != nil else { continue }
            out.append(s)
        }
        return out.sorted { ($1.count, $0.term, $0.alias) < ($0.count, $1.term, $1.alias) }
    }

    /// Para z bloku zmiany; gdy Term wielowyrazowy dzieli słowo z oryginałem („Rokm Max” → „Nimbu Max”), LCS wydziela wspólne „Max”,
    /// więc blok rozszerzamy o do 2 zgodnych słów z każdej strony.
    private static func widened(_ oi: Range<Int>, _ ci: Range<Int>, _ o: [String], _ c: [String], _ ok: [String], _ ck: [String],
                                terms: [DictionaryTerm], fillers: Set<String>) -> Pair? {
        for (l, r) in [(0, 0), (0, 1), (1, 0), (1, 1), (0, 2), (2, 0)] {
            let ol = oi.lowerBound - l, cl = ci.lowerBound - l, ou = oi.upperBound + r, cu = ci.upperBound + r
            guard ol >= 0, cl >= 0, ou <= o.count, cu <= c.count,
                  ok[ol..<oi.lowerBound] == ck[cl..<ci.lowerBound], ok[oi.upperBound..<ou] == ck[ci.upperBound..<cu] else { continue }
            if let p = pair(Array(o[ol..<ou]), Array(c[cl..<cu]), terms: terms, fillers: fillers) { return p }
        }
        return nil
    }

    private struct Pair { var raw: String; var corrected: String; var stem: String; var ending: String; var term: DictionaryTerm }

    private static func pair(_ rawTokens: [String], _ fixedTokens: [String], terms: [DictionaryTerm], fillers: Set<String>) -> Pair? {
        let before = rawTokens.map(trimmed), after = fixedTokens.map(trimmed)
        let raw = before.joined(separator: " "), corrected = after.joined(separator: " ")
        // Interpunkcja w środku frazy („ko, pt”): Replacement dopasowuje dosłowną spację, więc taki Alias nic by nie zmienił.
        guard trimmed(rawTokens.joined(separator: " ")) == raw, trimmed(fixedTokens.joined(separator: " ")) == corrected,
              !(before + after).contains(where: { $0.contains(where: \.isNumber) }),
              !before.allSatisfy({ fillers.contains(CorrectionGuard.key($0)) }),
              let found = candidate(raw: raw, corrected: corrected, terms: terms) else { return nil }
        return Pair(raw: raw, corrected: corrected, stem: found.stem, ending: found.ending, term: found.term)
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

    /// Strona poprawiona to Term (dowolna wielkość liter) albo Term w dokładnym zapisie + końcówka z liter („Nimbuie”, nie „portfel”
    /// przy „Port”); rdzeń = strona surowa bez tej samej końcówki.
    private static func candidate(raw: String, corrected: String, terms: [DictionaryTerm]) -> (stem: String, ending: String, term: DictionaryTerm)? {
        guard UserDictionary.key(raw) != UserDictionary.key(corrected),
              let term = terms.first(where: { t in
                  UserDictionary.key(corrected) == UserDictionary.key(t.text)
                      || (corrected.hasPrefix(t.text) && corrected.dropFirst(t.text.count).allSatisfy(\.isLetter))
              }) else { return nil }
        // Surowa forma to już Term z inną końcówką („Nimbuie” → „Nimbu”): korektor zmienił odmianę, nie poprawił nazwy.
        guard !UserDictionary.key(raw).hasPrefix(UserDictionary.key(term.text)) else { return nil }
        let ending = UserDictionary.key(corrected) == UserDictionary.key(term.text) ? "" : String(corrected.dropFirst(term.text.count)).lowercased()
        // Końcówka liczona na małych literach; `lowercased` zmieniające długość („İ") pomija parę.
        guard raw.lowercased().count == raw.count, raw.lowercased().hasSuffix(ending), raw.count > ending.count else { return nil }
        return (String(raw.dropLast(ending.count)), ending, term)
    }

    private static func words(_ s: String) -> [String] { s.split(separator: " ", omittingEmptySubsequences: true).map(String.init) }

    private static func trimmed(_ token: String) -> String { token.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
}
