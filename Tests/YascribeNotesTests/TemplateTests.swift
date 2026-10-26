import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes

@Test func builtInTemplatesAreDuplicableAndCantBeAdded() throws {
    #expect(Template.builtIns.map(\.id) == ["standard", "one-to-one", "weekly-team", "discovery-call"])
    #expect(Template.builtIns.allSatisfy { $0.builtin })
    var file = TemplatesFile()
    #expect(throws: TemplateError.builtinIsReadOnly) { try file.upsert(Template(id: "my-builtin", name: "Mine", builtin: true)) }
    let copy = Template.standard.duplicate()
    #expect(!copy.builtin && copy.id != "standard" && copy.name == "Standard copy")
    try file.upsert(copy)
    #expect(file.all().count == 5)
}

@Test func userTemplatesRoundTripThroughDisk() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = YascribePaths(root: root)
    var file = TemplatesFile()
    try file.upsert(Template(name: "Board update", instructions: "Decisions first."))
    try JSONFile.save(file, to: paths.templates)
    let back = try JSONFile.load(TemplatesFile.self, from: paths.templates, default: TemplatesFile())
    #expect(back == file)
    #expect(back.all().last?.name == "Board update")
}

@Test func renamingToExistingTemplateNameIsRejected() throws {
    var file = TemplatesFile()
    var a = Template(name: "Board update", instructions: "x")
    try file.upsert(a)
    try file.upsert(Template(name: "Sales sync", instructions: "y"))
    a.name = "sales SYNC"
    #expect(throws: TemplateError.nameTaken("sales SYNC")) { try file.upsert(a) }
    a.name = "Standard" // nazwa wbudowanego też jest zajęta
    #expect(throws: TemplateError.nameTaken("Standard")) { try file.upsert(a) }
    #expect(file.templates.map(\.name) == ["Board update", "Sales sync"]) // nic się nie zmieniło
}

// Uwaga 2 (odbiór 2026-10-16): szablon jako lista sekcji.

private let legacyJSON = #"{"templates":[{"id":"old","name":"Board update","instructions":"Decisions first.\nThen risks.","builtin":false}]}"#

@Test func legacyTemplateLoadsAsOneSectionWithoutLosingTheText() throws {
    let file = try JSONDecoder().decode(TemplatesFile.self, from: Data(legacyJSON.utf8))
    let t = try #require(file.templates.first)
    #expect(t.sections == nil && t.about == nil) // pola opcjonalne (E6): stary plik się wczytuje
    #expect(t.effectiveSections == [TemplateSection(title: "", instruction: "Decisions first.\nThen risks.")])
    #expect(t.promptText == "Decisions first.\nThen risks.") // dosłownie, jak przed zmianą
    // Ponowne zakodowanie nie gubi kluczy.
    let json = try #require(String(data: try JSONEncoder().encode(file), encoding: .utf8))
    for key in ["\"id\":\"old\"", "\"name\":\"Board update\"", "\"instructions\":\"Decisions first.\\nThen risks.\"", "\"builtin\":false"] {
        #expect(json.contains(key), "brak \(key) w \(json)")
    }
    #expect(try JSONDecoder().decode(TemplatesFile.self, from: Data(json.utf8)) == file)
}

@Test func promptIsComposedFromSectionsInOrderWithAboutFirst() {
    var t = Template(name: "X", sections: [TemplateSection(title: "Summary", instruction: "One paragraph."),
                                           TemplateSection(title: "Risks", instruction: "What could go wrong."),
                                           TemplateSection(title: "", instruction: "   ")]) // pusta pomijana
    let p = t.promptText
    #expect(p.contains("1. Summary: One paragraph."))
    #expect(p.contains("2. Risks: What could go wrong."))
    #expect(!p.contains("3."))
    #expect(p.range(of: "Summary")!.lowerBound < p.range(of: "Risks")!.lowerBound)
    #expect(!p.contains("About this meeting type"))
    t.about = "  Weekly sync of the forecasting team.  "
    #expect(t.promptText.hasPrefix("About this meeting type: Weekly sync of the forecasting team.\n\n"))
    t.sections?.swapAt(0, 1)
    #expect(t.promptText.range(of: "Risks")!.lowerBound < t.promptText.range(of: "Summary")!.lowerBound)
}

@Test func editingABuiltInSavesAnOverrideAndResetRemovesIt() throws {
    var file = TemplatesFile()
    #expect(!file.isEdited(id: "standard"))
    var edited = file.all()[0]
    edited.sections?[0].instruction = "Two sentences."
    edited.about = "Customer calls."
    try file.upsert(edited)
    #expect(file.isEdited(id: "standard") && file.templates.isEmpty)
    #expect(file.all().count == 4 && file.all()[0].builtin && file.all()[0].effectiveSections[0].instruction == "Two sentences.")
    #expect(file.all()[0].promptText.contains("About this meeting type: Customer calls."))
    #expect(Template.standard.effectiveSections[0].instruction != "Two sentences.") // wbudowany w kodzie nietknięty
    // Override przeżywa dysk.
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = YascribePaths(root: root)
    try JSONFile.save(file, to: paths.templates)
    #expect(try JSONFile.load(TemplatesFile.self, from: paths.templates, default: TemplatesFile()) == file)
    file.reset(id: "standard")
    #expect(!file.isEdited(id: "standard") && file == TemplatesFile())
    #expect(file.all()[0] == Template.standard)
    // Zapis treści równej domyślnej nie zostawia nadpisania.
    try file.upsert(Template.standard)
    #expect(!file.isEdited(id: "standard"))
}

@Test func builtInCantBeRemovedButCustomCan() throws {
    var file = TemplatesFile()
    #expect(throws: TemplateError.builtinCantBeRemoved) { try file.remove(id: "standard") }
    #expect(file.all().count == 4)
    var edited = Template.oneToOne
    edited.name = "1:1 weekly"
    try file.upsert(edited)
    #expect(throws: TemplateError.builtinCantBeRemoved) { try file.remove(id: "one-to-one") }
    #expect(file.isEdited(id: "one-to-one"))
    let mine = Template(name: "Mine", sections: [TemplateSection(title: "A", instruction: "b")])
    try file.upsert(mine)
    try file.remove(id: mine.id)
    #expect(file.templates.isEmpty)
}

@Test func templateWithoutAnySectionContentIsRejected() {
    var file = TemplatesFile()
    #expect(throws: TemplateError.noSections) { try file.upsert(Template(name: "Empty", sections: [TemplateSection(title: " ", instruction: "")])) }
}
