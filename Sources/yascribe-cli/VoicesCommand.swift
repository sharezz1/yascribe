import Darwin
import Foundation
import YascribeLocalASR
import YascribeNotes
import YascribeProviders
import YascribeSessionFormat
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
        if args.contains("--merge-dry-run") {
            guard model == .diarizer else { fail("--merge-dry-run działa tylko z modelem mówców (diarizer)", code: 64) }
            for session in sessions { try await mergeDryRun(session: session, embedder: embedder) }
            return
        }
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

    /// TASK-126: wszystkie grupy z czystą mową ≥ 1 s (bez progu 20 s), cosinusy i plan łączenia dla siatki progów.
    private static func mergeDryRun(session: URL, embedder: VoiceEmbedder) async throws {
        guard let runID = RunDirectory.latestRunID(in: session),
              let diarization = try JSONFile.load(SpeakerDiarization?.self, from: RunDirectory(session: session, runID: runID).speakers, default: nil) else {
            FileHandle.standardError.write(Data("\(session.path): brak speakers.json\n".utf8)); return
        }
        // Plik mógł już być złączony: liczymy na pierwotnych grupach.
        var original = diarization
        original.segments = diarization.segments.map { var s = $0; s.speaker = s.originalSpeaker ?? s.speaker; s.originalSpeaker = nil; return s }
        original.merges = nil
        let speech = VoiceSpans.speech(original).filter { !$0.value.spans.isEmpty }
        let attendees = NotesStore(session: session).readMeta().calendarEvent?.attendees?.count ?? 0
        let expected = SpeakerMerge.expected(attendees: attendees)
        print("== \(session.lastPathComponent): grup \(Set(original.segments.map(\.speaker)).count), z odciskiem \(speech.count), oczekiwano \(expected.map(String.init) ?? "-")")
        let vectors = try await embedder.embed(systemTrack: SessionDirectory(url: session).trackURL("system"), speakers: speech.mapValues(\.spans), model: .diarizer)
        let groups = vectors.keys.sorted().compactMap { key in
            speech[key].map { SpeakerMerge.Group(key: key, vector: vectors[key]!, seconds: $0.seconds, name: diarization.names?[diarization.currentKey(key)]) }
        }
        for (i, g) in groups.enumerated() { print(String(format: "[%2d] %@ %.0f s %@", i, g.key, g.seconds, g.name.map { "(\($0))" } ?? "")) }
        print("     " + groups.indices.map { String(format: "%6d", $0) }.joined())
        for (i, a) in groups.enumerated() {
            print(String(format: "[%2d] ", i) + groups.map { String(format: "%6.3f", VoiceVectors.cosine(a.vector, $0.vector)) }.joined())
        }
        for threshold in [0.70, 0.75, 0.80, 0.85] {
            for hint in [nil, expected] where hint == nil || expected != nil {
                let plan = SpeakerMerge.plan(groups, expected: hint, mergeThreshold: threshold)
                let left = Set(groups.map { plan[$0.key] ?? $0.key }).count
                let text = plan.sorted { $0.key < $1.key }.map { "\($0.key)→\($0.value)" }.joined(separator: " ")
                print(String(format: "próg %.2f%@: zostaje %d grup; %@", threshold, hint == nil ? "" : " +kalendarz", left, text))
            }
        }
    }
}
