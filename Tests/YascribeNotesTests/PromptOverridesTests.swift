import Foundation
import Testing
@testable import YascribeNotes

@Test func noEntryMeansTheDefaultBody() {
    let o = PromptOverrides()
    #expect(o.body(.correction) == CorrectionPrompt.defaultBody && o.body(.summary) == SummaryPrompt.defaultBody)
    #expect(o.trace(.correction) == PromptTrace(source: .default, text: CorrectionPrompt.defaultBody))
    #expect(!o.isStale(.correction))
}

@Test func customTextIsUsedAndTracedAndIndependentPerKind() throws {
    var o = PromptOverrides()
    try o.set(.correction, text: "  Fix commas only.\n")
    #expect(o.body(.correction) == "Fix commas only.")
    #expect(o.trace(.correction) == PromptTrace(source: .custom, text: "Fix commas only."))
    #expect(o.body(.summary) == SummaryPrompt.defaultBody)
}

@Test func textEqualToDefaultOrEmptyRemovesTheEntry() throws {
    var o = PromptOverrides()
    try o.set(.summary, text: "custom")
    try o.set(.summary, text: "  " + SummaryPrompt.defaultBody + "\n")
    #expect(o.summary == nil)
    try o.set(.correction, text: "custom")
    try o.set(.correction, text: " \n ")
    #expect(o.correction == nil)
}

@Test func textOverTheLimitIsRefusedAndLeavesTheEntryAlone() throws {
    var o = PromptOverrides()
    try o.set(.correction, text: "ok")
    #expect(throws: PromptOverrides.SetError.tooLong(max: 1_500)) { try o.set(.correction, text: String(repeating: "x", count: 1_501)) }
    try o.set(.correction, text: String(repeating: "x", count: 1_500))
    #expect(throws: PromptOverrides.SetError.tooLong(max: 2_000)) { try o.set(.summary, text: String(repeating: "x", count: 2_001)) }
    #expect(o.body(.correction).count == 1_500 && o.summary == nil)
}

@Test func entryBasedOnAnOlderDefaultIsStaleUntilAcknowledged() throws {
    var o = PromptOverrides(correction: PromptEntry(text: "mine", basedOn: "000000000000"))
    #expect(o.isStale(.correction))
    #expect(o.body(.correction) == "mine") // nigdy nie podmieniamy po cichu
    o.acknowledge(.correction)
    #expect(!o.isStale(.correction) && o.body(.correction) == "mine")
    var fresh = PromptOverrides()
    try fresh.set(.correction, text: "mine")
    #expect(!fresh.isStale(.correction))
}

@Test func hashIsStableTwelveHexAndSensitive() {
    #expect(PromptOverrides.hash("a") == "ca978112ca1b") // SHA-256("a") = ca978112ca1bbdca…
    #expect(PromptOverrides.hash("a") != PromptOverrides.hash("a "))
}

@Test func storeRoundTripsAndToleratesUnknownKeysAndMissingFile() throws {
    let dir = tempDir(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("prompts.json")
    #expect(PromptStore.load(from: url).overrides == PromptOverrides() && PromptStore.load(from: url).problem == nil)
    var o = PromptOverrides(); try o.set(.summary, text: "mine")
    try PromptStore.save(o, to: url)
    #expect(PromptStore.load(from: url).overrides == o)
    try Data(#"{"summary":{"text":"x","basedOn":"y","future":1},"later":true}"#.utf8).write(to: url)
    #expect(PromptStore.load(from: url).overrides.summary == PromptEntry(text: "x", basedOn: "y"))
}

@Test func corruptFileFallsBackToDefaultsAndIsKeptAsBakOnSave() throws {
    let dir = tempDir(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("prompts.json")
    try Data("{not json".utf8).write(to: url)
    let loaded = PromptStore.load(from: url)
    #expect(loaded.overrides == PromptOverrides() && loaded.problem != nil)
    #expect(try String(contentsOf: url, encoding: .utf8) == "{not json") // wczytanie niczego nie kasuje
    var o = PromptOverrides(); try o.set(.correction, text: "mine")
    try PromptStore.save(o, to: url)
    #expect(try String(contentsOf: url.appendingPathExtension("bak"), encoding: .utf8) == "{not json")
    #expect(PromptStore.load(from: url).overrides == o)
}

@Test func oldResultFilesWithoutPromptStillDecodeAndNewOnesRoundTrip() throws {
    let old = #"{"title":"T","markdown":"m","templateID":"standard","model":"x","context":"","generatedAt":"2026-11-01T10:00:00Z"}"#
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    #expect(try dec.decode(NoteSummary.self, from: Data(old.utf8)).prompt == nil)
    let c = CorrectedTranscript(transcript: transcript([]), model: "m", batches: 1, failedBatches: 0, rejectedLines: 0)
    let enc = JSONEncoder()
    var withTrace = c; withTrace.prompt = PromptTrace(source: .custom, text: "mine")
    #expect(try dec.decode(CorrectedTranscript.self, from: enc.encode(c)).prompt == nil)
    #expect(try dec.decode(CorrectedTranscript.self, from: enc.encode(withTrace)).prompt == PromptTrace(source: .custom, text: "mine"))
}
