import Foundation
import Testing
@testable import MeetNotesTranscription
@testable import MeetNotesNotes

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
