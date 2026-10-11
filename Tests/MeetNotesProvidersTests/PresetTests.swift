import Foundation
import Testing
@testable import MeetNotesProviders

private let asr = RoleAssignment(providerID: UUID(), model: "microsoft/mai-transcribe-2")

@Test func autoLanguageCannotBeConstructed() {
    // 🔴 „Nigdy auto" egzekwowane typem.
    #expect(throws: LanguageCodeError.autoIsForbidden) { _ = try LanguageCode("auto") }
    #expect(throws: LanguageCodeError.autoIsForbidden) { _ = try JSONDecoder().decode(LanguageCode.self, from: Data("\"AUTO\"".utf8)) }
    #expect(throws: LanguageCodeError.empty) { _ = try LanguageCode(" ") }
}

@Test func presetWithoutLanguageCannotBeSaved() {
    // P7: bramka, nie ostrzeżenie.
    var file = PresetsFile()
    #expect(throws: PresetError.missingLanguage) { try file.upsert(Preset(name: "Polish", language: nil, asr: asr)) }
    #expect(file.presets.isEmpty)
}

@Test func completePresetIsSavedAndReplacedById() throws {
    var file = PresetsFile()
    var p = Preset(name: "Polish", language: .polish, asr: asr)
    try file.upsert(p)
    p.name = "Polish (MAI)"
    try file.upsert(p)
    #expect(file.presets.count == 1)
    #expect(file.presets[0].name == "Polish (MAI)")
}

@Test func notesLanguageDefaultsToPresetLanguage() {
    #expect(Preset(name: "Polish", language: .polish, asr: asr).effectiveNotesLanguage == .polish)
    #expect(Preset(name: "Polish", language: .polish, asr: asr, notesLanguage: .english).effectiveNotesLanguage == .english)
}

@Test func storesRoundTripThroughDisk() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    let paths = MeetNotesPaths(root: root)
    var cache = ProbeCache()
    cache.record(ProbeResult(providerID: asr.providerID, model: asr.model, role: .asr, works: true, failure: nil,
                             shape: .audioTranscriptions, languageHandling: .enforced, embeddingDimension: nil,
                             checkedAt: Date(timeIntervalSince1970: 1_000)))
    try JSONFile.save(cache, to: paths.probeCache)
    let back = try JSONFile.load(ProbeCache.self, from: paths.probeCache, default: ProbeCache())
    #expect(back.result(provider: asr.providerID, model: asr.model, role: .asr)?.languageHandling == .enforced)
    #expect(try JSONFile.load(PresetsFile.self, from: paths.presets, default: PresetsFile()).presets.isEmpty)
}

@Test func dataDirectoryFollowsEnvironment() {
    #expect(MeetNotesPaths.fromEnvironment(["MEETNOTES_DATA_DIR": "/tmp/x/.devdata"]).root.path == "/tmp/x/.devdata")
}

@Test func providerFileNeverContainsAKey() throws {
    // P8 (przeniesione z B1 — Hermes 2.2: używa ProvidersFile z tego zadania): klucz nie jest polem struktury dostawcy — nie może trafić do pliku.
    let json = String(decoding: try JSONEncoder().encode(ProvidersFile(providers: [openRouter])), as: UTF8.self)
    #expect(!json.lowercased().contains("key"))
    #expect(maskedKey("sk-or-v1-abcdef1234") == "••••1234")
}

@Test func probeResultsForDifferentLanguagesDoNotOverwriteEachOther() {
    // ChatGPT #6: klasa obsługi języka jest wynikiem dla KONKRETNEGO języka.
    var cache = ProbeCache()
    let id = UUID()
    cache.record(ProbeResult(providerID: id, model: "m", role: .asr, works: true, languageHandling: .enforced, language: .polish))
    cache.record(ProbeResult(providerID: id, model: "m", role: .asr, works: true, languageHandling: .automatic, language: .english))
    #expect(cache.result(provider: id, model: "m", role: .asr, language: .polish)?.languageHandling == .enforced)
    #expect(cache.result(provider: id, model: "m", role: .asr, language: .english)?.languageHandling == .automatic)
}

@Test func presetWithEmptyModelCannotBeSaved() {
    var file = PresetsFile()
    #expect(throws: PresetError.missingASR) {
        try file.upsert(Preset(name: "Polish", language: .polish, asr: RoleAssignment(providerID: UUID(), model: " ")))
    }
}
