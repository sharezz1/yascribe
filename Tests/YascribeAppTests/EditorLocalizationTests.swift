import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeApp

@Test func editorPresentationKeepsTemplateContentAndIdentity() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let bundle = try #require(Bundle(url: root.appendingPathComponent("Resources/pl.lproj")))
    let original = Template.weeklyTeam
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let encoded = try encoder.encode(original)
    #expect(original.displayName(bundle: bundle) == "Cotygodniowe spotkanie zespołu")
    var renamed = original
    renamed.name = "Settings"
    #expect(renamed.displayName(bundle: bundle) == "Settings")
    let custom = Template(id: original.id, name: "Settings", builtin: false)
    #expect(custom.displayName(bundle: bundle) == "Settings")
    #expect(try encoder.encode(original) == encoded)
    #expect(original.promptText == Template.weeklyTeam.promptText)
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
