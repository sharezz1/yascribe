import Foundation
import Testing
import YascribeNotes
import YascribeProviders

@Test func libraryMessagesHavePolishFormatsAndPreserveNames() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let bundle = try #require(Bundle(url: root.appendingPathComponent("Resources/pl.lproj")))
    let folder = bundle.localizedString(forKey: "A folder named “%@” already exists.", value: nil, table: nil)
    #expect(String(format: folder, "Settings") == "Folder o nazwie „Settings” już istnieje.")
    let progress = bundle.localizedString(forKey: "Condensing part %lld of %lld (pass %lld)…", value: nil, table: nil)
    #expect(String(format: progress, Int64(2), Int64(5), Int64(1)) == "Skracanie części 2 z 5 (przebieg 1)…")
    let reason = bundle.localizedString(forKey: "Mistral: %@", value: nil, table: nil)
    #expect(String(format: reason, "server text") == "Mistral: server text")
}

@Test func probeDescriptionsKeepCanonicalEnglish() throws {
    #expect(ProviderCheck.describe(ProviderError.replyCutOff) == "The reply was cut off before the end.")
    let result = ProbeResult(providerID: UUID(), model: "Settings", role: .summary, failure: ProviderCheck.describe(ProviderError.replyCutOff))
    let decoded = try JSONDecoder().decode(ProbeResult.self, from: JSONEncoder().encode(result))
    #expect(decoded == result)
}

@Test func deletedAudioDaysUsePolishPluralForms() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let bundle = try #require(Bundle(url: root.appendingPathComponent("Resources/pl.lproj")))
    let format = bundle.localizedString(forKey: "Audio was deleted after %lld days", value: nil, table: nil)
    for (count, expected) in [(0, "Dźwięk usunięto po 0 dniach"), (1, "Dźwięk usunięto po 1 dniu"), (2, "Dźwięk usunięto po 2 dniach"), (5, "Dźwięk usunięto po 5 dniach"), (12, "Dźwięk usunięto po 12 dniach"), (22, "Dźwięk usunięto po 22 dniach"), (25, "Dźwięk usunięto po 25 dniach")] {
        #expect(String(format: format, locale: Locale(identifier: "pl"), Int64(count)) == expected)
    }
}
