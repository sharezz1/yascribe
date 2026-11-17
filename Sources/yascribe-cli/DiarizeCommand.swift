import Darwin
import Foundation
import YascribeLocalASR
import YascribeProviders
import YascribeSessionFormat
import YascribeTranscription

extension CLI {
    /// Diaryzacja toru `system` przebiegu → `speakers.json` (TASK-22 T3, odbiór silnika przed UI).
    /// `diarize <katalog sesji> [--run ID] [--sensitivity low|medium|high] [--download]`. Model pobiera tylko `--download`.
    static func diarize(_ args: [String]) async throws {
        func fail(_ message: String, code: Int32) -> Never {
            FileHandle.standardError.write(Data("\(message)\n".utf8)); exit(code)
        }
        SpeakerDiarizer.sweepStaleTemporaryFiles(now: Date()) // przed walidacją: wczesny błąd też sprząta stare PCM (R06)
        let session = URL(fileURLWithPath: try positional(args, 0))
        guard FileManager.default.fileExists(atPath: SessionDirectory(url: session).journalURL.path) else {
            fail("\(session.path): to nie katalog sesji (brak journal.jsonl)", code: 64)
        }
        let sensitivity: SpeakerSensitivity
        do { sensitivity = try SpeakerSensitivity.parse(value(args, "--sensitivity")) } catch { fail("\(error.localizedDescription)", code: 64) }
        let runOption = value(args, "--run")
        if let id = runOption, !RunDirectory.isValid(runID: id) { fail("zły identyfikator przebiegu: \(id)", code: 64) }
        guard let runID = runOption ?? RunDirectory.latestRunID(in: session) else { fail("\(session.path): brak przebiegu (runs/)", code: 1) }
        let run = RunDirectory(session: session, runID: runID)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: run.url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            fail("\(run.url.path): brak przebiegu", code: 1)
        }

        // Transkrypt czytany przed diaryzacją: uszkodzony plik kończy komendę bez nadpisania poprzedniego speakers.json.
        let transcript = try JSONFile.load(Transcript?.self, from: run.transcript, default: nil)
        let mistral = args.contains("--mistral")
        let store = DiarizerModelStore()
        if !mistral { do {
            if try DiarizerModelGate.decide(status: store.status(), download: args.contains("--download")) == .download {
                let line = PercentLine(label: "model")
                try await store.download { done, total in line.update(Double(done) / Double(max(total, 1))) }
                FileHandle.standardError.write(Data("\n".utf8))
                guard store.status() == .ready else { fail("model nie jest kompletny po pobraniu: \(store.directory.path)", code: 1) }
            }
        } catch let e as DiarizerModelStoreError { fail(e.message, code: 1) } }

        let summary = try SessionDirectory(url: session).summarize()
        guard let track = summary.tracks.first(where: { $0.id == "system" }), let frames = track.frames, track.sampleRate > 0 else {
            fail("\(session.path): brak toru system", code: 1)
        }
        let trackSeconds = Double(frames) / track.sampleRate
        let line = PercentLine(label: "mówcy")
        let started = Date()
        let segments: [MistralDiarization.Segment]
        if mistral {
            guard let key = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"], !key.isEmpty else { fail("Brak MISTRAL_API_KEY", code: 64) }
            let metadata = try JSONFile.load(RunMetadata?.self, from: run.metadata, default: nil)
            let input = try JSONFile.load(RunInput?.self, from: run.input, default: nil)
            let language = metadata != nil ? metadata?.snapshot.language : input?.snapshot.language
            segments = try await MistralDiarization.run(track: SessionDirectory(url: session).trackURL("system"),
                client: MistralDiarizationClient(key: key), language: language) { part, total, tokens in
                    print("część \(part)/\(total): \(tokens) tokenów")
                }
        } else {
            segments = try await SpeakerDiarizer(store: store).run(systemTrack: SessionDirectory(url: session).trackURL("system"),
                                                                      sensitivity: sensitivity) { line.update($0) }
        }
        let elapsed = Date().timeIntervalSince(started)
        FileHandle.standardError.write(Data("\n".utf8))

        let diarization = SpeakerDiarization.fromTrack(segments: segments, clock: SessionClock(summary: summary),
                                                       modelPin: mistral ? MistralDiarization.pin : DiarizerManifest.pin, sensitivity: mistral ? nil : sensitivity,
                                                       audioFingerprint: SpeakerDiarization.audioFingerprint(session: session), createdAt: Date())
        try JSONFile.save(diarization, to: run.speakers, createParents: false)

        print("przebieg: \(runID)")
        if !mistral { print("czułość: \(sensitivity.rawValue) (Fa \(sensitivity.fa), Fb \(sensitivity.fb))") }
        print(String(format: "czas: %.1f s, tor %.1f s, RTF %.4f, szczyt RSS %@", elapsed, trackSeconds, elapsed / max(trackSeconds, 0.001),
                     peakResidentMegabytes().map { String(format: "%.0f MB", $0) } ?? "?"))
        let seconds = diarization.secondsBySpeaker
        print("klastry: \(seconds.count), okruchy < \(Int(diarization.minClusterSeconds ?? 10)) s: \(diarization.crumbCount)")
        print("sekundy mowy: " + seconds.map { String(format: "%@ %.1f", $0.speaker, $0.seconds) }.joined(separator: ", "))
        if let transcript {
            let counts = SpeakerLabelCounts(transcript: transcript, diarization: diarization)
            print("litery: \(counts.letters), wypowiedzi them: \(counts.them), bez etykiety: \(counts.unlabeled)")
        }
    }

    /// Szczyt rezydentnej pamięci procesu (`mach_task_basic_info.resident_size_max`).
    static func peakResidentMegabytes() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.resident_size_max) / 1_048_576 : nil
    }

    /// Postęp na stderr: linia nadpisywana, tylko przy zmianie pełnego procentu (callbacki idą tysiącami).
    final class PercentLine: @unchecked Sendable {
        private let lock = NSLock()
        private var last = -1
        private let label: String
        init(label: String) { self.label = label }

        func update(_ fraction: Double) {
            let percent = Int((fraction * 100).rounded(.down))
            lock.lock(); defer { lock.unlock() }
            guard percent != last else { return }
            last = percent
            FileHandle.standardError.write(Data(String(format: "\r%@ %3d%%", label, percent).utf8))
        }
    }
}
