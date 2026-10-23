import Foundation
import Testing
import MeetNotesProviders
@testable import MeetNotesNotes
@testable import MeetNotesTranscription

private func build(_ t: Transcript, myNotes: String = "", context: String = "", language: LanguageCode? = .polish) -> NotePrompt? {
    NotePromptBuilder.build(template: .standard, transcript: t, myNotes: myNotes, context: context, notesLanguage: language)
}

@Test func promptTellsTheModelToAdmitAFragmentedTranscript() throws {
    let p = try #require(build(transcript([utt("Okay, so the forecast.")])))
    #expect(p.system.contains("inconsistent, fragmentary or garbled")) // jak odmowa Granoli: powiedz to, nie zmyślaj
    #expect(p.system.contains("Never invent"))
}

@Test func promptExcludesFlaggedUtterances() throws {
    // Review Focus #4: wypowiedź z flagą języka nie trafia do modelu.
    let t = transcript([utt("Prognoza na sobotę jest wyższa.", at: 1), utt("GIBBERISH-FROM-A-WRONG-LANGUAGE", at: 5, flagged: true)])
    let p = try #require(build(t))
    #expect(p.user.contains("Prognoza na sobotę"))
    #expect(!p.user.contains("GIBBERISH"))
}

@Test func promptCarriesMyNotesAndContext() throws {
    let p = try #require(build(transcript([utt("Dzień dobry.")]), myNotes: "ask about Sunday staffing", context: "Piotr and Adrian, forecast review"))
    #expect(p.user.contains("ask about Sunday staffing"))
    #expect(p.user.contains("Piotr and Adrian, forecast review"))
    #expect(p.system.contains("own notes are priority"))
}

@Test func contextEqualToMyNotesIsNotRepeated() throws {
    // Pole kontekstu jest wstępnie wypełnione My notes — ten sam tekst nie może iść do modelu dwa razy (przegląd T13).
    let notes = "ask about Sunday staffing"
    let t = transcript([utt("Dzień dobry.")])
    for context in [notes, "  \(notes)\n"] {
        let p = try #require(build(t, myNotes: notes, context: context))
        #expect(p.user.components(separatedBy: notes).count == 2)
        #expect(p.user.contains("Context from the user:\n(none)"))
    }
    // Inny kontekst zostaje, nawet gdy zawiera My notes.
    let p = try #require(build(t, myNotes: notes, context: notes + " and the budget"))
    #expect(p.user.components(separatedBy: notes).count == 3)
}

@Test func notesLanguageFollowsThePreset() throws {
    let p = try #require(build(transcript([utt("Dzień dobry.")]), language: .polish))
    #expect(p.system.contains("Write the notes in Polish."))
}

@Test func autoNotesLanguageUsesThePredominantOne() throws {
    let p = try #require(build(transcript([utt("Dzień dobry.")]), language: nil))
    #expect(p.system.contains("language that predominates in the transcript"))
}

@Test func emptyTranscriptProducesNoPrompt() {
    // Review Focus #1: nic do streszczenia → żadnego wywołania modelu.
    #expect(build(transcript([])) == nil)
    #expect(build(transcript([utt("   ")])) == nil)
    #expect(build(transcript([utt("tylko zaflagowane", flagged: true)])) == nil)
}

@Test func promptExcludesEchoOfTheOtherSide() throws {
    // Odbiór T13: echo z głośników („Me" powtarzające „Them") nie może trafić do modelu jako słowa użytkownika.
    let t = transcript([utt("Prognoza na sobotę jest wyższa niż na niedzielę.", .them, at: 1),
                        utt("Prognoza na sobotę jest wyższa niż na niedzielę.", .me, at: 1, echo: true)])
    let p = try #require(build(t))
    #expect(p.user.components(separatedBy: "Prognoza na sobotę").count == 2) // raz, nie dwa razy
    #expect(!p.user.contains("Me:"))
}

@Test func condensedPromptAddsTheOneSentence() throws {
    let sentence = "The transcript below is a condensed version of the full recording."
    let t = transcript([utt("Dzień dobry.")])
    let plain = try #require(build(t))
    let condensed = try #require(NotePromptBuilder.build(template: .standard, transcript: t, myNotes: "", context: "",
                                                         notesLanguage: .polish, condensed: true))
    #expect(!plain.system.contains(sentence))
    #expect(condensed.system.contains(sentence))
    #expect(condensed.system.contains("Never invent")) // reszta promptu ta sama
    #expect(condensed.user == plain.user)
}

@Test func mapPromptDemandsTheSameLineFormat() {
    let p = NotePromptBuilder.mapPrompt(part: ["[0:05] Me: Cześć.", "[0:09] Them: Dzień dobry."], index: 2, count: 5, notesLanguage: .polish)
    #expect(p.system.contains("part 2 of 5"))
    #expect(p.system.contains("[m:ss] Me") && p.system.contains("Them"))
    #expect(p.system.contains("same format"))
    #expect(p.system.contains("names, numbers, dates, decisions and tasks"))
    #expect(p.system.contains("Do not interpret"))
    #expect(p.user == "[0:05] Me: Cześć.\n[0:09] Them: Dzień dobry.")
}

