import Darwin
import Foundation
import YascribeLocalASR
import YascribeProviders
import YascribeTranscription

extension CLI {
    /// Kalibracja progów profili głosów (TASK-117): odciski mówców z bieżących `speakers.json` i macierz cosinusów.
    /// `voices <katalog sesji>… [--model diarizer|campplus]`. Niczego nie zapisuje; model musi być już pobrany w katalogu danych.
    /// Nie uruchamiać razem z wykrywaniem mówców w aplikacji (wspólny TMPDIR plików PCM).
    static func voices(_ args: [String]) async throws {
        func fail(_ message: String, code: Int32) -> Never {
            FileHandle.standardError.write(Data("\(message)\n".utf8)); exit(code)
        }
        guard let model = VoiceModel(cliName: value(args, "--model") ?? "diarizer") else { fail("--model: diarizer albo campplus", code: 64) }
        let sessions = args.indices.filter { i in !args[i].hasPrefix("--") && !(i > 0 && valued.contains(args[i - 1])) }.map { URL(fileURLWithPath: args[$0]) }
        guard !sessions.isEmpty else { print(usage); exit(64) }
        let root = YascribePaths.fromEnvironment().root
        let embedder = VoiceEmbedder(diarizerStore: DiarizerModelStore(directory: DiarizerModelStore.directory(root: root)),
                                     campPlusStore: CampPlusManifest.store(root: root))
        var rows: [(label: String, seconds: Double, vector: [Float])] = []
        for session in sessions {
            guard let runID = RunDirectory.latestRunID(in: session) else { fail("\(session.path): brak przebiegu (runs/)", code: 1) }
            let run = RunDirectory(session: session, runID: runID)
            guard let diarization = try JSONFile.load(SpeakerDiarization?.self, from: run.speakers, default: nil) else {
                fail("\(run.speakers.path): brak speakers.json", code: 1)
            }
            let speech = VoiceSpans.speech(diarization).filter { $0.value.seconds >= VoiceMatcher.minSeconds && !$0.value.spans.isEmpty }
            if speech.isEmpty { FileHandle.standardError.write(Data("\(session.lastPathComponent): brak mówców ≥ 20 s z czasem toru\n".utf8)); continue }
            let vectors = try await embedder.embed(systemTrack: session.appendingPathComponent("system.caf"), speakers: speech.mapValues(\.spans), model: model)
            for key in vectors.keys.sorted() {
                let name = diarization.names?[key].map { "(\($0))" } ?? ""
                rows.append(("\(session.lastPathComponent.suffix(12)):\(key)\(name)", speech[key]!.seconds, vectors[key]!))
            }
        }
        print("model: \(model.id)")
        for (i, row) in rows.enumerated() { print("[\(i)] \(row.label) \(Int(row.seconds)) s") }
        print("     " + rows.indices.map { String(format: "%6d", $0) }.joined())
        for (i, row) in rows.enumerated() {
            print(String(format: "[%2d] ", i) + rows.map { String(format: "%6.3f", VoiceVectors.cosine(row.vector, $0.vector)) }.joined())
        }
    }
}
