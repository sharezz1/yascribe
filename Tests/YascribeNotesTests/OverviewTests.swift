import Foundation
import Testing
import YascribeProviders
@testable import YascribeNotes
@testable import YascribeTranscription

@Test func overviewPromptAndPersistencePreserveMetadata() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    try store.updateMeta { $0.manualTitle = "Manual"; $0.folderID = "folder" }
    let stub = ChatStub { _ in "<think>hidden</think>\nForecast was reviewed.\nAnother line" }
    let ok = await Overview.generate(client: chatClient(stub), model: "m", transcript: transcript([utt("Forecast")]),
        notesLanguage: .polish, store: store, runID: "run", sourceTranscript: transcript([utt("Forecast")]), timeout: 10, chatTimeout: 10, maxTokens: 64, stillCurrent: { true })
    #expect(ok)
    #expect(store.readMeta().overview == "Forecast was reviewed.")
    #expect(store.readMeta().overviewRunID == "run")
    #expect(store.readMeta().manualTitle == "Manual" && store.readMeta().folderID == "folder")
    #expect(stub.calls.first?.system.contains("Polish") == true)
    #expect(stub.calls.first?.reasoningEnabled == false)
}

@Test func overviewFailureAndStaleRunDoNotSave() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let fail = ChatStub { _ in throw StubHTTPError(status: 500, body: "error") }
    let stale = ChatStub { _ in "Old result" }
    let t = transcript([utt("Forecast")])
    let failed = await Overview.generate(client: chatClient(fail), model: "m", transcript: t, notesLanguage: nil,
        store: store, runID: "run", sourceTranscript: transcript([utt("Forecast")]), timeout: 10, chatTimeout: 10, maxTokens: nil, stillCurrent: { true })
    let old = await Overview.generate(client: chatClient(stale), model: "m", transcript: t, notesLanguage: nil,
        store: store, runID: "run", sourceTranscript: transcript([utt("Forecast")]), timeout: 10, chatTimeout: 10, maxTokens: nil, stillCurrent: { false })
    #expect(!failed && !old && stale.calls.count == 1)
    #expect(store.readMeta().overview == nil)
    #expect(Overview.prompt(transcript: transcript([]), notesLanguage: nil) == nil)
}

@Test func overviewLegacyMetadataDecodes() throws {
    let meta = try JSONDecoder().decode(NoteMeta.self, from: Data("{\"manualTitle\":\"Mine\",\"folderID\":\"folder\"}".utf8))
    #expect(meta.overview == nil && meta.overviewRunID == nil)
    #expect(meta.overviewCorrectionFingerprint == nil)
    #expect(meta.manualTitle == "Mine" && meta.folderID == "folder")
}

@Test func overviewRefusedWriteDoesNotReportSuccess() async {
    let session = tempDir()
    let store = NotesStore(session: session, requiresExistingSession: true)
    let stub = ChatStub { _ in "A forecast was reviewed." }
    let text = transcript([utt("Forecast")])
    let saved = await Overview.generate(client: chatClient(stub), model: "m", transcript: text,
        notesLanguage: nil, store: store, runID: "run", sourceTranscript: text,
        timeout: 10, chatTimeout: 10, maxTokens: nil, stillCurrent: { true })
    #expect(stub.calls.count == 1)
    #expect(!saved)
    #expect(!FileManager.default.fileExists(atPath: session.path))
}

private final class OverviewCurrent: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true
    func get() -> Bool { lock.withLock { value } }
    func invalidate() { lock.withLock { value = false } }
}

@Test func delayedOverviewFromOldRunIsDiscarded() async throws {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let store = NotesStore(session: session)
    let current = OverviewCurrent()
    let stub = ChatStub(delay: .milliseconds(200)) { _ in "Old result" }
    let task = Task {
        await Overview.generate(client: chatClient(stub), model: "m", transcript: transcript([utt("Forecast")]),
            notesLanguage: nil, store: store, runID: "old", sourceTranscript: transcript([utt("Forecast")]), timeout: 10, chatTimeout: 10, maxTokens: nil,
            stillCurrent: { current.get() })
    }
    for _ in 0..<100 where stub.calls.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
    #expect(stub.calls.count == 1)
    current.invalidate()
    #expect(await task.value == false)
    #expect(store.readMeta().overview == nil)
}

@Test func overviewPreservesLongSentenceAndTracksTranscript() {
    let sentence = "The team reviewed the quarterly forecast and agreed to revise the staffing plan before the next meeting."
    #expect(Overview.clean(sentence) == sentence)
    let before = transcript([utt("Before")])
    let after = transcript([utt("After")])
    var meta = NoteMeta()
    meta.overview = sentence
    meta.overviewRunID = "run"
    meta.overviewTranscriptFingerprint = Overview.fingerprint(before)
    #expect(Overview.cached(meta, runID: "run", transcript: before) == sentence)
    #expect(Overview.cached(meta, runID: "run", transcript: after) == nil)
    #expect(Overview.cached(meta, runID: "other", transcript: before) == nil)
    #expect(Overview.fingerprint(before) != Overview.fingerprint(after))
    #expect(Overview.fingerprint(nil) == nil)
}

@Test func overviewCacheTracksCorrectedTranscript() async {
    let session = tempDir()
    defer { try? FileManager.default.removeItem(at: session) }
    let raw = transcript([utt("Original forecast")])
    let before = transcript([utt("Corrected forecast")])
    let after = transcript([utt("Updated forecast")])
    let store = NotesStore(session: session)
    let stub = ChatStub { _ in "A forecast was reviewed." }
    let saved = await Overview.generate(client: chatClient(stub), model: "m", transcript: before,
        notesLanguage: nil, store: store, runID: "run", sourceTranscript: raw, correctedTranscript: before,
        timeout: 10, chatTimeout: 10, maxTokens: nil, stillCurrent: { true })
    #expect(saved)
    let meta = store.readMeta()
    #expect(Overview.cached(meta, runID: "run", transcript: raw, correctedTranscript: before) != nil)
    #expect(Overview.cached(meta, runID: "run", transcript: raw, correctedTranscript: after) == nil)
    #expect(Overview.cached(meta, runID: "run", transcript: raw) == nil)
}