@Test func mapPromptAsksForAtMost40Percent() {
    let p = NotePromptBuilder.mapPrompt(part: ["[0:05] Me: x"], index: 1, count: 2, notesLanguage: nil)
    #expect(p.system.contains("Keep the result to at most 40% of the input length."))
}

@Test func mapPromptHasNoUserNotesNorContext() {
    let p = NotePromptBuilder.mapPrompt(part: ["[0:05] Me: x"], index: 1, count: 2, notesLanguage: .polish)
    #expect(!p.system.contains("Context from the user") && !p.user.contains("Context from the user"))
    #expect(!p.system.contains("own notes") && !p.user.contains("own notes"))
    #expect(!p.system.contains("Structure:")) // szablon notatki tylko w reduce
}

// MARK: Słownik w poleceniach podsumowania (F21 T6)

private func isMapCall(_ c: ChatStub.Call) -> Bool { c.system.contains("You condense part") }

/// Mapa „po ludzku": każda linia wejścia → ta sama etykieta `[m:ss] Me|Them:` i krótka treść.
private func condensed(_ user: String) -> String {
    user.components(separatedBy: "\n").map { line in
        guard let r = line.range(of: ": ") else { return line }
        return String(line[..<r.upperBound]) + "short"
    }.joined(separator: "\n")
}

private func occurrences(of needle: String, in s: String) -> Int { s.components(separatedBy: needle).count - 1 }

extension VocabularyInPromptTests {
    @Test func summaryPromptIncludesVocabularyLines() throws {
        let t = transcript([utt("Cześć.")])
        let p = try #require(NotePromptBuilder.build(template: .standard, transcript: t, myNotes: "", context: "", notesLanguage: .polish,
                                                     vocabulary: Self.vocabulary))
        #expect(p.system.contains(Self.vocabulary.promptLines!))
        #expect(!p.user.contains("Known names and terms"))
        // Po regułach i zdaniu o języku, przed szablonem.
        #expect(p.system.range(of: "Write the notes in Polish.")!.upperBound < p.system.range(of: "Known names and terms")!.lowerBound)
        #expect(p.system.range(of: "Meeting attendees")!.upperBound < p.system.range(of: "Structure:")!.lowerBound)
    }

    @Test func summaryPromptUnchangedWithoutVocabulary() throws {
        let t = transcript([utt("Cześć.")])
        let plain = build(t, myNotes: "n", context: "c")
        #expect(NotePromptBuilder.build(template: .standard, transcript: t, myNotes: "n", context: "c", notesLanguage: .polish, vocabulary: nil) == plain)
        #expect(NotePromptBuilder.build(template: .standard, transcript: t, myNotes: "n", context: "c", notesLanguage: .polish,
                                        vocabulary: PromptVocabulary()) == plain)
        let map = NotePromptBuilder.mapPrompt(part: ["[0:05] Me: x"], index: 1, count: 2, notesLanguage: nil)
        #expect(NotePromptBuilder.mapPrompt(part: ["[0:05] Me: x"], index: 1, count: 2, notesLanguage: nil, vocabulary: nil) == map)
    }

    @Test func mapPartsBudgetIncludesVocabularyLines() async throws {
        let budget = ContextBudget(tokens: 4_096)
        let v = DictionaryPrompt.make(Self.dictionary(150), link: nil, maxChars: DictionaryPrompt.maxChars(budget: budget))
        let words = String(repeating: "word ", count: 500)
        let t = transcript((0..<6).map { utt(String(words.prefix(2_500)), $0 % 2 == 0 ? .them : .me, at: Double($0) * 10) })
        func run(_ vocabulary: PromptVocabulary?) async throws -> [ChatStub.Call] {
            let session = tempDir()
            defer { try? FileManager.default.removeItem(at: session) }
            let stub = ChatStub { c in isMapCall(c) ? condensed(c.user) : "# T\nbody" }
            let gen = NoteGenerator(client: localChatClient(stub), model: "local-model")
            _ = try await gen.generate(session: session, template: .standard, transcript: t, context: "", notesLanguage: .polish,
                                       budget: budget, vocabulary: vocabulary, now: Date(timeIntervalSince1970: 5_000))
            return stub.calls
        }
        let plain = try await run(nil), with = try await run(v)
        let plainMaps = plain.filter(isMapCall), withMaps = with.filter(isMapCall)
        // Części są krótsze o koszt linii (system mapy jest dłuższy o `promptLines`, a `pairedInputChars` liczy z rzeczywistej długości).
        let cost = NotePromptBuilder.mapSystemChars(vocabulary: v) - NotePromptBuilder.mapSystemChars(vocabulary: nil)
        #expect(cost >= v.promptLines!.count)
        #expect(withMaps.map { $0.user.count }.max()! < plainMaps.map { $0.user.count }.max()!)
        #expect(withMaps.count > plainMaps.count)
        // Linie są w `system` każdego wywołania (mapa i reduce) dokładnie raz, nigdy w `user`; bez słownika ich nie ma.
        let lines = v.promptLines!
        #expect(with.allSatisfy { occurrences(of: lines, in: $0.system) == 1 && !$0.user.contains("Known names and terms") })
        #expect(with.count == withMaps.count + 1) // ostatnie wywołanie to reduce
        #expect(plain.allSatisfy { !$0.system.contains("Known names and terms") })
    }
}
