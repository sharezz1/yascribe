import Foundation
import Testing
@testable import YascribeTranscription
@testable import YascribeNotes

@Suite struct ReplacementTests {
    private func rules(_ terms: DictionaryTerm...) -> ReplacementRules { ReplacementRules(UserDictionary(terms: terms)) }

    /// Swift `==` na `String` porównuje kanonicznie (NFD == NFC); tu liczą się skalary.
    private func scalars(_ s: String) -> [Unicode.Scalar] { Array(s.unicodeScalars) }

    @Test func replacesAliasWithTermExactSpelling() {
        #expect(rules(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm")])).apply(to: "Rokm mówi") == "Nimbu mówi")
        #expect(rules(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm")])).apply(to: " Rokm\n") == " Nimbu\n")
        #expect(rules(DictionaryTerm("KOPT", aliases: [DictionaryAlias("Kopt")])).apply(to: "w Kopt obok") == "w KOPT obok")
    }

    @Test func matchingIgnoresCase() {
        #expect(rules(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm")])).apply(to: "rOkM") == "Nimbu")
    }

    @Test func matchesOnlyOnWordBoundaries() {
        let r = rules(DictionaryTerm("KOPT", aliases: [DictionaryAlias("ko pt"), DictionaryAlias("Kopt")]),
                      DictionaryTerm("Dorn", aliases: [DictionaryAlias("Dorna")]))
        #expect(r.apply(to: "pu dowolny") == "pu dowolny")
        #expect(r.apply(to: "ko pt.") == "KOPT.")
        #expect(r.apply(to: "Koptwski") == "Koptwski")
        #expect(r.apply(to: "Dornań") == "Dornań")
        #expect(r.apply(to: "żJarla") == "żJarla")
        #expect(r.apply(to: "(Dorna)") == "(Dorn)")
    }

    @Test func longestAliasWins() {
        let r = rules(DictionaryTerm("OnTrack", aliases: [DictionaryAlias("in"), DictionaryAlias("on track")]))
        #expect(r.apply(to: "on track") == "OnTrack")
        #expect(r.apply(to: "paczka on track i in") == "paczka OnTrack i OnTrack")
    }

