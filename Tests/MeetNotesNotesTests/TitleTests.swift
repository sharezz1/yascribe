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
