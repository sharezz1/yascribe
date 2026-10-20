import Foundation
import Testing
import MeetNotesProviders
import MeetNotesTranscription
@testable import MeetNotesLocalASR

private let local = Provider(name: "On this Mac", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
private let api = Provider(name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!)

private func snapshot(_ provider: Provider, fingerprint: String?) throws -> RunSnapshot {
    let preset = Preset(name: "Polish", language: .polish, asr: RoleAssignment(providerID: provider.id, model: "m"))
    return try RunSnapshot(preset: preset, provider: provider, probe: nil, modelFingerprint: fingerprint)
}

/// Pełny model z manifestu (pliki rzadkie o dokładnych rozmiarach) w `mn-<UUID>`, żeby `status() == .ready`.
private func readyStore() throws -> ModelStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true)
    let store = ModelStore(directory: root, download: { _, _, _ in })
    for (file, size) in ModelManifest.parakeetV3.files {
        let url = store.modelDirectory.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url)
        try h.truncate(atOffset: UInt64(size))
        try h.close()
    }
    return store
}

private func emptyStore() -> ModelStore {
    ModelStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)", isDirectory: true),
               download: { _, _, _ in })
}

private struct NoEngine: LocalASREngine {
    func load() async throws {}
    func transcribe(samples: [Float]) async throws -> (text: String, words: [TranscribedWord]) { ("", []) }
    func unload() async {}
}

@Test func missingModelRefusesRunAndNeverFallsBack() {
    // Review Focus #1: brak modelu = odmowa z przyciskiem pobrania; żaden klient nie powstaje (więc nic nie może pójść do API).
    #expect(RunGate.check(status: .missing)
            == RunGateRefusal(message: "The on-device speech model isn't downloaded yet. Download it in Settings.", canDownload: true))
    switch LocalASRFactory.client(provider: local, store: emptyStore(), engine: NoEngine()) {
    case .success: Issue.record("a client was created without a model")
    case .failure(let refusal): #expect(refusal.canDownload)
    }
}

@Test func readyAllowsRun() throws {
    #expect(RunGate.check(status: .ready) == nil)
    switch LocalASRFactory.client(provider: local, store: try readyStore(), engine: NoEngine()) {
    case .success(let c): #expect(c is LocalASRClient)
    case .failure(let refusal): Issue.record("refused: \(refusal.message)")
    }
}

@Test func invalidMissingAndUnknownVariantHaveDifferentMessages() {
    let invalid = RunGate.check(status: .invalid(reason: "Encoder.mlmodelc/weights/weight.bin has 1 bytes, expected 2"))
    let unknown = RunGate.check(status: .unknownVariant(reason: "found Encoder_v2.mlmodelc instead of Encoder.mlmodelc"))
    #expect(invalid?.message == "The on-device speech model failed its check: Encoder.mlmodelc/weights/weight.bin has 1 bytes, expected 2. Download it again.")
    #expect(invalid?.canDownload == true)
    #expect(unknown?.message == "Another app stored a different variant of this model: found Encoder_v2.mlmodelc instead of Encoder.mlmodelc.")
    #expect(unknown?.canDownload == false) // bez pętli „Download again"
    #expect(Set([RunGate.check(status: .missing)?.message, invalid?.message, unknown?.message]).count == 3)
}

@Test func resumeWithChangedModelFingerprintIsRefused() throws {
    // Review Focus #5: `AppModel.resume` podaje zapisaną migawkę, więc to ta bramka (nie `inputMismatch`) chroni przed mieszaniem modeli.
    let saved = try snapshot(local, fingerprint: "aaa")
    #expect(RunGate.checkResume(snapshot: saved, provider: local, currentFingerprint: "bbb")
            == RunGateRefusal(message: "The on-device model changed since this run. Start a new transcription.", canDownload: false))
    #expect(RunGate.checkResume(snapshot: saved, provider: local, currentFingerprint: nil) != nil)
}

@Test func resumeWithSameFingerprintIsAllowed() throws {
    #expect(RunGate.checkResume(snapshot: try snapshot(local, fingerprint: "aaa"), provider: local, currentFingerprint: "aaa") == nil)
    // przebieg bez zapisanego odcisku (nie powinien istnieć dla .fluidAudio) nie blokuje wznowienia
    #expect(RunGate.checkResume(snapshot: try snapshot(local, fingerprint: nil), provider: local, currentFingerprint: "bbb") == nil)
}

@Test func resumeOfApiRunIgnoresFingerprint() throws {
    #expect(RunGate.checkResume(snapshot: try snapshot(api, fingerprint: "aaa"), provider: api, currentFingerprint: "bbb") == nil)
    #expect(RunGate.checkResume(snapshot: try snapshot(api, fingerprint: nil), provider: api, currentFingerprint: nil) == nil)
}

@Test func apiProviderGetsNoFingerprintInSnapshot() throws {
    let store = try readyStore()
    #expect(RunGate.fingerprintForSnapshot(provider: api, store: store) == nil)
    let fp = RunGate.fingerprintForSnapshot(provider: local, store: store)
    #expect(fp != nil)
    #expect(fp == store.fingerprint())
    #expect(RunGate.fingerprintForSnapshot(provider: local, store: emptyStore()) == nil)
}
