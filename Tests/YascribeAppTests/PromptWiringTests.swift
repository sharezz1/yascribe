import Foundation
import Testing
import YascribeNotes
import YascribeProviders
@testable import YascribeTranscription
@testable import YascribeApp

/// Odpowiada na korektę „[n] tekst." z żądania (kropka na końcu) i zapisuje `system` każdego żądania.
private final class EchoHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    var systems: [String] { lock.withLock { seen } }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: Any]]
        lock.withLock { seen.append(messages.first { $0["role"] as? String == "system" }?["content"] as? String ?? "") }
        let user = messages.first { $0["role"] as? String == "user" }?["content"] as? String ?? ""
        let reply = user.hasPrefix("[") ? user.components(separatedBy: "\n").map { $0 + "." }.joined(separator: "\n") : "# Title\nbody"
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": reply]]]])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("PromptWiring") @MainActor struct PromptWiringTests {
    let provider = Provider(name: "Test", baseURL: URL(string: "https://example.test/v1")!)
    let session = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID().uuidString)")
    fileprivate let http = EchoHTTP()
    let text = Transcript(utterances: [Utterance(speaker: .them, start: 0, end: 1, text: "Forecast", words: [], approximateTiming: false)], failedChunks: [])

    func makeModel(_ prompts: PromptOverrides) -> NotesModel {
        let model = NotesModel()
        let preset = Preset(name: "Test", language: .polish, asr: nil, correction: RoleAssignment(providerID: provider.id, model: "c"),
                            summary: RoleAssignment(providerID: provider.id, model: "s"))
        let provider = provider, http = http
        model.presetFor = { _ in preset }
        model.presetsInfo = { ([preset], preset.id) }
        model.knownProviderIDs = { [provider.id] }
        model.clientFor = { _ in OpenAICompatibleClient(provider: provider, key: "test-fake-key", http: http) }
        model.prompts = { prompts }
        return model
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func correctionUsesTheCustomBodyAndLeavesATraceInCorrectedJSON() async throws {
        let run = RunDirectory(session: session, runID: "run")
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        var prompts = PromptOverrides(); try prompts.set(.correction, text: "Only fix commas.")
        let model = makeModel(prompts)
        let item = SessionItem(url: session, startedAt: Date(), transcript: text, runID: "run")
        #expect(model.improveTranscript(item, draft: .preset))
        try await waitUntil { !model.isCorrecting(item.id) }
        #expect(http.systems.count == 1 && http.systems[0].hasPrefix("Only fix commas.\nThe input is numbered lines"))
        #expect(CorrectedTranscript.load(session: session, runID: "run")?.prompt == PromptTrace(source: .custom, text: "Only fix commas."))
    }

    @Test func defaultCorrectionIsTracedAsDefault() async throws {
        let run = RunDirectory(session: session, runID: "run")
        try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        let model = makeModel(PromptOverrides())
        let item = SessionItem(url: session, startedAt: Date(), transcript: text, runID: "run")
        #expect(model.improveTranscript(item, draft: .preset))
        try await waitUntil { !model.isCorrecting(item.id) }
        #expect(CorrectedTranscript.load(session: session, runID: "run")?.prompt == PromptTrace(source: .default, text: CorrectionPrompt.defaultBody))
    }

    @Test func summaryUsesTheCustomRulesAndLeavesATraceInSummaryJSON() async throws {
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session) }
        var prompts = PromptOverrides(); try prompts.set(.summary, text: "- Write like a pirate.")
        let model = makeModel(prompts)
        let item = SessionItem(url: session, startedAt: Date(), transcript: text, runID: "run")
        #expect(model.generate(item: item, useCorrected: false, template: Template.builtIns[0], context: "", draft: .preset))
        try await waitUntil { model.state(item.id) != .generating }
        #expect(http.systems.contains { $0.contains("- Write like a pirate.") && !$0.contains("Be concrete") })
        #expect((try NotesStore(session: session).readSummary())?.prompt == PromptTrace(source: .custom, text: "- Write like a pirate."))
    }
}
