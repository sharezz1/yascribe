import Foundation
import Testing
@testable import YascribeNotes
@testable import YascribeTranscription

/// TASK-112: sugestie Aliasów z różnicy surowy transkrypt → korekta LLM. Nazwy zmyślone (repo publiczne).
@Suite struct AliasSuggestionsTests {
    private let nimbu = DictionaryTerm("Nimbu")
    private let kopt = DictionaryTerm("KOPT")

    private func source(_ id: String, _ pairs: [(String, String)], failed: Bool = false) -> AliasSuggestions.Source {
        let raw = transcript(pairs.map { utt($0.0) })
        let fixed = CorrectedTranscript(transcript: transcript(pairs.map { utt($0.1) }), model: "m", batches: 1,
                                        failedBatches: failed ? 1 : 0, rejectedLines: 0)
        return AliasSuggestions.Source(id: id, raw: raw, corrected: fixed)
    }

    private func find(_ sources: [AliasSuggestions.Source], _ terms: [DictionaryTerm]? = nil, dismissed: Set<String> = [],
                      common: Set<String> = []) -> [AliasSuggestion] {
        AliasSuggestions.find(in: sources, dictionary: UserDictionary(terms: terms ?? [nimbu, kopt]), dismissed: dismissed,
                              fillerWords: ["yyy"], isCommonWord: { common.contains($0.lowercased()) })
    }

    @Test func inflectedFormsOfOneNameBecomeOneStemSuggestion() throws {
        let s = find([source("a", [("byłem w Rokmie wczoraj", "byłem w Nimbuie wczoraj"), ("Rokm działa.", "Nimbu działa.")])])
        let one = try #require(s.first)
        #expect(s.count == 1)
        #expect((one.alias, one.inflects, one.term, one.count, one.sessions) == ("Rokm", true, "Nimbu", 2, ["a"]))
        #expect(Set(one.forms) == ["Rokmie", "Rokm"])
        #expect(one.risky == false)
        #expect(one.termID == nimbu.id)
    }

    @Test func singleOccurrenceIsNotEnough() {
        #expect(find([source("a", [("w Rokmie", "w Nimbuie")])]).isEmpty)
    }

    @Test func riskyPairNeedsTwoMeetings() throws {
        let pair = ("ten rok jest", "ten Nimbu jest")
        #expect(find([source("a", [pair, pair])], common: ["rok"]).isEmpty)
        let s = try #require(find([source("a", [pair]), source("b", [pair])], common: ["rok"]).first)
        #expect((s.alias, s.inflects, s.risky, s.sessions) == ("rok", false, true, ["a", "b"]))
    }

    @Test func pairAlreadyCoveredByAnAliasIsNotSuggested() {
        let term = DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm", inflects: true)])
        let pair = ("w Rokmie", "w Nimbuie")
        #expect(find([source("a", [pair, pair])], [term]).isEmpty)
        // Korektor zgubił końcówkę: bez Replacement przed diffem wyszłoby zbędne „Rokmie*”, które `Rokm*` już pokrywa.
        let dropped = ("w Rokmie", "w Nimbu")
        #expect(find([source("a", [dropped, dropped])], [term]).isEmpty)
    }

    @Test func dismissedSuggestionStaysHidden() throws {
        let pair = ("w Rokmie", "w Nimbuie")
        let s = try #require(find([source("a", [pair, pair])]).first)
        #expect(find([source("a", [pair, pair])], dismissed: [s.id]).isEmpty)
    }

    @Test func suggestionThatWouldFailValidationIsDropped() {
        // „Rokm" jest już (wyłączonym) Aliasem innego Terma: upsert rzuciłby `aliasTaken`.
        let other = DictionaryTerm("Orbit", aliases: [DictionaryAlias("Rokm", enabled: false)])
        let pair = ("Rokm tu", "Nimbu tu")
        #expect(find([source("a", [pair, pair])], [nimbu, other]).isEmpty)
    }

    @Test func onlyTermsDigitsAndCaseAreIgnored() {
        let pairs = [("zrobic to", "zrobić to"), ("o 13 Rokm", "o 14 Nimbu"), ("nimbu tak", "Nimbu tak")]
        #expect(find([source("a", pairs + pairs)]).isEmpty)
    }

