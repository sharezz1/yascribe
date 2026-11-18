import Foundation
import Testing
@testable import YascribeApp

@Test func languagePreferencesUseApplicationDomain() throws {
    let name = "UILanguageTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(UILanguage.current(in: defaults) == .auto)
    #expect(!UILanguage.auto.select(in: defaults))
    #expect(UILanguage.pl.select(in: defaults))
    #expect(defaults.stringArray(forKey: "AppleLanguages") == ["pl"])
    #expect(UILanguage.en.select(in: defaults))
    #expect(defaults.stringArray(forKey: "AppleLanguages") == ["en"])
    #expect(UILanguage.auto.select(in: defaults))
    #expect(defaults.persistentDomain(forName: name)?["AppleLanguages"] == nil)
}

@Test @MainActor func languageRestartChecksAgainAndConsumesIntent() {
    let restart = LanguageRestart()
    var terminations = 0
    var launches = 0
    restart.request(ifIdle: false) { terminations += 1 }
    #expect(terminations == 0)
    restart.request(ifIdle: true) { terminations += 1 }
    #expect(!restart.consume(ifIdle: false) { launches += 1 })
    #expect(!restart.consume(ifIdle: true) { launches += 1 })
    restart.request(ifIdle: true) { terminations += 1 }
    #expect(restart.consume(ifIdle: true) { launches += 1 })
    #expect(terminations == 2 && launches == 1)
}

@Test @MainActor func failedLanguageRestartDoesNotAffectLaterQuit() {
    let restart = LanguageRestart()
    restart.request(ifIdle: true) { }
    #expect(!restart.consume(ifIdle: true) { throw CocoaError(.fileWriteUnknown) })
    #expect(!restart.requested)
}
