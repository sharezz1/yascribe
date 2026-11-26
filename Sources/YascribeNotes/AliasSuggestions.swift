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
    /// Sugestia pochodzi z poprawki użytkownika (TASK-116), nie tylko z różnicy surowy → korektor.
    public var fromEdits: Bool
    /// Poprawiona fraza nie jest jeszcze Termem: `accept` utworzy nowy Term z tym Aliasem.
    public var isNewTerm: Bool

    /// Odrzucenie zapisane z `*` albo bez chowa sugestię w obu wariantach: wersja 0.1.23 dawała `*` także samym formom podstawowym,
    /// a późniejsza forma z końcówką zmienia `id` z dokładnego na `*`.
    public func isDismissed(in ids: Set<String>) -> Bool {
        let a = UserDictionary.key(alias), t = UserDictionary.key(term)
        return ids.contains(a + "→" + t) || ids.contains(a + "*→" + t)
    }

    public init(id: String, termID: UUID, term: String, alias: String, inflects: Bool, risky: Bool, forms: [String], count: Int, sessions: [String],
                fromEdits: Bool = false, isNewTerm: Bool = false) {
        self.id = id
        self.termID = termID
        self.term = term
        self.alias = alias
        self.inflects = inflects
        self.risky = risky
        self.forms = forms
        self.count = count
        self.sessions = sessions
        self.fromEdits = fromEdits
        self.isNewTerm = isNewTerm
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

    /// Jedna poprawka użytkownika (TASK-116): `before` jest już po Replacement, `after` to tekst po edycji.
    /// `editKey` (np. „sessionID#index”) służy do policzenia tej samej poprawki raz, gdy widać ją w Original i Corrected.
    public struct EditPair: Equatable, Sendable {
        public var sessionID: String
        public var editKey: String
        public var before: String
        public var after: String
        public init(sessionID: String, editKey: String, before: String, after: String) {
            self.sessionID = sessionID
            self.editKey = editKey
            self.before = before
            self.after = after
        }
    }

    /// Najmniej wystąpień z korektora; jedna poprawka użytkownika wystarcza (D3). Ryzykowna sugestia musi pochodzić z ≥2 spotkań.
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
        /// Klucze poprawek: ta sama edycja widziana w Original i Corrected liczy się raz na grupę.
        var editKeys = Set<String>()
        /// Nowy Term (tylko z edycji): `termID` jest przeznaczony dla `accept`, bo Terma jeszcze nie ma w słowniku.
        var isNewTerm = false
    }

    /// `isCommonWord`: słowo istnieje w zwykłym słowniku (aplikacja: słownik systemowy pl/en); wołane tylko dla grup po progu.
    /// shortcut: wejście korektora odtwarzamy bieżącym słownikiem; Alias usunięty po korekcie przypisze jego podmiany korektorowi —
    /// zapis tekstu wysłanego korektorowi, gdy to będzie widać w sugestiach.
    public static func find(in sources: [Source], dictionary: UserDictionary, dismissed: Set<String>,
                            fillerWords: [String], edits: [EditPair] = [],
                            isCommonWord: (String) -> Bool) -> [AliasSuggestion] {
        let rules = ReplacementRules(dictionary)
        let fillers = Set(fillerWords.map(CorrectionGuard.key))
        // Najdłuższy Term wygrywa („KOPT Max" przed „KOPT").
        let terms = dictionary.terms.sorted { $0.text.count > $1.text.count }
        var groups: [String: Group] = [:]
        // Wszystkie surowe słowa (po Replacement) i linie: Alias, który dopasowałby więcej wystąpień, niż korektor zamienił na Term,
        // przepisałby też słowa zostawione albo poprawione inaczej („szko*” i „szkoła”, „Nima” jako imię) — jest ryzykowny.
        var rawCounts: [String: Int] = [:]
        var rawLines: [String] = []
        // Sesje, których surowy tekst faktycznie policzyliśmy; edycje z tych sesji nie dokładają `before` drugi raz.
        var countedSourceIDs = Set<String>()
        for source in sources {
            if Task.isCancelled { return [] }
            let raw = source.raw.utterances, fixed = source.corrected.transcript.utterances
            guard !source.corrected.failedCompletely, raw.count == fixed.count else { continue }
            // Wypowiedź wyłączona z notatek (ukryta przez użytkownika, echo, zły język) nie idzie do korektora — żadnej różnicy w niej nie liczymy.
            for (r, f) in zip(raw, fixed) where !r.excludedFromNotes && !f.excludedFromNotes {
                // Korektor dostał tekst po Replacement (NotesModel): pary pokryte już Aliasem nie są różnicą.
                let o = words(rules.apply(to: r.text)), c = words(f.text)
                let ok = o.map(CorrectionGuard.key), ck = c.map(CorrectionGuard.key)
                guard !o.isEmpty, !c.isEmpty else { continue }
                for k in ok { rawCounts[k, default: 0] += 1 }
                rawLines.append(ok.joined(separator: " "))
                countedSourceIDs.insert(source.id)
                if ok == ck { continue }
                for step in CorrectionGuard.align(ok, ck) {
                    switch step {
                    case .same: continue
                    case .changed(let oi, let ci):
                        guard (1...3).contains(oi.count), (1...3).contains(ci.count),
                              let w = widened(oi, ci, o, c, ok, ck, terms: terms, fillers: fillers),
                              let pair = w.pair else { continue }
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

        // Edycje użytkownika (TASK-116): ta sama maszyneria align/widened/pair, ale próg to jedna poprawka.
        // Ta sama poprawka w Original i Corrected nie może też podwójnie zawyżyć `matched` i zrobić Aliasu ryzykownym.
        var countedEditLines = Set<String>()
        for edit in edits {
            if Task.isCancelled { return [] }
            // `before` jest już po Replacement; `apply` jest idempotentne i chowa pary pokryte istniejącym Aliasem.
            let o = words(rules.apply(to: edit.before)), c = words(edit.after)
            let ok = o.map(CorrectionGuard.key), ck = c.map(CorrectionGuard.key)
            guard !o.isEmpty, !c.isEmpty, ok != ck else { continue }
            // Sesja obecna w `sources` ma już policzony surowy tekst; drugie dodanie `before` zawyżyłoby `matched`.
            if countedEditLines.insert(edit.editKey).inserted, !countedSourceIDs.contains(edit.sessionID) {
                for k in ok { rawCounts[k, default: 0] += 1 }
                rawLines.append(ok.joined(separator: " "))
            }
            for step in CorrectionGuard.align(ok, ck) {
                switch step {
                case .same: continue
                case .changed(let oi, let ci):
                    // Puste strony to usunięcie/wstawienie, >3 słowa to przepisanie zdania; to nie uczy nazwy.
                    guard (1...3).contains(oi.count), (1...3).contains(ci.count),
                          let w = widened(oi, ci, o, c, ok, ck, terms: terms, fillers: fillers) else { continue }
                    // Liczby i negacje po obu stronach bloku: poprawka liczby/negacji nie uczy nazwy (F1).
                    guard !(w.raw + w.fixed).map(trimmed).contains(where: isNumberOrNegation) else { continue }
                    if let pair = w.pair {
                        let id = UserDictionary.key(pair.stem) + "→" + UserDictionary.key(pair.term.text)
                        var g = groups[id] ?? Group(termID: pair.term.id, term: pair.term.text, stem: pair.stem)
                        if g.editKeys.insert(edit.editKey).inserted {
                            g.sessions.insert(edit.sessionID)
                            g.forms[pair.raw, default: 0] += 1
                            if !pair.ending.isEmpty { g.hasEnding = true; g.endedTargets.insert(pair.corrected) }
                        }
                        groups[id] = g
                    } else if let fresh = newPair(w.raw, w.fixed, dictionary: dictionary, fillers: fillers) {
                        let id = UserDictionary.key(fresh.stem) + "→" + UserDictionary.key(fresh.term)
                        var g = groups[id] ?? Group(termID: UUID(), term: fresh.term, stem: fresh.stem, isNewTerm: true)
                        if g.editKeys.insert(edit.editKey).inserted {
                            g.sessions.insert(edit.sessionID)
                            g.forms[fresh.stem, default: 0] += 1
                        }
                        groups[id] = g
                    }
                }
            }
        }

        // Ten sam rdzeń poprawiany na różne Termy: dane są sprzeczne, Add dla któregokolwiek przepisałby wszystkie wystąpienia.
        var termsPerStem: [String: Set<UUID>] = [:]
        // Pojedyncza halucynacja poniżej progu nie kasuje mocnej sugestii; edycja już przeszła próg (D3).
        for g in groups.values where g.count >= minCount || !g.editKeys.isEmpty {
            termsPerStem[UserDictionary.key(g.stem), default: []].insert(g.termID)
        }

        var out: [AliasSuggestion] = []
        for g in groups.values where (g.count >= minCount || !g.editKeys.isEmpty) && termsPerStem[UserDictionary.key(g.stem)]?.count == 1 {
            if Task.isCancelled { return [] }
            let inflects = g.hasEnding
            let stemKey = g.stem.lowercased(), phrase = stemKey.contains(" ")
            // Fraza tylko bez odmiany: „ko pt*” zjadłoby „ko ptak”, a liczenie wystąpień frazy nie widzi końcówek.
            if inflects && (phrase || !UserDictionary.inflectionStemIsValid(g.stem)) { continue }
            let id = UserDictionary.key(g.stem) + (inflects ? "*" : "") + "→" + UserDictionary.key(g.term)
            let total = g.count + g.editKeys.count
            let forms = g.forms.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
            let matched = phrase ? rawLines.reduce(0) { $0 + occurrences(of: stemKey, in: $1) }
                : rawCounts.reduce(0) { $0 + ((inflects ? $1.key.hasPrefix(stemKey) : $1.key == stemKey) ? $1.value : 0) }
            let risky = isCommon(g.stem, isCommonWord) || forms.contains { isCommon($0, isCommonWord) } || matched > total
            if risky && g.sessions.count < minRiskySessions { continue }
            if g.isNewTerm {
                // Nowy Term nie ma jeszcze wpisu w słowniku: `accept` utworzy go z tym samym `termID`.
                let s = AliasSuggestion(id: id, termID: g.termID, term: g.term, alias: g.stem, inflects: false, risky: risky,
                                        forms: Array(forms.prefix(3)), count: total, sessions: g.sessions.sorted(),
                                        fromEdits: true, isNewTerm: true)
                if s.isDismissed(in: dismissed) { continue }
                guard (try? accept(s, in: dictionary)) != nil else { continue }
                out.append(s)
            } else {
                guard let term = dictionary.terms.first(where: { $0.id == g.termID }),
                      !term.aliases.contains(where: { UserDictionary.key($0.text) == UserDictionary.key(g.stem) }),
                      // Term + „końcówka” to zwykłe słowo: korekta dotyczyła tego słowa, nie Terma („pordfel → portfel” przy „Port”).
                      !g.endedTargets.contains(where: isCommonWord) else { continue }
                let s = AliasSuggestion(id: id, termID: g.termID, term: g.term, alias: g.stem, inflects: inflects, risky: risky,
                                        forms: Array(forms.prefix(3)), count: total, sessions: g.sessions.sorted(),
                                        fromEdits: !g.editKeys.isEmpty)
                if s.isDismissed(in: dismissed) { continue }
                // Add musi przejść ten sam `upsert` co ręczne dodanie; inaczej sugestia byłaby przyciskiem, który zawsze zawodzi.
                guard (try? accept(s, in: dictionary)) != nil else { continue }
                out.append(s)
            }
        }
        return out.sorted { ($1.count, $0.term, $0.alias) < ($0.count, $1.term, $1.alias) }
    }

    /// Rozszerzony blok zmiany; `pair` jest nil, gdy poprawiona forma nie jest istniejącym Termem (ścieżka nowego Terma).
    private struct Widened { var raw: [String]; var fixed: [String]; var pair: Pair? }

    /// Para z bloku zmiany; gdy Term wielowyrazowy dzieli słowo z oryginałem („Rokm Max” → „Nimbu Max”), LCS wydziela wspólne „Max”,
    /// więc blok rozszerzamy o do 2 zgodnych słów z każdej strony.
    private static func widened(_ oi: Range<Int>, _ ci: Range<Int>, _ o: [String], _ c: [String], _ ok: [String], _ ck: [String],
                                terms: [DictionaryTerm], fillers: Set<String>) -> Widened? {
        // Wypełniacze sprawdzamy na samym bloku zmiany: rozszerzenie o „Max” nie może przepuścić „yyy Max → Nimbu Max”.
        guard !oi.allSatisfy({ fillers.contains(ok[$0]) }) else { return nil }
        // Pierwsze pasujące rozszerzenie zostaje dla nowego Terma, gdy żadne nie trafia w istniejący Term.
        var fallback: (raw: [String], fixed: [String])?
        for (l, r) in [(0, 0), (0, 1), (1, 0), (1, 1), (0, 2), (2, 0)] {
            let ol = oi.lowerBound - l, cl = ci.lowerBound - l, ou = oi.upperBound + r, cu = ci.upperBound + r
            guard ol >= 0, cl >= 0, ou <= o.count, cu <= c.count,
                  ok[ol..<oi.lowerBound] == ck[cl..<ci.lowerBound], ok[oi.upperBound..<ou] == ck[ci.upperBound..<cu] else { continue }
            let raw = Array(o[ol..<ou]), fixed = Array(c[cl..<cu])
            if let p = pair(raw, fixed, terms: terms) { return Widened(raw: raw, fixed: fixed, pair: p) }
            if fallback == nil { fallback = (raw, fixed) }
        }
        guard let f = fallback else { return nil }
        return Widened(raw: f.raw, fixed: f.fixed, pair: nil)
    }

    /// Para „nowy Term”: poprawiona fraza zostaje Termem, surowa — Aliasem bez odmiany. Odrzucamy kolizje z istniejącym Termem/Aliasem
    /// i przerywniki: `upsert` i tak by je odrzucił, a sugestia nie może być przyciskiem, który zawsze zawodzi.
    private static func newPair(_ rawTokens: [String], _ fixedTokens: [String], dictionary: UserDictionary,
                                fillers: Set<String>) -> (stem: String, term: String)? {
        let before = rawTokens.map(trimmed), after = fixedTokens.map(trimmed)
        let raw = before.joined(separator: " "), corrected = after.joined(separator: " ")
        // Interpunkcja w środku frazy: Replacement dopasowuje dosłowną spację, więc taki Alias nic by nie zmienił.
        guard !raw.isEmpty, !corrected.isEmpty,
              trimmed(rawTokens.joined(separator: " ")) == raw, trimmed(fixedTokens.joined(separator: " ")) == corrected,
              UserDictionary.key(raw) != UserDictionary.key(corrected),
              !(before + after).contains(where: { $0.contains(where: \.isNumber) }),
              !(before + after).contains(where: { fillers.contains(CorrectionGuard.key($0)) }),
              // Poprawiona strona nie może być już Termem/Aliasem: to nie nowa nazwa, tylko nadpisanie istniejącej.
              !dictionary.terms.contains(where: { UserDictionary.key($0.text) == UserDictionary.key(corrected) }),
              // Surowa strona ani poprawiona nie może być odmienioną formą Terma: „widzę Nimbua” → „widzę Nimbuie” to nie nowa nazwa.
              !dictionary.terms.contains(where: { isTermForm(raw, of: $0) || isTermForm(corrected, of: $0) }),
              dictionary.owner(ofAlias: corrected) == nil,
              dictionary.owner(ofAlias: raw) == nil else { return nil }
        return (raw, corrected)
    }

    /// Dokładnie Term albo Term + końcówka z liter, zaczynający się tą samą literą („Nimbuie”, „Nimbuowski” przy „Nimbu”).
    private static func isTermForm(_ text: String, of term: DictionaryTerm) -> Bool {
        let key = UserDictionary.key(text), base = UserDictionary.key(term.text)
        if key == base { return true }
        let lower = text.lowercased(), termLower = term.text.lowercased()
        return text.first == term.text.first && lower.hasPrefix(termLower)
            && lower.dropFirst(termLower.count).allSatisfy(\.isLetter)
    }

    private struct Pair { var raw: String; var corrected: String; var stem: String; var ending: String; var term: DictionaryTerm }

    private static func pair(_ rawTokens: [String], _ fixedTokens: [String], terms: [DictionaryTerm]) -> Pair? {
        let before = rawTokens.map(trimmed), after = fixedTokens.map(trimmed)
        let raw = before.joined(separator: " "), corrected = after.joined(separator: " ")
        // Interpunkcja w środku frazy („ko, pt”): Replacement dopasowuje dosłowną spację, więc taki Alias nic by nie zmienił.
        guard trimmed(rawTokens.joined(separator: " ")) == raw, trimmed(fixedTokens.joined(separator: " ")) == corrected,
              !(before + after).contains(where: { $0.contains(where: \.isNumber) }),
              let found = candidate(raw: raw, corrected: corrected, terms: terms) else { return nil }
        return Pair(raw: raw, corrected: corrected, stem: found.stem, ending: found.ending, term: found.term)
    }

    /// Słownik z dopisanym Aliasem (przez `upsert`); błąd walidacji przechodzi do wywołującego.
    public static func accept(_ s: AliasSuggestion, in d: UserDictionary) throws(DictionaryError) -> UserDictionary {
        var out = d
        // Nowy Term: `find` nadał `termID`, więc Add jest tą samą walidacją co ręczne dodanie.
        // Druga poprawka ucząca innego Aliasu tego samego Terma musi dopisać Alias, nie nadpisać listy (`upsert` podmienia cały Term).
        if s.isNewTerm {
            if var term = d.terms.first(where: { $0.id == s.termID || UserDictionary.key($0.text) == UserDictionary.key(s.term) }) {
                term.aliases.append(DictionaryAlias(s.alias, risky: s.risky, enabled: true, inflects: false))
                try out.upsert(term)
            } else {
                try out.upsert(DictionaryTerm(s.term, aliases: [DictionaryAlias(s.alias, risky: s.risky, enabled: true, inflects: false)],
                                              id: s.termID))
            }
            return out
        }
        guard var term = d.terms.first(where: { $0.id == s.termID }) else { throw .emptyTerm }
        term.aliases.append(DictionaryAlias(s.alias, risky: s.risky, enabled: true, inflects: s.inflects))
        try out.upsert(term)
        return out
    }

    /// Liczba słów różniących się między tekstami po kluczach `TokenAlign`: `editPairs` wybiera bazę bliższą tekstowi poprawki.
    public static func differingWords(_ a: String, _ b: String) -> Int {
        let ka = words(a).map(CorrectionGuard.key), kb = words(b).map(CorrectionGuard.key)
        return CorrectionGuard.align(ka, kb).reduce(0) { n, step in
            guard case .changed(let l, let r) = step else { return n }
            return n + max(l.count, r.count)
        }
    }

    /// Cyfra albo słowo liczebnikowe/negacja po którymkolwiek rdzeniu (F1): poprawka liczby lub negacji nie uczy nazwy.
    private static func isNumberOrNegation(_ token: String) -> Bool {
        let t = UserDictionary.key(token).trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        guard !t.isEmpty else { return false }
        if t.contains(where: \.isNumber) { return true }
        if negationWords.contains(t) || negationPrefixes.contains(where: { t.hasPrefix($0) }) || t.hasSuffix("n't") || t.hasSuffix("n\u{2019}t") { return true }
        if numberWordsEN.contains(t) || numberWordsPL.contains(t) { return true }
        if numberPrefixesPL.contains(where: { t.hasPrefix($0) }) { return true }
        // Złożenia z myślnikiem („twenty-one”): sprawdzamy każdą część osobno.
        if t.contains("-") { return t.split(separator: "-").contains { isNumberOrNegation(String($0)) } }
        return false
    }

    /// Pełne słowa EN (liczebniki i porządkowe).
    private static let numberWordsEN: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion", "trillion",
        "hundreds", "thousands", "millions", "billions", "trillions",
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
        "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth",
        "twentieth", "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth", "ninetieth",
        "once", "twice", "thrice",
    ]

    /// Polskie formy liczebników, których nie da się bezpiecznie dopasować krótkim prefiksem.
    private static let numberWordsPL: Set<String> = [
        "jeden", "jedna", "jedno", "jedne", "jedni", "jednego", "jednej", "jednym", "jednych",
        // „jedną" nie łapie się żadnym wąskim prefiksem („jedn-" objąłby „jednak", „jednostka").
        "jedną", "jednemu", "jednymi", "jednemi",
        "dwa", "dwie", "dwu", "dwóch", "dwoma", "dwom", "dwoje", "dwojga",
        "trzy", "trzech", "trzem", "trzema", "troje", "trojga", "trzej",
        "cztery", "czterech", "czterem", "czterema", "czworo",
        "pięć", "pięciu", "pięcią", "pięcioma", "piątka",
        "sześć", "sześciu", "sześcioma", "szóstka",
        "siedem", "siedmiu", "siedmioma", "siódemka",
        "osiem", "ośmiu", "ośmioma", "ósemka",
        "dziewięć", "dziewięciu", "dziewięcioma", "dziewiątka",
        "dziesięć", "dziesięciu", "dziesięcioma", "dziesiątka",
        "sto", "stu", "stoma", "setka", "setki", "setkę", "setek", "setkami",
        "tysiąc", "tysiące", "tysięcy", "tysiącami", "tysiączny",
        "milion", "miliony", "milionów", "milionami", "milionowy",
        "zero", "zerowy", "zerowa", "zerowe",
    ]

    /// Rdzenie polskich liczebników (odmiany i dziesiątki); pełne krótkie formy są wyżej, żeby nie łapać „stołek” czy „student”.
    private static let numberPrefixesPL: [String] = [
        "dwudziest", "dwadzie", "dwunast", "dwoj", "dwust", "dwieści", "dwiesc",
        "trzydzie", "trzynast", "trzeci", "trzyst",
        "czterdzie", "czternast", "czter", "czteryst",
        "pięćdzie", "piecdzie", "pięćset", "piecset", "piętnast", "pietnast", "pięci", "pieci", "piąt", "piat",
        "sześćdzie", "szescdzie", "sześćset", "szescset", "szesnast", "sześci", "szesci", "szóst", "szost",
        "siedemdzie", "siedemset", "siedemnast", "siedmi",
        "osiemdzie", "osiemset", "osiemnast", "ośmi", "osmi",
        "dziewięćdzie", "dziewiecdzie", "dziewięćset", "dziewiecset", "dziewiętnast", "dziewietnast", "dziewię", "dziewie", "dziewiąt", "dziewiat",
        "jedenast", "jedyn", "dziesiąt", "dziesiat",
        // Pełne rdzenie 11–18 z „-naście" (z diakrytykami i bez): „dwanaście” → „piętnaście” to liczebnik, nie nazwa (F4).
        "jedenaśc", "jedenasc", "dwanaśc", "dwanasc", "trzynaśc", "trzynasc",
        "czternaśc", "czternasc", "piętnaśc", "pietnasc", "szesnaśc", "szesnasc",
        "siedemnaśc", "siedemnasc", "osiemnaśc", "osiemnasc", "dziewiętnaśc", "dziewietnasc",
        "pierwsz", "drug", "czwart",
        // Odmiany liczebników rzeczownikowych: „tysiącem", „milionem", „setką" (F1).
        "tysi", "tysięcz", "tysiecz", "milion", "miliard", "setk",
        // „sto"/„stu" tylko w całości (wyżej), bo prefiks „sto-" złapałby „stoi", „stół", „stoper".
    ]

    private static let negationWords: Set<String> = [
        "nie", "bez", "brak", "nigdy", "ani", "żaden", "zadna", "żadna", "żadne", "zadne", "żadnego", "zadnego",
        "żadnej", "zadnej", "no", "not", "never", "none", "nobody", "nothing", "nowhere", "without", "nor", "neither", "cannot",
    ]

    /// Prefiksy odmian negacji; „nie”, „bez” i „ani” tylko w całości, żeby nie łapać „niebo”, „bezpieczny”, „animacja”.
    private static let negationPrefixes: [String] = ["brak", "żadn", "zadn"]

    /// Fraza jest zwykła, gdy każde jej słowo jest zwykłe („on track"); pojedyncze słowo — gdy samo jest zwykłe.
    private static func isCommon(_ phrase: String, _ isCommonWord: (String) -> Bool) -> Bool {
        phrase.split(separator: " ").allSatisfy { isCommonWord(String($0)) }
    }

    /// Strona poprawiona to Term (dowolna wielkość liter) albo Term + końcówka z liter, zaczynający się tą samą literą co Term
    /// („Koptem” przy „KOPT”, nie „portfel” przy „Port”); rdzeń = strona surowa bez tej samej końcówki.
    private static func candidate(raw: String, corrected: String, terms: [DictionaryTerm]) -> (stem: String, ending: String, term: DictionaryTerm)? {
        guard UserDictionary.key(raw) != UserDictionary.key(corrected),
              let term = terms.first(where: { t in
                  UserDictionary.key(corrected) == UserDictionary.key(t.text)
                      || (corrected.first == t.text.first && corrected.lowercased().hasPrefix(t.text.lowercased())
                          && corrected.lowercased().dropFirst(t.text.lowercased().count).allSatisfy(\.isLetter))
              }) else { return nil }
        // Surowa forma to już Term z inną końcówką („Nimbuie” → „Nimbu”): korektor zmienił odmianę, nie poprawił nazwy.
        guard !UserDictionary.key(raw).hasPrefix(UserDictionary.key(term.text)) else { return nil }
        let ending = UserDictionary.key(corrected) == UserDictionary.key(term.text) ? "" : String(corrected.lowercased().dropFirst(term.text.lowercased().count))
        // Końcówka liczona na małych literach; `lowercased` zmieniające długość („İ") pomija parę.
        guard raw.lowercased().count == raw.count, raw.lowercased().hasSuffix(ending), raw.count > ending.count else { return nil }
        return (String(raw.dropLast(ending.count)), ending, term)
    }

    /// Wystąpienia frazy jako całych słów w linii kluczy (oddzielonych spacją).
    private static func occurrences(of phrase: String, in line: String) -> Int {
        (" " + line + " ").components(separatedBy: " " + phrase + " ").count - 1
    }

    private static func words(_ s: String) -> [String] { s.split(separator: " ", omittingEmptySubsequences: true).map(String.init) }

    private static func trimmed(_ token: String) -> String { token.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
}
