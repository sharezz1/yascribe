import AVFoundation
import Foundation
import YascribeProviders

public enum CloudDiarizationError: Error, LocalizedError, Equatable {
    case tooLong, audioFormat
    public var errorDescription: String? {
        switch self {
        case .tooLong: "Recording too long for speaker detection."
        case .audioFormat: "Could not encode audio for speaker detection."
        }
    }
}

public enum CloudDiarization {
    public static func bitrate(trackSeconds: Double, limitBytes: Int?) -> Int? {
        guard let limitBytes else { return 48_000 }
        return [48_000, 24_000].first { trackSeconds * Double($0) / 8 * 4 / 3 <= Double(limitBytes) * 0.9 }
    }
    public static func segments(_ words: [DiarizedWord], gap: Double = 1.5) -> [(speaker: String, start: Double, end: Double)] {
        var result: [(speaker: String, start: Double, end: Double)] = []
        for word in words {
            if let last = result.last, last.speaker == word.speaker, word.start - last.end < gap {
                result[result.count - 1].end = max(last.end, word.end)
            } else { result.append((word.speaker, word.start, word.end)) }
        }
        return result
    }
    public static func run(track: URL, client: any DiarizationClient, model: String, language: LanguageCode?, limitBytes: Int?) async throws -> [(speaker: String, start: Double, end: Double)] {
        let input = try AVAudioFile(forReading: track)
        guard let rate = bitrate(trackSeconds: Double(input.length) / input.processingFormat.sampleRate, limitBytes: limitBytes) else { throw CloudDiarizationError.tooLong }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("yascribe-cloud-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try AACEncoder.encode(caf: track, to: temporary, bitrate: rate)
        let data = try Data(contentsOf: temporary)
        try Task.checkCancellation()
        let words = try await client.diarize(m4a: data, model: model, language: language)
        try Task.checkCancellation()
        return segments(words)
    }
}
