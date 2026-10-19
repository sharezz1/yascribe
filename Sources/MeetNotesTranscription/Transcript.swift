import Foundation
import MeetNotesProviders

/// Podział „ja / oni" za darmo, z kanałów, bez modelu (rozdz. 8).
public enum Speaker: String, Codable, Sendable {
    case me
    case them
}

public struct Word: Codable, Equatable, Sendable {
    public var text: String
    /// Sekundy na osi sesji (0 = pierwsza próbka ścieżki systemowej).
    public var start: Double
    public var end: Double
}

public struct Utterance: Codable, Equatable, Sendable {
    public var speaker: Speaker
    public var start: Double
    public var end: Double
    public var text: String
    public var words: [Word]
    /// Kształt czatowy nie daje znaczników słów: czas to zakres całego okna.
    public var approximateTiming: Bool
    /// Wynik strażnika języka (P11).
    public var languageMismatch: LanguageCode?

    /// Echo z głośników: ta sama wypowiedź jest też w ścieżce „Them" (`EchoFilter`). Opcjonalne — stare pliki go nie mają.
    public var echoOfThem: Bool?

    /// Oznaczona wypowiedź (zły język albo echo) nie trafia do notatki jako fakt.
    public var excludedFromNotes: Bool { languageMismatch != nil || echoOfThem == true }
}

public struct ChunkFailure: Codable, Equatable, Sendable {
    public var track: String
    public var index: Int
    public var start: Double
    public var end: Double
    public var error: String
}

public struct Transcript: Codable, Equatable, Sendable {
    public var utterances: [Utterance]
    /// Jawne luki: okna, których nie udało się przetranskrybować (§6.4).
    public var failedChunks: [ChunkFailure]

    public var languageFlagCount: Int { utterances.filter { $0.languageMismatch != nil }.count }
    public var echoCount: Int { utterances.filter { $0.echoOfThem == true }.count }
}

/// Migawka presetu w chwili przebiegu — nie odwołanie (spec fazy 1, §8, P12).
public enum RunSnapshotError: Error, Equatable {
    case chatShapeNotForMeetings
}

public struct RunSnapshot: Codable, Equatable, Sendable {
    /// Pełny preset z chwili przebiegu — z korektą, podsumowaniem i promptami (spec §8, ChatGPT #14).
    public var preset: Preset
    public var presetID: UUID
    public var presetName: String
    public var providerID: UUID
    public var providerName: String
    public var providerBaseURL: URL
    public var model: String
    public var shape: ASRShape
    public var language: LanguageCode?
    public var languageHandling: LanguageHandling
    public var dictionaryVersion: String

    public init(preset: Preset, provider: Provider, probe: ProbeResult?, dictionaryVersion: String = "none") throws {
        try preset.validate()
        // Bez znaczników słów pakowane okno rozciąga jedno „zdanie" na minuty ciszy,
        // a klikalna linia czasu kłamie (ChatGPT #7). Kształt czatowy — tylko dyktowanie.
        if probe?.shape == .chatAudio { throw RunSnapshotError.chatShapeNotForMeetings }
        self.preset = preset
        guard let asr = preset.asr else { throw PresetError.missingASR }
        presetID = preset.id
        presetName = preset.name
        providerID = provider.id
        providerName = provider.name
        providerBaseURL = provider.baseURL
        model = asr.model
        shape = probe?.shape ?? .audioTranscriptions
        self.language = preset.language
        languageHandling = probe?.languageHandling ?? .unknown
        self.dictionaryVersion = dictionaryVersion
    }
}

public struct RunMetadata: Codable, Equatable, Sendable {
    public var runID: String
    public var snapshot: RunSnapshot
    public var startedAt: Date
    public var finishedAt: Date?
    public var chunkCount: Int
    public var requestCount: Int
    public var audioSecondsSent: Double
    public var failedChunkCount: Int
    public var languageFlagCount: Int
}
