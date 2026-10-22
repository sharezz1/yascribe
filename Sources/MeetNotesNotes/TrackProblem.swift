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
        tracks.compactMap { neverStarted($0, among: tracks) ?? classify($0, transcript: transcript) }
    }

    /// Tor, który nie dostał ani jednej próbki (`stalledNs`, 0 klatek), gdy inny tor nagrał dźwięk: nic nie grało w głośnikach
    /// (np. dyktowanie do mikrofonu), więc to informacja, nie ostrzeżenie. Odmowa uprawnienia zostaje ostrzeżeniem.
    static func neverStarted(_ t: SessionSummary.Track, among tracks: [SessionSummary.Track]) -> TrackProblem? {
        guard t.permissionDenied == nil, t.failure?.hasPrefix("stalled") == true, t.frames == 0,
              tracks.contains(where: { $0.id != t.id && $0.failure == nil && ($0.frames ?? 0) > 0 }) else { return nil }
        let system = t.id == SessionSummary.timelineTrackID
        let name = system ? "System audio" : "Microphone"
        let lower = system ? "system audio" : "the microphone"
        // Tory na tym samym urządzeniu Bluetooth: tryb rozmowy potrafi zablokować dźwięk systemowy (faza 2.0.2, sesja 08f6).
        let other = tracks.first { $0.id != t.id && ($0.frames ?? 0) > 0 }
        let sameHeadset = other.map { DeviceUID.same(t.deviceUIDs.last ?? "", $0.deviceUIDs.last ?? "") } ?? false
        let headset = sameHeadset
            ? " Both tracks were on the same headset; in call mode it can block system audio. Use the Mac's microphone or speakers."
            : ""
        return TrackProblem(trackID: t.id, isWarning: false, name: name, line: "\(name) captured nothing.",
                            detail: "\(name) never received any sound, which is what happens when nothing is playing on this Mac. "
                                + "The other track was recorded normally. If you expected \(lower), check System Settings → "
                                + "Privacy & Security.\(headset)")
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
        guard let reason = t.failure else { return wrongSpeed(t, name: name) }
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

    /// Zegar toru poszedł inaczej niż deklarowana częstotliwość (słuchawki Bluetooth zmieniające tryb): mowa jest przyspieszona
    /// albo spowolniona, a transkrypt może jej nie rozpoznać (sesja ec0b: 6 słów zamiast 1832). Neutralne wobec przyczyny.
    static func wrongSpeed(_ t: SessionSummary.Track, name: String) -> TrackProblem? {
        guard let ratio = t.rateMismatch else { return nil }
        let devices = t.deviceUIDs.isEmpty ? "" : " Devices: \(t.deviceUIDs.joined(separator: ", "))."
        return TrackProblem(trackID: t.id, isWarning: true, name: name, line: "\(name) was recorded at the wrong speed.",
                            detail: "The track's clock ran at \(Int((ratio * 100).rounded()))% of the declared rate, so its audio is sped up or "
                                + "slowed down and speech may be missing from the transcript. Bluetooth headphones switching modes can "
                                + "cause this. Record again with the Mac's microphone or speakers if it matters.\(devices)")
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
            // Oś sesji zaczyna pierwsza próbka dźwięku systemowego, która potrafi przyjść długo po starcie mikrofonu
            // (odbiór 2026-10-19: 28 s). Okres zakończony przed zerem osi nie dotyczy niczego w transkrypcie — bez linii;
            // przekraczający zero zaczyna się od 0:00 (decyzja użytkownika 2026-10-19).
            return (t.mutes ?? []).compactMap { m in
                if let end = m.endFrame, at(end) <= 0 { return nil }
                let start = max(0, at(m.frameIndex))
                let line = m.endFrame.map { "\(name) muted \(TrackProblem.clock(start))–\(TrackProblem.clock(at($0)))" }
                    ?? "\(name) muted from \(TrackProblem.clock(start)) to the end"
                return MuteNote(trackID: t.id, start: start, line: line)
            }
        }
        .sorted { $0.start < $1.start }
    }
}
