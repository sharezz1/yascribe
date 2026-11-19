import Foundation
import Testing
import YascribeProviders
@testable import YascribeApp

@Test func settingsMessagesPreserveUnknownValues() {
    let userValue = "Settings"
    #expect(localizedProviderMessage(userValue) == userValue)
    #expect(localizedProviderMessage("Invalid API key.") == "Invalid API key.")
}

@Test func polishSettingsResourcesContainTranslatedMessages() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let bundle = try #require(Bundle(url: root.appendingPathComponent("Resources/pl.lproj")))
    #expect(bundle.localizedString(forKey: "Invalid API key.", value: nil, table: nil) == "Nieprawidłowy klucz API.")
    #expect(bundle.localizedString(forKey: "Move Here", value: nil, table: nil) == "Przenieś tutaj")
    #expect(bundle.localizedString(forKey: "Not downloaded", value: nil, table: nil) == "Nie pobrano")
}
