import CryptoKit
import Foundation
import YascribeProviders

public struct SpeakerDiarization: Codable, Equatable, Sendable {
    public struct Segment: Codable, Equatable, Sendable {
        public var speaker: String
        public var start: Double
        public var end: Double
        /// Czas na torze (nie w sesji) — wejście do odcisku głosu (TASK-117); starsze pliki go nie mają.
        public var trackStart: Double? = nil
        public var trackEnd: Double? = nil
        public init(speaker: String, start: Double, end: Double, trackStart: Double? = nil, trackEnd: Double? = nil) {
            self.speaker = speaker; self.start = start; self.end = end; self.trackStart = trackStart; self.trackEnd = trackEnd
        }
    }

    public var version: Int
    public var modelPin: String
    public var sensitivity: SpeakerSensitivity?
    public var fa: Double?
    public var fb: Double?
    public var threshold: Double?
    public var minClusterSeconds: Double?
    public var audioFingerprint: String?
    public var createdAt: Date?
    public var segments: [Segment]
    public var names: [String: String]? = nil
    /// Imiona podstawione z profili głosów (TASK-117); klucz mówcy → profil. Same identyfikatory, nigdy wektory.
    public var voiceMatches: [String: VoiceMatch]? = nil
    /// „To nie X” dla mówcy w tym wykryciu; ponowne wykrycie pisze plik od nowa, więc odrzucenia znikają z kluczami.
    public var voiceRejected: [String: [UUID]]? = nil

    public init(version: Int, modelPin: String, sensitivity: SpeakerSensitivity?, fa: Double?, fb: Double?,
                threshold: Double?, minClusterSeconds: Double?, audioFingerprint: String?, createdAt: Date?, segments: [Segment]) {
        self.version = version; self.modelPin = modelPin; self.sensitivity = sensitivity
        self.fa = fa; self.fb = fb; self.threshold = threshold; self.minClusterSeconds = minClusterSeconds
        self.audioFingerprint = audioFingerprint; self.createdAt = createdAt; self.segments = segments
    }

    public func renamed(_ speaker: String, to name: String?) -> SpeakerDiarization? {
        guard segments.contains(where: { $0.speaker == speaker }) else { return nil }
        var result = self
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var names = self.names ?? [:]
        names[speaker] = trimmed.isEmpty ? nil : trimmed
        result.names = names.isEmpty ? nil : names
        return result
    }

    /// Dopasowania z profili: imię do `names` (notatka, znaczniki, archiwum działają bez zmian) i ślad w `voiceMatches`.
    /// Klucz z imieniem (ręcznym albo już dopasowanym) zostaje nietknięty.
    public func applying(_ matches: [VoiceMatcher.Match], names profileNames: [UUID: String], model: String) -> SpeakerDiarization {
        var result = self
        for match in matches where result.names?[match.key] == nil {
            guard let name = profileNames[match.profileID], segments.contains(where: { $0.speaker == match.key }) else { continue }
            result.names = (result.names ?? [:]).merging([match.key: name]) { $1 }
            result.voiceMatches = (result.voiceMatches ?? [:]).merging([match.key: VoiceMatch(profileID: match.profileID, similarity: match.similarity, model: model)]) { $1 }
        }
        return result
    }

    /// Klucze z imieniem — dopasowanie ich pomija.
    public var namedKeys: Set<String> { Set(names?.keys.map { $0 } ?? []) }

    public static func fromTrack(segments: [(speaker: String, start: Double, end: Double)], clock: SessionClock,
                                 track: String = "system", modelPin: String, sensitivity: SpeakerSensitivity?,
                                 threshold: Double = 0.6, minClusterSeconds: Double = 10,
                                 audioFingerprint: String?, createdAt: Date) -> SpeakerDiarization {
        SpeakerDiarization(version: 1, modelPin: modelPin, sensitivity: sensitivity, fa: sensitivity?.fa, fb: sensitivity?.fb,
                           threshold: threshold, minClusterSeconds: minClusterSeconds, audioFingerprint: audioFingerprint,
                           createdAt: createdAt, segments: segments.map {
            Segment(speaker: $0.speaker, start: clock.sessionSeconds(track: track, trackSeconds: $0.start),
                    end: clock.sessionSeconds(track: track, trackSeconds: $0.end), trackStart: $0.start, trackEnd: $0.end)
        })
    }

    /// Tożsamość wykrycia mówców (same odcinki, bez imion): ponowne wykrycie daje nowe odcinki pod tymi samymi kluczami
    /// (`speaker_0`…), więc notatka porównuje ten skrót, zanim pokaże imię.
    public var segmentsDigest: String {
        var hasher = SHA256()
        for s in segments { hasher.update(data: Data("\(s.speaker)\u{0}\(s.start)\u{0}\(s.end)\n".utf8)) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func audioFingerprint(session: URL) -> String? {
        let audio = session.appendingPathComponent("system.caf")
        guard let size = (try? FileManager.default.attributesOfItem(atPath: audio.path)[.size]) as? NSNumber,
              let journal = try? Data(contentsOf: session.appendingPathComponent("journal.jsonl")) else { return nil }
        var hash = SHA256()
        hash.update(data: Data("YascribeSpeakers-input-v1\n".utf8))
        hash.update(data: journal)
        hash.update(data: Data("\(size.uint64Value)".utf8))
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func knownPins(localPin: String) -> Set<String> { Set([localPin, MistralDiarization.pin]).union(SpeakerCapability.pins) }

    public static func load(run: RunDirectory, acceptedPins: Set<String>, currentAudioFingerprint: String?) -> SpeakerDiarization? {
        guard let value = try? JSONFile.load(SpeakerDiarization?.self, from: run.speakers, default: nil),
              value.version == 1, acceptedPins.contains(value.modelPin),
              currentAudioFingerprint == nil || value.audioFingerprint == currentAudioFingerprint else { return nil }
        return value
    }
}

public struct VoiceMatch: Codable, Equatable, Sendable {
    public var profileID: UUID
    public var similarity: Double
    /// Model, którym dopasowano; po zmianie modelu UI nie pokazuje „Rozpoznano po głosie” (imię zostaje).
    public var model: String?
    public init(profileID: UUID, similarity: Double, model: String?) { self.profileID = profileID; self.similarity = similarity; self.model = model }
}

extension RunDirectory {
    public var speakers: URL { url.appendingPathComponent("speakers.json") }
}
