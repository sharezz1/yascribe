import Foundation
import Testing
@testable import MeetNotesNotes

@Test func titleIsTheFirstHeading() {
    let r = NoteTitle.parse("# Scheduling forecast\n\n## Topic\n- x")
    #expect(r.title == "Scheduling forecast")
    #expect(r.body.hasPrefix("## Topic"))
}

@Test func titleToleratesPreambleAndCodeFence() {
    let a = NoteTitle.parse("Sure, here is your note:\n\n# **Forecast gap**\nBody")
    #expect(a.title == "Forecast gap")
    #expect(a.body == "Body")
    let b = NoteTitle.parse("```markdown\n# Fenced\nBody line\n```")
    #expect(b.title == "Fenced")
    #expect(b.body == "Body line")
}

@Test func noHeadingMeansNoTitle() {
    let a = NoteTitle.parse("## Only a section\ntext")
    #expect(a.title == nil)
    #expect(a.body.hasPrefix("## Only"))
    #expect(NoteTitle.parse("one\ntwo\nthree\n# Too late").title == nil) // nagłówek po 3. niepustej linii to nie tytuł
}

@Test func displayTitlePrecedenceIsManualThenAutoThenNoteThenUntitled() {
    #expect(NoteTitle.display(meta: NoteMeta(manualTitle: "M", autoTitle: "A"), noteTitle: "N") == "M")
    #expect(NoteTitle.display(meta: NoteMeta(autoTitle: "A"), noteTitle: "N") == "A")
    #expect(NoteTitle.display(meta: NoteMeta(), noteTitle: "N") == "N")
    #expect(NoteTitle.display(meta: NoteMeta(manualTitle: "  "), noteTitle: nil) == "Untitled meeting")
}

@Test func titleRuleIsInBothPrompts() throws {
    // Odbiór T13: tytuł na 15 słów z przedrostkiem „Notatki z rozmowy". Reguła jest w prompcie notatki i autotytułu.
    let t = transcript([utt("Prognoza na sobotę jest wyższa niż na niedzielę.")])
    let notes = try #require(NotePromptBuilder.build(template: .standard, transcript: t, myNotes: "", context: "", notesLanguage: .polish))
    let auto = try #require(AutoTitle.prompt(transcript: t, notesLanguage: .polish))
    for system in [notes.system, auto.system] {
        #expect(system.contains("at most 8 words") && system.contains("Notatki z rozmowy") && system.contains("Meeting notes"))
    }
}

@Test func labelPrefixIsStrippedFromTitles() {
    #expect(NoteTitle.parse("# Notatki z rozmowy: presja na wygląd i sport\nbody").title == "Presja na wygląd i sport")
    #expect(AutoTitle.clean("Meeting notes - forecast gap with Piotr") == "Forecast gap with Piotr")
    #expect(AutoTitle.clean("\"Podsumowanie spotkania: Plan zmian\"") == "Plan zmian")
    // Bez separatora albo bez treści po etykiecie tytuł zostaje.
    #expect(NoteTitle.parse("# Notes on churn\nbody").title == "Notes on churn")
    #expect(NoteTitle.parse("# Summary:\nbody").title == "Summary:")
}
