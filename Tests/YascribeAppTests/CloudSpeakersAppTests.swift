import Foundation
import AVFoundation
import Testing
import YascribeProviders
import YascribeNotes
import YascribeRecording
import YascribeSessionFormat
@testable import YascribeTranscription
@testable import YascribeApp

private actor CloudHTTP: HTTPClient {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = request.url!.path.contains("speech-to-text")
            ? #"{"words":[{"type":"word","speaker_id":"speaker_0","start":0,"end":12}]}"#
            : #"{"words":[{"speaker_label":"speaker_0","start":0,"end":12}]}"#
        return (Data(response.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Test @MainActor func cloudSpeakersAppUsesRunProviderAndLanguage() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mn-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let previous = getenv("YASCRIBE_DATA_DIR").map { String(cString: $0) }
    setenv("YASCRIBE_DATA_DIR", root.path, 1)
    let model = AppModel()
    if let previous { setenv("YASCRIBE_DATA_DIR", previous, 1) } else { unsetenv("YASCRIBE_DATA_DIR") }
    let provider = Provider(name: "Cloud", baseURL: URL(string: "https://example.com")!)
    let secrets = InMemorySecretStore()
    model.secrets = secrets
    model.providers = ProvidersFile(providers: [provider])
    let http = CloudHTTP()
    model.diarizationHTTP = http
    let session = root.appendingPathComponent("session")
    let timebase = Timebase(numer: 1, denom: 1)
    let source = FileSource(trackID: "system", samples: [Int16](repeating: 1000, count: 32_000), sampleRate: 16_000, channels: 1, startHostTime: 1_000_000_000, timebase: timebase)
    try SessionRecorder(directory: session, sources: [source], conditions: [], clock: ManualHostClock(), timebase: timebase, zeroWatch: [:]).start()
    let run = RunDirectory(session: session, runID: "run")
    try FileManager.default.createDirectory(at: run.url, withIntermediateDirectories: true)
    func saveInput(_ modelName: String) throws -> RunSnapshot {
        let preset = Preset(name: "Saved", language: .polish, asr: RoleAssignment(providerID: provider.id, model: modelName))
        let snapshot = try RunSnapshot(preset: preset, provider: provider, probe: nil)
        try JSONFile.save(RunInput(snapshot: snapshot, gate: EnergyGate.Config(), maxChunkSeconds: 10, crosstalk: CrosstalkFilter(), trackFrames: [:]), to: run.input)
        return snapshot
    }
    let snapshot = try saveInput("elevenlabs/scribe-v2")
    var item = SessionItem(url: session, summary: nil, startedAt: Date(), transcript: nil, progress: nil)
    item.runID = "run"; item.runSnapshot = snapshot
    #expect(await !model.detectSpeakersAfterTranscription(sessionURL: session, runID: "run", themUtterances: 1))
    #expect(model.lastError == nil)
    model.detectSpeakersAgain(item: item)
    #expect(model.lastError == "Couldn't detect speakers: No API key.")
    model.lastError = nil
    try secrets.set(provider.id, "test-key")
    _ = try saveInput("openai/whisper-1")
    #expect(await !model.detectSpeakersAfterTranscription(sessionURL: session, runID: "run", themUtterances: 1))
    #expect(await http.requests.isEmpty)
    _ = try saveInput("elevenlabs/scribe-v2")
    #expect(await model.detectSpeakersAfterTranscription(sessionURL: session, runID: "run", themUtterances: 1))
    let requests = await http.requests
    #expect(requests.count == 1)
    let body = try #require(requests.first?.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["diarize"] as? Bool == true)
    #expect(json["language"] as? String == "pl")
    let speakers = try JSONFile.load(SpeakerDiarization?.self, from: run.speakers, default: nil)
    #expect(speakers?.modelPin == "openrouter/elevenlabs/scribe-v2/diarize-v1")
    model.renameSpeaker(item: item, key: "speaker_0", name: " Ala ")
    let renamed = try JSONFile.load(SpeakerDiarization?.self, from: run.speakers, default: nil)
    #expect(renamed?.names?["speaker_0"] == "Ala")
    #expect(KnownPeople.load(root: root).names == ["Ala"])
    var replacement = try #require(renamed)
    replacement.segments = [.init(speaker: "new-speaker", start: 0, end: 12)]
    replacement.names = nil
    try JSONFile.save(replacement, to: run.speakers)
    let before = try Data(contentsOf: run.speakers)
    model.renameSpeaker(item: item, key: "speaker_0", name: "Ola")
    #expect(try Data(contentsOf: run.speakers) == before)
    #expect(KnownPeople.load(root: root).names == ["Ala"])
    let eleven = Provider(name: "ElevenLabs", baseURL: URL(string: "https://example.com")!, kind: .elevenLabs)
    model.providers = ProvidersFile(providers: [provider, eleven])
    try secrets.set(eleven.id, "eleven-key")
    let elevenPreset = Preset(name: "Saved", language: .polish, asr: RoleAssignment(providerID: eleven.id, model: "scribe_v2"))
    let elevenSnapshot = try RunSnapshot(preset: elevenPreset, provider: eleven, probe: nil)
    try JSONFile.save(RunInput(snapshot: elevenSnapshot, gate: EnergyGate.Config(), maxChunkSeconds: 10, crosstalk: CrosstalkFilter(), trackFrames: [:]), to: run.input)
    #expect(await model.detectSpeakersAfterTranscription(sessionURL: session, runID: "run", themUtterances: 1))
    let elevenRequest = try #require(await http.requests.last)
    #expect(elevenRequest.url?.path.contains("speech-to-text") == true)
    #expect(String(decoding: elevenRequest.httpBody ?? Data(), as: UTF8.self).contains("name=\"diarize\"\r\n\r\ntrue"))
    let elevenSpeakers = try JSONFile.load(SpeakerDiarization?.self, from: run.speakers, default: nil)
    #expect(elevenSpeakers?.modelPin == SpeakerCapability.pin(api: .elevenLabs, model: "scribe_v2"))
    try JSONFile.save(replacement, to: run.speakers)
    _ = try saveInput("elevenlabs/scribe-v2")
    let transcript = run.url.appendingPathComponent("transcript.json")
    let transcriptBytes = Data("previous transcript".utf8)
    try transcriptBytes.write(to: transcript)
    // Extend the CAF as a sparse file so the real duration limit is exercised without encoding hours of audio.
    let track = session.appendingPathComponent("system.caf")
    let audio = try AVAudioFile(forReading: track)
    let bytesPerFrame = UInt64(audio.fileFormat.streamDescription.pointee.mBytesPerFrame)
    let header = try Data(contentsOf: track)
    let dataChunk = try #require(header.range(of: Data("data".utf8)))
    let audioBytes = UInt64(audio.processingFormat.sampleRate * 18_000) * bytesPerFrame
    let file = try FileHandle(forWritingTo: track)
    try file.seek(toOffset: UInt64(dataChunk.lowerBound + 4))
    var chunkSize = (audioBytes + 4).bigEndian
    try withUnsafeBytes(of: &chunkSize) { try file.write(contentsOf: $0) }
    try file.truncate(atOffset: UInt64(dataChunk.lowerBound + 16) + audioBytes)
    try file.close()
    #expect(await model.detectSpeakersAfterTranscription(sessionURL: session, runID: "run", themUtterances: 1))
    #expect(model.lastError == "Couldn't detect speakers: Recording too long for speaker detection.")
    #expect(try Data(contentsOf: run.speakers) == before)
    #expect(try Data(contentsOf: transcript) == transcriptBytes)
    #expect(await http.requests.count == 2)
    model.providers = ProvidersFile(providers: [])
    #expect(model.supportsCloudSpeakers(item))
    model.lastError = nil
    #expect(await !model.detectSpeakersAfterTranscription(sessionURL: session, runID: "run", themUtterances: 1))
    #expect(model.lastError == nil)
    model.detectSpeakersAgain(item: item)
    #expect(model.lastError == "Couldn't detect speakers: No API key.")
}

@Test func cloudSpeakersConfirmationRequiresExistingNames() {
    #expect(!SpeakerMenuDecision.needsConfirmation(names: nil))
    #expect(!SpeakerMenuDecision.needsConfirmation(names: [:]))
    #expect(SpeakerMenuDecision.needsConfirmation(names: ["a": "Ala"]))
}
