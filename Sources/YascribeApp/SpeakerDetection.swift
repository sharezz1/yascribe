import Foundation
import YascribeProviders

/// „Czy diaryzować po transkrypcji” (TASK-22 D7), wydzielone z `AppModel.run`, bo `AppModel` nie da się zbudować w teście.
enum SpeakerDetectionDecision {
    /// `setting == nil` = włączone (domyślnie po pobraniu modelu). Brak modelu, toru `system` albo wypowiedzi „them” = nie.
    /// `hasSystemTrack` czyta dziennik, więc woła się go dopiero po tanich warunkach (F04).
    nonisolated(nonsending) static func shouldRun(ready: Bool, setting: Bool?, themUtterances: Int, hasSystemTrack: () async -> Bool) async -> Bool {
        guard ready, setting != false, themUtterances > 0 else { return false }
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


enum MistralSource {
    static func provider(providers: [Provider], secrets: any SecretStore) -> (Provider, String)? {
        for provider in providers where provider.api == .mistral {
            let stored = try? secrets.get(provider.id)
            #if DEBUG
            let key = stored.flatMap { $0.isEmpty ? nil : $0 } ?? ProcessInfo.processInfo.environment["YASCRIBE_MISTRAL_KEY"]
            #else
            let key = stored
            #endif
            if let key, !key.isEmpty { return (provider, key) }
        }
        return nil
    }
}
