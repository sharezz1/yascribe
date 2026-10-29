import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeApp

private final class OverviewHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [[String: Any]] = []
    var delay = false
    var calls: [[String: Any]] { lock.withLock { requests } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        lock.withLock { requests.append(body) }
        if delay { try await Task.sleep(for: .milliseconds(300)) }
        let data = Data("{\"choices\":[{\"message\":{\"content\":\"The team reviewed a forecast.\"}}]}".utf8)
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Test @MainActor func overviewUnavailableClientOffersRetryWithoutStartingWork() {
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    let text = Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "Forecast", words: [], approximateTiming: false)], failedChunks: [])
    let item = SessionItem(url: session, startedAt: Date(), transcript: text, runID: "run")
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let preset = Preset(name: "Test", language: .polish, asr: nil,
        summary: RoleAssignment(providerID: provider.id, model: "summary"))
    let model = NotesModel()
    model.presetFor = { _ in preset }
    #expect(model.summaryChoice(for: item) != nil)
    #expect(model.clientFor(provider.id) == nil)
    model.generateOverview(item)
    #expect(model.overviewFailure.contains(item.id))
    #expect(!model.isTitling(item.id))
    #expect(!FileManager.default.fileExists(atPath: session.path))
}

@Test @MainActor func overviewRunsAfterTranscriptionEvenWithManualTitle() async throws {
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: session) }
    let id = "2026-10-23T09-00-00Z-bbbb"
    let run = RunDirectory(session: session, runID: id)
    try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
    let transcript = Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "Forecast", words: [], approximateTiming: false)], failedChunks: [])
    try JSONFile.save(transcript, to: run.transcript)
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let preset = Preset(name: "Test", language: .polish, asr: RoleAssignment(providerID: provider.id, model: "asr"),
                        summary: RoleAssignment(providerID: provider.id, model: "preset"))
    let snapshot = try RunSnapshot(preset: preset, provider: provider, probe: nil)
    let store = NotesStore(session: session)
    try store.updateMeta { $0.manualTitle = "Manual"; $0.folderID = "folder"; $0.setOverride(.summary, RoleOverride(providerID: provider.id, model: "override")) }
    let http = OverviewHTTP()
    let model = NotesModel()
    model.knownProviderIDs = { [provider.id] }
    model.clientFor = { _ in OpenAICompatibleClient(provider: provider, key: "test-fake-key", http: http) }
    await model.afterTranscription(sessionURL: session, runID: id, snapshot: snapshot, transcript: transcript)
    #expect(http.calls.count == 1)
    #expect(http.calls.first?["model"] as? String == "override")
    #expect(store.readMeta().overview == "The team reviewed a forecast.")
    #expect(store.readMeta().overviewRunID == id)
    #expect(store.readMeta().overviewTranscriptFingerprint == Overview.fingerprint(transcript))
    #expect(store.readMeta().manualTitle == "Manual" && store.readMeta().folderID == "folder")
    #expect(store.readMeta().modelOverrides?.summary?.model == "override")
}

@Test @MainActor func resumedSameRunDiscardsDelayedOverview() async throws {
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: session) }
    let id = "2026-10-23T09-00-00Z-bbbb"
    let run = RunDirectory(session: session, runID: id)
    try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
    let old = Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "Before", words: [], approximateTiming: false)], failedChunks: [])
    let new = Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "After", words: [], approximateTiming: false)], failedChunks: [])
    try JSONFile.save(old, to: run.transcript)
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let preset = Preset(name: "Test", language: .polish, asr: RoleAssignment(providerID: provider.id, model: "asr"), summary: RoleAssignment(providerID: provider.id, model: "summary"))
    let snapshot = try RunSnapshot(preset: preset, provider: provider, probe: nil)
    let store = NotesStore(session: session)
    try store.updateMeta { $0.manualTitle = "Manual" }
    let http = OverviewHTTP()
    http.delay = true
    let model = NotesModel()
    model.knownProviderIDs = { [provider.id] }
    model.clientFor = { _ in OpenAICompatibleClient(provider: provider, key: "test-fake-key", http: http) }
    let task = Task { await model.afterTranscription(sessionURL: session, runID: id, snapshot: snapshot, transcript: old) }
    for _ in 0..<100 where http.calls.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
    #expect(http.calls.count == 1)
    try JSONFile.save(new, to: run.transcript)
    await task.value
    #expect(store.readMeta().overview == nil)
}

@Test @MainActor func automaticOverviewRejectsCorrectionChangedDuringRequest() async throws {
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: session) }
    let id = "2026-10-23T09-00-00Z-bbbb"
    let run = RunDirectory(session: session, runID: id)
    let raw = Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "Original forecast", words: [], approximateTiming: false)], failedChunks: [])
    var changed = raw
    changed.utterances[0].text = "Corrected forecast"
    try JSONFile.save(raw, to: run.transcript)
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let preset = Preset(name: "Test", language: .polish, asr: RoleAssignment(providerID: provider.id, model: "asr"), summary: RoleAssignment(providerID: provider.id, model: "summary"))
    let snapshot = try RunSnapshot(preset: preset, provider: provider, probe: nil)
    let store = NotesStore(session: session)
    try store.updateMeta { $0.manualTitle = "Manual" }
    let http = OverviewHTTP()
    http.delay = true
    let model = NotesModel()
    model.knownProviderIDs = { [provider.id] }
    model.clientFor = { _ in OpenAICompatibleClient(provider: provider, key: "test-fake-key", http: http) }
    let task = Task { await model.afterTranscription(sessionURL: session, runID: id, snapshot: snapshot, transcript: raw) }
    for _ in 0..<100 where http.calls.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
    #expect(http.calls.count == 1)
    try JSONFile.save(CorrectedTranscript(transcript: changed, model: "correction", batches: 1, failedBatches: 0, rejectedLines: 0), to: run.corrected)
    await task.value
    #expect(store.readMeta().overview == nil)
}

@Test @MainActor func manualOverviewRejectsCorrectionChangedDuringRequest() async throws {
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: session) }
    let id = "2026-10-23T09-00-00Z-bbbb"
    let run = RunDirectory(session: session, runID: id)
    let raw = Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "Original forecast", words: [], approximateTiming: false)], failedChunks: [])
    var before = raw
    before.utterances[0].text = "First correction"
    var after = raw
    after.utterances[0].text = "Second correction"
    let corrected = CorrectedTranscript(transcript: before, model: "correction", batches: 1, failedBatches: 0, rejectedLines: 0)
    try JSONFile.save(raw, to: run.transcript)
    try JSONFile.save(corrected, to: run.corrected)
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let preset = Preset(name: "Test", language: .polish, asr: nil, summary: RoleAssignment(providerID: provider.id, model: "summary"))
    let item = SessionItem(url: session, startedAt: Date(), transcript: raw, runID: id, corrected: corrected)
    let http = OverviewHTTP()
    http.delay = true
    let model = NotesModel()
    model.presetFor = { _ in preset }
    model.clientFor = { _ in OpenAICompatibleClient(provider: provider, key: "test-fake-key", http: http) }
    model.generateOverview(item)
    for _ in 0..<100 where http.calls.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
    #expect(http.calls.count == 1)
    try JSONFile.save(CorrectedTranscript(transcript: after, model: "correction", batches: 1, failedBatches: 0, rejectedLines: 0), to: run.corrected)
    for _ in 0..<200 where model.isTitling(item.id) { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!model.isTitling(item.id))
    #expect(NotesStore(session: session).readMeta().overview == nil)
}