    @Test func multiWordPhraseAndPhraseWithEnding() throws {
        let s = try #require(find([source("a", [("to ko pt", "to KOPT"), ("ko pt.", "KOPT.")])]).first)
        #expect((s.alias, s.inflects, s.term) == ("ko pt", false, "KOPT"))
        let e = try #require(find([source("a", [("z ko ptem", "z KOPTem"), ("ko pta", "KOPTa")])]).first)
        #expect((e.alias, e.inflects, e.count) == ("ko pt", true, 2))
    }

    @Test func failedOrMisalignedCorrectionsAreSkipped() {
        let pair = ("w Rokmie", "w Nimbuie")
        #expect(find([source("a", [pair, pair], failed: true)]).isEmpty)
        var misaligned = source("a", [pair, pair])
        misaligned.corrected.transcript.utterances.removeLast()
        #expect(find([misaligned]).isEmpty)
    }

    @Test func disabledAliasOfTheSameTermBlocksTheSuggestion() {
        let term = DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm", risky: true, enabled: false)])
        let pair = ("Rokm tu", "Nimbu tu")
        #expect(find([source("a", [pair, pair])], [term]).isEmpty)
    }

    @Test func fillerOnlyBlockIsIgnored() {
        let pair = ("yyy tak", "Nimbu tak")
        #expect(find([source("a", [pair, pair])]).isEmpty)
    }

    @Test func acceptedAliasFixesTheRawText() throws {
        let pairs = [("byłem w Rokmie wczoraj", "byłem w Nimbuie wczoraj"), ("Rokm działa.", "Nimbu działa.")]
        let s = try #require(find([source("a", pairs)]).first)
        let rules = ReplacementRules(try AliasSuggestions.accept(s, in: UserDictionary(terms: [nimbu, kopt])))
        for (raw, fixed) in pairs { #expect(rules.apply(to: raw) == fixed) }
    }

    @Test func baseFormOnlyGivesAnExactAlias() throws {
        let s = try #require(find([source("a", [("szko tu", "Nimbu tu"), ("szko tam", "Nimbu tam")])]).first)
        #expect((s.alias, s.inflects) == ("szko", false))
    }

    @Test func stemThatWouldRewriteKeptWordsIsRisky() throws {
        let pairs = [("w Rokmie", "w Nimbuie"), ("w Rokmie", "w Nimbuie"), ("Rokmowski przyszedł", "Rokmowski przyszedł")]
        #expect(find([source("a", pairs)]).isEmpty)
        let s = try #require(find([source("a", pairs), source("b", [("Rokma tu", "Nimbua tu")])]).first)
        #expect((s.alias, s.inflects, s.risky) == ("Rokm", true, true))
    }

    @Test func punctuationInsideThePhraseIsIgnored() {
        let pair = ("to ko, pt tu", "to KOPT tu")
        #expect(find([source("a", [pair, pair])]).isEmpty)
    }

    @Test func stemCorrectedToDifferentTermsIsDropped() {
        #expect(find([source("a", [("Rokm tu", "Nimbu tu"), ("Rokm tu", "Nimbu tu"), ("Rokm tam", "KOPT tam"), ("Rokm tam", "KOPT tam")])]).isEmpty)
    }

    @Test func ordinaryWordStartingWithTheTermIsNotAnEnding() {
        let port = DictionaryTerm("Port")
        let lower = ("ten pordfel", "ten portfel"), upper = ("Pordfel tu", "Portfel tu")
        #expect(find([source("a", [lower, lower])], [port]).isEmpty)
        #expect(find([source("a", [upper, upper])], [port], common: ["portfel"]).isEmpty)
    }

    @Test func multiWordTermSharingAWordWithTheRawText() throws {
        let max = DictionaryTerm("Nimbu Max")
        let pair = ("mamy Rokm Max tu", "mamy Nimbu Max tu")
        let s = try #require(find([source("a", [pair, pair])], [max]).first)
        #expect((s.alias, s.inflects, s.term) == ("Rokm Max", false, "Nimbu Max"))
    }

    @Test func acceptAddsTheAliasWithItsFlags() throws {
        let pair = ("ten rok jest", "ten Nimbu jest")
        let s = try #require(find([source("a", [pair]), source("b", [pair])], common: ["rok"]).first)
        let d = try AliasSuggestions.accept(s, in: UserDictionary(terms: [nimbu, kopt]))
        let alias = try #require(d.terms.first { $0.id == nimbu.id }?.aliases.first)
        #expect((alias.text, alias.inflecting, alias.risky, alias.enabled) == ("rok", false, true, true))
        #expect(find([source("a", [pair]), source("b", [pair])], d.terms, common: ["rok"]).isEmpty)
    }
}
