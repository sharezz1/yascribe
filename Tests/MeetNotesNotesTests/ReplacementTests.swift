import Foundation
import Testing
@testable import MeetNotesTranscription
@testable import MeetNotesNotes

@Suite struct ReplacementTests {
    private func rules(_ terms: DictionaryTerm...) -> ReplacementRules { ReplacementRules(UserDictionary(terms: terms)) }

    /// Swift `==` na `String` porównuje kanonicznie (NFD == NFC); tu liczą się skalary.
    private func scalars(_ s: String) -> [Unicode.Scalar] { Array(s.unicodeScalars) }

    @Test func replacesAliasWithTermExactSpelling() {
        #expect(rules(DictionaryTerm("Zowie", aliases: [DictionaryAlias("Zoim")])).apply(to: "Zoim mówi") == "Zowie mówi")
        #expect(rules(DictionaryTerm("Zowie", aliases: [DictionaryAlias("Zoim")])).apply(to: " Zoim\n") == " Zowie\n")
        #expect(rules(DictionaryTerm("PUDO", aliases: [DictionaryAlias("Pudo")])).apply(to: "w Pudo obok") == "w PUDO obok")
    }

    @Test func matchingIgnoresCase() {
        #expect(rules(DictionaryTerm("Zowie", aliases: [DictionaryAlias("Zoim")])).apply(to: "zOiM") == "Zowie")
    }

    @Test func matchesOnlyOnWordBoundaries() {
        let r = rules(DictionaryTerm("PUDO", aliases: [DictionaryAlias("pu do"), DictionaryAlias("Pudo")]),
                      DictionaryTerm("Jarl", aliases: [DictionaryAlias("Jarla")]))
        #expect(r.apply(to: "pu dowolny") == "pu dowolny")
        #expect(r.apply(to: "pu do.") == "PUDO.")
        #expect(r.apply(to: "Pudowski") == "Pudowski")
        #expect(r.apply(to: "Jarlań") == "Jarlań")
        #expect(r.apply(to: "żJarla") == "żJarla")
        #expect(r.apply(to: "(Jarla)") == "(Jarl)")
    }

    @Test func longestAliasWins() {
        let r = rules(DictionaryTerm("InPost", aliases: [DictionaryAlias("in"), DictionaryAlias("in post")]))
        #expect(r.apply(to: "in post") == "InPost")
        #expect(r.apply(to: "paczka in post i in") == "paczka InPost i InPost")
    }

