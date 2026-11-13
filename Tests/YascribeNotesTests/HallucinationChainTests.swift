import Foundation
import Testing
import YascribeProviders
import YascribeRecording
import YascribeSessionFormat
@testable import YascribeTranscription
@testable import YascribeNotes

private actor WindowClient: TranscriptionClient {
    nonisolated let provider = Provider(name: "Local test", baseURL: Provider.fluidAudioBaseURL, kind: .fluidAudio)
    var calls = 0
    func transcribe(wav: Data, model: String, language: LanguageCode?, shape: ASRShape) -> TranscriptionResult {
        calls += 1
        // Ostatnie okno `system` = pierwsze okno `mic_raw`: wyciek kontekstu między torami oznaczyłby mic_raw-0.
        return .init(text: "Dla mnie to nie jest łatwe.", words: [])
    }
}

@Suite struct HallucinationChainTests {
    @Test func savedWindowsResumeWithoutASRFlagPerTrackAndStayCompleteButOutsideNotes() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let rate = 16_000, timebase = Timebase(numer: 1, denom: 1)
        var samples = [Int16](repeating: 0, count: 22 * rate)
        for start in [0, 10, 20] {
            samples.replaceSubrange((start*rate)..<((start+1)*rate), with: repeatElement(Int16(4_000), count: rate))
        }
        let sources = ["system", "mic_raw"].map {
            FileSource(trackID: $0, samples: samples, sampleRate: 16_000, channels: 1,
                       startHostTime: $0 == "system" ? 1_000_000_000 : 31_000_000_000, timebase: timebase, chunkFrames: 1_600)
        }
        try SessionRecorder(directory: dir, sources: sources, conditions: [], clock: ManualHostClock(), timebase: timebase, zeroWatch: [:]).start()
        let stub = WindowClient()
        let preset = Preset(name: "test", language: .polish, asr: RoleAssignment(providerID: stub.provider.id, model: "test"))
        let snapshot = try RunSnapshot(preset: preset, provider: stub.provider, probe: nil)
        var crosstalk = CrosstalkFilter(); crosstalk.correlationThreshold = 2
        let id = "2026-11-13T00-00-00Z-aaaa"
        let run = RunDirectory(session: dir, runID: id)
        let first = try await TranscriptionRunner(session: dir, runID: id, snapshot: snapshot, client: stub,
                                                maxChunkSeconds: 12, maxSourceSpan: 3, repetitionFilterEnabled: true, crosstalk: crosstalk, offlineAEC: nil).run()
        #expect(await stub.calls == 6)
        #expect(first.utterances.filter { $0.suspectedHallucination == true }.count == 4)
        let cached = WindowClient()
        let flagged = try await TranscriptionRunner(session: dir, runID: id, snapshot: snapshot, client: cached,
                                                   repetitionFilterEnabled: false).run()
        #expect(await cached.calls == 0)
        #expect(flagged == first)
        #expect(flagged.failedChunks.isEmpty && flagged.utterances.count == 6)
        #expect(flagged.utterances.filter { $0.suspectedHallucination == true }.count == 4)
        for track in ["system", "mic_raw"] {
            let first = try JSONDecoder().decode(ChunkResult.self, from: Data(contentsOf: run.chunk(track, 0)))
            let second = try JSONDecoder().decode(ChunkResult.self, from: Data(contentsOf: run.chunk(track, 1)))
            #expect(first.suspectedHallucination == nil) // kontekst nie przechodzi z system na mic
            #expect(second.suspectedHallucination == true && !second.result.text.isEmpty)
        }
        let fromDisk = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: run.transcript))
        #expect(fromDisk == flagged)
        #expect(NotePromptBuilder.transcriptLines(fromDisk).count == 2)
        #expect(NotePromptBuilder.transcriptLines(fromDisk).joined().contains("Dla mnie"))
        let prompt = try #require(NotePromptBuilder.build(template: .standard, transcript: fromDisk, myNotes: "", context: "", notesLanguage: .polish))
        #expect(prompt.user.contains("Dla mnie"))
        #expect(AudioRetention.transcriptionFinished(dir))
        let meta = try #require(try JSONFile.load(RunMetadata?.self, from: run.metadata, default: nil))
        #expect(meta.requestCount == 0 && meta.failedChunkCount == 0 && meta.chunkCount == 6)
        // Brakujące okno musi porównać świeży wynik z poprzednikiem odczytanym z cache.
        try FileManager.default.removeItem(at: run.chunk("system", 1))
        let repaired = try await TranscriptionRunner(session: dir, runID: id, snapshot: snapshot, client: cached, repetitionFilterEnabled: false).run()
        #expect(await cached.calls == 1)
        #expect(repaired == flagged)
        // N4 zapisze false w wyniku okna i wersjach transkryptu; kolejne scalenie nie przywraca flagi.
        var restored = try JSONDecoder().decode(ChunkResult.self, from: Data(contentsOf: run.chunk("system", 2)))
        restored.suspectedHallucination = false
        try JSONFile.save(restored, to: run.chunk("system", 2))
        let next = try await TranscriptionRunner(session: dir, runID: id, snapshot: snapshot, client: cached, repetitionFilterEnabled: false).run()
        #expect(await cached.calls == 1)
        #expect(next.utterances.contains { $0.text == "Dla mnie to nie jest łatwe." && $0.suspectedHallucination == false && !$0.excludedFromNotes })
    }
}
