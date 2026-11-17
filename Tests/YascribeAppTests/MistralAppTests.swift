import Foundation
import Testing
import YascribeProviders
import YascribeLocalASR
import YascribeRecording
import YascribeSessionFormat
@testable import YascribeTranscription
@testable import YascribeApp

private actor CountingMistralHTTP: HTTPClient {
    let secrets: InMemorySecretStore
    let providerID: UUID
    var requests: [URLRequest] = []
    init(secrets: InMemorySecretStore, providerID: UUID) { self.secrets = secrets; self.providerID = providerID }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if requests.count == 1 { try secrets.set(providerID, "new-key") }
        let status = requests.count == 1 ? 200 : 401
        let data = Data("{\"segments\":[],\"usage\":{\"total_tokens\":1}}".utf8)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Test @MainActor func mistralAppUsesRunLanguageAndKeepsSpeakersOnSecondPartError() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
    setenv("YASCRIBE_DATA_DIR", root.path, 1)
    let model = AppModel()
    if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
    let provider = Provider(name: "Mistral", baseURL: MistralDiarizationClient.baseURL, kind: .mistral)
    let secrets = InMemorySecretStore()
    model.secrets = secrets
    model.providers = ProvidersFile(providers: [provider])
    model.settings.speakerSource = .mistral
    #expect(!model.speakerSourceReady)
    try secrets.set(provider.id, "test-key")
    model.settings.speakerSource = .local
    #expect(model.speakerSourceReady == (model.speakerModel.store.status() == .ready))
    model.settings.speakerSource = .mistral
    #expect(model.speakerSourceReady)
    let http = CountingMistralHTTP(secrets: secrets, providerID: provider.id)
    model.mistralHTTP = http
    model.mistralPartSeconds = 1
    let session = root.appendingPathComponent("session")
    let timebase = Timebase(numer: 1, denom: 1)
    let source = FileSource(trackID: "system", samples: [Int16](repeating: 1000, count: 32_000), sampleRate: 16_000, channels: 1, startHostTime: 1_000_000_000, timebase: timebase)
    try SessionRecorder(directory: session, sources: [source], conditions: [], clock: ManualHostClock(), timebase: timebase, zeroWatch: [:]).start()
    let run = RunDirectory(session: session, runID: "run")
    try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
    let asr = Provider(name: "ASR", baseURL: URL(string: "https://example.com")!)
    let preset = Preset(name: "Saved", language: .polish, asr: RoleAssignment(providerID: asr.id, model: "asr"))
    let snapshot = try RunSnapshot(preset: preset, provider: asr, probe: nil)
    let input = RunInput(snapshot: snapshot, gate: EnergyGate.Config(), maxChunkSeconds: 10, crosstalk: CrosstalkFilter(), trackFrames: [:])
    try JSONFile.save(input, to: run.input)
    let original = Data("previous speakers".utf8)
    try original.write(to: run.speakers)
    model.settings.detectSpeakers = false
    #expect(await !model.detectSpeakersAfterTranscription(sessionURL: session, runID: "run", themUtterances: 1))
    #expect(await http.requests.isEmpty)
    model.settings.speakerSource = .local
    for (file, size) in DiarizerManifest.offline.files {
        let url = model.speakerModel.store.directory.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
    }
    model.settings.detectSpeakers = true
    #expect(model.speakerSourceReady)
    #expect(await model.detectSpeakersAfterTranscription(sessionURL: session, runID: "run", themUtterances: 1))
    #expect(await http.requests.isEmpty)
    model.settings.speakerSource = .mistral
    await model.detectSpeakers(sessionURL: session, runID: "run", sensitivity: .medium)
    let requests = await http.requests
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-key" })
    #expect(requests.allSatisfy { String(decoding: $0.httpBody ?? Data(), as: UTF8.self).contains("name=\"language\"\r\n\r\npl\r\n") })
    #expect(try Data(contentsOf: run.speakers) == original)
    #expect(model.lastError == "Couldn't detect speakers: Mistral rejected the API key.")
}
