import Foundation
import YascribeTranscription

/// Jeden status sesji dla listy (spec 1.5 §6). Kolejność warunków = kolejność cyklu życia:
/// nagrywanie → transkrypcja → korekta → tytuł → … Trwające nagranie NIGDY nie jest „Recovered".
public enum SessionStatus: Equatable, Sendable {
    case recording
    case transcribing(Double)
    case correcting
    case titling
    case recovered
    case partial(gaps: Int)
    case interrupted
    case notesReady
    case flagged(Int)
    case transcriptReady
    case correctionFailed
    case notTranscribed

    /// Czy katalog sesji to ten, który właśnie nagrywamy. Porównanie po nazwie katalogu: URL z `contentsOfDirectory`
    /// bywa zapisany z ukośnikiem na końcu, a URL zbudowany przez `appendingPathComponent` — bez.
    public static func isRecording(_ session: URL, recordingDirectory: URL?) -> Bool {
        guard let recordingDirectory else { return false }
        return session.lastPathComponent == recordingDirectory.lastPathComponent
    }

    public static func of(isRecording: Bool, progress: Double?, correcting: Bool, titling: Bool, crashed: Bool,
                          transcript: Transcript?, hasRun: Bool, hasNotes: Bool, correctionFailed: Bool = false) -> SessionStatus {
        if isRecording { return .recording }
        if let p = progress, p < 1 { return .transcribing(p) }
        if correcting { return .correcting }
        if titling { return .titling }
        if crashed { return .recovered }
        if let t = transcript {
            if !t.failedChunks.isEmpty { return .partial(gaps: t.failedChunks.count) }
            if correctionFailed { return .correctionFailed } // widoczne w wierszu, dopóki użytkownik nie ponowi korekty
            if hasNotes { return .notesReady }
            if t.languageFlagCount > 0 { return .flagged(t.languageFlagCount) }
            return .transcriptReady
        }
        return hasRun ? .interrupted : .notTranscribed
    }
}

/// Czemu „Transcribe again…" jest teraz niedostępne (D13); `nil` = dostępne. Jedna bramka dla nagłówka transkryptu i stanu
/// „No transcript yet" (F6): nie zależy od transkryptu, bo po próbie bez transkryptu też trzeba móc wybrać inny model.
public enum TranscribeAgain {
    public static func blocker(audioDeletedAfterDays: Int?, transcribing: Bool, moving: Bool) -> String? {
        if let n = audioDeletedAfterDays { return "Audio was deleted after \(n) days" }
        if transcribing { return "This recording is being transcribed" }
        if moving { return "Meetings are being moved to a new folder" }
        return nil
    }
}
