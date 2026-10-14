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

@Test func autoLanguagePresetValidatesButStillNeedsAnExplicitChoice() throws {
    var p = Preset(name: "Mixed", language: nil, asr: asr, languageAuto: true)
    try p.validate()
    #expect(p.isAutoLanguage)
    #expect(p.languageLabel == "Auto ⚠")
    #expect(p.languageChoice == .auto)
    p.languageChoice = .code(.polish)
    #expect(p.language == .polish && p.languageAuto == nil && !p.isAutoLanguage)
    #expect(p.languageLabel == "PL")
    p.languageChoice = .unset
    #expect(throws: PresetError.missingLanguage) { try p.validate() }
    p.languageAuto = false
    #expect(throws: PresetError.missingLanguage) { try p.validate() }
}

@Test func phaseOnePresetJSONStillDecodes() throws {
    // Preset zapisany w fazie 1: bez `languageAuto`, ze `summary.prompt`. Nie wolno go ani odrzucić, ani po cichu zmienić.
    let json = """
    {"id":"00000000-0000-0000-0000-0000000000AA","name":"Polish","language":"pl",
     "asr":{"providerID":"00000000-0000-0000-0000-000000000001","model":"microsoft/mai-transcribe-2"},
     "summary":{"providerID":"00000000-0000-0000-0000-000000000001","model":"s","prompt":"Be brief"}}
    """
    let p = try JSONDecoder().decode(Preset.self, from: Data(json.utf8))
    #expect(p.languageAuto == nil)
    #expect(p.language == .polish)
    #expect(p.summary?.prompt == "Be brief")
    try p.validate()
    let again = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(p))
    #expect(again == p)
}

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)"))
}

@Test func realPhaseOnePresetsAndProvidersStillDecode() throws {
    // Prawdziwe pliki z fazy 1 (E6): wczytują się, a ponowne zakodowanie nie dodaje ani nie gubi kluczy.
    let rawPresets = try fixture("phase1-presets.json")
    let presets = try JSONDecoder().decode(PresetsFile.self, from: rawPresets)
    #expect(presets.presets.count == 2)
    for p in presets.presets {
        try p.validate()
        #expect(p.languageAuto == nil) // stary plik nie ma nowego klucza i nie dostaje go z nil
    }
    #expect(presets.presets.first { $0.name == "Polski" }?.summary?.model == "deepseek/deepseek-v4.1-flash")
    let rawProviders = try fixture("phase1-providers.json")
    let providers = try JSONDecoder().decode(ProvidersFile.self, from: rawProviders)
    #expect(providers.providers.map(\.name) == ["OpenRouter"])
    for (raw, again) in [(rawPresets, try JSONEncoder().encode(presets)), (rawProviders, try JSONEncoder().encode(providers))] {
        let a = try JSONSerialization.jsonObject(with: raw) as? NSDictionary
        let b = try JSONSerialization.jsonObject(with: again) as? NSDictionary
        #expect(a == b)
    }
}
