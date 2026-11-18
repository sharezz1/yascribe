import Foundation
import Testing
@testable import YascribeNotes

@Test func knownPeopleMostRecentFirstNoDuplicates() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var people = KnownPeople.load(root: root)
    people.use(" \n")
    #expect(people.names.isEmpty)
    people.use(" Ala ")
    people.use("Ola")
    people.use("ala")
    #expect(people.names == ["ala", "Ola"])
    for i in 0..<205 { people.use("Person \(i)") }
    #expect(people.names.count == 200 && people.names.first == "Person 204")
    try people.save(root: root)
    #expect(KnownPeople.load(root: root).names == people.names)
}

@Test func noteLinesUseNames() {
    var named = utt("hello", .them, at: 5)
    named.speakerLabel = "Ala"
    let lines = NotePromptBuilder.transcriptLines(transcript([named, utt("mine", .me, at: 6), utt("other", .them, at: 7)]))
    #expect(lines == ["[0:05] Ala: hello", "[0:06] Me: mine", "[0:07] Them: other"])
}
