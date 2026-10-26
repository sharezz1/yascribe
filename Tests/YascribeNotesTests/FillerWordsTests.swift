import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes
@testable import YascribeTranscription

private let list = FillerWords.defaults

@Test func fillerRemovalKeepsPunctuationAndSentenceShape() {
    #expect(FillerWords.remove("No to jest, yyy, test.", words: list) == "No to jest, test.")
    #expect(FillerWords.remove("Wiem yyy.", words: list) == "Wiem.")          // koniec zdania przechodzi na poprzednie słowo
    #expect(FillerWords.remove("Wiem, yyy.", words: list) == "Wiem.")         // bez „Wiem,."
    #expect(FillerWords.remove("Yyy, to jest test.", words: list) == "To jest test.") // wielka litera po usuniętym początku zdania
    #expect(FillerWords.remove("Jest. Mhm, nie wiem.", words: list) == "Jest. Nie wiem.")
    #expect(FillerWords.remove("To jest eee dobre pytanie", words: list) == "To jest dobre pytanie")
    // Zdanie z prawdziwej odpowiedzi modelu (próba P1, wariant B): „yy" zostało po korekcie.
    #expect(FillerWords.remove("Mleko kokosowe w Ciapcie kupisz teraz, yy, u Płaza kupisz mleko kokosowe, wszędzie jest",
                               words: list) == "Mleko kokosowe w Ciapcie kupisz teraz, u Płaza kupisz mleko kokosowe, wszędzie jest")
}

@Test func stretchedFillersMatchButShortWordsAreNotHit() {
    #expect(FillerWords.remove("No yyyyy dobrze", words: ["yyy"]) == "No dobrze")
    #expect(FillerWords.remove("Eeee tak", words: ["eee"]) == "Tak")
    // Pojedyncze „m" (metry) to nie przerywnik „mm"; „no" i „tak" nie są na liście domyślnej.
    #expect(FillerWords.remove("Mam 5 m i no tak", words: ["mm"]) == "Mam 5 m i no tak")
    #expect(!list.contains("no") && !list.contains("tak") && !list.contains("wiesz"))
}

@Test func fillerRemovalLeavesNonFillersAndEmptyResultsAlone() {
    let s = "To jest   zwykłe zdanie."
    #expect(FillerWords.remove(s, words: list) == s) // bez zmian = dokładnie ten sam napis (nawet z podwójną spacją)
    #expect(FillerWords.remove("Mhm.", words: list) == "Mhm.")        // same przerywniki: nie tworzymy pustej wypowiedzi
    #expect(FillerWords.remove("Yyy eee", words: list) == "Yyy eee")
    #expect(FillerWords.remove("coś yyy", words: []) == "coś yyy")    // pusta lista = wyłączone
}

@Test func fillerListParsesAndFormats() {
    #expect(FillerWords.parse(" Yyy, eee ;MHM\nyyy,, ") == ["yyy", "eee", "mhm"]) // małe litery, bez pustych i powtórzeń
    #expect(FillerWords.format(["yyy", "eee"]) == "yyy, eee")
    #expect(FillerWords.parse(FillerWords.format(FillerWords.defaults)) == FillerWords.defaults)
}

@Test func globalSettingsFillersAreOptionalAndDefaultToOn() throws {
    // E6: stary settings.json bez pól nadal się czyta; brak = włączone z listą domyślną (nil).
    let old = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
    #expect(old.removeFillers == nil && old.fillerWords == nil && old.removeFillersEnabled)
    var s = GlobalSettings()
    s.removeFillers = false
    s.fillerWords = ["yyy"]
    let back = try JSONDecoder().decode(GlobalSettings.self, from: JSONEncoder().encode(s))
    #expect(!back.removeFillersEnabled && back.fillerWords == ["yyy"])
}

// MARK: korektor (A: polecenie dla modelu, B: filtr po korekcie)

private let assignment = RoleAssignment(providerID: testProvider.id, model: "fix-model")

@Test func correctorAsksTheModelToDropFillersAndFiltersWhatRemains() async {
    let t = transcript([utt("no to jest yyy test"), utt("mhm dobrze")])
    // „Model" ignoruje polecenie i oddaje przerywniki: filtr po korekcji je usuwa.
    let stub = ChatStub { $0.user }
    let c = Corrector(client: chatClient(stub), assignment: assignment, fillerWords: ["yyy", "mhm"])
    let r = await c.correct(t, language: .polish)
    #expect(r.transcript.utterances.map(\.text) == ["no to jest test", "dobrze"])
    #expect(stub.calls[0].system.contains("remove filler sounds") && stub.calls[0].system.contains("yyy, mhm"))
    #expect(r.failedBatches == 0)
}

@Test func correctorWithoutFillerWordsChangesNothingAndKeepsThePromptAsBefore() async {
    let t = transcript([utt("no to jest yyy test")])
    let stub = ChatStub { $0.user }
    let c = Corrector(client: chatClient(stub), assignment: assignment)
    let r = await c.correct(t, language: .polish)
    #expect(r.transcript.utterances.map(\.text) == ["no to jest yyy test"])
    #expect(!stub.calls[0].system.contains("filler"))
}

@Test func fillerFilterAlsoCleansLinesWhoseBatchFailedButNotATotalFailure() async {
    // Dwie partie, pierwsza pada: filtr czyści też jej linie (deterministyczny, niezależny od modelu).
    let a = String(repeating: "słowo ", count: 6) + "yyy"
    let t = transcript([utt(a, at: 0), utt(a, at: 5)])
    let calls = LockedCounter() // pierwsza partia dostaje odpowiedź ze złym numerem, druga poprawną
    let flaky = ChatStub { call in calls.next() == 1 ? "[9] zly numer" : call.user }
    let c = Corrector(client: chatClient(flaky), assignment: assignment, maxBatchChars: 40, fillerWords: ["yyy"])
    let r = await c.correct(t, language: .polish)
    #expect(r.batches == 2 && r.failedBatches == 1)
    #expect(r.transcript.utterances.allSatisfy { !$0.text.contains("yyy") })
}

@Test func fullyFailedCorrectionLeavesFillersAlone() async {
    let t = transcript([utt("no yyy test")])
    let c = Corrector(client: chatClient(ChatStub { _ in "[9] zly numer" }), assignment: assignment, fillerWords: ["yyy"])
    let r = await c.correct(t, language: .polish)
    #expect(r.failedCompletely && r.transcript.utterances.map(\.text) == ["no yyy test"])
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}
