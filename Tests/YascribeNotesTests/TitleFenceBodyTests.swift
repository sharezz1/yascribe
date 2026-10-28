import Testing
import Foundation
@testable import YascribeNotes

/// Regresja z rundy F: zamykające ``` z treści notatki było zdejmowane bez pary.
/// Blok kodu w treści notatki musi zachować oba ogrodzenia.
@Test func bodyKeepsCodeBlockFenceWithLanguage() {
    let r = NoteTitle.parse("# Plan\n\n```swift\nlet x = 1\n```\n\nGotowe.")
    #expect(r.title == "Plan")
    #expect(r.body == "```swift\nlet x = 1\n```\n\nGotowe.")
}

@Test func bodyKeepsPlainCodeBlockFence() {
    let r = NoteTitle.parse("# Plan\n\n```\nlet x = 1\n```")
    #expect(r.body == "```\nlet x = 1\n```")
}

/// Owinięta odpowiedź (preambuła + ogrodzenie wokół nagłówka) nadal traci samo ogrodzenie.
@Test func wrappedNoteStillStripsWrapperFence() {
    let r = NoteTitle.parse("Oto notatka:\n```markdown\n# Plan\nTreść\n```")
    #expect(r.title == "Plan")
    #expect(r.body == "Oto notatka:\nTreść")
}
