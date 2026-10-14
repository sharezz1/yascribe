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
