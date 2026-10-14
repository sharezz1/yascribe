import Foundation
import Testing
import MeetNotesProviders
@testable import MeetNotesNotes

@Test func builtInTemplatesAreReadOnlyAndDuplicable() throws {
    #expect(Template.builtIns.map(\.id) == ["standard", "one-to-one", "weekly-team", "discovery-call"])
    #expect(Template.builtIns.allSatisfy { $0.builtin })
    var file = TemplatesFile()
    #expect(throws: TemplateError.builtinIsReadOnly) { try file.upsert(Template.standard) }
    let copy = Template.standard.duplicate()
    #expect(!copy.builtin && copy.id != "standard" && copy.name == "Standard copy")
    try file.upsert(copy)
    #expect(file.all().count == 5)
}

@Test func userTemplatesRoundTripThroughDisk() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = MeetNotesPaths(root: root)
    var file = TemplatesFile()
    try file.upsert(Template(name: "Board update", instructions: "Decisions first."))
    try JSONFile.save(file, to: paths.templates)
    let back = try JSONFile.load(TemplatesFile.self, from: paths.templates, default: TemplatesFile())
    #expect(back == file)
    #expect(back.all().last?.name == "Board update")
}
