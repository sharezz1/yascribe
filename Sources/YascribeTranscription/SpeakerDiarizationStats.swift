import Foundation
import YascribeProviders

/// Liczby do wydruku CLI `diarize` (odbiór T3); czyste funkcje, żeby dało się je sprawdzić bez modelu i bez sesji.
public struct SpeakerLabelCounts: Equatable, Sendable {
    /// Różne litery przydzielone wypowiedziom „them” (po regule okruchów).
    public var letters: Int
    public var them: Int
    public var unlabeled: Int

    public init(transcript: Transcript, diarization: SpeakerDiarization) {
        let labels = SpeakerLabels.labels(for: transcript, diarization: diarization)
        let them = zip(transcript.utterances, labels).filter { $0.0.speaker == .them }
        self.letters = Set(them.compactMap(\.1)).count
        self.them = them.count
        self.unlabeled = them.filter { $0.1 == nil }.count
    }
}

extension SpeakerDiarization {
    /// Sekundy mowy na mówcę (surowy identyfikator klastra), od największych.
    public var secondsBySpeaker: [(speaker: String, seconds: Double)] {
        var totals: [String: Double] = [:]
        for s in segments { totals[s.speaker, default: 0] += s.end - s.start }
        return totals.map { ($0.key, $0.value) }.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.speaker < $1.speaker }
    }

    /// Klastry z mniejszą ilością mowy niż `minClusterSeconds` nie dostają litery (ta sama granica co w `SpeakerLabels`).
    public var crumbCount: Int {
        secondsBySpeaker.filter { $0.seconds < (minClusterSeconds ?? 10) }.count
    }
}

public struct SpeakerSensitivityError: Error, LocalizedError, Equatable, Sendable {
    public var value: String
    public var errorDescription: String? { "--sensitivity \(value): use \(SpeakerSensitivity.allCases.map(\.rawValue).joined(separator: "|"))" }
}

extension SpeakerSensitivity {
    /// Argument CLI: brak = domyślna, nieznana wartość = błąd (nie cicha wartość domyślna).
    public static func parse(_ raw: String?) throws -> SpeakerSensitivity {
        guard let raw else { return .defaultValue }
        guard let value = SpeakerSensitivity(rawValue: raw) else { throw SpeakerSensitivityError(value: raw) }
        return value
    }
}
