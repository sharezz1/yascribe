import Foundation
import MeetNotesSessionFormat
import MeetNotesTranscription

/// Problem toru nagrania na liście i w widoku spotkania (odbiór 2026-10-16, poprawka 6).
///
/// `allZerosNs` w dzienniku znaczy tylko „pierwsze N s toru to cyfrowe zera" — rejestrator przestaje potem patrzeć,
/// a tor nagrywa dalej tak samo przy odmowie uprawnienia jak przy zwykłej ciszy (zegar i liczba klatek rosną w obu
/// przypadkach). Dowodem, że dźwięk przyszedł później, jest transkrypt: bramka energetyczna nie przepuszcza zer do ASR,
/// więc każda wypowiedź mówcy tego toru znaczy, że tor nie był pusty. Bez transkryptu — nie wiadomo, ostrzeżenie zostaje.
public struct TrackProblem: Equatable, Sendable {
    public var trackID: String
    /// `false` = sama informacja (bez ⚠ na liście).
    public var isWarning: Bool
    /// „System audio" / „Microphone".
    public var name: String
    /// Jedno zdanie: linia nad transkryptem.
    public var line: String
    /// Wyjaśnienie zwykłym językiem: co, kiedy, czy nagranie trwało dalej (popover w widoku spotkania).
    public var detail: String

    public static func of(tracks: [SessionSummary.Track], transcript: Transcript?) -> [TrackProblem] {
        tracks.compactMap { classify($0, transcript: transcript) }
    }

    static func classify(_ t: SessionSummary.Track, transcript: Transcript?) -> TrackProblem? {
        let system = t.id == SessionSummary.timelineTrackID
        let name = system ? "System audio" : "Microphone"
        let lower = system ? "system audio" : "the microphone"
        let total = t.frames.flatMap { f in t.sampleRate > 0 ? " Recorded \(clock(Double(f) / t.sampleRate)) in total." : nil } ?? ""
        if let p = t.permissionDenied {
            return TrackProblem(trackID: t.id, isWarning: true, name: name, line: "\(name) wasn't allowed — this track is empty.",
                                detail: "macOS didn't let MeetNotes record \(lower) (\(p)). Allow it in System Settings → "
                                    + "Privacy & Security, then record again.")
        }
        guard let reason = t.failure else { return nil }
        guard reason.hasPrefix("allZeros") else {
            return TrackProblem(trackID: t.id, isWarning: true, name: name, line: "\(name) had a problem: \(reason).",
                                detail: "The \(lower) track reported “\(reason)” while recording. What it captured is kept.\(total)")
        }
        let seconds = Int(reason.dropFirst("allZeros".count).dropLast()) ?? 60
        let window = seconds == 60 ? "first minute" : "first \(seconds) seconds"
        let who = system ? "the other side (Them)" : "you (Me)"
        // `track.audible` (od 1.5b): dźwięk przyszedł po zerach — wiadomo od razu, bez transkryptu.
        if let frame = t.audibleFrame, t.sampleRate > 0 {
            let at = clock((t.offsetSeconds ?? 0) + Double(frame) / t.sampleRate)
            return TrackProblem(trackID: t.id, isWarning: false, name: name,
                                line: "\(name) was silent for the \(window); recording continued.",
                                detail: "For the \(window), \(lower) carried only digital silence, so MeetNotes flagged it — "
                                    + "that's also how a missing permission looks. Sound started at \(at). Nothing is missing.\(total)")
        }
        // Stare sesje (bez `track.audible`): dowodem jest transkrypt.
        let heard = transcript.map { $0.utterances.contains { $0.speaker == (system ? .them : .me) } }
        switch heard {
        case true?:
            return TrackProblem(trackID: t.id, isWarning: false, name: name,
                                line: "\(name) was silent for the \(window); recording continued.",
                                detail: "For the \(window), \(lower) carried only digital silence, so MeetNotes flagged it — "
                                    + "that's also how a missing permission looks. Sound came later: the transcript has lines from "
                                    + "\(who). Nothing is missing.\(total)")
        case false?:
            return TrackProblem(trackID: t.id, isWarning: true, name: name, line: "\(name) recorded only silence.",
                                detail: "\(name) carried only digital silence from the start, and the transcript has no lines from "
                                    + "\(who). Usually MeetNotes isn't allowed to record \(lower) — check System Settings → "
                                    + "Privacy & Security.\(total)")
        case nil:
            return TrackProblem(trackID: t.id, isWarning: true, name: name, line: "\(name) was silent for the \(window).",
                                detail: "For the \(window), \(lower) carried only digital silence — that's how a missing "
                                    + "permission looks, but it can also be a quiet start. Recording continued; the transcript "
                                    + "will show whether sound came later.\(total)")
        }
    }

    static func clock(_ s: Double) -> String {
        let s = max(0, s)
        let i = Int(s)
        return i >= 3600 ? String(format: "%d:%02d:%02d", i / 3600, i / 60 % 60, i % 60) : String(format: "%d:%02d", i / 60, i % 60)
    }
}

/// Okres wyciszenia toru z pigułki jako linia transkryptu: „Microphone muted 0:05–0:12” (macos.md §11.5).
/// Liczony z podsumowania sesji, nie z `Transcript` — transkrypcja zostaje bez zmian.
public struct MuteNote: Equatable, Sendable {
    public var trackID: String
    /// Sekundy na osi sesji (jak `Utterance.start`) — do ułożenia linii między wypowiedziami.
    public var start: Double
    public var line: String

    public static func of(summary: SessionSummary?) -> [MuteNote] {
        guard let summary else { return [] }
        let clock = SessionClock(summary: summary)
        return summary.tracks.flatMap { t -> [MuteNote] in
            guard t.sampleRate > 0 else { return [] }
            let name = t.id == SessionSummary.timelineTrackID ? "System audio" : "Microphone"
            let at = { (f: Int) in clock.sessionSeconds(track: t.id, trackSeconds: Double(f) / t.sampleRate) }
            return (t.mutes ?? []).map { m in
                let start = at(m.frameIndex)
                let line = m.endFrame.map { "\(name) muted \(TrackProblem.clock(start))–\(TrackProblem.clock(at($0)))" }
                    ?? "\(name) muted from \(TrackProblem.clock(start)) to the end"
                return MuteNote(trackID: t.id, start: start, line: line)
            }
        }
        .sorted { $0.start < $1.start }
    }
}
