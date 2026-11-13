import Foundation
import YascribeProviders
import YascribeSessionFormat

/// „Keep this text” (N4): trwałe przywrócenie wypowiedzi oznaczonej przez `RepetitionFilter`. Nośnik to istniejące
/// `suspectedHallucination == false` (bez nowego pola, E6): runner ocenia tylko `nil`, więc ponowne scalenie przy wznowieniu
/// i „Retry Failed Parts” zostawia `false`, a `excludedFromNotes` przestaje wykluczać.
public extension Transcript {
    /// Klucz to mówca i czasy, nie tekst: wiersz w UI ma już Replacement, a wersja poprawiona inny tekst. Zwraca, czy coś zmienił.
    @discardableResult
    mutating func keepSuspected(_ u: Utterance) -> Bool {
        var changed = false
        for i in utterances.indices where utterances[i].suspectedHallucination == true
            && utterances[i].speaker == u.speaker && utterances[i].start == u.start && utterances[i].end == u.end {
            utterances[i].suspectedHallucination = false
            changed = true
        }
        return changed
    }
}

public extension RunDirectory {
    /// Przywraca okna źródłowe wypowiedzi (`chunks/*.json`) i samą wypowiedź w `transcript.json`.
    /// Okno źródłowe: oznaczone, tego samego mówcy, a jego rozpiętość na osi sesji przecina się z wypowiedzią (ściśle,
    /// żeby sąsiednie okno stykające się granicą zostało nietknięte). Zwraca liczbę przywróconych okien.
    @discardableResult
    func keepSuspected(_ u: Utterance, session: URL) throws -> Int {
        let summary = try SessionDirectory(url: session).summarize()
        let clock = SessionClock(summary: summary)
        let tracks = Set(TranscriptionRunner.tracks(in: summary).filter { $0.speaker == u.speaker }.map(\.id))
        let files = (try? FileManager.default.contentsOfDirectory(at: url.appendingPathComponent("chunks"), includingPropertiesForKeys: nil)) ?? []
        var restored = 0
        for file in files where file.pathExtension == "json" {
            guard var r = try JSONFile.load(ChunkResult?.self, from: file, default: nil),
                  r.suspectedHallucination == true, tracks.contains(r.track) else { continue }
            let start = clock.sessionSeconds(track: r.track, trackSeconds: r.chunk.sourceStartSeconds)
            let end = clock.sessionSeconds(track: r.track, trackSeconds: r.chunk.sourceEndSeconds)
            guard start < u.end, end > u.start else { continue }
            r.suspectedHallucination = false
            try JSONFile.save(r, to: file)
            restored += 1
        }
        if var t = try JSONFile.load(Transcript?.self, from: transcript, default: nil), t.keepSuspected(u) {
            try JSONFile.save(t, to: transcript)
        }
        return restored
    }
}
