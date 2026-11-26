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

    private func find(_ sources: [AliasSuggestions.Source] = [], _ terms: [DictionaryTerm]? = nil, dismissed: Set<String> = [],
                      common: Set<String> = [], edits: [AliasSuggestions.EditPair] = []) -> [AliasSuggestion] {
        AliasSuggestions.find(in: sources, dictionary: UserDictionary(terms: terms ?? [nimbu, kopt]), dismissed: dismissed,
                              fillerWords: ["yyy"], edits: edits, isCommonWord: { common.contains($0.lowercased()) })
    }

    private func edit(_ session: String, _ note: String, _ before: String, _ after: String) -> AliasSuggestions.EditPair {
        .init(sessionID: session, editKey: "\(session)#\(note)", before: before, after: after)
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
        // Fraza z końcówką: bez sugestii („ko pt*” przepisałoby „ko ptak”).
        #expect(find([source("a", [("z ko ptem", "z KOPTem"), ("ko pta", "KOPTa")])]).isEmpty)
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

    @Test func exactAliasThatWouldRewriteKeptWordsIsRisky() throws {
        let pairs = [("Nima tu", "Nimbu tu"), ("Nima tam", "Nimbu tam"), ("Nima przyszła", "Nima przyszła")]
        #expect(find([source("a", pairs)]).isEmpty)
        let s = try #require(find([source("a", pairs), source("b", [("Nima jest", "Nimbu jest")])]).first)
        #expect((s.alias, s.inflects, s.risky) == ("Nima", false, true))
    }

    @Test func wordsCorrectedToSomethingElseAlsoCountAsRisk() {
        // „szkoła” korektor poprawił gramatycznie (nie zostawił), ale `szko*` i tak by je przepisało.
        #expect(find([source("a", [("w szkoa", "w Nimbua"), ("w szkoa", "w Nimbua"), ("w szkoła", "w szkole")])]).isEmpty)
    }

    @Test func dismissalFromTheOldIDFormatStillHides() {
        // 0.1.23 zapisywała `*` także dla samych form podstawowych.
        let pair = ("szko tu", "Nimbu tu")
        #expect(find([source("a", [pair, pair])], dismissed: ["szko*→nimbu"]).isEmpty)
        #expect(find([source("a", [("w Rokmie", "w Nimbuie"), ("w Rokmie", "w Nimbuie")])], dismissed: ["rokm→nimbu"]).isEmpty)
    }

    @Test func singleHallucinationDoesNotCancelAStrongSuggestion() {
        // Inna poprawka tego samego słowa robi z sugestii ryzykowną (2 spotkania), ale jej nie kasuje.
        let s = find([source("a", [("Rokm tu", "Nimbu tu"), ("Rokm tam", "KOPT tam")]), source("b", [("Rokm tu", "Nimbu tu")])])
        #expect(s.map(\.term) == ["Nimbu"])
        #expect(s.first?.risky == true)
    }

    @Test func termWrittenWithDifferentCaseAfterTheFirstLetter() throws {
        let s = try #require(find([source("a", [("z kopem", "z Koptem"), ("z kopem", "z Koptem")])]).first)
        #expect((s.alias, s.inflects, s.term) == ("kop", true, "KOPT"))
    }

    @Test func fillerWidenedIntoAMultiWordTermIsIgnored() {
        let pair = ("yyy Max tu", "Nimbu Max tu")
        #expect(find([source("a", [pair, pair])], [DictionaryTerm("Nimbu Max")]).isEmpty)
    }

    @Test func acceptAddsTheAliasWithItsFlags() throws {
        let pair = ("ten rok jest", "ten Nimbu jest")
        let s = try #require(find([source("a", [pair]), source("b", [pair])], common: ["rok"]).first)
        let d = try AliasSuggestions.accept(s, in: UserDictionary(terms: [nimbu, kopt]))
        let alias = try #require(d.terms.first { $0.id == nimbu.id }?.aliases.first)
        #expect((alias.text, alias.inflecting, alias.risky, alias.enabled) == ("rok", false, true, true))
        #expect(find([source("a", [pair]), source("b", [pair])], d.terms, common: ["rok"]).isEmpty)
    }

    // MARK: - TASK-116: nauka z poprawek użytkownika

    @Test func singleEditToAnExistingTermSuggestsTheAlias() throws {
        let s = try #require(find(edits: [edit("a", "0", "byłem w Rokmie", "byłem w Nimbuie")]).first)
        // Jedna poprawka wystarcza (D3); reszta zachowuje się jak w TASK-112.
        #expect((s.alias, s.inflects, s.term, s.count, s.sessions) == ("Rokm", true, "Nimbu", 1, ["a"]))
        #expect((s.fromEdits, s.isNewTerm) == (true, false))
        #expect(s.termID == nimbu.id)
    }

    @Test func editTeachesANewTerm() throws {
        let s = try #require(find(edits: [edit("a", "0", "pracuję w Rokm", "pracuję w Nimbu Corp")]).first)
        #expect((s.alias, s.term, s.inflects, s.count) == ("Rokm", "Nimbu Corp", false, 1))
        #expect((s.fromEdits, s.isNewTerm) == (true, true))
        let d = try AliasSuggestions.accept(s, in: UserDictionary(terms: [nimbu, kopt]))
        let term = try #require(d.terms.first { $0.id == s.termID })
        #expect(term.text == "Nimbu Corp")
        #expect((term.aliases.first?.text, term.aliases.first?.inflecting) == ("Rokm", false))
    }

    @Test func editCoveredByAnExistingAliasIsNotSuggested() {
        // `before` jest już po Replacement; drugie `apply` jest idempotentne i chowa parę pokrytą Aliasem.
        let term = DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Rokm", inflects: true)])
        #expect(find([], [term], edits: [edit("a", "0", "w Rokmie", "w Nimbuie")]).isEmpty)
    }

    @Test func editsOfNumbersAreIgnored() {
        #expect(find(edits: [edit("a", "0", "mamy 5 sztuk", "mamy 6 sztuk")]).isEmpty)
        #expect(find(edits: [edit("a", "0", "mamy dwa koty", "mamy trzy koty")]).isEmpty)
        #expect(find(edits: [edit("a", "0", "mamy twenty sztuk", "mamy thirty sztuk")]).isEmpty)
    }

    @Test func numeralAndNegationInflectionsAreFiltered() {
        let cases = [
            ("mamy pięciu ludzi", "mamy sześciu ludzi"),
            ("mamy dwoma ludźmi", "mamy trzema ludźmi"),
            ("mamy żadnego Rokma", "mamy Nimbu"),
            ("to isn't Rokm", "to is Nimbu"),
            ("mamy twenty-one sztuk", "mamy thirty-two sztuk"),
        ]
        for (before, after) in cases {
            #expect(find(edits: [edit("a", "0", before, after)]).isEmpty, "\(before) → \(after)")
        }
    }

    @Test func editsOfNegationsAreIgnored() {
        #expect(find(edits: [edit("a", "0", "to nie Rokm", "to jest Nimbu")]).isEmpty)
    }

    @Test func rewrittenSentenceIsNotALesson() {
        let e = edit("a", "0", "alfa beta gamma delta epsilon", "Nimbu KOPT Rokm zeta theta")
        #expect(find(edits: [e]).isEmpty)
    }

    @Test func deletionAndInsertionAreIgnored() {
        #expect(find(edits: [edit("a", "0", "Rokm tu jest", "Rokm tu")]).isEmpty)
        #expect(find(edits: [edit("a", "0", "Rokm tu", "Rokm tu jest")]).isEmpty)
    }

    @Test func caseOnlyEditIsIgnored() {
        #expect(find(edits: [edit("a", "0", "nimbu tu", "Nimbu tu")]).isEmpty)
    }

    @Test func theSameEditInOriginalAndCorrectedCountsOnce() throws {
        let e = edit("a", "0", "w Rokmie", "w Nimbuie")
        let s = try #require(find(edits: [e, e]).first)
        #expect((s.count, s.sessions) == (1, ["a"]))
    }

    @Test func newTermDoesNotOverwriteARawAlias() {
        let other = DictionaryTerm("Orbit", aliases: [DictionaryAlias("Rokm", enabled: false)])
        #expect(find([], [nimbu, other], edits: [edit("a", "0", "Rokm tu", "Nimbu Corp tu")]).isEmpty)
    }

    @Test func newTermTargetMustNotAlreadyBeAnAlias() {
        let term = DictionaryTerm("Nimbu", aliases: [DictionaryAlias("Orbit")])
        #expect(find([], [term], edits: [edit("a", "0", "Rokm tu", "Orbit tu")]).isEmpty)
    }

    @Test func dismissedEditSuggestionStaysHidden() throws {
        let e = edit("a", "0", "w Rokmie", "w Nimbuie")
        let s = try #require(find(edits: [e]).first)
        #expect(find([], nil, dismissed: [s.id], edits: [e]).isEmpty)
    }

    @Test func riskyEditStillNeedsTwoMeetings() throws {
        let a = edit("a", "0", "ten rok jest", "ten Nimbu jest")
        #expect(find([], nil, common: ["rok"], edits: [a]).isEmpty)
        let s = try #require(find([], nil, common: ["rok"], edits: [a, edit("b", "0", "ten rok jest", "ten Nimbu jest")]).first)
        #expect((s.alias, s.inflects, s.risky, s.sessions) == ("rok", false, true, ["a", "b"]))
    }

    @Test func editAliasThatWouldRewriteKeptWordsIsRisky() throws {
        // Ta sama linia zawiera nietknięte „Rokmowski”: Alias „Rokm*” przepisałby je, więc jedna poprawka nie wystarcza.
        let a = edit("a", "0", "w Rokmie i Rokmowski", "w Nimbuie i Rokmowski")
        #expect(find(edits: [a]).isEmpty)
        let b = edit("b", "0", "w Rokmie i Rokmowski", "w Nimbuie i Rokmowski")
        let s = try #require(find(edits: [a, b]).first)
        #expect((s.alias, s.inflects, s.risky, s.sessions) == ("Rokm", true, true, ["a", "b"]))
    }

    @Test func repeatedWordInEditedLineMakesTheAliasRisky() throws {
        // W linii zostaje nietknięte drugie „Rokm": Alias „Rokm" przepisałby je, więc jedna poprawka nie wystarcza.
        let a = edit("a", "0", "Rokm tu Rokm", "Rokm tu Nimbu")
        #expect(find(edits: [a]).isEmpty)
        let b = edit("b", "0", "Rokm tu Rokm", "Rokm tu Nimbu")
        let s = try #require(find(edits: [a, b]).first)
        #expect((s.alias, s.term, s.risky, s.sessions) == ("Rokm", "Nimbu", true, ["a", "b"]))
    }

    @Test func repeatedWordInEditedLineMakesANewTermRisky() throws {
        // Ta sama sytuacja na ścieżce nowego Terma („Nimbu" nie ma jeszcze w słowniku).
        let a = edit("a", "0", "Rokm tu Rokm", "Rokm tu Nimbu")
        #expect(find([], [kopt], edits: [a]).isEmpty)
        let b = edit("b", "0", "Rokm tu Rokm", "Rokm tu Nimbu")
        let s = try #require(find([], [kopt], edits: [a, b]).first)
        #expect((s.alias, s.term, s.risky, s.sessions) == ("Rokm", "Nimbu", true, ["a", "b"]))
    }

    @Test func editThatLooksLikeInsertionIsNotALesson() {
        // „Rokm Rokm" → „Nimbu Rokm" to dla LCS wstawienie i usunięcie, nie podmiana: nie tworzymy z tego Aliasu.
        let e = edit("a", "0", "Rokm Rokm", "Nimbu Rokm")
        #expect(find(edits: [e]).isEmpty)
        #expect(find([], [kopt], edits: [e]).isEmpty)
    }

    @Test func editInASessionAlreadyInSourcesIsNotCountedTwice() throws {
        // Surowy tekst sesji „a" jest już policzony w `sources`; `before` z edycji nie może zawyżyć `matched`.
        let pair = ("w Rokmie", "w Nimbuie")
        let s = try #require(find([source("a", [pair])], edits: [edit("a", "0", "w Rokmie", "w Nimbuie")]).first)
        #expect((s.alias, s.inflects, s.risky, s.count, s.sessions) == ("Rokm", true, false, 2, ["a"]))
    }

    @Test func numeralInflectionsInEditsAreFiltered() {
        #expect(find(edits: [edit("a", "0", "z tysiącem sztuk", "z milionem sztuk")]).isEmpty)
        #expect(find(edits: [edit("a", "0", "mamy jedną sztukę", "mamy pojedynczą sztukę")]).isEmpty)
    }

    @Test func ordinaryWordStartingWithStoIsNotANumeral() throws {
        // „sto"/„stu" tylko w całości: prefiks „sto-" blokowałby zwykłe „stoi".
        let s = try #require(find(edits: [edit("a", "0", "stoi Rokm", "stoi Nimbu")]).first)
        #expect((s.alias, s.term) == ("Rokm", "Nimbu"))
    }

    @Test func hundredsInflectionsInEditsAreFiltered() {
        #expect(find(edits: [edit("a", "0", "do dwustu sztuk", "do trzystu sztuk")]).isEmpty)
    }
}
