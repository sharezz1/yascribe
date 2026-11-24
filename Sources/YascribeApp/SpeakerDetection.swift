import Foundation
import YascribeProviders
import YascribeLocalASR
import YascribeTranscription

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
        if let error = error as? DiarizerModelStoreError { return error.displayMessage ?? error.message }
        if let error = error as? CloudDiarizationError { return error.displayMessage }
        if case let .http(_, body)? = error as? ProviderError,
           let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] {
            for field in ["detail", "error"] {
                if let message = (json[field] as? [String: Any])?["message"] as? String, !message.isEmpty { return message }
            }
        }
        return ProviderCheck.describe(error)
    }
}

/// Decyzje profili głosów (TASK-117), wydzielone z `AppModel`, żeby dało się je sprawdzić bez modelu.
enum VoiceLearning {
    /// Powód, dla którego nie da się zapamiętać głosu tego mówcy; `nil` = można.
    static func refusal(hasAudio: Bool, hasTrackTimes: Bool, seconds: Double, modelReady: Bool) -> String? {
        if !hasAudio { return String(localized: "This meeting's audio was deleted, so the voice can't be remembered.") }
        if !hasTrackTimes { return String(localized: "Detect speakers again on this Mac to remember this voice.") }
        if seconds < VoiceMatcher.minSeconds { return String(localized: "This speaker talks for less than 20 seconds, so the voice can't be remembered.") }
        if !modelReady { return String(localized: "The voice model is not downloaded. Download it in Settings.") }
        return nil
    }

    /// Pytamy o zgodę tylko raz (`nil`) i tylko wtedy, gdy nauka faktycznie by się udała.
    static func shouldAsk(consent: Bool?, refusal: String?) -> Bool { consent == nil && refusal == nil }

    /// Odcisk trafia do pliku wyłącznie przy zgodzie aktualnej w chwili zapisu (zgoda mogła zniknąć w trakcie liczenia).
    static func mayStore(consent: Bool?) -> Bool { consent == true }

    /// Ten sam mówca nadal nosi to ręczne imię w tym samym wykryciu (nie zmieniono go ani nie wykryto mówców ponownie).
    static func stillNamed(_ d: SpeakerDiarization?, key: String, name: String, digest: String) -> Bool {
        guard let d, d.segmentsDigest == digest, d.voiceMatches?[key] == nil, let current = d.names?[key] else { return false }
        return current.caseInsensitiveCompare(name) == .orderedSame
    }
}

/// Mówca do zapamiętania po zgodzie (okno zgody w spotkaniu).
struct VoiceLearnRequest: Equatable {
    var sessionURL: URL
    var runID: String
    var key: String
    var name: String
    var diarization: SpeakerDiarization
}

/// Wszystko, czego potrzebuje rozpoznawanie poza MainActor; `embed` = `VoiceEmbedder.embed` albo atrapa testu.
struct VoiceContext: Sendable {
    typealias Embed = @Sendable (URL, [String: [ClosedRange<Double>]], VoiceModel) async throws -> [String: [Float]]
    var model: VoiceModel
    var profiles: [VoiceProfile]
    var embed: Embed

    /// Odciski mówców ≥ 20 s, dopasowanie i imiona. Błąd liczenia nie psuje wykrycia: etykiety zostają, wraca komunikat.
    func recognize(_ d: SpeakerDiarization, systemTrack: URL) async throws -> (SpeakerDiarization, String?) {
        let speech = VoiceSpans.speech(d).filter { $0.value.seconds >= VoiceMatcher.minSeconds && !$0.value.spans.isEmpty && !d.namedKeys.contains($0.key) }
        guard !speech.isEmpty else { return (d, nil) }
        do {
            let vectors = try await embed(systemTrack, speech.mapValues(\.spans), model)
            let speakers = vectors.compactMap { key, vector in speech[key].map { VoiceMatcher.Speaker(key: key, vector: vector, seconds: $0.seconds) } }
            let matches = VoiceMatcher.match(speakers: speakers, profiles: profiles, model: model.id, rejected: d.voiceRejected ?? [:], skip: d.namedKeys)
            return (d.applying(matches, names: Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.name) }), model: model.id), nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (d, String(localized: "Couldn't recognize voices: \(SpeakerDetectionError.text(error))"))
        }
    }
}