    @Test func aliasDoesNotRechainIntoItsResult() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("A", aliases: [DictionaryAlias("b")]))
        let r = ReplacementRules(d)
        #expect(r.apply(to: "b") == "A")
        #expect(r.apply(to: r.apply(to: "b")) == "A")
    }

    @Test func termTextContainingOwnAliasIsNotReplacedAgain() {
        let r = rules(DictionaryTerm("Pudo Max", aliases: [DictionaryAlias("pudo")]))
        #expect(r.apply(to: "pudo") == "Pudo Max")
        #expect(r.apply(to: r.apply(to: "pudo")) == r.apply(to: "pudo"))
    }

    @Test func termTextContainingOtherTermsAliasIsNotReplacedAgain() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("PUDO", aliases: [DictionaryAlias("Pudo")]))
        try d.upsert(DictionaryTerm("Jarl Pudo", aliases: [DictionaryAlias("jarlpudo")]))
        let r = ReplacementRules(d)
        #expect(r.apply(to: "jarlpudo") == "Jarl Pudo")
        #expect(r.apply(to: r.apply(to: "jarlpudo")) == "Jarl Pudo")
        #expect(r.apply(to: "Jarl Pudo i Pudo") == "Jarl Pudo i PUDO")
    }

    @Test func termIdentityIsCaseSensitive() {
        let r = rules(DictionaryTerm("queue"), DictionaryTerm("Zowie", aliases: [DictionaryAlias("Zoim")]))
        #expect(!r.isEmpty)
        #expect(r.apply(to: "Queue i Zoim") == "Queue i Zowie")
        #expect(r.apply(to: "Queue stoi") == "Queue stoi")
    }

    @Test func disabledAliasIsIgnored() {
        let r = rules(DictionaryTerm("PUDO", aliases: [DictionaryAlias("pu do", risky: true, enabled: false)]))
        #expect(r.isEmpty)
        #expect(r.apply(to: "pu do") == "pu do")
        let mixed = rules(DictionaryTerm("PUDO", aliases: [DictionaryAlias("pu do", risky: true, enabled: false), DictionaryAlias("Pudo")]))
        #expect(!mixed.isEmpty)
        #expect(mixed.apply(to: "pu do i Pudo") == "pu do i PUDO")
    }

    @Test func isIdempotent() throws {
        var d = UserDictionary()
        try d.upsert(DictionaryTerm("Zowie", aliases: [DictionaryAlias("Zoim")]))
        try d.upsert(DictionaryTerm("PUDO", aliases: [DictionaryAlias("Pudo"), DictionaryAlias("pu do")]))
        try d.upsert(DictionaryTerm("InPost", aliases: [DictionaryAlias("in"), DictionaryAlias("in post")]))
        try d.upsert(DictionaryTerm("A", aliases: [DictionaryAlias("b")]))
        try d.upsert(DictionaryTerm("CPP", aliases: [DictionaryAlias("c++ (x)")]))
        try d.upsert(DictionaryTerm("Jarl", aliases: [DictionaryAlias("Jarla")]))
        try d.upsert(DictionaryTerm("Genesys", aliases: [DictionaryAlias("Dżenesis")]))
        let r = ReplacementRules(d)
        let texts = ["Zoim mówi", "zOiM", "w Pudo obok", "pu dowolny", "pu do.", "Jarlań", "in post i in", "b", "c++ (x) i cccc",
                     "Mówię o Dżenesis".decomposedStringWithCanonicalMapping, "x\u{0301}yz", ""]
        for x in texts {
            let once = r.apply(to: x)
            #expect(scalars(r.apply(to: once)) == scalars(once), "\(x)")
        }
        #expect(r.apply(to: "Zoim i Pudo w in post, b") == "Zowie i PUDO w InPost, A")
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
        let r = rules(DictionaryTerm("Genesys", aliases: [DictionaryAlias("Dżenesis")]))
        let nfd = "Mówię o Dżenesis".decomposedStringWithCanonicalMapping
        #expect(scalars(nfd) != scalars("Mówię o Dżenesis".precomposedStringWithCanonicalMapping))
        #expect(scalars(r.apply(to: nfd)) == scalars("Mówię o Genesys".precomposedStringWithCanonicalMapping))
        // Alias w NFD (np. ręcznie wpisany do dictionary.json z pominięciem upsert) też trafia w tekst NFC.
        let nfdAlias = rules(DictionaryTerm("Genesys", aliases: [DictionaryAlias("Dżenesis".decomposedStringWithCanonicalMapping)]))
        #expect(nfdAlias.apply(to: "o Dżenesis".precomposedStringWithCanonicalMapping) == "o Genesys")
    }

    @Test func combiningMarkContinuesTheWord() {
        let r = rules(DictionaryTerm("Y", aliases: [DictionaryAlias("x")]))
        #expect(scalars(r.apply(to: "x\u{0301}yz")) == scalars("x\u{0301}yz"))
        #expect(r.apply(to: "x yz") == "Y yz")
    }

    @Test func emptyRulesReturnSameTranscript() {
        let nfd = "Mówię o Dżenesis".decomposedStringWithCanonicalMapping
        let t = transcript([utt(nfd, .me, at: 3, flagged: true), utt("Zoim", .them, at: 7, echo: true)])
        for r in [ReplacementRules(UserDictionary()),
                  rules(DictionaryTerm("Zowie", aliases: [DictionaryAlias("Zoim", risky: true, enabled: false)]))] {
            #expect(r.isEmpty)
            let out = Replacement.apply(t, rules: r)
            #expect(out == t)
            #expect(scalars(out.utterances[0].text) == scalars(nfd))
            #expect(out.utterances[1].text == "Zoim")
        }
    }

    @Test func transcriptReplacementKeepsWordsAndTimes() {
        var u = utt("Zoim mówi", .them, at: 5, flagged: true, echo: true)
        u.words = [Word(text: "Zoim", start: 5, end: 5.4), Word(text: "mówi", start: 5.5, end: 6)]
        u.approximateTiming = true
        let t = Transcript(utterances: [u, utt("bez zmian", .me, at: 9)],
                           failedChunks: [ChunkFailure(track: "system", index: 2, start: 60, end: 90, error: "x")])
        let out = Replacement.apply(t, rules: rules(DictionaryTerm("Zowie", aliases: [DictionaryAlias("Zoim")])))
        #expect(out.utterances.map(\.text) == ["Zowie mówi", "bez zmian"])
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
