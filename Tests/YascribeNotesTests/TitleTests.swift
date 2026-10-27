import Foundation
import Testing
@testable import YascribeNotes

@Test func titleHandlesCRLF() {
    let result = NoteTitle.parse("# Title\r\nBody\r\n")
    #expect(result.title == "Title" && result.body == "Body")
    #expect(NoteTitle.parse("# \r\nBody").title == nil)
    #expect(NoteTitle.stripLabel("Notes: \r\nplan\r") == "Plan")
    #expect(NoteTitle.clean("\rTitle\r") == "Title")
}

@Test func titleRemovesOnlyMatchingDecorationPairs() {
    #expect(NoteTitle.parse("# Review of \"Plan B\"\nbody").title == "Review of \"Plan B\"")
    #expect(NoteTitle.parse("# **\"Tytuł\"**\nbody").title == "Tytuł")
    #expect(NoteTitle.parse("# \"Podsumowanie spotkania: Plan zmian\"\nbody").title == "Plan zmian")
    for (input, expected) in [("„Plan”", "Plan"), ("«Plan»", "Plan"), ("“Plan”", "Plan"),
                              ("‘Plan’", "Plan"), ("'Plan'", "Plan"), ("*Plan*", "Plan"), ("**Plan**", "Plan"),
                              ("\"Plan", "\"Plan"), ("Plan”", "Plan”")] {
        #expect(NoteTitle.clean(input) == expected)
    }
}

@Test func titleStripsUnpairedAsterisksAndListMarkers() {
    #expect(NoteTitle.clean("* Forecast gap") == "Forecast gap")
    #expect(NoteTitle.clean("- Forecast gap") == "Forecast gap")
    #expect(NoteTitle.clean("• Forecast gap") == "Forecast gap")
    #expect(NoteTitle.clean("**Forecast gap") == "Forecast gap")
    #expect(NoteTitle.clean("*Plan*") == "Plan")
    #expect(NoteTitle.parse("# *Plan\nbody").title == "Plan")
    #expect(NoteTitle.parse("# - Plan zmian\nbody").title == "Plan zmian")
    // Ozdobniki w środku i niedopasowane cudzysłowy zostają nietknięte.
    #expect(NoteTitle.clean("Review of \"Plan B\"") == "Review of \"Plan B\"")
    #expect(NoteTitle.clean("Plan”") == "Plan”")
    #expect(NoteTitle.parse("# Plan „B” zmian\nbody").title == "Plan „B” zmian")
}

@Test func titleNormalizesCRLFInBody() {
    #expect(NoteTitle.parse("# T\r\nA\r\nB\r\n").body == "A\nB")
    #expect(NoteTitle.parse("# T\rA\rB").body == "A\nB")
}

@Test func displaySkipsNewlineOnlyTitles() {
    #expect(NoteTitle.display(meta: NoteMeta(manualTitle: "\r"), noteTitle: nil) == NoteTitle.untitled)
}

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

@Test func savedAutoTitleIsTheMeetingTitle() throws {
    // Odbiór 2026-10-16, błąd 4: meta.json z samym autoTitle (bez ręcznego) i summary.json z tytułem notatki.
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    try store.updateMeta { $0.autoTitle = "Nowe normy Euro 7" }
    try store.writeSummary(NoteSummary(title: "Euro 7 i OBM", markdown: "x", templateID: "standard", model: "m",
                                       context: "", generatedAt: Date(timeIntervalSince1970: 1_000)))
    let meta = store.readMeta()
    let noteTitle = try store.readSummary()?.title
    #expect(meta.manualTitle == nil)
    #expect(NoteTitle.display(meta: meta, noteTitle: noteTitle) == "Nowe normy Euro 7")
    #expect(NoteTitle.fieldText(meta: meta, noteTitle: noteTitle) == "Nowe normy Euro 7") // pole: tekst, nie placeholder
    #expect(NoteTitle.fieldText(meta: NoteMeta(), noteTitle: nil) == "") // „Untitled meeting" zostaje placeholderem
}

@Test func unchangedTitleFieldIsNotSavedAsManual() {
    let meta = NoteMeta(autoTitle: "Forecast gap")
    #expect(!NoteTitle.isEdit("Forecast gap", meta: meta, noteTitle: nil)) // Enter bez zmiany
    #expect(!NoteTitle.isEdit("  Forecast gap ", meta: meta, noteTitle: nil))
    #expect(!NoteTitle.isEdit("", meta: NoteMeta(), noteTitle: nil)) // puste pole przy „Untitled meeting"
    #expect(NoteTitle.isEdit("Forecast gap with Piotr", meta: meta, noteTitle: nil))
    #expect(NoteTitle.isEdit("", meta: meta, noteTitle: nil)) // wyczyszczenie to zmiana (wraca autotytuł)
}

@Test func typingASpaceAfterTheAutoTitleKeepsIt() {
    // Dopisywanie słów do autotytułu: „Forecast gap " nie może wrócić do „Forecast gap" w trakcie pisania.
    let meta = NoteMeta(autoTitle: "Forecast gap")
    #expect(NoteTitle.fieldEdit("Forecast gap ", meta: meta, noteTitle: nil) == "Forecast gap ")
    #expect(NoteTitle.fieldEdit("Forecast gap", meta: meta, noteTitle: nil) == nil) // tekst = tytuł → pole śledzi sesję
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
