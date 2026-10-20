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
    #expect(p.system.contains("inconsistent, fragmentary or garbled")) // jak odmowa inne narzędzie: powiedz to, nie zmyślaj
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
