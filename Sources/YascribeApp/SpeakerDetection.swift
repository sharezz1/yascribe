import Foundation
import YascribeProviders

/// „Czy diaryzować po transkrypcji” (TASK-22 D7), wydzielone z `AppModel.run`, bo `AppModel` nie da się zbudować w teście.
enum SpeakerDetectionDecision {
    /// Brak obsługi mówców, toru `system` albo wypowiedzi „them” = nie.
    /// `hasSystemTrack` czyta dziennik, więc woła się go dopiero po tanich warunkach (F04).
    nonisolated(nonsending) static func shouldRun(capable: Bool, themUtterances: Int, hasSystemTrack: () async -> Bool) async -> Bool {
        guard capable, themUtterances > 0 else { return false }
        return await hasSystemTrack()
    }
}

enum SpeakerDetectionWork {
    /// Czeka na faktyczny koniec pracy; anulowanie wywołującego (także sprzed wywołania) anuluje pracę (R05, F02).
    static func result<T: Sendable>(of work: Task<T, any Error>) async -> Result<T, any Error> {
        await withTaskCancellationHandler { await work.result } onCancel: { work.cancel() }
    }
}

/// Bilet jednej operacji wykrywania mówców (spec §8 R05): nowsza operacja tej samej sesji dostaje wyższą generację.
struct SpeakerDetectionTicket: Equatable {
    var session: String
    var runID: String
    var generation: Int

    /// Zapis `speakers.json` tylko z bieżącego, nieanulowanego biletu: stary przebieg nie nadpisuje nowszego.
    static func mayWrite(_ ticket: SpeakerDetectionTicket, current: SpeakerDetectionTicket?, cancelled: Bool) -> Bool {
        !cancelled && ticket == current
    }
}

/// Tekst błędu wykrywania mówców: komunikat serwera, gdy go podał (np. ElevenLabs `quota_exceeded` przychodzi jako 401,
/// więc samo „Invalid API key.” by kłamało); inaczej opis jak przy sprawdzaniu dostawcy.
enum SpeakerDetectionError {
    static func text(_ error: Error) -> String {
        if case let .http(_, body)? = error as? ProviderError,
           let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] {
            for field in ["detail", "error"] {
                if let message = (json[field] as? [String: Any])?["message"] as? String, !message.isEmpty { return message }
            }
        }
        return ProviderCheck.describe(error)
    }
}
