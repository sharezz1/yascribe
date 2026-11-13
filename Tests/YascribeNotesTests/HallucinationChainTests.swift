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
        // N4 „Keep this text”: okno, transcript.json i corrected.json; przeżywa restart i ponowne scalenie.
        var correctedText = repaired
        for i in correctedText.utterances.indices where !correctedText.utterances[i].excludedFromNotes { correctedText.utterances[i].text += " (poprawione)" }
        try JSONFile.save(CorrectedTranscript(transcript: correctedText, model: "m", batches: 1, failedBatches: 0, rejectedLines: 0), to: run.corrected)
        // Wiersz w UI: tekst po Replacement może być inny, klucz to mówca i czasy.
        var shown = try #require(repaired.utterances.first { $0.speaker == .them && $0.suspectedHallucination == true })
        shown.text = "inny tekst po Replacement"
        // R03: nieczytelne chunks/ (plik zamiast katalogu) to błąd, nie „brak okien” — transcript i corrected bez zmian.
        let chunks = run.url.appendingPathComponent("chunks"), aside = run.url.appendingPathComponent("chunks-aside")
        try FileManager.default.moveItem(at: chunks, to: aside)
        try Data().write(to: chunks)
        let transcriptBytes = try Data(contentsOf: run.transcript), correctedBytes = try Data(contentsOf: run.corrected)
        #expect(throws: (any Error).self) { try run.keepSuspectedEverywhere(shown, session: dir) }
        #expect(try Data(contentsOf: run.transcript) == transcriptBytes)
        #expect(try Data(contentsOf: run.corrected) == correctedBytes)
        try FileManager.default.removeItem(at: chunks)
        try FileManager.default.moveItem(at: aside, to: chunks)
        try run.keepSuspectedEverywhere(shown, session: dir)
        // Restart: ponowny odczyt z dysku.
        let reread = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: run.transcript))
        let kept = reread.utterances.filter { $0.suspectedHallucination == false }
        #expect(kept.count == 1 && kept[0].speaker == .them && kept[0].start == shown.start && !kept[0].excludedFromNotes)
        #expect(reread.utterances.filter { $0.suspectedHallucination == true }.count == 3) // pozostałe okna nietknięte
        #expect(NotePromptBuilder.transcriptLines(reread).count == 3)
        let correctedReread = try #require(CorrectedTranscript.load(session: dir, runID: id))
        #expect(correctedReread.transcript.utterances.filter { $0.suspectedHallucination == false }.map(\.start) == [shown.start])
        #expect(NotePromptBuilder.transcriptLines(correctedReread.transcript).count == 3)
        // Ponowne scalenie (wznowienie / „Retry Failed Parts”) bez ASR daje dokładnie zapisany transkrypt.
        let next = try await TranscriptionRunner(session: dir, runID: id, snapshot: snapshot, client: cached, repetitionFilterEnabled: false).run()
        #expect(await cached.calls == 1)
        #expect(next == reread)
        #expect(next.utterances.contains { $0.text == "Dla mnie to nie jest łatwe." && $0.suspectedHallucination == false && !$0.excludedFromNotes })
        #expect(NotePromptBuilder.transcriptLines(next).count == 3)
    }
}
