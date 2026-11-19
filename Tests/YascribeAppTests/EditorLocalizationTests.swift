import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeApp

@Test @MainActor func editorPresentationKeepsTemplateContentAndIdentity() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mn-template-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = Template.weeklyTeam
    let sections = [TemplateSection(title: "Next steps", instruction: "Keep user instructions verbatim.")]
    var storedSections: [[TemplateSection]] = []
    var prompts: [String] = []
    for (language, title, newName, copySuffix) in [
        ("pl", "Cotygodniowe spotkanie zespołu", "Nowy szablon", " – kopia"),
        ("en", original.name, "New template", " copy"),
    ] {
        let bundle = try #require(Bundle(url: root.appendingPathComponent("Resources/\(language).lproj")))
        let state = TemplateEditorState()
        var file = TemplatesFile()
        state.startNew(bundle: bundle)
        var draft = try #require(state.draft)
        #expect(draft.name == newName)
        draft.name = "Settings"
        draft.sections = sections
        try file.upsert(draft)

        #expect(original.displayName(bundle: bundle) == title)
        let collision = Template(name: (original.name + copySuffix).uppercased(), sections: sections)
        try file.upsert(collision)
        state.select(original)
        state.duplicate(in: file, bundle: bundle)
        let copy = try #require(state.draft)
        #expect(copy.name == original.name + copySuffix + " 2")
        #expect(copy.id != original.id && !copy.builtin)
        try file.upsert(copy)

        let url = directory.appendingPathComponent("\(language).json")
        try JSONFile.save(file, to: url)
        let reopened = try JSONFile.load(TemplatesFile.self, from: url, default: TemplatesFile())
        let savedDraft = try #require(reopened.all().first { $0.id == draft.id })
        let savedCopy = try #require(reopened.all().first { $0.id == copy.id })
        #expect(savedDraft.name == "Settings" && savedDraft.displayName(bundle: bundle) == "Settings")
        #expect(savedCopy.name == copy.name && savedCopy.about == original.about)
        #expect(savedCopy.effectiveSections == original.effectiveSections)
        storedSections.append(savedDraft.effectiveSections)
        prompts.append(savedCopy.promptText)
    }
    #expect(storedSections == [sections, sections])
    #expect(prompts == [original.promptText, original.promptText])
}

@Test func modelLanguageLabelsUseInterfaceLanguage() throws {
    let polish = try LanguageCode("pl")
    #expect(languageDisplayName(polish, locale: Locale(identifier: "pl")) == "polski")
    #expect(languageDisplayName(polish, locale: Locale(identifier: "en")) == "Polish")
    #expect(polish.englishName == "Polish")
}

@Test func dictionaryPluralResourcesHavePolishAndEnglishForms() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for (language, expected) in [("pl", ["0 terminów", "1 termin", "2 terminy", "5 terminów", "12 terminów", "22 terminy", "25 terminów"]),
                                 ("en", ["0 terms", "1 term", "2 terms", "5 terms", "12 terms", "22 terms", "25 terms"])] {
        let bundle = try #require(Bundle(url: root.appendingPathComponent("Resources/\(language).lproj")))
        let format = bundle.localizedString(forKey: "%lld terms", value: nil, table: nil)
        for (count, value) in zip([0, 1, 2, 5, 12, 22, 25], expected) {
            #expect(String(format: format, locale: Locale(identifier: language), Int64(count)) == value)
        }
    }
}
