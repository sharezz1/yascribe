import Foundation
import MeetNotesProviders
import MeetNotesSessionFormat

/// Wynik jednego okna, zapisany na dysk — podstawa wznawiania (P5).
public struct ChunkResult: Codable, Equatable, Sendable {
    public var track: String
    public var chunk: Chunk
    public var result: TranscriptionResult
}

/// Czas ścieżki → oś sesji przez kotwice zegara (T8), a nie nominalną częstotliwość.
public struct SessionClock: Sendable {
    public let summary: SessionSummary

    public init(summary: SessionSummary) { self.summary = summary }

    public func sessionSeconds(track: String, trackSeconds: Double) -> Double {
        guard let t = summary.tracks.first(where: { $0.id == track }) else { return trackSeconds }
        let frame = Int((trackSeconds * t.sampleRate).rounded())
        let anchor = summary.tracks.first(where: { $0.id == SessionSummary.timelineTrackID })?.firstSampleHostTime
            ?? summary.startedHostTime
        if let host = summary.hostTime(track: track, frame: frame) {
            return summary.timebase.secondsBetween(host, anchor)
        }
        return (t.offsetSeconds ?? 0) + trackSeconds
    }
}

public enum Merger {
    /// Słowa jednego mówcy z przerwą krótszą niż ta są jedną wypowiedzią.
    public static let utteranceGap = 1.2

    public static func merge(_ results: [ChunkResult], speakers: [String: Speaker], clock: SessionClock,
                             language: LanguageCode?, failures: [ChunkFailure] = []) -> Transcript {
        var utterances: [Utterance] = []
        for track in Set(results.map(\.track)).sorted() {
            let speaker = speakers[track] ?? .them
            var words: [Word] = []
            for r in results.filter({ $0.track == track }).sorted(by: { $0.chunk.index < $1.chunk.index }) {
                if let ws = r.result.words, !ws.isEmpty {
                    for w in ws {
                        let s = clock.sessionSeconds(track: track, trackSeconds: r.chunk.sourceSeconds(chunkSeconds: w.start, rate: Resampler.asrRate))
                        let e = clock.sessionSeconds(track: track, trackSeconds: r.chunk.sourceSeconds(chunkSeconds: w.end, rate: Resampler.asrRate))
                        words.append(Word(text: w.word.trimmingCharacters(in: .whitespaces), start: s, end: max(s, e)))
                    }
                } else if !r.result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let s = clock.sessionSeconds(track: track, trackSeconds: r.chunk.sourceStartSeconds)
                    let e = clock.sessionSeconds(track: track, trackSeconds: r.chunk.sourceEndSeconds)
                    utterances.append(Utterance(speaker: speaker, start: s, end: e, text: r.result.text,
                                                words: [], approximateTiming: true, languageMismatch: nil))
                }
            }
            words.sort { $0.start < $1.start }
            var group: [Word] = []
            func flush() {
                guard let f = group.first, let l = group.last else { return }
                utterances.append(Utterance(speaker: speaker, start: f.start, end: l.end,
                                            text: group.map(\.text).joined(separator: " "), words: group,
                                            approximateTiming: false, languageMismatch: nil))
                group = []
            }
            for w in words {
                if let last = group.last, w.start - last.end > utteranceGap { flush() }
                group.append(w)
            }
            flush()
        }
        for i in utterances.indices {
            let text = utterances[i].text
            if let language {
                utterances[i].languageMismatch = LanguageGuard.mismatch(text, expected: language)
            } else {
                // Auto: nie ma oczekiwanego języka, więc strażnik PL/EN milczy; tekst w większości w obcym alfabecie
                // to bełkot (spec 1.5, decyzja użytkownika 2026-10-14) — flaga i poza notatkami.
                utterances[i].languageMismatch = LanguageGuard.nonLatinScript(text)
            }
        }
        utterances.sort { $0.start < $1.start }
        return Transcript(utterances: utterances, failedChunks: failures)
    }
}