    @Test func aliasDoesNotRechainIntoItsResult() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("A", aliases: [DictionaryAlias("b")]))
        let r = ReplacementRules(d)
        #expect(r.apply(to: "b") == "A")
        #expect(r.apply(to: r.apply(to: "b")) == "A")
    }

    @Test func termTextContainingOwnAliasIsNotReplacedAgain() {
        let r = rules(DictionaryTerm("Kopt Max", aliases: [DictionaryAlias("kopt")]))
        #expect(r.apply(to: "kopt") == "Kopt Max")
        #expect(r.apply(to: r.apply(to: "kopt")) == r.apply(to: "kopt"))
    }

    @Test func termTextContainingOtherTermsAliasIsNotReplacedAgain() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("KOPT", aliases: [DictionaryAlias("Kopt")]))
        try d.upsert(DictionaryTerm("Dorn Kopt", aliases: [DictionaryAlias("dornkopt")]))
        let r = ReplacementRules(d)
        #expect(r.apply(to: "dornkopt") == "Dorn Kopt")
        #expect(r.apply(to: r.apply(to: "dornkopt")) == "Dorn Kopt")
        #expect(r.apply(to: "Dorn Kopt i Kopt") == "Dorn Kopt i KOPT")
    }

    private func upserted(_ terms: DictionaryTerm...) throws -> ReplacementRules {
        var d = UserDictionary()
        for t in terms { try d.upsert(t) }
        return ReplacementRules(d)
    }

    @Test func replacementDoesNotCreateAliasAcrossBoundary() throws {
        let r1 = try upserted(DictionaryTerm("A", aliases: [DictionaryAlias("x")]), DictionaryTerm("B", aliases: [DictionaryAlias("A y")]))
        #expect(r1.apply(to: "x y") == "B")
        #expect(r1.apply(to: r1.apply(to: "x y")) == r1.apply(to: "x y"))
        let r2 = try upserted(DictionaryTerm("New York", aliases: [DictionaryAlias("nyc")]),
                              DictionaryTerm("City", aliases: [DictionaryAlias("in New")]))
        #expect(r2.apply(to: "in nyc") == "City York")
        #expect(r2.apply(to: r2.apply(to: "in nyc")) == r2.apply(to: "in nyc"))
    }

    @Test func overlappingTermIdentitiesRemainStable() throws {
        let r3 = try upserted(DictionaryTerm("A B", aliases: [DictionaryAlias("x")]), DictionaryTerm("B C", aliases: [DictionaryAlias("y")]),
                              DictionaryTerm("Z", aliases: [DictionaryAlias("C")]))
        #expect(r3.apply(to: "A y") == "A B Z")
        #expect(r3.apply(to: r3.apply(to: "A y")) == r3.apply(to: "A y"))
        let r4 = try upserted(DictionaryTerm("A", aliases: [DictionaryAlias("A B")]))
        #expect(r4.apply(to: "A B B") == "A")
        #expect(r4.apply(to: r4.apply(to: "A B B")) == r4.apply(to: "A B B"))
    }

    /// Klucz `UserDictionary` składa wielkość liter jak ICU `(?i:)`: bez tego „strase" → „Straße" → „Other" (Alias „STRASSE").
    @Test func caseFoldEquivalentAliasCannotRewriteTerm() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("Straße", aliases: [DictionaryAlias("strase"), DictionaryAlias("Maßnahme")]))
        #expect(throws: DictionaryError.aliasIsTerm(alias: "STRASSE", term: "Straße")) {
            try d.upsert(DictionaryTerm("Other", aliases: [DictionaryAlias("STRASSE")]))
        }
        #expect(throws: DictionaryError.duplicateTerm("STRASSE")) { try d.upsert(DictionaryTerm("STRASSE")) }
        #expect(throws: DictionaryError.aliasTaken(alias: "MASSNAHME", by: "Straße")) {
            try d.upsert(DictionaryTerm("Other", aliases: [DictionaryAlias("MASSNAHME")]))
        }
        #expect(throws: DictionaryError.aliasIsTerm(alias: "MASSNAHME", term: "Straße")) { try d.upsert(DictionaryTerm("MASSNAHME")) }
        #expect(ReplacementRules(d).apply(to: "strase") == "Straße")
    }

    /// „ς" (końcowa sigma) i „σ" mają ten sam klucz, jak w ICU `(?i:)`; samo `lowercased()` ich nie zrównuje.
    @Test func finalSigmaFoldsLikeSigma() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("λόγος", aliases: [DictionaryAlias("logos")]))
        #expect(throws: DictionaryError.aliasIsTerm(alias: "λόγοσ", term: "λόγος")) {
            try d.upsert(DictionaryTerm("Other", aliases: [DictionaryAlias("λόγοσ")]))
        }
        #expect(ReplacementRules(d).apply(to: "logos") == "λόγος")
    }

    /// Łańcuch dłuższy niż 5 rund (R10): wynik po 5 rundach, bez gwarancji idempotencji dalej.
    @Test func fixpointStopsAfterFiveRounds() throws {
        let r = try upserted(DictionaryTerm("P1", aliases: [DictionaryAlias("x")]), DictionaryTerm("P2", aliases: [DictionaryAlias("P1 y")]),
                             DictionaryTerm("P3", aliases: [DictionaryAlias("P2 y")]), DictionaryTerm("P4", aliases: [DictionaryAlias("P3 y")]),
                             DictionaryTerm("P5", aliases: [DictionaryAlias("P4 y")]), DictionaryTerm("P6", aliases: [DictionaryAlias("P5 y")]))
        #expect(r.apply(to: "x y y y y y") == "P5 y")
        #expect(r.apply(to: "P5 y") == "P6")
    }

    /// Filtr wstępny (R17) nie zmienia wyniku: każda para słownik × tekst daje to samo z filtrem i bez (porównanie skalarów).
    @Test func preFilterNeverChangesResults() throws {
        func t(_ text: String, _ aliases: String...) -> DictionaryTerm { DictionaryTerm(text, aliases: aliases.map { DictionaryAlias($0) }) }
        let nfd = { (s: String) in s.decomposedStringWithCanonicalMapping }
        let dictionaries: [[DictionaryTerm]] = [
            [],
            [t("Hash", "#tag"), t("Nimbu", "Rokm")],                      // Alias od symbolu: filtr wyłączony
            [t("Strasse", "straße"), t("Fuß", "fuss")],                     // ß ≡ SS
            [t("Logos", "λόγοσ")],                                          // ς ≡ σ
            [t("Orbit", "Żorbit"), t("Żuraw", nfd("żuraw"))],           // NFD/NFC
            [t("Y", "x")],                                                  // znak łączący po słowie
            [t("KOPT", "ko pt", "Kopt"), t("Dorn", "Dorna")],               // wielowyrazowy
            [t("e-mail", "e-mejl"), t("OnTrack", "in", "on track")],          // z łącznikiem, najdłuższy
            [t("Kopt Max", "kopt")],                                        // ochrona tekstu Terma
            [t("KOPT", "Kopt"), t("Dorn Kopt", "dornkopt")],
            [t("A", "x"), t("B", "A y")], [t("A B", "x"), t("B C", "y"), t("Z", "C")],
            [t("Nimbu", "Rokm"), t("queue")],                               // wielkość liter
            [t(".NET", "dotnet"), t("Core", "kor")],                         // Term od symbolu: filtr wyłączony
        ]
        let texts = ["", "   ", "...!?", "a #tag b", "#TAG", "tag", "STRASSE i Straße", "strasse x", "FUSS", "Fuß", "λόγος", "ΛΌΓΟΣ", "λόγοι",
                     nfd("o Żorbit"), "o Żorbit", "dżenesisy", "ŻURAW", nfd("Żuraw"), "x\u{0301}yz", "x\u{0301}", "x y", "ko pt.", "pu dowolny",
                     "KO PT", "Koptwski", "Dornań", "wyślij e-mejl", "e-mejla", "e mejl", "on track i in", "kopt", "Kopt Max", "dornkopt",
                     "Dorn Kopt i Kopt", "x y", "A y", "A B B", "rOkM i ROKM", "Queue i Rokm", "nic tu nie ma", "dotnet i kor", ".NET kor"]
        for terms in dictionaries {
            let r = ReplacementRules(UserDictionary(terms: terms))
            for x in texts {
                #expect(scalars(r.apply(to: x)) == scalars(r.apply(to: x, preFilter: false)), "\(terms.map(\.text)) \(x)")
            }
        }
        #expect(ReplacementRules(UserDictionary(terms: dictionaries[1])).mayMatch("nic tu nie ma"))
        #expect(ReplacementRules(UserDictionary(terms: dictionaries[13])).mayMatch("nic tu nie ma"))
    }

    /// Przypadki brzegowe filtra (M1): wynik z filtrem i bez niego równy oczekiwanemu (`==`, równoważność kanoniczna).
    @Test func preFilterMatchesRegexOnAdversarialCases() throws {
        let prefix = String(repeating: "lorem ipsum ", count: 4200)   // ok. 50 tys. znaków innych słów
        let cases: [(alias: String, text: String, expected: String)] = [
            ("fi", "\u{FB01}", "Target"),                                // ligatura ﬁ
            ("k", "\u{212A}", "Target"),                                 // znak Kelvina
            ("\u{01C5}", "\u{01C6}", "Target"),                          // ǅ / ǆ
            ("i", "\u{0131}", "\u{0131}"),                                // ı bez kropki: ICU go nie składa do i
            ("\u{0130}", "i\u{0307}", "Target"),                         // İ / i + kropka
            ("o'neil", "O'NEIL", "Target"),
            ("r2.d2", "R2.D2", "Target"),
            ("3d", "x_3D\u{203F}3d", "x_Target\u{203F}Target"),           // łączniki Pc nie są słowem
            ("a", "a\u{2163} a\u{00B2}", "a\u{2163} a\u{00B2}"),          // Nl i No przedłużają słowo
            ("ko pt", "pu\u{0301} do", "pu\u{0301} do"),
            ("x\u{0301} y", "X\u{0301} Y", "Target"),                     // Alias ze znakiem łączącym w środku
            ("Rokm", "\u{1F600} Rokm \u{1F600}\u{1F600}zoim", "\u{1F600} Target \u{1F600}\u{1F600}Target"),  // UTF-16 poza BMP
            ("Rokm", prefix + "Rokm", prefix + "Target"),
        ]
        for c in cases {
            let r = rules(DictionaryTerm("Target", aliases: [DictionaryAlias(c.alias)]))
            #expect(r.apply(to: c.text) == c.expected, "\(c.alias) \(c.text.prefix(40))")
            #expect(r.apply(to: c.text, preFilter: false) == c.expected, "\(c.alias) \(c.text.prefix(40))")
        }
        // Punkt stały po długim przedrostku: druga runda też musi trafić w słowo daleko od początku.
        let chain = try upserted(DictionaryTerm("A", aliases: [DictionaryAlias("x")]), DictionaryTerm("B", aliases: [DictionaryAlias("A y")]))
        #expect(chain.apply(to: prefix + "\u{1F600}x y") == prefix + "\u{1F600}B")
        #expect(chain.apply(to: prefix + "\u{1F600}x y", preFilter: false) == prefix + "\u{1F600}B")
    }

    @Test func preFilterSkipsRegexWhenNoCandidateToken() {
        let r = rules(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm")]))
        let runs = ReplacementRules.RegexRuns()
        ReplacementRules.$regexRuns.withValue(runs) { #expect(r.apply(to: "nic tu nie ma") == "nic tu nie ma") }
        #expect(runs.count == 0)
        ReplacementRules.$regexRuns.withValue(runs) { #expect(r.apply(to: "ROKM mówi") == "Nimbu mówi") }
        #expect(runs.count == 2)
    }

    @Test func termIdentityIsCaseSensitive() {
        let r = rules(DictionaryTerm("queue"), DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm")]))
        #expect(!r.isEmpty)
        #expect(r.apply(to: "Queue i Rokm") == "Queue i Nimbu")
        #expect(r.apply(to: "Queue stoi") == "Queue stoi")
    }

    @Test func disabledAliasIsIgnored() {
        let r = rules(DictionaryTerm("KOPT", aliases: [DictionaryAlias("ko pt", risky: true, enabled: false)]))
        #expect(r.isEmpty)
        #expect(r.apply(to: "ko pt") == "ko pt")
        let mixed = rules(DictionaryTerm("KOPT", aliases: [DictionaryAlias("ko pt", risky: true, enabled: false), DictionaryAlias("Kopt")]))
        #expect(!mixed.isEmpty)
        #expect(mixed.apply(to: "ko pt i Kopt") == "ko pt i KOPT")
    }

    @Test func isIdempotent() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm")]))
        try d.upsert(DictionaryTerm("KOPT", aliases: [DictionaryAlias("Kopt"), DictionaryAlias("ko pt")]))
        try d.upsert(DictionaryTerm("OnTrack", aliases: [DictionaryAlias("in"), DictionaryAlias("on track")]))
        try d.upsert(DictionaryTerm("A", aliases: [DictionaryAlias("b")]))
        try d.upsert(DictionaryTerm("CPP", aliases: [DictionaryAlias("c++ (x)")]))
        try d.upsert(DictionaryTerm("Dorn", aliases: [DictionaryAlias("Dorna")]))
        try d.upsert(DictionaryTerm("Orbit", aliases: [DictionaryAlias("Żorbit")]))
        let r = ReplacementRules(d)
        let texts = ["Rokm mówi", "rOkM", "w Kopt obok", "pu dowolny", "ko pt.", "Dornań", "on track i in", "b", "c++ (x) i cccc",
                     "Mówię o Żorbit".decomposedStringWithCanonicalMapping, "x\u{0301}yz", ""]
        for x in texts {
            let once = r.apply(to: x)
            #expect(scalars(r.apply(to: once)) == scalars(once), "\(x)")
        }
        #expect(r.apply(to: "Rokm i Kopt w on track, b") == "Nimbu i KOPT w OnTrack, A")
    }

    @Test func specialCharactersInAliasAreLiteral() {
        let r = rules(DictionaryTerm("CPP", aliases: [DictionaryAlias("c++ (x)")]),
                      DictionaryTerm("E.ON", aliases: [DictionaryAlias("e.on")]))
        #expect(r.apply(to: "c++ (x)") == "CPP")
        #expect(r.apply(to: "cccc") == "cccc")
        #expect(r.apply(to: "c x") == "c x")
        #expect(r.apply(to: "e.on i exon") == "E.ON i exon")
    }

    @Test func nfdTextMatchesNfcAlias() {
        let r = rules(DictionaryTerm("Orbit", aliases: [DictionaryAlias("Żorbit")]))
        let nfd = "Mówię o Żorbit".decomposedStringWithCanonicalMapping
        #expect(scalars(nfd) != scalars("Mówię o Żorbit".precomposedStringWithCanonicalMapping))
        #expect(scalars(r.apply(to: nfd)) == scalars("Mówię o Orbit".precomposedStringWithCanonicalMapping))
        // Alias w NFD (np. ręcznie wpisany do dictionary.json z pominięciem upsert) też trafia w tekst NFC.
        let nfdAlias = rules(DictionaryTerm("Orbit", aliases: [DictionaryAlias("Żorbit".decomposedStringWithCanonicalMapping)]))
        #expect(nfdAlias.apply(to: "o Żorbit".precomposedStringWithCanonicalMapping) == "o Orbit")
    }

    @Test func combiningMarkContinuesTheWord() {
        let r = rules(DictionaryTerm("Y", aliases: [DictionaryAlias("x")]))
        #expect(scalars(r.apply(to: "x\u{0301}yz")) == scalars("x\u{0301}yz"))
        #expect(r.apply(to: "x yz") == "Y yz")
    }

    @Test func emptyRulesReturnSameTranscript() {
        let nfd = "Mówię o Żorbit".decomposedStringWithCanonicalMapping
        let t = transcript([utt(nfd, .me, at: 3, flagged: true), utt("Rokm", .them, at: 7, echo: true)])
        for r in [ReplacementRules(UserDictionary()),
                  rules(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm", risky: true, enabled: false)]))] {
            #expect(r.isEmpty)
            let out = Replacement.apply(t, rules: r)
            #expect(out == t)
            #expect(scalars(out.utterances[0].text) == scalars(nfd))
            #expect(out.utterances[1].text == "Rokm")
        }
    }

    @Test func transcriptReplacementKeepsWordsAndTimes() {
        var u = utt("Rokm mówi", .them, at: 5, flagged: true, echo: true)
        u.words = [Word(text: "Rokm", start: 5, end: 5.4), Word(text: "mówi", start: 5.5, end: 6)]
        u.approximateTiming = true
        let t = Transcript(utterances: [u, utt("bez zmian", .me, at: 9)],
                           failedChunks: [ChunkFailure(track: "system", index: 2, start: 60, end: 90, error: "x")])
        let out = Replacement.apply(t, rules: rules(DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm")])))
        #expect(out.utterances.map(\.text) == ["Nimbu mówi", "bez zmian"])
        #expect(out.failedChunks == t.failedChunks)
        for (a, b) in zip(out.utterances, t.utterances) {
            #expect(a.words == b.words)
            #expect(a.start == b.start)
            #expect(a.end == b.end)
            #expect(a.speaker == b.speaker)
            #expect(a.languageMismatch == b.languageMismatch)
            #expect(a.echoOfThem == b.echoOfThem)
            #expect(a.approximateTiming == b.approximateTiming)
        }
    }
}
